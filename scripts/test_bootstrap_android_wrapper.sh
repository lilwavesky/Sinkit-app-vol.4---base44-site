#!/usr/bin/env bash
# Offline regression test for scripts/bootstrap_android_wrapper.sh
#
# WHY THIS EXISTS
#   Codemagic build 6b036ee58f52ca27512a5365 failed with
#     "Directory '.../gen' does not contain a Gradle build."
#   because Gradle 9 refuses to run ANY task (including `wrapper`) in a directory that has no
#   settings.gradle[.kts|.dcl]. An earlier test double did not enforce that rule, so the bug was
#   not caught. The double below DOES enforce it, plus the failure modes the bootstrap must handle.
#
# WHAT IT IS (AND IS NOT)
#   * It builds a fake "Gradle distribution" (a TEST DOUBLE of the gradle CLI) inside a private
#     temp directory and serves it through a file:// URL via GRADLE_DISTRIBUTIONS_BASE.
#   * It copies the script under test into a throw-away project skeleton in that temp directory.
#   * NOTHING produced here is ever written into this repository's android/ directory, and the
#     test double is NOT a Gradle wrapper. The real wrapper is only ever produced by the real
#     `gradle wrapper` task of the real, checksum-verified distribution (see the bootstrap script).
#
# Usage:   bash scripts/test_bootstrap_android_wrapper.sh
# Env:     SCRIPT_UNDER_TEST   path of the bootstrap script to test (default: sibling script)
# Exit:    0 = all checks passed, 1 = at least one check failed, 2 = missing prerequisite tool
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_UNDER_TEST:-$HERE/bootstrap_android_wrapper.sh}"
VERSION="9.3.1"

for tool in zip unzip curl awk find cksum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: required tool '$tool' not found" >&2; exit 2; }
done
[ -f "$SCRIPT_UNDER_TEST" ] || { echo "ERROR: script under test not found: $SCRIPT_UNDER_TEST" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/karen-wrapper-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tmp"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "    PASS: $*"; }
bad() { FAIL=$((FAIL + 1)); echo "    FAIL: $*"; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
section() { echo; echo "== $* =="; }

sha256_file() {
  if [ ! -f "$1" ]; then echo "MISSING"; return 0; fi
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# ---------------------------------------------------------------------------------------------
# Test double of the Gradle distribution. Behaviour is switched by MOCK_* environment variables
# that are inherited from the bootstrap script's environment at run time.
# ---------------------------------------------------------------------------------------------
make_dist() { # $1 = server dir ; builds gradle-$VERSION-bin.zip + .sha256 inside it
  local server="$1" src="$WORK/distsrc"
  rm -rf "$src"
  mkdir -p "$src/gradle-$VERSION/bin" "$server"
  cat > "$src/gradle-$VERSION/bin/gradle" <<'MOCK_GRADLE'
#!/usr/bin/env bash
# ===== TEST DOUBLE of the Gradle CLI. Used only by scripts/test_bootstrap_android_wrapper.sh =====
set -eu
[ "${1:-}" = "wrapper" ] || { echo "test double: only the 'wrapper' task is implemented" >&2; exit 2; }
shift
echo "$*" >> "${MOCK_ARGS_LOG:-/dev/null}"
SUM=""; TYPE="bin"; URLARG=""   # the real `gradle wrapper` defaults to the bin distribution
while [ "$#" -gt 0 ]; do
  case "$1" in
    --gradle-distribution-sha256-sum) SUM="$2"; shift 2 ;;
    --distribution-type)              TYPE="$2"; shift 2 ;;
    --gradle-distribution-url)        URLARG="$2"; shift 2 ;;
    --gradle-version)                 shift 2 ;;
    *)                                shift ;;
  esac
done
case "$URLARG" in *-all.zip) TYPE=all ;; *-bin.zip) TYPE=bin ;; esac
[ -z "${MOCK_FORCE_TYPE:-}" ] || TYPE="$MOCK_FORCE_TYPE"

# --- The Gradle 9 rule that broke Codemagic build 6b036ee5...: no settings file => hard error.
if [ ! -f settings.gradle ] && [ ! -f settings.gradle.kts ] && [ ! -f settings.gradle.dcl ]; then
  {
    echo "Directory '$PWD' does not contain a Gradle build."
    echo
    echo "A Gradle build's root directory should contain:"
    echo "  settings.gradle, settings.gradle.kts or settings.gradle.dcl"
  } >&2
  exit 1
