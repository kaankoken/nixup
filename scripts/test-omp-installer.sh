#!/usr/bin/env bash
# Provider-order tests for modules/agents/scripts/install-omp.sh
# Injects only PATH, OMP_INSTALL_OFFICIAL_URL, OMP_INSTALL_PROVIDER_LOG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/modules/agents/scripts/install-omp.sh"
FAIL=0
PASS=0

assert() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name (expected=$(printf %q "$expected") actual=$(printf %q "$actual"))"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name (missing $(printf %q "$needle") in $(printf %q "$haystack"))"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "PASS $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name (unexpected $(printf %q "$needle") in $(printf %q "$haystack"))"
    FAIL=$((FAIL + 1))
  fi
}

if [[ ! -f "$INSTALLER" ]]; then
  echo "FAIL installer missing at $INSTALLER"
  exit 1
fi

write_fail_pkg() {
  local name="$1"
  cat >"$HARNESS_STATE/bin/$name" <<SH
#!/usr/bin/env bash
printf '%s %s\n' "$name" "\$*" >>"\$HARNESS_STATE/log"
exit 1
SH
  chmod +x "$HARNESS_STATE/bin/$name"
}

write_success_pkg() {
  local name="$1"
  cat >"$HARNESS_STATE/bin/$name" <<SH
#!/usr/bin/env bash
printf '%s %s\n' "$name" "\$*" >>"\$HARNESS_STATE/log"
if [[ "\$1" == "install" ]]; then
  cat >"\$HARNESS_STATE/bin/omp" <<'OMP'
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
  echo "omp 0.0.0-test"
  exit 0
fi
exit 0
OMP
  chmod +x "\$HARNESS_STATE/bin/omp"
  exit 0
fi
exit 1
SH
  chmod +x "$HARNESS_STATE/bin/$name"
}

write_curl_success() {
  cat >"$HARNESS_STATE/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$HARNESS_STATE/log"
url=""
out=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    out="$a"
  fi
  case "$a" in
    http://*|https://*) url="$a" ;;
  esac
  prev="$a"
done
printf 'curl_url=%s\n' "$url" >>"$HARNESS_STATE/log"
body='#!/usr/bin/env bash
cat >"$HARNESS_STATE/bin/omp" <<'"'"'OMP'"'"'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "omp 0.0.0-curl"
  exit 0
fi
exit 0
OMP
chmod +x "$HARNESS_STATE/bin/omp"
'
if [[ -n "$out" ]]; then
  printf '%s\n' "$body" >"$out"
else
  printf '%s\n' "$body"
fi
exit 0
SH
  chmod +x "$HARNESS_STATE/bin/curl"
}

write_curl_fail() {
  cat >"$HARNESS_STATE/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$HARNESS_STATE/log"
exit 1
SH
  chmod +x "$HARNESS_STATE/bin/curl"
}

write_healthy_omp() {
  cat >"$HARNESS_STATE/bin/omp" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "omp 1.2.3-existing"
  exit 0
fi
exit 0
SH
  chmod +x "$HARNESS_STATE/bin/omp"
}

make_harness() {
  local dir="$1"
  mkdir -p "$dir/bin" "$dir/state"
  : >"$dir/state/log"
  : >"$dir/state/provider.log"
  # Point log path used by installer; also keep harness log for assertions
  export HARNESS_STATE="$dir"
  export OMP_INSTALL_PROVIDER_LOG="$dir/state/provider.log"
  export OMP_INSTALL_OFFICIAL_URL="https://omp.sh/install-test-url"
  # Isolate PATH: only harness bin + bare essentials
  export PATH="$dir/bin:/usr/bin:/bin"
  # symlink log to state/log for convenience in shims
  ln -sfn "$dir/state/log" "$dir/log" 2>/dev/null || true
  # shims write to $HARNESS_STATE/log — map to state/log
  : >"$dir/log"
  if [[ ! -f "$dir/log" ]]; then
    : >"$dir/state/log"
  fi
  # Always use state/log as HARNESS_STATE/log via file
  rm -f "$dir/log"
  # Make log a real file at HARNESS_STATE/log
  : >"$dir/log"
}

# Ensure shims write to $HARNESS_STATE/log as a file at dir/log
# (dir is HARNESS_STATE)

