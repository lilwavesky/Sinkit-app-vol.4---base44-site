#!/usr/bin/env bash
# bootstrap_android_wrapper.sh
#
# Provisions the OFFICIAL Gradle Wrapper for android/:
#     android/gradlew
#     android/gradlew.bat
#     android/gradle/wrapper/gradle-wrapper.jar
#
# HOW (nothing here is hand-written):
#   1. Reads the Gradle version, distribution type AND distributionSha256Sum from
#      android/gradle/wrapper/gradle-wrapper.properties (single source of truth; that file is never modified).
#      distributionSha256Sum is REQUIRED: it is the SHA-256 of the exact archive named by distributionUrl
#      (today gradle-<version>-all.zip) and is what makes the wrapper verify the distribution it downloads.
#   2. Before downloading anything large, cross-checks that value against the checksum Gradle publishes for
#      that exact distribution type (<url>.zip.sha256), and explains if it is the bin.zip checksum by mistake.
#   3. Downloads the official Gradle *bin* distribution used only to run the generator and verifies its
#      SHA-256 against the checksum Gradle publishes next to it (and, optionally, against a checksum you pin).
#   4. Runs the real `gradle wrapper` task of that distribution (passing --gradle-distribution-sha256-sum)
#      inside a temporary directory that is a
#      VALID Gradle build. (Gradle 9 refuses to run any task, `wrapper` included, in a directory that has
#      no settings.gradle[.kts|.dcl]. An empty directory was the cause of Codemagic build 6b036ee5...:
#      "Directory '.../gen' does not contain a Gradle build.")
#   5. Validates the generated files (including that the generated gradle-wrapper.properties carries the same
#      distributionSha256Sum and the same distribution file name), installs them atomically into android/,
#      marks gradlew executable.
#   6. Verifies the result by running `android/gradlew --version` (the wrapper then downloads the -all archive
#      and enforces distributionSha256Sum itself), which must report the expected version, and checks that
#      gradle-wrapper.properties was left byte-for-byte untouched.
#
# Idempotent: a structurally valid wrapper that is already present is left untouched (it is still verified).
#
# Environment variables (all optional):
#   GRADLE_VERSION                expected version; must equal the one in gradle-wrapper.properties
#   GRADLE_DISTRIBUTIONS_BASE     default https://services.gradle.org/distributions  (mirror / test hook)
#   GRADLE_BIN_DISTRIBUTION_SHA256  pin: additionally require the downloaded gradle-<version>-BIN.zip (the
#                                   generator archive, NOT the -all.zip) to have exactly this SHA-256.
#                                   (GRADLE_DISTRIBUTION_SHA256 is a deprecated alias of this variable.)
#   FORCE_WRAPPER_REGENERATE=1    regenerate even when a valid wrapper is already present
#
# Exit codes: 0 ok | 2 configuration (incl. missing/malformed distributionSha256Sum) | 3 network/download
#             | 4 checksum (mismatch of any checksum) | 5 archive extraction
#             | 6 wrapper generation | 7 installation/permissions | 8 verification | 9 missing prerequisite
#
# Portable to macOS' bash 3.2 and Linux (no associative arrays, no mapfile, no GNU-only flags).
set -euo pipefail

readonly EX_CONFIG=2 EX_NETWORK=3 EX_CHECKSUM=4 EX_EXTRACT=5 EX_GENERATE=6 EX_INSTALL=7 EX_VERIFY=8 EX_PREREQ=9
readonly DEFAULT_BASE_URL="https://services.gradle.org/distributions"

log()  { printf '[wrapper-bootstrap] %s\n' "$*"; }
warn() { printf '[wrapper-bootstrap] WARNING: %s\n' "$*" >&2; }
die()  { local code="$1"; shift; printf '[wrapper-bootstrap] ERROR (exit %s): %s\n' "$code" "$*" >&2; exit "$code"; }

# ---------------------------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------------------------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
WRAPPER_DIR="$ANDROID_DIR/gradle/wrapper"
PROPS="$WRAPPER_DIR/gradle-wrapper.properties"
GRADLEW="$ANDROID_DIR/gradlew"
GRADLEW_BAT="$ANDROID_DIR/gradlew.bat"
WRAPPER_JAR="$WRAPPER_DIR/gradle-wrapper.jar"
STAGE_SUFFIX=".new.$$"
TMP=""

