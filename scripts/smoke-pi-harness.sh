#!/usr/bin/env bash
# Smoke-check Pi goal harness CLI + config after home-manager activation.
# Hard miss → exit 1. Soft warnings (sg, package list) do not fail the run.
set -euo pipefail

fail=0
warn=0

need() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "OK   $name ($(command -v "$name"))"
  else
    echo "MISS $name"
    fail=1
  fi
}

need_any() {
  # need_any label cmd1 cmd2 ...
  local label="$1"
  shift
  local c
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "OK   $label via $c ($(command -v "$c"))"
      return 0
    fi
  done
  echo "MISS $label (tried: $*)"
  fail=1
}

echo "=== pi goal harness smoke ==="

need pi
need rtk
need_any "bd|beads" bd beads
need tokensave
need headroom

if command -v sg >/dev/null 2>&1 || command -v ast-grep >/dev/null 2>&1; then
  if command -v sg >/dev/null 2>&1; then
    echo "OK   sg ($(command -v sg))"
  else
    echo "OK   ast-grep ($(command -v ast-grep))"
  fi
else
  echo "WARN no sg/ast-grep on PATH"
  warn=1
fi

# browser-use (nix activation installs via uv) — soft warn only
if command -v browser-use >/dev/null 2>&1; then
  echo "OK   browser-use ($(browser-use --version 2>/dev/null | head -1 || command -v browser-use))"
  echo "     note: doctor needs Chrome + chrome://inspect/#remote-debugging"
else
  echo "WARN browser-use not on PATH (run home activation / uv tool install browser-use)"
  warn=1
fi

# webwright skill (optional tier-4) — soft
if [[ -f "${HOME}/.agents/skills/webwright/SKILL.md" ]]; then
  echo "OK   webwright skill (${HOME}/.agents/skills/webwright)"
else
  echo "WARN webwright skill missing (activation clones microsoft/Webwright skill)"
  warn=1
fi

agent="${HOME}/.pi/agent"
if [[ -f "${agent}/settings.json" ]]; then
  echo "OK   ${agent}/settings.json"
else
  echo "MISS ${agent}/settings.json"
  fail=1
fi

if [[ -f "${agent}/mcp.json" ]]; then
  echo "OK   ${agent}/mcp.json"
else
  echo "MISS ${agent}/mcp.json"
  fail=1
fi

# Optional harness markers (soft)
for f in \
  "${agent}/settings.harness.json" \
  "${agent}/AGENTS.md" \
  "${agent}/skills/goal-harness/SKILL.md" \
  "${agent}/templates/project/AGENTS.md.tmpl"; do
  if [[ -e "$f" ]]; then
    echo "OK   $f"
  else
    echo "WARN missing optional $f (activate home-manager?)"
    warn=1
  fi
done

list_out=""
if command -v pi >/dev/null 2>&1; then
  set +e
  list_out="$(pi list 2>&1)"
  list_rc=$?
  set -e
  if [[ $list_rc -ne 0 ]]; then
    echo "WARN pi list exited $list_rc"
    echo "$list_out" | head -n 40
    warn=1
  else
    echo "OK   pi list"
    if echo "$list_out" | grep -qiE 'dynamic-workflow|pi-dynamic'; then
      echo "OK   dynamic-workflows mentioned in pi list"
    else
      echo "WARN dynamic-workflows not listed (pi install npm:@quintinshaw/pi-dynamic-workflows?)"
      warn=1
    fi
  fi
fi

echo "=== summary: fail=$fail warn=$warn ==="
if [[ $fail -ne 0 ]]; then
  echo "HARD FAIL — install missing tools / re-run agent activation"
  exit 1
fi
echo "PASS (warnings are soft)"
exit 0