run_installer() {
  set +e
  # shellcheck disable=SC2094
  env PATH="$PATH" \
    OMP_INSTALL_OFFICIAL_URL="$OMP_INSTALL_OFFICIAL_URL" \
    OMP_INSTALL_PROVIDER_LOG="$OMP_INSTALL_PROVIDER_LOG" \
    HARNESS_STATE="$HARNESS_STATE" \
    sh "$INSTALLER" >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

# --- Case 1: healthy existing omp invokes no installer ---
case1() {
  local d rc log
  d="$(mktemp -d "${TMPDIR:-/tmp}/omp-install-test.XXXXXX")"
  make_harness "$d"
  write_healthy_omp
  write_fail_pkg zb
  write_fail_pkg brew
  write_curl_fail
  : >"$d/log"
  rc="$(run_installer)"
  assert_eq "case1_exit0" "0" "$rc"
  log="$(cat "$d/log" 2>/dev/null || true)"
  assert_not_contains "case1_no_zb" "zb " "$log"
  assert_not_contains "case1_no_brew" "brew " "$log"
  assert_not_contains "case1_no_curl" "curl " "$log"
  rm -rf "$d"
}

# --- Case 2: ZeroBrew succeeds; brew/curl never called ---
case2() {
  local d rc log
  d="$(mktemp -d "${TMPDIR:-/tmp}/omp-install-test.XXXXXX")"
  make_harness "$d"
  write_success_pkg zb
  write_success_pkg brew
  write_curl_success
  rc="$(run_installer)"
  assert_eq "case2_exit0" "0" "$rc"
  log="$(cat "$d/log")"
  assert_contains "case2_zb_install" "zb install omp" "$log"
  assert_not_contains "case2_no_brew" "brew " "$log"
  assert_not_contains "case2_no_curl" "curl " "$log"
  assert "case2_omp_healthy" env PATH="$d/bin:/usr/bin:/bin" omp --version >/dev/null 2>&1
  rm -rf "$d"
}

# --- Case 3: ZeroBrew fails; brew succeeds with exact formula ---
case3() {
  local d rc log
  d="$(mktemp -d "${TMPDIR:-/tmp}/omp-install-test.XXXXXX")"
  make_harness "$d"
  write_fail_pkg zb
  write_success_pkg brew
  write_curl_success
  rc="$(run_installer)"
  assert_eq "case3_exit0" "0" "$rc"
  log="$(cat "$d/log")"
  assert_contains "case3_zb_tried" "zb install omp" "$log"
  assert_contains "case3_brew_formula" "brew install can1357/tap/omp" "$log"
  assert_not_contains "case3_no_curl" "curl " "$log"
  rm -rf "$d"
}

# --- Case 4: both PMs fail; official URL fetched and piped to sh ---
case4() {
  local d rc log
  d="$(mktemp -d "${TMPDIR:-/tmp}/omp-install-test.XXXXXX")"
  make_harness "$d"
  write_fail_pkg zb
  write_fail_pkg brew
  write_curl_success
  rc="$(run_installer)"
  assert_eq "case4_exit0" "0" "$rc"
  log="$(cat "$d/log")"
  assert_contains "case4_curl_url" "https://omp.sh/install-test-url" "$log"
  assert_contains "case4_zb" "zb install omp" "$log"
  assert_contains "case4_brew" "brew install can1357/tap/omp" "$log"
  rm -rf "$d"
}

# --- Case 5: installer exit 0 without healthy omp falls through ---
case5() {
  local d rc log
  d="$(mktemp -d "${TMPDIR:-/tmp}/omp-install-test.XXXXXX")"
  make_harness "$d"
  # Unhealthy omp on PATH so a later refresh of real brew paths cannot
  # short-circuit the fallthrough (command -v prefers harness bin first).
  cat >"$d/bin/omp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$d/bin/omp"
  cat >"$d/bin/zb" <<'SH'
#!/usr/bin/env bash
printf 'zb %s\n' "$*" >>"$HARNESS_STATE/log"
# Claim success without repairing the broken omp.
exit 0
SH
  chmod +x "$d/bin/zb"
  write_success_pkg brew
  write_curl_fail
  rc="$(run_installer)"
  assert_eq "case5_exit0" "0" "$rc"
  log="$(cat "$d/log")"
  assert_contains "case5_zb" "zb install omp" "$log"
  assert_contains "case5_brew_after_zb" "brew install can1357/tap/omp" "$log"
  rm -rf "$d"
}

# --- Case 6: all providers fail → non-zero ---
case6() {
  local d rc
  d="$(mktemp -d "${TMPDIR:-/tmp}/omp-install-test.XXXXXX")"
  make_harness "$d"
  write_fail_pkg zb
  write_fail_pkg brew
  write_curl_fail
  rc="$(run_installer)"
  assert "case6_nonzero" test "$rc" -ne 0
  rm -rf "$d"
}

# --- Case 7: rerun after success is idempotent (no PM/curl work) ---
case7() {
  local d rc log
  d="$(mktemp -d "${TMPDIR:-/tmp}/omp-install-test.XXXXXX")"
  make_harness "$d"
  write_success_pkg zb
  write_success_pkg brew
  write_curl_success
  rc="$(run_installer)"
  assert_eq "case7_first_exit0" "0" "$rc"
  : >"$d/log"
  rc="$(run_installer)"
  assert_eq "case7_second_exit0" "0" "$rc"
  log="$(cat "$d/log")"
  assert_eq "case7_idempotent_empty_log" "" "$log"
  rm -rf "$d"
}

echo "=== test-omp-installer ==="
case1
case2
case3
case4
case5
case6
case7

echo "=== summary pass=$PASS fail=$FAIL ==="
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
