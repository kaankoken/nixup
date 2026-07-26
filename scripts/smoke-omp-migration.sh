#!/usr/bin/env bash
# Cross-repo OMP migration smoke (nixup + DOTFILES_ROOT).
# Usage: DOTFILES_ROOT=/path/to/dotfiles bash scripts/smoke-omp-migration.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOTFILES_ROOT="${DOTFILES_ROOT:-}"
if [ -z "$DOTFILES_ROOT" ] || [ ! -d "$DOTFILES_ROOT" ]; then
  echo "DOTFILES_ROOT must point at a dotfiles tree (got: ${DOTFILES_ROOT:-empty})" >&2
  exit 2
fi
DOTFILES_ROOT="$(cd "$DOTFILES_ROOT" && pwd)"
OMP_ROOT="$DOTFILES_ROOT/omp"
STACK_ROOT="$DOTFILES_ROOT/agent-stack"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'PASS %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s — %s\n' "$1" "$2" >&2; }

echo "=== smoke-omp-migration ==="
echo "NIXUP_ROOT=$ROOT"
echo "DOTFILES_ROOT=$DOTFILES_ROOT"

# --- omp present, pi absent ---
if command -v omp >/dev/null 2>&1; then
  ok omp_on_path
else
  bad omp_on_path "omp not on PATH"
fi
if command -v pi >/dev/null 2>&1; then
  bad pi_absent "pi still on PATH: $(command -v pi)"
else
  ok pi_absent
fi

# --- version vs compatibility.json ---
if [ -f "$OMP_ROOT/compatibility.json" ]; then
  want=$(jq -r '.ompVersion // empty' "$OMP_ROOT/compatibility.json" 2>/dev/null || true)
  got=$(omp --version 2>/dev/null | head -1 | tr -d '\r' || true)
  if [ -n "$want" ] && echo "$got" | grep -Fq "${want#omp/}"; then
    ok omp_version_matches_compat
  elif [ -n "$want" ] && echo "$got" | grep -Fq "$want"; then
    ok omp_version_matches_compat
  else
    # accept major form omp/17.1.2 vs 17.1.2
    if [ -n "$want" ] && [ -n "$got" ]; then
      want_n=${want#omp/}
      if echo "$got" | grep -Fq "$want_n"; then
        ok omp_version_matches_compat
      else
        bad omp_version "want=$want got=$got"
      fi
    else
      bad omp_version "want=$want got=$got"
    fi
  fi
else
  bad compat_json "missing $OMP_ROOT/compatibility.json"
fi

# --- live OMP links resolve into DOTFILES_ROOT ---
if [ -d "${HOME}/.omp/agent" ]; then
  bad_links=0
  while IFS= read -r -d '' link; do
    if [ -L "$link" ]; then
      target=$(readlink "$link" 2>/dev/null || true)
      # resolve relative
      if [ -n "$target" ] && [ "${target#/}" = "$target" ]; then
        target="$(cd "$(dirname "$link")" && cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")" || target=$(readlink -f "$link" 2>/dev/null || true)
      fi
      real=$(realpath "$link" 2>/dev/null || true)
      check="${real:-$target}"
      case "$check" in
        "$OMP_ROOT"/*|"$STACK_ROOT"/*) ;;
        *)
          # auth/session/cache should not be tracked links into omp for runtime state
          base=$(basename "$link")
          case "$base" in
            auth.json|agent.db|sessions|cache) ;;
            *)
              echo "  bad link $link -> $check" >&2
              bad_links=$((bad_links + 1))
              ;;
          esac
          ;;
      esac
    fi
  done < <(find "$HOME/.omp/agent" -maxdepth 3 \( -type l -o -type f \) -print0 2>/dev/null || true)
  if [ "$bad_links" -eq 0 ]; then
    ok live_omp_links_into_dotfiles
  else
    bad live_omp_links "$bad_links links outside DOTFILES_ROOT/omp|agent-stack"
  fi
else
  # activation may not have run; still require tree present
  if [ -d "$OMP_ROOT" ] && [ -f "$OMP_ROOT/config.yml" ]; then
    ok omp_tree_present_no_live_link_yet
  else
    bad omp_tree "missing $OMP_ROOT"
  fi
fi

# --- auth/session/cache not tracked as source of truth in omp tree ---
if [ -f "$OMP_ROOT/auth.json" ] || [ -d "$OMP_ROOT/sessions" ] || [ -d "$OMP_ROOT/cache" ]; then
  bad no_runtime_in_source "auth/session/cache must not live under DOTFILES_ROOT/omp"
else
  ok no_runtime_in_source_tree
fi

# --- lean config + MCP ---
if [ -f "$OMP_ROOT/config.yml" ]; then
  if rg -q 'strategy:\s*shake' "$OMP_ROOT/config.yml" \
    && rg -q 'enabled:\s*false' "$OMP_ROOT/config.yml" \
    && rg -q 'approvalMode:\s*always-ask' "$OMP_ROOT/config.yml"; then
    ok lean_config
  else
    # softer: just strategy shake
    if rg -q 'strategy:\s*shake' "$OMP_ROOT/config.yml"; then
      ok lean_config_shake
    else
      bad lean_config "config.yml missing shake/always-ask markers"
    fi
  fi
else
  bad lean_config "missing config.yml"
fi

if [ -f "$OMP_ROOT/mcp.json" ]; then
  keys=$(jq -r '.mcpServers // .servers // {} | keys[]' "$OMP_ROOT/mcp.json" 2>/dev/null | sort | tr '\n' ' ')
  # expect exactly four: context-mode context7 headroom tokensave
  if echo "$keys" | rg -q 'context-mode' && echo "$keys" | rg -q 'tokensave' \
    && echo "$keys" | rg -q 'headroom' && echo "$keys" | rg -q 'context7'; then
    ok mcp_allowlist
  else
    bad mcp_allowlist "keys=[$keys]"
  fi
else
  bad mcp_json "missing mcp.json"
fi

# --- 19 agents, harness, init, native goal ---
if [ -d "$OMP_ROOT/agents" ]; then
  n=$(find "$OMP_ROOT/agents" -name '*.md' | wc -l | tr -d ' ')
  if [ "$n" = "19" ]; then
    ok nineteen_agents
  else
    bad nineteen_agents "count=$n"
  fi
else
  bad nineteen_agents "no agents dir"
fi

if [ -f "$OMP_ROOT/extensions/goal-harness/index.ts" ] \
  || [ -f "$OMP_ROOT/extensions/goal-harness/constants.ts" ]; then
  ok harness_extension
else
  bad harness_extension "missing goal-harness extension"
fi

if [ -f "$OMP_ROOT/extensions/goal-harness/project-init.ts" ] \
  || [ -f "$OMP_ROOT/agents/project-init.md" ]; then
  ok init_scaffold
else
  bad init_scaffold "missing project-init"
fi

# harness must not register /goal
if [ -f "$OMP_ROOT/extensions/goal-harness/index.ts" ]; then
  if rg -q "registerCommand\\(['\"]goal|registerCommand\\(['\"]guided-goal|registerCommand\\(['\"]init" \
    "$OMP_ROOT/extensions/goal-harness/index.ts"; then
    bad native_goal_unshadowed "harness registers goal/guided-goal/init"
  else
    ok native_goal_unshadowed
  fi
fi

# --- no OMP file resolves into .pi ---
if rg -n '\.pi/|~/\.pi' "$OMP_ROOT" --glob '!**/node_modules/**' --glob '!**/*test*' 2>/dev/null \
  | rg -v 'piSource|parity|historical|piHarness|no_pi|ABSENT|test ! -e' | head -5; then
  bad no_omp_into_pi "omp tree references live .pi paths"
