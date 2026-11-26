<#
.SYNOPSIS
  Provisions the OFFICIAL Gradle Wrapper for android\ (gradlew, gradlew.bat, gradle-wrapper.jar).

.DESCRIPTION
  PowerShell twin of scripts/bootstrap_android_wrapper.sh (same logic, same exit codes).

   1. Reads the Gradle version, distribution type AND distributionSha256Sum from
      android\gradle\wrapper\gradle-wrapper.properties (single source of truth; that file is never modified).
      distributionSha256Sum is REQUIRED: it is the SHA-256 of the exact archive named by distributionUrl
      (today gradle-<version>-all.zip) and makes the wrapper verify the distribution it downloads.
   2. Before downloading anything large, cross-checks that value against the checksum Gradle publishes for that
      exact distribution type (<url>.zip.sha256) and explains if it is the bin.zip checksum by mistake.
   3. Downloads the official Gradle *bin* distribution used only to run the generator and verifies its SHA-256
      against the checksum Gradle publishes next to it (and, optionally, against a checksum you pin).
   4. Runs the real `gradle wrapper` task (passing --gradle-distribution-sha256-sum) inside a temporary
      directory that is a VALID Gradle build.
      (Gradle 9 refuses to run any task, `wrapper` included, in a directory without settings.gradle[.kts|.dcl];
      an empty directory caused Codemagic build 6b036ee5...: "Directory '...\gen' does not contain a Gradle build.")
   5. Validates the generated files (the generated gradle-wrapper.properties must carry the same
      distributionSha256Sum and the same distribution file name) and installs them atomically into android\.
   6. Verifies the result: `android\gradlew.bat --version` must report the expected version (the wrapper
      downloads the -all archive and enforces distributionSha256Sum itself), and gradle-wrapper.properties
      must be byte-for-byte unchanged.

  Idempotent: a structurally valid wrapper that is already present is left untouched (it is still verified).

  Environment variables (optional): GRADLE_VERSION, GRADLE_DISTRIBUTIONS_BASE, FORCE_WRAPPER_REGENERATE=1,
  GRADLE_BIN_DISTRIBUTION_SHA256 (pins the generator's -bin.zip, NOT the wrapper's -all.zip;
  GRADLE_DISTRIBUTION_SHA256 is a deprecated alias).

  Exit codes: 0 ok | 1 unexpected | 2 configuration (incl. missing/malformed distributionSha256Sum)
              | 3 network/download | 4 checksum (mismatch of any checksum) | 5 extraction
              6 wrapper generation | 7 installation/permissions | 8 verification | 9 missing prerequisite

  NOTE FOR GIT: gradlew must be executable on macOS/Linux. If you commit the generated files from Windows, run
      git update-index --chmod=+x android/gradlew
  (the CI bootstrap also runs chmod +x, so builds work either way).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is extremely slow with the progress bar in Windows PowerShell 5.1
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$script:ExitCode = 0
$script:TmpDir   = $null

$EX_CONFIG = 2; $EX_NETWORK = 3; $EX_CHECKSUM = 4; $EX_EXTRACT = 5
$EX_GENERATE = 6; $EX_INSTALL = 7; $EX_VERIFY = 8; $EX_PREREQ = 9
$DefaultBaseUrl = 'https://services.gradle.org/distributions'

function Write-Log([string]$Message)  { Write-Host "[wrapper-bootstrap] $Message" }
function Write-Warn([string]$Message) { Write-Host "[wrapper-bootstrap] WARNING: $Message" -ForegroundColor Yellow }
function Fail([int]$Code, [string]$Message) { $script:ExitCode = $Code; throw $Message }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------
function Test-Sha256([string]$Value) { return ($Value -match '^[0-9a-f]{64}$') }
# Strict form for the value configured in gradle-wrapper.properties: lower-case only (-cmatch is case-sensitive).
function Test-Sha256Strict([string]$Value) { return ($Value -cmatch '^[0-9a-f]{64}$') }