fi
[ "${MOCK_FAIL_WRAPPER:-0}" != "1" ] || { echo "simulated: Could not resolve distribution" >&2; exit 1; }

VER="$(basename "$(dirname "$(dirname "$0")")")"; VER="${VER#gradle-}"
mkdir -p gradle/wrapper

# gradlew (double): >4000 bytes, shebang, mentions the jar, refuses to run without it
{
  echo '#!/bin/sh'
  echo '# TEST DOUBLE gradlew. Licensed under the Apache License, Version 2.0 (imitates the real header).'
  i=0; while [ "$i" -lt 120 ]; do echo "# padding line $i ................................................"; i=$((i + 1)); done
  echo 'APP_HOME=$(cd "$(dirname "$0")" && pwd -P)'
  echo 'JAR="$APP_HOME/gradle/wrapper/gradle-wrapper.jar"   # the real file launches this jar'
  echo '[ -s "$JAR" ] || { echo "Error: Could not find gradle-wrapper.jar" >&2; exit 1; }'
  echo 'if [ "${1:-}" = "--version" ]; then'
  echo '  echo; echo "------------------------------------------------------------"'
  echo "  echo 'Gradle ${MOCK_REPORTED_VERSION:-$VER}'"
  echo '  echo "------------------------------------------------------------"; exit 0'
  echo 'fi'
  echo 'exit 0'
} > gradlew
{ echo '@rem TEST DOUBLE gradlew.bat'; i=0; while [ "$i" -lt 40 ]; do echo "@rem padding line $i ........................................"; i=$((i + 1)); done; } > gradlew.bat

if [ "${MOCK_OMIT_JAR:-0}" != "1" ]; then
  if [ "${MOCK_CORRUPT_JAR:-0}" = "1" ]; then
    head -c 20000 /dev/urandom > gradle/wrapper/gradle-wrapper.jar
  else
    j="$(mktemp -d)"; mkdir -p "$j/org/gradle/wrapper"
    printf 'not-a-real-class' > "$j/org/gradle/wrapper/GradleWrapperMain.class"
    head -c 20000 /dev/urandom > "$j/padding.bin"
    ( cd "$j" && zip -q -0 -r wrapper.jar org padding.bin )
    mv "$j/wrapper.jar" gradle/wrapper/gradle-wrapper.jar; rm -rf "$j"
  fi
fi
{
  echo 'distributionBase=GRADLE_USER_HOME'
  echo 'distributionPath=wrapper/dists'
  if [ -n "$SUM" ] && [ "${MOCK_DROP_SHA:-0}" != "1" ]; then
    if [ "${MOCK_WRONG_SHA:-0}" = "1" ]; then echo 'distributionSha256Sum=1111111111111111111111111111111111111111111111111111111111111111'
    else echo "distributionSha256Sum=$SUM"; fi
  fi
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-%s.zip\n' "$VER" "$TYPE"
  echo 'zipStoreBase=GRADLE_USER_HOME'
  echo 'zipStorePath=wrapper/dists'
} > gradle/wrapper/gradle-wrapper.properties
echo "BUILD SUCCESSFUL (test double)"
MOCK_GRADLE
  chmod +x "$src/gradle-$VERSION/bin/gradle"
  ( cd "$src" && zip -q -r "$server/gradle-$VERSION-bin.zip" "gradle-$VERSION" )
  sha256_file "$server/gradle-$VERSION-bin.zip" > "$server/gradle-$VERSION-bin.zip.sha256"
}