cleanup() {
  rm -f "$GRADLEW$STAGE_SUFFIX" "$GRADLEW_BAT$STAGE_SUFFIX" "$WRAPPER_JAR$STAGE_SUFFIX" 2>/dev/null || true
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------
require_tool() { command -v "$1" >/dev/null 2>&1 || die "$EX_PREREQ" "required tool '$1' was not found in PATH."; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1;  then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else die "$EX_PREREQ" "no SHA-256 tool found (need sha256sum, shasum or openssl)."; fi
}

to_lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

is_sha256() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9a-f]*) return 1 ;; esac
  return 0
}

file_size() { wc -c < "$1" | tr -d ' '; }

# prop_value <file> <key>: value of "key=value" (last occurrence), CR/whitespace trimmed, empty if absent.
prop_value() {
  grep -E "^[[:space:]]*$2[[:space:]]*=" "$1" | tail -n 1 | cut -d= -f2- \
    | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true
}

fetch() { # <url> <destination file>
  curl --fail --location --silent --show-error --retry 3 --retry-delay 2 \
       --connect-timeout 30 --max-time 1800 --output "$2" "$1"
}

# fetch_published_sha256 <bin|all>: sets PUBLISHED_SHA256 to the checksum Gradle publishes for that exact archive.
PUBLISHED_SHA256=""
fetch_published_sha256() {
  local type="$1" url f v
  url="${BASE_URL}/gradle-${GRADLE_VERSION}-${type}.zip.sha256"
  f="$TMP/published-${type}.sha256"
  fetch "$url" "$f" || die "$EX_NETWORK" "download failed: $url (the published checksum is needed to validate distributionSha256Sum; failing closed)."
  v="$(tr -d '\r' < "$f" | awk 'NR == 1 { print tolower($1) }')"
  is_sha256 "$v" || die "$EX_CHECKSUM" "$url does not contain a valid SHA-256 value (got: '$v')."
  PUBLISHED_SHA256="$v"
}

# A wrapper jar must be an intact zip archive that actually contains the wrapper classes.
jar_is_valid() {
  local listing
  [ -f "$1" ] || return 1
  [ "$(file_size "$1")" -ge 10000 ] || return 1
  unzip -tq "$1" >/dev/null 2>&1 || return 1
  # Capture first, then match without a pipe: `unzip -l | grep -q` can die with SIGPIPE under pipefail.
  listing="$(unzip -l "$1" 2>/dev/null)" || return 1
  case "$listing" in *org/gradle/wrapper/*) return 0 ;; esac
  return 1
}

# Shape of the generated launcher scripts (deliberately not tied to licence wording or exact size).
gradlew_is_plausible() {
  [ -f "$1" ] || return 1
  [ "$(file_size "$1")" -ge 2000 ] || return 1
  [ "$(head -c 2 "$1")" = "#!" ] || return 1
  grep -q 'gradle-wrapper.jar' "$1" || return 1
}
gradlew_bat_is_plausible() { [ -f "$1" ] && [ "$(file_size "$1")" -ge 1000 ]; }

wrapper_is_valid() {
  jar_is_valid "$WRAPPER_JAR" && gradlew_is_plausible "$GRADLEW" && gradlew_bat_is_plausible "$GRADLEW_BAT"
}

java_major_version() { # prints the Java major version, or nothing if it cannot be determined
  local jbin="java" v="" major=""
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then jbin="$JAVA_HOME/bin/java"; fi
  command -v "$jbin" >/dev/null 2>&1 || return 0
  v="$("$jbin" -version 2>&1 | awk -F'"' '/version/ && !d { print $2; d=1 }')" || true
  case "$v" in
    1.*) major="${v#1.}"; major="${major%%.*}" ;;
    *)   major="${v%%.*}"; major="${major%%-*}"; major="${major%%+*}"; major="${major%%_*}" ;;
  esac
  case "$major" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s' "$major"
}

# ---------------------------------------------------------------------------------------------
# 1. Configuration: version and distribution type come from gradle-wrapper.properties
# ---------------------------------------------------------------------------------------------
[ -d "$ANDROID_DIR" ] || die "$EX_CONFIG" "android/ directory not found at $ANDROID_DIR."
[ -f "$PROPS" ]       || die "$EX_CONFIG" "$PROPS not found."

DIST_URL="$(prop_value "$PROPS" distributionUrl | sed -e 's#\\:#:#g')"
[ -n "$DIST_URL" ] || die "$EX_CONFIG" "no distributionUrl found in $PROPS."

DIST_FILE="${DIST_URL##*/}"
case "$DIST_FILE" in
  gradle-*-all.zip) PROPS_TYPE="all"; PROPS_VERSION="${DIST_FILE#gradle-}"; PROPS_VERSION="${PROPS_VERSION%-all.zip}" ;;
  gradle-*-bin.zip) PROPS_TYPE="bin"; PROPS_VERSION="${DIST_FILE#gradle-}"; PROPS_VERSION="${PROPS_VERSION%-bin.zip}" ;;
  *) die "$EX_CONFIG" "cannot derive the Gradle version from distributionUrl '$DIST_URL' (expected .../gradle-<version>-(all|bin).zip)." ;;
