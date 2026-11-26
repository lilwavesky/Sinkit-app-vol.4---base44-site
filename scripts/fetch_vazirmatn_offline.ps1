$ErrorActionPreference = "Stop"
$OutDir = Join-Path $PSScriptRoot "..\assets\google_fonts"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$BaseUrl = "https://github.com/rastikerdar/vazirmatn/raw/master/fonts/ttf"
foreach ($weight in @("Regular", "Medium", "Bold")) {
    Write-Host "Downloading Vazirmatn-$weight.ttf ..."
    Invoke-WebRequest -Uri "$BaseUrl/Vazirmatn-$weight.ttf" -OutFile (Join-Path $OutDir "Vazirmatn-$weight.ttf")
}
Write-Host "Done. Vazirmatn Regular, Medium, and Bold are now bundled offline in assets/google_fonts/."