SERVER="$WORK/server";            make_dist "$SERVER"
# Stand-in for gradle-$VERSION-all.zip: only its published checksum is ever fetched (the 230 MB archive is
# downloaded by the wrapper itself at `gradlew --version`, which the double does not emulate).
head -c 4096 /dev/urandom > "$WORK/fake-all.bin"
ALL_SUM="$(sha256_file "$WORK/fake-all.bin")"
BIN_SUM="$(tr -d '[:space:]' < "$SERVER/gradle-$VERSION-bin.zip.sha256")"
echo "$ALL_SUM" > "$SERVER/gradle-$VERSION-all.zip.sha256"
WRONG_SUM="2222222222222222222222222222222222222222222222222222222222222222"
BAD_SUM="$WORK/server_badsum";    mkdir -p "$BAD_SUM"
cp "$SERVER/gradle-$VERSION-bin.zip" "$BAD_SUM/"
echo "0000000000000000000000000000000000000000000000000000000000000000" > "$BAD_SUM/gradle-$VERSION-bin.zip.sha256"
JUNK_SUM="$WORK/server_junksum";  mkdir -p "$JUNK_SUM"
cp "$SERVER/gradle-$VERSION-bin.zip" "$JUNK_SUM/"
echo "this is not a checksum" > "$JUNK_SUM/gradle-$VERSION-bin.zip.sha256"
CORRUPT="$WORK/server_corrupt";   mkdir -p "$CORRUPT"
head -c 50000 /dev/urandom > "$CORRUPT/gradle-$VERSION-bin.zip"
sha256_file "$CORRUPT/gradle-$VERSION-bin.zip" > "$CORRUPT/gradle-$VERSION-bin.zip.sha256"
for d in "$BAD_SUM" "$JUNK_SUM" "$CORRUPT"; do cp "$SERVER/gradle-$VERSION-all.zip.sha256" "$d/"; done

new_project() { # $1 = dir name (may contain spaces / '#') ; $2 = distributionSha256Sum ('-' = omit; default: the -all sum) ; $3 = all|bin
  local p="$WORK/$1" sum="${2-$ALL_SUM}" type="${3:-all}"
  mkdir -p "$p/scripts" "$p/android/gradle/wrapper"
  cp "$SCRIPT_UNDER_TEST" "$p/scripts/bootstrap_android_wrapper.sh"
  {
    echo 'distributionBase=GRADLE_USER_HOME'
    echo 'distributionPath=wrapper/dists'
    if [ "$sum" != "-" ]; then echo "distributionSha256Sum=$sum"; fi
    echo "distributionUrl=https\\://services.gradle.org/distributions/gradle-$VERSION-$type.zip"
    echo 'zipStoreBase=GRADLE_USER_HOME'
    echo 'zipStorePath=wrapper/dists'
  } > "$p/android/gradle/wrapper/gradle-wrapper.properties"
  printf '%s' "$p"
}

RC=0
run_bs() { # $1 = project dir ; remaining args = extra VAR=value environment assignments
  local proj="$1"; shift
  env GRADLE_DISTRIBUTIONS_BASE="file://$SERVER" TMPDIR="$WORK/tmp" "$@" \
    bash "$proj/scripts/bootstrap_android_wrapper.sh" > "$WORK/last.log" 2>&1
  RC=$?
}
log_has()    { grep -q -- "$1" "$WORK/last.log"; }
banner_ok()  { grep -qx "Gradle $VERSION" "$WORK/last.log"; }   # whole line, as printed by `gradlew --version`
same_sum()   { [ "$2" != "MISSING" ] && [ "$(sha256_file "$1")" = "$2" ]; }
same_inode() { [ -n "$2" ] && [ "$(ls -i "$1" 2>/dev/null | awk '{print $1}')" = "$2" ]; }
no_leaks()   { [ -z "$(ls -A "$WORK/tmp" 2>/dev/null)" ]; }
jar_ok()     { unzip -tq "$1/android/gradle/wrapper/gradle-wrapper.jar" >/dev/null 2>&1; }
no_wrapper() { [ ! -e "$1/android/gradlew" ] && [ ! -e "$1/android/gradlew.bat" ] && [ ! -e "$1/android/gradle/wrapper/gradle-wrapper.jar" ]; }
no_staging() { [ -z "$(find "$1/android" -name '*.new.*' 2>/dev/null)" ]; }
show_log()   { sed 's/^/        | /' "$WORK/last.log" | tail -n 25; }

# =============================================================================================
section "1. fresh project (path with spaces and '#'): generation in a VALID Gradle build dir"
P="$(new_project 'proj with space#1')"
PROPS_SUM="$(sha256_file "$P/android/gradle/wrapper/gradle-wrapper.properties")"
ARGS_LOG="$WORK/args.log"; : > "$ARGS_LOG"
run_bs "$P" MOCK_ARGS_LOG="$ARGS_LOG"
check "exit code 0" test "$RC" -eq 0
[ "$RC" -eq 0 ] || show_log
check "gradlew installed and executable"          test -x "$P/android/gradlew"
check "gradlew.bat installed"                      test -f "$P/android/gradlew.bat"
check "gradle-wrapper.jar installed and is a valid zip" jar_ok "$P"
check "gradle-wrapper.properties untouched"        same_sum "$P/android/gradle/wrapper/gradle-wrapper.properties" "$PROPS_SUM"
check "'gradlew --version' output has the line 'Gradle $VERSION'" banner_ok
check "published SHA-256 was verified"             log_has "SHA-256 verified"
check "no temp directories leaked"                 no_leaks
check "no staging files left behind"               no_staging "$P"
check "--gradle-version and --gradle-distribution-url are not combined" \
  test -z "$(grep -e '--gradle-version' "$ARGS_LOG" | grep -e '--gradle-distribution-url')"