esac

# The checksum configured for the wrapper itself. It must be the checksum of the archive named by distributionUrl
# (-all.zip today), never the one of the -bin.zip that this script downloads to run the generator.
DIST_SHA256="$(prop_value "$PROPS" distributionSha256Sum)"
if [ -z "$DIST_SHA256" ]; then
  die "$EX_CONFIG" "$PROPS has no distributionSha256Sum. Add the SHA-256 of gradle-${PROPS_VERSION}-${PROPS_TYPE}.zip from https://gradle.org/release-checksums/ (it is what makes the wrapper verify the distribution it downloads)."
fi
is_sha256 "$DIST_SHA256" || die "$EX_CONFIG" "distributionSha256Sum in $PROPS is not 64 lowercase hexadecimal characters (got: '$DIST_SHA256')."

GRADLE_VERSION="${GRADLE_VERSION:-$PROPS_VERSION}"
if [ "$GRADLE_VERSION" != "$PROPS_VERSION" ]; then
  die "$EX_CONFIG" "GRADLE_VERSION=$GRADLE_VERSION but $PROPS references $PROPS_VERSION. Align them."
fi
case "$GRADLE_VERSION" in ''|*[!0-9A-Za-z.-]*) die "$EX_CONFIG" "invalid Gradle version '$GRADLE_VERSION'." ;; esac

BASE_URL="${GRADLE_DISTRIBUTIONS_BASE:-$DEFAULT_BASE_URL}"
BASE_URL="${BASE_URL%/}"
if [ -z "${GRADLE_BIN_DISTRIBUTION_SHA256:-}" ] && [ -n "${GRADLE_DISTRIBUTION_SHA256:-}" ]; then
  warn "GRADLE_DISTRIBUTION_SHA256 is deprecated; it pins the generator's -bin.zip. Use GRADLE_BIN_DISTRIBUTION_SHA256 (the wrapper's -all.zip checksum lives in gradle-wrapper.properties)."
fi
PINNED_SHA256="$(to_lower "${GRADLE_BIN_DISTRIBUTION_SHA256:-${GRADLE_DISTRIBUTION_SHA256:-}}")"
if [ -n "$PINNED_SHA256" ] && ! is_sha256 "$PINNED_SHA256"; then
  die "$EX_CONFIG" "GRADLE_BIN_DISTRIBUTION_SHA256 is not a 64-character hexadecimal SHA-256 value."
fi
PROPS_SHA256_BEFORE="$(sha256_of "$PROPS")"

log "Project root:  $ROOT"
log "Target Gradle: $GRADLE_VERSION (distribution type from properties: $PROPS_TYPE)"
log "Configured distributionSha256Sum (for gradle-${GRADLE_VERSION}-${PROPS_TYPE}.zip): $DIST_SHA256"