# Value of "key=value" (last occurrence), trimmed; empty string if absent.
function Get-PropValue([string]$Path, [string]$Key) {
    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match ('^\s*' + [regex]::Escape($Key) + '\s*=') } | Select-Object -Last 1
    if (-not $line) { return '' }
    return (($line -split '=', 2)[1]).Trim()
}

function Get-ZipEntryNames([string]$Path) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try { return @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
}

# A wrapper jar must be an intact zip archive that contains the wrapper classes.
function Test-WrapperJar([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt 10000) { return $false }
    try {
        $names = Get-ZipEntryNames $Path
        return (@($names | Where-Object { $_ -like 'org/gradle/wrapper/*' }).Count -gt 0)
    } catch { return $false }
}

function Test-GradlewPlausible([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt 2000) { return $false }
    $text = [System.IO.File]::ReadAllText($Path)
    return ($text.StartsWith('#!') -and $text.Contains('gradle-wrapper.jar'))
}

function Test-GradlewBatPlausible([string]$Path) {
    return ((Test-Path -LiteralPath $Path -PathType Leaf) -and ((Get-Item -LiteralPath $Path).Length -ge 1000))
}

# Runs a native command with stderr merged, streams its output, and returns exit code + output.
function Invoke-Native([string]$File, [string[]]$Arguments, [string]$WorkDir) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # native stderr must not become a terminating error in Windows PowerShell 5.1
    Push-Location -LiteralPath $WorkDir
    try {
        $lines = & $File @Arguments 2>&1 | ForEach-Object { $text = $_.ToString(); Write-Host $text; $text }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $code; Output = (@($lines) -join "`n") }
}

function Save-Url([string]$Url, [string]$OutFile) {
    $lastError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 1800
            return
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt 3) { Write-Warn "download attempt $attempt of 3 failed ($lastError); retrying..."; Start-Sleep -Seconds 2 }
        }
    }
    Fail $EX_NETWORK "download failed: $Url ($lastError). Check network/proxy access, or point GRADLE_DISTRIBUTIONS_BASE at a mirror."
}