# =============================================================================================
section "2. idempotence: a valid wrapper must not be touched or re-downloaded"
GW_SUM="$(sha256_file "$P/android/gradlew")"; JAR_SUM="$(sha256_file "$P/android/gradle/wrapper/gradle-wrapper.jar")"
GW_INODE="$(ls -i "$P/android/gradlew" | awk '{print $1}')"; JAR_INODE="$(ls -i "$P/android/gradle/wrapper/gradle-wrapper.jar" | awk '{print $1}')"
check "precondition: section 1 produced a wrapper" test -f "$P/android/gradlew" -a -f "$P/android/gradle/wrapper/gradle-wrapper.jar"
mv "$SERVER" "$SERVER.offline"          # any download attempt would now fail
run_bs "$P"
mv "$SERVER.offline" "$SERVER"
check "exit code 0 with the download server unavailable" test "$RC" -eq 0
[ "$RC" -eq 0 ] || show_log
check "reports that the wrapper is already present"     log_has "already present"
check "gradlew content unchanged"  same_sum "$P/android/gradlew" "$GW_SUM"
check "jar content unchanged"      same_sum "$P/android/gradle/wrapper/gradle-wrapper.jar" "$JAR_SUM"
check "gradlew not rewritten (same inode)" same_inode "$P/android/gradlew" "$GW_INODE"
check "jar not rewritten (same inode)"     same_inode "$P/android/gradle/wrapper/gradle-wrapper.jar" "$JAR_INODE"
check "gradlew --version still verified"   banner_ok

# =============================================================================================
section "3. broken/partial wrapper is repaired"
rm -f "$P/android/gradle/wrapper/gradle-wrapper.jar"
run_bs "$P"
check "missing jar -> regenerated (exit 0)" test "$RC" -eq 0
check "jar present and valid again"        jar_ok "$P"
head -c 5000 /dev/urandom > "$P/android/gradle/wrapper/gradle-wrapper.jar"
run_bs "$P"
check "corrupt jar -> regenerated (exit 0)" test "$RC" -eq 0
check "jar valid again"                    jar_ok "$P"
printf '#!/bin/sh\necho "hand-written stub"\n' > "$P/android/gradlew"
run_bs "$P"
check "hand-written stub gradlew -> replaced by generated one" test "$RC" -eq 0
check "stub content is gone"               test -z "$(grep -l 'hand-written stub' "$P/android/gradlew" 2>/dev/null)"

# =============================================================================================
section "4. FORCE_WRAPPER_REGENERATE=1"
run_bs "$P" FORCE_WRAPPER_REGENERATE=1
check "exit code 0"                         test "$RC" -eq 0
check "downloaded again"                    log_has "Downloading official Gradle"

# =============================================================================================
section "5. failure handling (exit codes: 2 config, 3 network, 4 checksum, 5 extract, 6 generate, 8 verify)"
P="$(new_project 'p_badsum')";   run_bs "$P" GRADLE_DISTRIBUTIONS_BASE="file://$BAD_SUM"
check "checksum mismatch -> exit 4"        test "$RC" -eq 4
check "mismatch message printed"           log_has "mismatch"
check "nothing installed after mismatch"   no_wrapper "$P"

P="$(new_project 'p_junksum')";  run_bs "$P" GRADLE_DISTRIBUTIONS_BASE="file://$JUNK_SUM"
check "malformed .sha256 content -> exit 4" test "$RC" -eq 4
check "nothing installed"                   no_wrapper "$P"

P="$(new_project 'p_pin')";      run_bs "$P" GRADLE_DISTRIBUTION_SHA256=1111111111111111111111111111111111111111111111111111111111111111
check "pinned checksum != published -> exit 4" test "$RC" -eq 4
check "nothing installed"                   no_wrapper "$P"