# Gradle 9 needs Java 17+. Fail early with a clear message instead of a stack trace.
if { [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; } && ! command -v java >/dev/null 2>&1; then
  die "$EX_PREREQ" "no Java runtime found (set JAVA_HOME or put java 17+ in PATH)."
fi
JAVA_MAJOR="$(java_major_version)"
if [ -z "$JAVA_MAJOR" ]; then
  warn "could not determine the Java version; Gradle will report it if it is unsuitable."
elif [ "$JAVA_MAJOR" -lt 17 ]; then
  die "$EX_PREREQ" "Java $JAVA_MAJOR found, but Gradle $GRADLE_VERSION requires Java 17 or newer (check JAVA_HOME / the Codemagic 'java:' setting)."
else
  log "Java major version: $JAVA_MAJOR"
fi

# ---------------------------------------------------------------------------------------------
# 2. Generate + install the wrapper (skipped when a structurally valid one already exists)
# ---------------------------------------------------------------------------------------------
generate_and_install() {
  require_tool curl
  require_tool unzip
  require_tool awk

  # Fail fast on permissions, before downloading ~130 MB.
  mkdir -p "$WRAPPER_DIR" 2>/dev/null || die "$EX_INSTALL" "cannot create $WRAPPER_DIR (permissions?)."
  { [ -w "$ANDROID_DIR" ] && [ -w "$WRAPPER_DIR" ]; } || die "$EX_INSTALL" "no write permission for $ANDROID_DIR or $WRAPPER_DIR."

  TMP="$(mktemp -d "${TMPDIR:-/tmp}/karen-gradle.XXXXXX")" || die "$EX_INSTALL" "cannot create a temporary directory."

  # ---- the wrapper checksum must belong to the exact distribution type in distributionUrl ----
  # Done first, with a tiny download, so a wrong value fails before the ~130 MB archive is fetched.
  fetch_published_sha256 "$PROPS_TYPE"
  if [ "$PUBLISHED_SHA256" != "$DIST_SHA256" ]; then
    local other="bin" hint=""
    if [ "$PROPS_TYPE" = "bin" ]; then other="all"; fi
    if fetch "${BASE_URL}/gradle-${GRADLE_VERSION}-${other}.zip.sha256" "$TMP/published-${other}.sha256" 2>/dev/null; then
      if [ "$(tr -d '\r' < "$TMP/published-${other}.sha256" | awk 'NR == 1 { print tolower($1) }')" = "$DIST_SHA256" ]; then
        hint=" The configured value is the checksum of the -${other}.zip, but distributionUrl points to the -${PROPS_TYPE}.zip: wrong distribution type."
      fi
    fi
    die "$EX_CHECKSUM" "distributionSha256Sum in $PROPS ($DIST_SHA256) does not match the checksum Gradle publishes for gradle-${GRADLE_VERSION}-${PROPS_TYPE}.zip ($PUBLISHED_SHA256).${hint}"
  fi
  log "distributionSha256Sum matches the checksum published for gradle-${GRADLE_VERSION}-${PROPS_TYPE}.zip."

  # ---- download (generator distribution: -bin.zip) ------------------------------------------
  local archive_url="${BASE_URL}/gradle-${GRADLE_VERSION}-bin.zip"
  local archive="$TMP/gradle.zip" sumfile="$TMP/gradle.zip.sha256"
  log "Downloading official Gradle ${GRADLE_VERSION} distribution: $archive_url"
  fetch "$archive_url" "$archive" \
    || die "$EX_NETWORK" "download failed: $archive_url (check network/proxy access, or point GRADLE_DISTRIBUTIONS_BASE at a mirror)."
  fetch "${archive_url}.sha256" "$sumfile" \
    || die "$EX_NETWORK" "download failed: ${archive_url}.sha256"

  # ---- checksum -----------------------------------------------------------------------------
  local expected actual
  expected="$(tr -d '\r' < "$sumfile" | awk 'NR == 1 { print tolower($1) }')"
  is_sha256 "$expected" || die "$EX_CHECKSUM" "the published checksum file does not contain a valid SHA-256 value (got: '$expected')."
  if [ -n "$PINNED_SHA256" ] && [ "$PINNED_SHA256" != "$expected" ]; then
    die "$EX_CHECKSUM" "pinned GRADLE_BIN_DISTRIBUTION_SHA256 ($PINNED_SHA256) differs from the checksum Gradle publishes for gradle-${GRADLE_VERSION}-bin.zip ($expected)."
  fi
  actual="$(sha256_of "$archive")"
  if [ "$actual" != "$expected" ]; then
    die "$EX_CHECKSUM" "SHA-256 mismatch for Gradle ${GRADLE_VERSION}: expected $expected, got $actual. The download is corrupt or was tampered with."
  fi
  log "SHA-256 verified: $actual"

  # ---- extract ------------------------------------------------------------------------------
  unzip -tq "$archive" >/dev/null 2>&1 || die "$EX_EXTRACT" "the downloaded archive failed its integrity test."
  mkdir -p "$TMP/dist"
  unzip -q "$archive" -d "$TMP/dist" || die "$EX_EXTRACT" "could not extract the Gradle distribution (disk space / permissions?)."
  local gradle_bin="$TMP/dist/gradle-${GRADLE_VERSION}/bin/gradle"
  [ -f "$gradle_bin" ] || die "$EX_EXTRACT" "bin/gradle not found in the extracted distribution (unexpected archive layout)."
  chmod +x "$gradle_bin" || die "$EX_EXTRACT" "cannot make $gradle_bin executable."

  # ---- generate (in a VALID Gradle build) ---------------------------------------------------
  local gen="$TMP/gen"
  mkdir -p "$gen"
  # Gradle 9 aborts with "Directory '...' does not contain a Gradle build" unless a settings file exists.
  printf "rootProject.name = 'karen-wrapper-generator'\n" > "$gen/settings.gradle"
  : > "$gen/build.gradle"

  run_wrapper_task() {
    ( cd "$gen" && GRADLE_USER_HOME="$TMP/gradle-user-home" "$gradle_bin" wrapper "$@" --no-daemon --console=plain )
  }
  log "Running the official 'gradle wrapper' task in $gen"
  if [ "$BASE_URL" = "$DEFAULT_BASE_URL" ]; then
    run_wrapper_task --gradle-version "$GRADLE_VERSION" --distribution-type "$PROPS_TYPE" \
        --gradle-distribution-sha256-sum "$DIST_SHA256" \
      || die "$EX_GENERATE" "the 'gradle wrapper' task failed (see the Gradle output above)."
  else
    run_wrapper_task --gradle-distribution-url "${BASE_URL}/gradle-${GRADLE_VERSION}-${PROPS_TYPE}.zip" \
        --gradle-distribution-sha256-sum "$DIST_SHA256" \
      || die "$EX_GENERATE" "the 'gradle wrapper' task failed (see the Gradle output above)."
  fi

  local g_gradlew="$gen/gradlew" g_bat="$gen/gradlew.bat" g_jar="$gen/gradle/wrapper/gradle-wrapper.jar"
  [ -f "$g_gradlew" ] && [ -f "$g_bat" ] && [ -f "$g_jar" ] \
    || die "$EX_GENERATE" "the 'gradle wrapper' task did not produce gradlew, gradlew.bat and gradle-wrapper.jar."
  jar_is_valid "$g_jar"            || die "$EX_GENERATE" "the generated gradle-wrapper.jar is not a valid wrapper archive."
  gradlew_is_plausible "$g_gradlew" || die "$EX_GENERATE" "the generated gradlew does not look like a Gradle launcher script."
  gradlew_bat_is_plausible "$g_bat" || die "$EX_GENERATE" "the generated gradlew.bat is missing or truncated."

  # The properties Gradle would generate must agree with the committed ones on checksum and archive. (Only the
  # three wrapper files are installed; the committed gradle-wrapper.properties is never replaced.)
  local g_props="$gen/gradle/wrapper/gradle-wrapper.properties" g_sha g_url
  [ -f "$g_props" ] || die "$EX_GENERATE" "the 'gradle wrapper' task did not produce gradle-wrapper.properties."
  g_sha="$(prop_value "$g_props" distributionSha256Sum)"
  if [ "$g_sha" != "$DIST_SHA256" ]; then
    die "$EX_GENERATE" "the generated gradle-wrapper.properties has distributionSha256Sum '${g_sha:-<missing>}', expected '$DIST_SHA256'."
  fi
  g_url="$(prop_value "$g_props" distributionUrl)"
  if [ "${g_url##*/}" != "$DIST_FILE" ]; then
    die "$EX_GENERATE" "the generated gradle-wrapper.properties references '${g_url##*/}' but the committed one references '$DIST_FILE'."
  fi

  # ---- install atomically (stage next to the destination, then rename) ----------------------
  install -m 755 "$g_gradlew" "$GRADLEW$STAGE_SUFFIX"      || die "$EX_INSTALL" "cannot write to $ANDROID_DIR."
  install -m 644 "$g_bat"     "$GRADLEW_BAT$STAGE_SUFFIX"  || die "$EX_INSTALL" "cannot write to $ANDROID_DIR."
  install -m 644 "$g_jar"     "$WRAPPER_JAR$STAGE_SUFFIX"  || die "$EX_INSTALL" "cannot write to $WRAPPER_DIR."
  mv -f "$WRAPPER_JAR$STAGE_SUFFIX" "$WRAPPER_JAR" \
    && mv -f "$GRADLEW_BAT$STAGE_SUFFIX" "$GRADLEW_BAT" \
    && mv -f "$GRADLEW$STAGE_SUFFIX" "$GRADLEW" \
    || die "$EX_INSTALL" "could not move the generated wrapper files into place."

  log "Official Gradle wrapper files installed into android/ (generated by the real 'gradle wrapper' task of Gradle ${GRADLE_VERSION})."
  log "  gradle-wrapper.jar sha256: $(sha256_of "$WRAPPER_JAR")"
  log "  gradlew            sha256: $(sha256_of "$GRADLEW")"
}

if [ "${FORCE_WRAPPER_REGENERATE:-0}" != "1" ] && wrapper_is_valid; then
  log "A structurally valid Gradle wrapper is already present; not regenerating (set FORCE_WRAPPER_REGENERATE=1 to override)."
else
  generate_and_install
fi

# ---------------------------------------------------------------------------------------------
# 3. Verify: executable bit, jar integrity, and `gradlew --version` must report the expected version
# ---------------------------------------------------------------------------------------------
chmod +x "$GRADLEW" || die "$EX_VERIFY" "cannot make $GRADLEW executable (file-system permissions?)."
[ -x "$GRADLEW" ]  || die "$EX_VERIFY" "$GRADLEW is not executable (file system mounted noexec?)."
jar_is_valid "$WRAPPER_JAR" || die "$EX_VERIFY" "$WRAPPER_JAR is missing or not a valid wrapper archive."

VERSION_OUT=""
VERSION_OK=0
attempt=1
while [ "$attempt" -le 2 ]; do
  if VERSION_OUT="$( cd "$ANDROID_DIR" && ./gradlew --version 2>&1 )"; then VERSION_OK=1; break; fi
  warn "'./gradlew --version' failed (attempt $attempt of 2):"
  printf '%s\n' "$VERSION_OUT" >&2
  attempt=$((attempt + 1))
  [ "$attempt" -le 2 ] && sleep 5
done
[ "$VERSION_OK" -eq 1 ] || die "$EX_VERIFY" "'./gradlew --version' failed. If the output above shows a download error, the wrapper could not fetch the Gradle distribution (network)."

printf '%s\n' "$VERSION_OUT"
if ! printf '%s\n' "$VERSION_OUT" | awk -v want="Gradle $GRADLE_VERSION" '$0 == want { found = 1 } END { exit !found }'; then
  die "$EX_VERIFY" "'./gradlew --version' did not report 'Gradle $GRADLE_VERSION'."
fi

# gradle-wrapper.properties (including distributionSha256Sum) must have been preserved byte for byte.
[ "$(sha256_of "$PROPS")" = "$PROPS_SHA256_BEFORE" ] \
  || die "$EX_VERIFY" "$PROPS was modified during bootstrap; it must never be (distributionSha256Sum would be at risk)."
[ "$(prop_value "$PROPS" distributionSha256Sum)" = "$DIST_SHA256" ] \
  || die "$EX_VERIFY" "distributionSha256Sum is no longer present in $PROPS."

log "OK: android/gradlew reports Gradle $GRADLE_VERSION; wrapper jar is intact; distributionSha256Sum ($DIST_SHA256) is configured and preserved."
