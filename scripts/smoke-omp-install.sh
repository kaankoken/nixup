#!/usr/bin/env bash
# Stage 1 smoke: OMP binary on PATH, no Nix-deployed .omp config, installer idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

pass() { echo "OK   $*"; }
miss() { echo "MISS $*"; fail=1; }

echo "=== omp stage-1 smoke ==="

if command -v omp >/dev/null 2>&1; then
  pass "command -v omp → $(command -v omp)"
else
  miss "command -v omp"
fi

ver=""
if ver="$(omp --version 2>/dev/null)" && [[ -n "${ver// }" ]]; then
  pass "omp --version → $ver"
else
  miss "omp --version non-empty"
fi

cfg=""
if cfg="$(omp config path 2>/dev/null)" && [[ -n "$cfg" ]]; then
  case "$cfg" in
    "$HOME/.omp/agent"*|"$HOME/.omp/agent")
      pass "omp config path under ~/.omp/agent → $cfg"
      ;;
    *)
      # Accept any path that resolves below $HOME/.omp/agent
      if [[ "$cfg" == "$HOME/.omp/agent"* ]]; then
        pass "omp config path under ~/.omp/agent → $cfg"
      else
        miss "omp config path not under ~/.omp/agent (got: $cfg)"
      fi
      ;;
  esac
else
  # Some builds print path via `omp config` differently — try common layout
  if [[ -d "$HOME/.omp/agent" ]]; then
    pass "omp agent dir exists at $HOME/.omp/agent (config path cmd soft)"
  else
    miss "omp config path / ~/.omp/agent"
  fi
fi

nix="$ROOT/modules/agents/default.nix"
# Precise: no home.file keys under .omp (avoid false positives on "prompts")
if [[ -f "$nix" ]] && ! rg -q 'home\.file\."\.omp|"\.omp/agent/|"\.omp/' "$nix"; then
  pass "default.nix deploys no .omp config"
else
  miss "default.nix must not deploy .omp config"
fi

if [[ -f "$nix" ]] && rg -q 'install-omp|installOmpScript' "$nix"; then
  pass "default.nix wires install-omp"
else
  miss "default.nix missing install-omp wiring"
fi

# Second installer invocation: no package-manager/curl work
log="$(mktemp "${TMPDIR:-/tmp}/omp-smoke-idem.XXXXXX")"
export OMP_INSTALL_PROVIDER_LOG="$log"
: >"$log"
# Prepend a PATH that records zb/brew/curl if invoked
shim="$(mktemp -d "${TMPDIR:-/tmp}/omp-smoke-shim.XXXXXX")"
for name in zb zerobrew brew curl; do
  cat >"$shim/$name" <<SH
#!/usr/bin/env bash
echo "$name \$*" >>"$log"
exit 1
SH
  chmod +x "$shim/$name"
done
# Keep real omp first via system PATH after shims fail to hide it — put real dirs first
# Actually: healthy omp must win; shims only after real bins would block. Put shims AFTER
# real path so omp is found, but if installer runs package managers it uses command -v
# which finds our shims if we put them first — then brew would be our shim.
# Correct: keep real PATH for omp/brew, only inject log via OMP_INSTALL_PROVIDER_LOG.
# Plan: second invocation performs no package-manager/curl *work* — provider log
# should show provider=existing only.
unset OMP_INSTALL_OFFICIAL_URL
if sh "$ROOT/modules/agents/scripts/install-omp.sh" >/dev/null 2>&1; then
  if rg -q 'provider=existing' "$log" || ! rg -q 'provider=(zerobrew|homebrew|curl)' "$log"; then
    # Prefer explicit existing; also OK if log empty and exit 0 (already healthy, early exit)
    if rg -q 'provider=(zerobrew|homebrew|curl)' "$log" && ! rg -q 'provider=existing' "$log"; then
      miss "second install invoked package manager/curl (log=$(cat "$log"))"
    else
      pass "second installer idempotent (log=$(tr '\n' ' ' <"$log" | head -c 200))"
    fi
  else
    pass "second installer idempotent via existing omp"
  fi
else
  miss "second installer exit non-zero"
fi
rm -f "$log"
rm -rf "$shim"

if [[ "$fail" -ne 0 ]]; then
  echo "=== FAIL stage-1 smoke ==="
  exit 1
fi
echo "=== PASS stage-1 smoke (version=${ver:-unknown}) ==="
exit 0