P="$(new_project 'p_pin_ok')";   run_bs "$P" GRADLE_DISTRIBUTION_SHA256="$(sha256_file "$SERVER/gradle-$VERSION-bin.zip" | tr 'a-f' 'A-F')"
check "matching pinned checksum (upper-case input) accepted" test "$RC" -eq 0

P="$(new_project 'p_nonet')";    run_bs "$P" GRADLE_DISTRIBUTIONS_BASE="file://$WORK/does-not-exist"
check "download failure -> exit 3"         test "$RC" -eq 3
check "nothing installed"                   no_wrapper "$P"
check "no temp directories leaked"          no_leaks

P="$(new_project 'p_corrupt')";  run_bs "$P" GRADLE_DISTRIBUTIONS_BASE="file://$CORRUPT"
check "corrupt archive (valid checksum) -> exit 5" test "$RC" -eq 5
check "nothing installed"                   no_wrapper "$P"

P="$(new_project 'p_genfail')";  run_bs "$P" MOCK_FAIL_WRAPPER=1
check "gradle wrapper task failure -> exit 6" test "$RC" -eq 6
check "nothing installed"                   no_wrapper "$P"

P="$(new_project 'p_nojar')";    run_bs "$P" MOCK_OMIT_JAR=1
check "wrapper task produced no jar -> exit 6" test "$RC" -eq 6
check "nothing installed (no partial wrapper)" no_wrapper "$P"

P="$(new_project 'p_badjar')";   run_bs "$P" MOCK_CORRUPT_JAR=1
check "generated jar not a valid archive -> exit 6" test "$RC" -eq 6
check "nothing installed"                   no_wrapper "$P"

P="$(new_project 'p_badver')";   run_bs "$P" MOCK_REPORTED_VERSION=9.0.0
check "gradlew reports wrong version -> exit 8" test "$RC" -eq 8

P="$(new_project 'p_vermismatch')"; run_bs "$P" GRADLE_VERSION=9.0.0
check "GRADLE_VERSION differs from gradle-wrapper.properties -> exit 2" test "$RC" -eq 2

P="$(new_project 'p_noprops')";  rm -f "$P/android/gradle/wrapper/gradle-wrapper.properties"; run_bs "$P"
check "missing gradle-wrapper.properties -> exit 2" test "$RC" -eq 2

if [ "$(id -u)" -eq 0 ]; then
  echo "    SKIP: read-only target directory check (running as root; permissions are not enforced)"
else
  P="$(new_project 'p_readonly')"; chmod a-w "$P/android" "$P/android/gradle/wrapper"; run_bs "$P"
  chmod u+w "$P/android" "$P/android/gradle/wrapper"
  check "unwritable android/ -> exit 7 before any download" test "$RC" -eq 7
fi
check "no temp directories leaked by any failure path" no_leaks

# =============================================================================================
section "6. Java prerequisite (Gradle 9 needs Java 17+): version parsing and early, clear failure"
fake_jdk() { # $1 = dir name, $2 = text of the first line of `java -version`
  mkdir -p "$WORK/$1/bin"
  printf '#!/bin/sh\necho '"'"'%s'"'"' >&2\necho "Runtime Environment (fake)" >&2\n' "$2" > "$WORK/$1/bin/java"
  chmod +x "$WORK/$1/bin/java"
  printf '%s' "$WORK/$1"
}
J="$(fake_jdk jdk8  'java version "1.8.0_392"')"
P="$(new_project 'p_java8')";  run_bs "$P" JAVA_HOME="$J"
check "Java 1.8 rejected -> exit 9"  test "$RC" -eq 9
check "message names the Java version" log_has "Java 8 found"
check "rejected before any download"  no_wrapper "$P"
J="$(fake_jdk jdk11 'openjdk version "11.0.2" 2019-01-15')"
P="$(new_project 'p_java11')"; run_bs "$P" JAVA_HOME="$J"
check "Java 11 rejected -> exit 9"   test "$RC" -eq 9
for v in '17' '17.0.12' '21-ea' '21.0.12.1'; do
  J="$(fake_jdk "jdk_ok" "openjdk version \"$v\" 2026-01-01")"
  P="$(new_project "p_java_$v")"; run_bs "$P" JAVA_HOME="$J"
  check "Java version string '$v' accepted" test "$RC" -eq 0
done
check "no temp directories leaked" no_leaks

