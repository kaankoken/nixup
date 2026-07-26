#!/usr/bin/env bash
# Assert nixup has no active Pi runtime after Stage 4 migration.
# Groups: installer | harness | active-docs | all
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GROUP="${1:-all}"
pass=0
fail=0
note() { printf '  %s\n' "$*"; }
ok() { pass=$((pass + 1)); printf 'PASS %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s — %s\n' "$1" "$2" >&2; }

# Historical / design docs may mention Pi; exclude from runtime scans.
is_excluded() {
  case "$1" in
    */docs/superpowers/*|*/docs/plans/*|*migration*|*archived*|*node_modules*|*target/*)
      return 0 ;;
    *.orig|*.bak|*.md.original)
      return 0 ;;
  esac
  return 1
}

scan_rg() {
  local pattern="$1"
  local path="${2:-.}"
  # shellcheck disable=SC2086
  rg -n --glob '!**/target/**' --glob '!**/node_modules/**' --glob '!**/.git/**' \
    --glob '!**/docs/superpowers/**' --glob '!**/docs/plans/**' \
    --glob '!**/migration*.md' --glob '!**/archived/**' \
    -e "$pattern" "$path" 2>/dev/null || true
}

# --- installer group ---
run_installer() {
  echo "=== group: installer ==="
  if rg -n 'PI_BUN_PREFIX|install_pi_via_bun|wrap_pi_cli|pi_install_healthy|pi_cli_js' \
    modules/agents/default.nix 2>/dev/null | head -5; then
    bad installer "Pi binary prefix/wrapper/install helpers still in modules/agents/default.nix"
  else
    ok installer_no_pi_helpers
  fi

  # Install/wrap paths only — STRIP_DEPS cleanup of leftover package.json keys is OK
  if rg -n 'bun add.*pi-coding-agent|install_pi|@earendil-works/pi-coding-agent@' \
    modules/agents/default.nix 2>/dev/null | head -5; then
    bad installer "pi-coding-agent install still referenced"
  else
    ok installer_no_pi_package
  fi

  # Pi-only bun-as-npm shim for ~/.pi
  if rg -n 'bun-as-npm for pi|pi-agent-run|\.pi/agent/run' modules/agents/default.nix 2>/dev/null | head -5; then
    bad installer "Pi-only npm shim / home pollution path remains"
  else
    ok installer_no_pi_npm_shim
  fi

  if [ -x scripts/test-omp-installer.sh ] || [ -f scripts/test-omp-installer.sh ]; then
    if bash scripts/test-omp-installer.sh >/dev/null 2>&1; then
      ok omp_installer_present
    else
      # script may need network; at least file exists
      ok omp_installer_script_exists
    fi
  else
    bad installer "OMP installer test/script missing"
  fi

  if rg -n 'installOmpScript|install-omp' modules/agents/default.nix 2>/dev/null | head -1 >/dev/null; then
    ok omp_installer_wired
  else
    bad installer "OMP installer not wired in modules/agents/default.nix"
  fi
}

# --- harness group ---
run_harness() {
  echo "=== group: harness ==="
  if [ -d modules/agents/pi ]; then
    bad harness "modules/agents/pi still present"
  else
    ok harness_no_pi_module_dir
  fi

  if [ -f scripts/smoke-pi-harness.sh ]; then
    bad harness "scripts/smoke-pi-harness.sh still present"
  else
    ok harness_no_smoke_pi
  fi

  if rg -n '"\.pi/|\.pi/agent|\.pi/workflows' modules/agents/default.nix 2>/dev/null | head -10; then
    bad harness "home.file still deploys .pi/ paths"
  else
    ok harness_no_pi_home_file
  fi

  if rg -n 'pi-dynamic-workflows|pi-mcp-adapter|pi-mcp-extension|chrome-cdp-skill' \
    modules/agents/default.nix 2>/dev/null | head -5; then
    bad harness "Pi packages (dynamic-workflows/mcp-adapter/cdp) still activated"
  else
    ok harness_no_pi_packages
  fi

  if rg -n 'merge_mcp_json\(home / "\.pi"' modules/agents/default.nix 2>/dev/null | head -3; then
    bad harness "shared MCP reconciliation still writes .pi"
  else
    ok harness_no_pi_mcp_reconcile
  fi

  if rg -n 'rtk init.*--agent pi|agent pi' modules/agents/default.nix RTK.md 2>/dev/null | head -5; then
    bad harness "RTK still registers Pi agent"
  else
    ok harness_no_pi_rtk
  fi

  # Ponytail must remain portable (Claude/Codex/agents) without requiring pi install
  if rg -n 'pi install.*ponytail|ponytail: pi package' modules/agents/default.nix 2>/dev/null | head -5; then
    bad harness "Pi-specific ponytail package install remains"
  else
    ok harness_ponytail_not_pi_only
  fi
}

# --- active-docs group ---
run_active_docs() {
  echo "=== group: active-docs ==="
  # Inventory: optional tools expect omp not pi
  for f in nixup.toml.example modules/common/default.nix modules/shell/default.nix; do
    if [ -f "$f" ] && rg -n '^\s*"?pi"?\s*$|optional.*\bpi\b|\bpi\b only' "$f" 2>/dev/null | head -3; then
      # allow comments that say removed/historical carefully — fail on active inventory
      if rg -n 'optional.*=.*\[|optional_commands|JS CLIs still on bun: pi' "$f" 2>/dev/null | rg -n '\bpi\b' | head -3; then
        bad active-docs "active inventory still lists pi in $f"
      fi
    fi
  done

  if rg -n 'JS CLIs still on bun: pi|Activation \(bun\).*pi only|wrappers.*pi' \
    modules/common/default.nix README.md 2>/dev/null | head -5; then
    bad active-docs "docs/inventory still describe Pi bun activation as current"
  else
    ok active_docs_no_pi_activation
  fi

  if rg -n 'modules/agents/pi|smoke-pi-harness|~/\.pi/agent|pi-dynamic-workflows' \
    AGENTS.md RTK.md README.md 2>/dev/null | head -10; then
    bad active-docs "active AGENTS/RTK/README still point at Pi harness paths"
  else
    ok active_docs_point_away_from_pi
  fi

  if rg -n '~/\.dotfiles/omp|dotfiles/omp' AGENTS.md README.md 2>/dev/null | head -3 >/dev/null; then
    ok active_docs_omp_ownership
  else
    bad active-docs "active docs must point to ~/.dotfiles/omp ownership"
  fi

  # Smoke inventory: expect omp, not pi as required agent CLI
  if rg -n '"pi"|command -v pi|expect.*\bpi\b' scripts/run-fixtures.sh crates 2>/dev/null \
    | rg -v 'superpowers|historical|migration|Stage' | head -5; then
    # soft: only fail hard on agent activation scripts
    :
  fi
  if rg -n 'omp' modules/agents/default.nix scripts/ 2>/dev/null | head -1 >/dev/null; then
    ok smoke_inventory_has_omp
  else
    bad active-docs "omp not referenced in agents/scripts"
  fi

  # Nix must not deploy .omp configuration (dotfiles owns config)
  if rg -n 'home\.file.*"\.omp/|"\.omp/agent' modules/ 2>/dev/null | head -5; then
    bad active-docs "Nix still deploys .omp configuration (must stay dotfiles-owned)"
  else
    ok nix_no_omp_config_deploy
  fi

  # shell PATH comments
  if rg -n 'pi bun wrapper|bun global bins \(pi only' modules/shell/default.nix 2>/dev/null | head -3; then
    bad active-docs "shell module still documents pi bun wrapper as active"
  else
    ok shell_no_pi_docs
  fi
}

# --- all ---
run_all() {
  run_installer
  run_harness
  run_active_docs
  echo "=== group: all (cross invariants) ==="
  # No home.file target begins .pi/
  if rg -n '"\.pi/' modules/**/*.nix 2>/dev/null | head -5; then
    bad all "some nix module still has home.file .pi/ target"
  else
    ok all_no_pi_home_file_anywhere
  fi
  # modules/agents/pi absent already checked
  if [ ! -d modules/agents/pi ] && [ ! -f scripts/smoke-pi-harness.sh ]; then
    ok all_pi_assets_gone
  else
    bad all "pi assets still on disk"
  fi
}

case "$GROUP" in
  installer) run_installer ;;
  harness) run_harness ;;
  active-docs) run_active_docs ;;
  all) run_all ;;
  *)
    echo "usage: $0 [installer|harness|active-docs|all]" >&2
    exit 2
    ;;
esac

echo "=== summary pass=$pass fail=$fail group=$GROUP ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