# Checksum Gradle publishes for one exact archive (<base>/gradle-<version>-<type>.zip.sha256); fails closed.
function Get-PublishedSha256([string]$BaseUrl, [string]$Version, [string]$Type, [string]$Dir) {
    $url  = "$BaseUrl/gradle-$Version-$Type.zip.sha256"
    $file = Join-Path $Dir "published-$Type.sha256"
    Save-Url $url $file
    $value = ((Get-Content -LiteralPath $file -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    if (-not (Test-Sha256 $value)) { Fail $EX_CHECKSUM "$url does not contain a valid SHA-256 value (got: '$value')." }
    return $value
}

function Get-JavaMajor {
    $javaCmd = $null
    if ($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin\java.exe'))) { $javaCmd = Join-Path $env:JAVA_HOME 'bin\java.exe' }
    elseif (Get-Command java -ErrorAction SilentlyContinue) { $javaCmd = (Get-Command java).Source }
    if (-not $javaCmd) { Fail $EX_PREREQ 'no Java runtime found (set JAVA_HOME or put java 17+ in PATH).' }
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $first = (& $javaCmd -version 2>&1 | Select-Object -First 1).ToString() } finally { $ErrorActionPreference = $previous }
    if ($first -match 'version "([^"]+)"') {
        $v = $Matches[1]
        if ($v -match '^1\.(\d+)') { return [int]$Matches[1] }
        if ($v -match '^(\d+)')    { return [int]$Matches[1] }
    }
    return $null
}

# ------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------
function Invoke-Main {
    $root       = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $androidDir = Join-Path $root 'android'
    $wrapperDir = Join-Path $androidDir 'gradle\wrapper'
    $props      = Join-Path $wrapperDir 'gradle-wrapper.properties'
    $gradlew    = Join-Path $androidDir 'gradlew'
    $gradlewBat = Join-Path $androidDir 'gradlew.bat'
    $wrapperJar = Join-Path $wrapperDir 'gradle-wrapper.jar'

    # ---- 1. configuration from gradle-wrapper.properties --------------------------------------
    if (-not (Test-Path -LiteralPath $androidDir -PathType Container)) { Fail $EX_CONFIG "android\ directory not found at $androidDir." }
    if (-not (Test-Path -LiteralPath $props -PathType Leaf))           { Fail $EX_CONFIG "$props not found." }

    $urlLine = Get-Content -LiteralPath $props | Where-Object { $_ -match '^\s*distributionUrl\s*=' } | Select-Object -Last 1
    if (-not $urlLine) { Fail $EX_CONFIG "no distributionUrl found in $props." }
    $distUrl  = (($urlLine -split '=', 2)[1]).Trim().Replace('\:', ':')
    $distFile = $distUrl.Substring($distUrl.LastIndexOf('/') + 1)
    if ($distFile -match '^gradle-(.+)-(all|bin)\.zip$') {
        $propsVersion = $Matches[1]
        $propsType    = $Matches[2]
    } else {
        Fail $EX_CONFIG "cannot derive the Gradle version from distributionUrl '$distUrl' (expected .../gradle-<version>-(all|bin).zip)."
    }

    # The checksum configured for the wrapper itself: the checksum of the archive named by distributionUrl
    # (-all.zip today), never the one of the -bin.zip that this script downloads to run the generator.
    $distSha = Get-PropValue $props 'distributionSha256Sum'
    if (-not $distSha) {
        Fail $EX_CONFIG "$props has no distributionSha256Sum. Add the SHA-256 of gradle-$propsVersion-$propsType.zip from https://gradle.org/release-checksums/ (it is what makes the wrapper verify the distribution it downloads)."
    }
    if (-not (Test-Sha256Strict $distSha)) { Fail $EX_CONFIG "distributionSha256Sum in $props is not 64 lowercase hexadecimal characters (got: '$distSha')." }

    $version = if ($env:GRADLE_VERSION) { $env:GRADLE_VERSION } else { $propsVersion }
    if ($version -ne $propsVersion) { Fail $EX_CONFIG "GRADLE_VERSION=$version but $props references $propsVersion. Align them." }
    if ($version -notmatch '^[0-9A-Za-z.\-]+$') { Fail $EX_CONFIG "invalid Gradle version '$version'." }

    $baseUrl = if ($env:GRADLE_DISTRIBUTIONS_BASE) { $env:GRADLE_DISTRIBUTIONS_BASE.TrimEnd('/') } else { $DefaultBaseUrl }
    if ((-not $env:GRADLE_BIN_DISTRIBUTION_SHA256) -and $env:GRADLE_DISTRIBUTION_SHA256) {
        Write-Warn "GRADLE_DISTRIBUTION_SHA256 is deprecated; it pins the generator's -bin.zip. Use GRADLE_BIN_DISTRIBUTION_SHA256 (the wrapper's -all.zip checksum lives in gradle-wrapper.properties)."
    }
    $pinRaw = if ($env:GRADLE_BIN_DISTRIBUTION_SHA256) { $env:GRADLE_BIN_DISTRIBUTION_SHA256 } elseif ($env:GRADLE_DISTRIBUTION_SHA256) { $env:GRADLE_DISTRIBUTION_SHA256 } else { '' }
    $pinned  = $pinRaw.Trim().ToLowerInvariant()
    if ($pinned -and -not (Test-Sha256 $pinned)) { Fail $EX_CONFIG 'GRADLE_BIN_DISTRIBUTION_SHA256 is not a 64-character hexadecimal SHA-256 value.' }
    $propsShaBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $props).Hash.ToLowerInvariant()

    Write-Log "Project root:  $root"
    Write-Log "Target Gradle: $version (distribution type from properties: $propsType)"
    Write-Log "Configured distributionSha256Sum (for gradle-$version-$propsType.zip): $distSha"

    $javaMajor = Get-JavaMajor
    if ($null -eq $javaMajor)    { Write-Warn 'could not determine the Java version; Gradle will report it if it is unsuitable.' }
    elseif ($javaMajor -lt 17)   { Fail $EX_PREREQ "Java $javaMajor found, but Gradle $version requires Java 17 or newer (check JAVA_HOME)." }
    else                         { Write-Log "Java major version: $javaMajor" }

    # ---- 2. generate + install (skipped when a structurally valid wrapper exists) --------------
    $valid = (Test-WrapperJar $wrapperJar) -and (Test-GradlewPlausible $gradlew) -and (Test-GradlewBatPlausible $gradlewBat)
    if (($env:FORCE_WRAPPER_REGENERATE -ne '1') -and $valid) {
        Write-Log 'A structurally valid Gradle wrapper is already present; not regenerating (set FORCE_WRAPPER_REGENERATE=1 to override).'
    } else {
        New-Item -ItemType Directory -Force -Path $wrapperDir | Out-Null
        $probe = Join-Path $wrapperDir ('.write-test-' + [guid]::NewGuid().ToString('N'))
        try { [System.IO.File]::WriteAllText($probe, 'x'); Remove-Item -LiteralPath $probe -Force }
        catch { Fail $EX_INSTALL "no write permission for $wrapperDir." }

        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('karen-gradle-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir | Out-Null
        $tmp = $script:TmpDir

        # the wrapper checksum must belong to the exact distribution type in distributionUrl;
        # done first, with a tiny download, so a wrong value fails before the ~130 MB archive is fetched
        $published = Get-PublishedSha256 $baseUrl $version $propsType $tmp
        if ($published -ne $distSha) {
            $other = if ($propsType -eq 'bin') { 'all' } else { 'bin' }
            $hint = ''
            try {
                $otherFile = Join-Path $tmp "published-$other.sha256"
                Invoke-WebRequest -Uri "$baseUrl/gradle-$version-$other.zip.sha256" -OutFile $otherFile -UseBasicParsing -TimeoutSec 60
                $otherValue = ((Get-Content -LiteralPath $otherFile -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
                if ($otherValue -eq $distSha) {
                    $hint = " The configured value is the checksum of the -$other.zip, but distributionUrl points to the -$propsType.zip: wrong distribution type."
                }
            } catch { $hint = '' }
            Fail $EX_CHECKSUM "distributionSha256Sum in $props ($distSha) does not match the checksum Gradle publishes for gradle-$version-$propsType.zip ($published).$hint"
        }
        Write-Log "distributionSha256Sum matches the checksum published for gradle-$version-$propsType.zip."

        # download (generator distribution: -bin.zip)
        $archiveUrl = "$baseUrl/gradle-$version-bin.zip"
        $archive    = Join-Path $tmp 'gradle.zip'
        $sumFile    = Join-Path $tmp 'gradle.zip.sha256'
        Write-Log "Downloading official Gradle $version distribution: $archiveUrl"
        Save-Url $archiveUrl $archive
        Save-Url "$archiveUrl.sha256" $sumFile

        # checksum
        $firstToken = ((Get-Content -LiteralPath $sumFile -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
        if (-not (Test-Sha256 $firstToken)) { Fail $EX_CHECKSUM "the published checksum file does not contain a valid SHA-256 value (got: '$firstToken')." }
        if ($pinned -and ($pinned -ne $firstToken)) { Fail $EX_CHECKSUM "pinned GRADLE_BIN_DISTRIBUTION_SHA256 ($pinned) differs from the checksum Gradle publishes for gradle-$version-bin.zip ($firstToken)." }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
        if ($actual -ne $firstToken) { Fail $EX_CHECKSUM "SHA-256 mismatch for Gradle ${version}: expected $firstToken, got $actual. The download is corrupt or was tampered with." }
        Write-Log "SHA-256 verified: $actual"

        # extract
        $distDir = Join-Path $tmp 'dist'
        try { [System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $distDir) }
        catch { Fail $EX_EXTRACT "could not extract the Gradle distribution: $($_.Exception.Message)" }
        $gradleBat = Join-Path $distDir "gradle-$version\bin\gradle.bat"
        if (-not (Test-Path -LiteralPath $gradleBat -PathType Leaf)) { Fail $EX_EXTRACT 'bin\gradle.bat not found in the extracted distribution (unexpected archive layout).' }

        # generate inside a VALID Gradle build
        $gen = Join-Path $tmp 'gen'
        New-Item -ItemType Directory -Path $gen | Out-Null
        # Gradle 9 aborts with "Directory '...' does not contain a Gradle build" unless a settings file exists.
        [System.IO.File]::WriteAllText((Join-Path $gen 'settings.gradle'), "rootProject.name = 'karen-wrapper-generator'`n")
        [System.IO.File]::WriteAllText((Join-Path $gen 'build.gradle'), '')

        if ($baseUrl -eq $DefaultBaseUrl) { $wrapperArgs = @('wrapper', '--gradle-version', $version, '--distribution-type', $propsType) }
        else                              { $wrapperArgs = @('wrapper', '--gradle-distribution-url', "$baseUrl/gradle-$version-$propsType.zip") }
        $wrapperArgs += @('--gradle-distribution-sha256-sum', $distSha, '--no-daemon', '--console=plain')

        Write-Log "Running the official 'gradle wrapper' task in $gen"
        $previousHome = $env:GRADLE_USER_HOME
        $env:GRADLE_USER_HOME = Join-Path $tmp 'gradle-user-home'
        try { $result = Invoke-Native $gradleBat $wrapperArgs $gen } finally { $env:GRADLE_USER_HOME = $previousHome }
        if ($result.ExitCode -ne 0) { Fail $EX_GENERATE "the 'gradle wrapper' task failed with exit code $($result.ExitCode) (see the Gradle output above)." }

        $gGradlew = Join-Path $gen 'gradlew'
        $gBat     = Join-Path $gen 'gradlew.bat'
        $gJar     = Join-Path $gen 'gradle\wrapper\gradle-wrapper.jar'
        if (-not ((Test-Path -LiteralPath $gGradlew) -and (Test-Path -LiteralPath $gBat) -and (Test-Path -LiteralPath $gJar))) {
            Fail $EX_GENERATE "the 'gradle wrapper' task did not produce gradlew, gradlew.bat and gradle-wrapper.jar."
        }
        if (-not (Test-WrapperJar $gJar))           { Fail $EX_GENERATE 'the generated gradle-wrapper.jar is not a valid wrapper archive.' }
        if (-not (Test-GradlewPlausible $gGradlew)) { Fail $EX_GENERATE 'the generated gradlew does not look like a Gradle launcher script.' }
        if (-not (Test-GradlewBatPlausible $gBat))  { Fail $EX_GENERATE 'the generated gradlew.bat is missing or truncated.' }

        # The properties Gradle would generate must agree with the committed ones on checksum and archive.
        # (Only the three wrapper files are installed; the committed gradle-wrapper.properties is never replaced.)
        $gProps = Join-Path $gen 'gradle\wrapper\gradle-wrapper.properties'
        if (-not (Test-Path -LiteralPath $gProps -PathType Leaf)) { Fail $EX_GENERATE "the 'gradle wrapper' task did not produce gradle-wrapper.properties." }
        $gSha = Get-PropValue $gProps 'distributionSha256Sum'
        if ($gSha -ne $distSha) {
            $shown = if ($gSha) { $gSha } else { '<missing>' }
            Fail $EX_GENERATE "the generated gradle-wrapper.properties has distributionSha256Sum '$shown', expected '$distSha'."
        }
        $gUrl  = (Get-PropValue $gProps 'distributionUrl').Replace('\:', ':')
        $gFile = $gUrl.Substring($gUrl.LastIndexOf('/') + 1)
        if ($gFile -ne $distFile) { Fail $EX_GENERATE "the generated gradle-wrapper.properties references '$gFile' but the committed one references '$distFile'." }

        # install atomically (stage next to the destination, then rename)
        $suffix = ".new.$PID"
        try {
            Copy-Item -LiteralPath $gGradlew -Destination "$gradlew$suffix"    -Force
            Copy-Item -LiteralPath $gBat     -Destination "$gradlewBat$suffix"  -Force
            Copy-Item -LiteralPath $gJar     -Destination "$wrapperJar$suffix"  -Force
            Move-Item -LiteralPath "$wrapperJar$suffix" -Destination $wrapperJar -Force
            Move-Item -LiteralPath "$gradlewBat$suffix" -Destination $gradlewBat -Force
            Move-Item -LiteralPath "$gradlew$suffix"    -Destination $gradlew    -Force
        } catch {
            Remove-Item -LiteralPath "$gradlew$suffix", "$gradlewBat$suffix", "$wrapperJar$suffix" -Force -ErrorAction SilentlyContinue
            Fail $EX_INSTALL "could not install the generated wrapper files: $($_.Exception.Message)"
        }
        Write-Log "Official Gradle wrapper files installed into android\ (generated by the real 'gradle wrapper' task of Gradle $version)."
        Write-Log ("  gradle-wrapper.jar sha256: " + (Get-FileHash -Algorithm SHA256 -LiteralPath $wrapperJar).Hash.ToLowerInvariant())
        Write-Log ("  gradlew            sha256: " + (Get-FileHash -Algorithm SHA256 -LiteralPath $gradlew).Hash.ToLowerInvariant())
        Write-Log 'Reminder: on macOS/Linux gradlew must be executable. If you commit from Windows run: git update-index --chmod=+x android/gradlew'
    }

    # ---- 3. verify -----------------------------------------------------------------------------
    if (-not (Test-WrapperJar $wrapperJar)) { Fail $EX_VERIFY "$wrapperJar is missing or not a valid wrapper archive." }
    $versionResult = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $versionResult = Invoke-Native $gradlewBat @('--version') $androidDir
        if ($versionResult.ExitCode -eq 0) { break }
        Write-Warn "'gradlew.bat --version' failed (attempt $attempt of 2)."
        if ($attempt -lt 2) { Start-Sleep -Seconds 5 }
    }
    if ($versionResult.ExitCode -ne 0) { Fail $EX_VERIFY "'gradlew.bat --version' failed. If the output above shows a download error, the wrapper could not fetch the Gradle distribution (network)." }
    $found = @($versionResult.Output -split "`r?`n" | Where-Object { $_.Trim() -eq "Gradle $version" }).Count -gt 0
    if (-not $found) { Fail $EX_VERIFY "'gradlew.bat --version' did not report 'Gradle $version'." }
    # gradle-wrapper.properties (including distributionSha256Sum) must have been preserved byte for byte.
    $propsShaAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $props).Hash.ToLowerInvariant()
    if ($propsShaAfter -ne $propsShaBefore) { Fail $EX_VERIFY "$props was modified during bootstrap; it must never be (distributionSha256Sum would be at risk)." }
    if ((Get-PropValue $props 'distributionSha256Sum') -ne $distSha) { Fail $EX_VERIFY "distributionSha256Sum is no longer present in $props." }
    Write-Log "OK: android\gradlew.bat reports Gradle $version; wrapper jar is intact; distributionSha256Sum ($distSha) is configured and preserved."
}

try {
    Invoke-Main
} catch {
    if ($script:ExitCode -eq 0) { $script:ExitCode = 1 }
    Write-Host "[wrapper-bootstrap] ERROR (exit $($script:ExitCode)): $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($script:TmpDir -and (Test-Path -LiteralPath $script:TmpDir)) {
        Remove-Item -LiteralPath $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit $script:ExitCode