# =============================================================================================
section "7. distributionSha256Sum: required, exact distribution type, forwarded to the wrapper task, preserved"
PROPS_REL="android/gradle/wrapper/gradle-wrapper.properties"
args_has()      { grep -q -- "$1" "$ARGS_LOG"; }
args_lacks()    { ! grep -q -e "$1" "$ARGS_LOG"; }
no_download()   { ! grep -q 'Downloading official Gradle' "$WORK/last.log"; }
props_same()    { same_sum "$1/$PROPS_REL" "$2"; }

echo "  -- 7a. valid configuration: value forwarded with --gradle-distribution-sha256-sum, properties preserved"
P="$(new_project 'p_sum_ok')"; B="$(sha256_file "$P/$PROPS_REL")"; : > "$ARGS_LOG"
run_bs "$P" MOCK_ARGS_LOG="$ARGS_LOG"
check "exit code 0"                                                  test "$RC" -eq 0
[ "$RC" -eq 0 ] || show_log
check "cross-check against the published -all.zip checksum logged"   log_has "published for gradle-$VERSION-all.zip"
check "wrapper task received --gradle-distribution-sha256-sum <configured value>" args_has "--gradle-distribution-sha256-sum $ALL_SUM"
check "the sum flag was passed exactly once"                         test "$(grep -o -e '--gradle-distribution-sha256-sum' "$ARGS_LOG" | wc -l | tr -d ' ')" -eq 1
check "gradle-wrapper.properties byte-identical after generation"    props_same "$P" "$B"
check "distributionSha256Sum line still present with the exact value" grep -qx "distributionSha256Sum=$ALL_SUM" "$P/$PROPS_REL"
check "completion message names the preserved checksum"              log_has "distributionSha256Sum ($ALL_SUM) is configured and preserved"
run_bs "$P"
check "idempotent re-run keeps properties byte-identical"            props_same "$P" "$B"
: > "$ARGS_LOG"; run_bs "$P" FORCE_WRAPPER_REGENERATE=1 MOCK_ARGS_LOG="$ARGS_LOG"
check "forced regeneration: exit code 0"                             test "$RC" -eq 0
check "forced regeneration keeps properties byte-identical"          props_same "$P" "$B"
check "forced regeneration passes the checksum to the wrapper task again" args_has "--gradle-distribution-sha256-sum $ALL_SUM"
rm -f "$P/android/gradle/wrapper/gradle-wrapper.jar"; run_bs "$P"
check "repair of a missing jar keeps properties byte-identical"      props_same "$P" "$B"

echo "  -- 7b. default download URL (services.gradle.org, via curl shim): --gradle-version + type + sum, never --gradle-distribution-url"
SHIM="$WORK/shimbin"; mkdir -p "$SHIM"; REAL_CURL="$(command -v curl)"
cat > "$SHIM/curl" <<SHIMEOF
#!/bin/sh
# test shim: serves the official download URLs from the local test server, everything else untouched
n=\$#; i=0
while [ "\$i" -lt "\$n" ]; do
  a="\$1"; shift
  case "\$a" in https://services.gradle.org/distributions/*) a="file://$SERVER/\${a#https://services.gradle.org/distributions/}" ;; esac
  set -- "\$@" "\$a"; i=\$((i + 1))
done
exec "$REAL_CURL" "\$@"
SHIMEOF
chmod +x "$SHIM/curl"
P="$(new_project 'p_default_mode')"; B="$(sha256_file "$P/$PROPS_REL")"; : > "$ARGS_LOG"
run_bs "$P" PATH="$SHIM:$PATH" GRADLE_DISTRIBUTIONS_BASE=https://services.gradle.org/distributions MOCK_ARGS_LOG="$ARGS_LOG"
check "exit code 0 in default-URL mode"                              test "$RC" -eq 0
[ "$RC" -eq 0 ] || show_log
check "passed --gradle-version $VERSION"                             args_has "--gradle-version $VERSION"
check "passed --distribution-type all (type of distributionUrl)"     args_has "--distribution-type all"
check "passed --gradle-distribution-sha256-sum <configured value>"   args_has "--gradle-distribution-sha256-sum $ALL_SUM"
check "did not pass --gradle-distribution-url"                       args_lacks "--gradle-distribution-url"
check "properties byte-identical"                                    props_same "$P" "$B"