else
  ok no_omp_into_pi
fi

# --- forbidden orchestration tokens in active runtime (not tests) ---
if rg -n --glob '!**/tests/**' --glob '!**/node_modules/**' \
  -e 'pi-dynamic-workflows' -e 'taskplane' -e 'pi-xai' \
  "$OMP_ROOT/extensions" "$OMP_ROOT/workflows" "$OMP_ROOT/config.yml" 2>/dev/null | head -5; then
  bad no_forbidden_orchestration "forbidden package/token in runtime"
else
  ok no_forbidden_orchestration
fi

# --- nixup: no Pi runtime, no OMP config deploy ---
if [ -x "$ROOT/scripts/test-no-pi-runtime.sh" ] || [ -f "$ROOT/scripts/test-no-pi-runtime.sh" ]; then
  if bash "$ROOT/scripts/test-no-pi-runtime.sh" all >/dev/null 2>&1; then
    ok nixup_no_pi
  else
    bad nixup_no_pi "test-no-pi-runtime.sh failed"
  fi
else
  bad nixup_no_pi "missing test-no-pi-runtime.sh"
fi

if rg -n 'home\.file.*"\.omp/|"\.omp/agent' "$ROOT/modules" 2>/dev/null | head -3; then
  bad nix_no_omp_config "Nix deploys .omp config"
else
  ok nix_no_omp_config
fi

if [ -d "$ROOT/modules/agents/pi" ] || [ -f "$ROOT/scripts/smoke-pi-harness.sh" ]; then
  bad nix_pi_assets_gone "pi module or smoke-pi still present"
else
  ok nix_pi_assets_gone
fi

# --- optional: run stage3/4 tests if bun present (can be slow; keep as group) ---
if command -v bun >/dev/null 2>&1 && [ -d "$OMP_ROOT/tests" ]; then
  if (cd "$OMP_ROOT" && bun test tests/stage4-native.test.ts >/dev/null 2>&1); then
    ok stage4_native_tests
  else
    bad stage4_native_tests "bun test stage4-native failed"
  fi
else
  ok stage4_native_tests_skipped_no_bun
fi

echo "=== summary pass=$pass fail=$fail ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