echo "  -- 7c. the checksum must belong to the exact distribution type named by distributionUrl"
P="$(new_project 'p_bin_sum_for_all' "$BIN_SUM")"; B="$(sha256_file "$P/$PROPS_REL")"; run_bs "$P"
check "bin.zip checksum configured for an all.zip URL -> exit 4"     test "$RC" -eq 4
check "message explains the bin/all confusion"                       log_has "checksum of the -bin.zip, but distributionUrl points to the -all.zip"
check "rejected BEFORE the large download"                           no_download
check "nothing installed"                                            no_wrapper "$P"
check "properties untouched"                                         props_same "$P" "$B"

P="$(new_project 'p_all_sum_for_bin' "$ALL_SUM" bin)"; B="$(sha256_file "$P/$PROPS_REL")"; run_bs "$P"
check "all.zip checksum configured for a bin.zip URL -> exit 4"      test "$RC" -eq 4
check "message explains the all/bin confusion"                       log_has "checksum of the -all.zip, but distributionUrl points to the -bin.zip"
check "rejected BEFORE the large download"                           no_download
check "properties untouched"                                         props_same "$P" "$B"

P="$(new_project 'p_bin_ok' "$BIN_SUM" bin)"; : > "$ARGS_LOG"; run_bs "$P" MOCK_ARGS_LOG="$ARGS_LOG"
check "bin.zip URL with the bin.zip checksum -> exit 0"              test "$RC" -eq 0
check "wrapper task got the bin checksum and the -bin.zip URL"       args_has "--gradle-distribution-sha256-sum $BIN_SUM"
check "the -bin.zip URL was used"                                    args_has "gradle-$VERSION-bin.zip"

P="$(new_project 'p_wrong_sum' "$WRONG_SUM")"; B="$(sha256_file "$P/$PROPS_REL")"; run_bs "$P"
check "well-formed but wrong checksum -> exit 4"                     test "$RC" -eq 4
check "message shows configured and published values"                log_has "does not match the checksum Gradle publishes for gradle-$VERSION-all.zip ($ALL_SUM)"
check "no bin/all hint for a plainly wrong value"                    test -z "$(grep 'wrong distribution type' "$WORK/last.log")"
check "rejected BEFORE the large download"                           no_download
check "nothing installed"                                            no_wrapper "$P"
check "properties untouched"                                         props_same "$P" "$B"

echo "  -- 7d. distributionSha256Sum is mandatory and strictly formatted (exit 2)"
P="$(new_project 'p_nosum' -)";           run_bs "$P"
check "missing distributionSha256Sum -> exit 2"                      test "$RC" -eq 2
check "message names the property and the release-checksums page"    log_has "https://gradle.org/release-checksums/"
check "nothing installed, nothing downloaded"                        no_wrapper "$P"
P="$(new_project 'p_shortsum' abc123)";   run_bs "$P"
check "too-short checksum -> exit 2"                                 test "$RC" -eq 2
P="$(new_project 'p_upper' "$(printf '%s' "$ALL_SUM" | tr 'a-f' 'A-F')")"; run_bs "$P"
check "upper-case checksum -> exit 2 (must be lower-case)"           test "$RC" -eq 2
P="$(new_project 'p_nonhex' gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg)"; run_bs "$P"
check "non-hexadecimal checksum -> exit 2"                           test "$RC" -eq 2
check "nothing installed by any malformed configuration"             no_wrapper "$P"

echo "  -- 7e. cannot validate the configured checksum -> fail closed"
NOALL="$WORK/server_noall"; mkdir -p "$NOALL"; cp "$SERVER/gradle-$VERSION-bin.zip" "$SERVER/gradle-$VERSION-bin.zip.sha256" "$NOALL/"
P="$(new_project 'p_noall')"; run_bs "$P" GRADLE_DISTRIBUTIONS_BASE="file://$NOALL"
check "-all.zip.sha256 unavailable -> exit 3 (never trusts an unverifiable value)" test "$RC" -eq 3
check "nothing installed"                                            no_wrapper "$P"
check "no download of the large archive"                             no_download
JUNKALL="$WORK/server_junkall"; mkdir -p "$JUNKALL"; cp "$NOALL"/* "$JUNKALL/"; echo "not a checksum" > "$JUNKALL/gradle-$VERSION-all.zip.sha256"
P="$(new_project 'p_junkall')"; run_bs "$P" GRADLE_DISTRIBUTIONS_BASE="file://$JUNKALL"
check "malformed published -all.zip.sha256 -> exit 4"                test "$RC" -eq 4

echo "  -- 7f. the generated properties must carry the same checksum and archive as the committed ones"
P="$(new_project 'p_gen_nosum')"; B="$(sha256_file "$P/$PROPS_REL")"; run_bs "$P" MOCK_DROP_SHA=1
check "wrapper task dropped distributionSha256Sum -> exit 6"         test "$RC" -eq 6
check "nothing installed"                                            no_wrapper "$P"
check "properties untouched"                                         props_same "$P" "$B"
P="$(new_project 'p_gen_wrongsum')"; run_bs "$P" MOCK_WRONG_SHA=1
check "wrapper task changed distributionSha256Sum -> exit 6"         test "$RC" -eq 6
check "nothing installed"                                            no_wrapper "$P"
P="$(new_project 'p_gen_wrongtype')"; run_bs "$P" MOCK_FORCE_TYPE=bin
check "generated properties reference the other archive type -> exit 6" test "$RC" -eq 6
check "message names both archives"                                  log_has "references 'gradle-$VERSION-bin.zip' but the committed one references 'gradle-$VERSION-all.zip'"
check "nothing installed"                                            no_wrapper "$P"

echo "  -- 7g. generator pin: GRADLE_BIN_DISTRIBUTION_SHA256 pins the -bin.zip only (GRADLE_DISTRIBUTION_SHA256 = deprecated alias)"
P="$(new_project 'p_binpin_bad')"; run_bs "$P" GRADLE_BIN_DISTRIBUTION_SHA256="$WRONG_SUM"
check "wrong bin pin -> exit 4"                                      test "$RC" -eq 4
check "message talks about the pinned value"                         log_has "pinned GRADLE_BIN_DISTRIBUTION_SHA256"
P="$(new_project 'p_binpin_all')"; run_bs "$P" GRADLE_BIN_DISTRIBUTION_SHA256="$ALL_SUM"
check "all.zip checksum used as the bin pin -> exit 4"               test "$RC" -eq 4
P="$(new_project 'p_binpin_ok')"; run_bs "$P" GRADLE_BIN_DISTRIBUTION_SHA256="$BIN_SUM"
check "correct bin pin -> exit 0"                                    test "$RC" -eq 0
P="$(new_project 'p_alias')";     run_bs "$P" GRADLE_DISTRIBUTION_SHA256="$BIN_SUM"
check "deprecated alias still honoured -> exit 0"                    test "$RC" -eq 0
check "deprecated alias prints a warning"                            log_has "GRADLE_DISTRIBUTION_SHA256 is deprecated"

echo "  -- 7h. the repository's REAL gradle-wrapper.properties is accepted by the bootstrap (format/type/version consistency)"
REPO_PROPS="$HERE/../$PROPS_REL"
if [ -f "$REPO_PROPS" ]; then
  REPO_SUM="$(grep -E '^distributionSha256Sum=' "$REPO_PROPS" | tail -n 1 | cut -d= -f2- | tr -d '\r')"
  check "real file declares distributionSha256Sum as 64 lowercase hex characters" test "${#REPO_SUM}" -eq 64 -a -z "$(printf '%s' "$REPO_SUM" | tr -d '0-9a-f')"
  check "real file's checksum is not the bin.zip checksum of the test fixture (sanity)" test "$REPO_SUM" != "$BIN_SUM"
  REAL="$WORK/server_real"; mkdir -p "$REAL"; cp "$SERVER"/* "$REAL/"; printf '%s\n' "$REPO_SUM" > "$REAL/gradle-$VERSION-all.zip.sha256"
  P="$(new_project 'p_real_props')"; cp "$REPO_PROPS" "$P/$PROPS_REL"; B="$(sha256_file "$P/$PROPS_REL")"; : > "$ARGS_LOG"
  run_bs "$P" GRADLE_DISTRIBUTIONS_BASE="file://$REAL" MOCK_ARGS_LOG="$ARGS_LOG"
  check "bootstrap accepts the real properties file (exit 0) when the published -all checksum equals it" test "$RC" -eq 0
  [ "$RC" -eq 0 ] || show_log
  check "the real file's checksum is what gets forwarded to the wrapper task" args_has "--gradle-distribution-sha256-sum $REPO_SUM"
  check "the real properties file is preserved byte for byte"       props_same "$P" "$B"
else
  bad "repository gradle-wrapper.properties not found at $REPO_PROPS"
fi
check "no temp directories leaked by any section-7 path"             no_leaks

# =============================================================================================
echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
