{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Fail-soft installer helpers run during home-manager activation.
  # Official channels change — keep commands documented and soft.
  #
  # Shared stack (see AGENTS.md): RTK, beads, headroom, tokensave, caveman,
  # browser-use (uv tool; Chrome CDP), webwright optional (long-horizon Playwright),
  # ponytail, context-mode, context7, ast-grep (Nix). Code graph = tokensave only
  # (codebase-memory is stripped on activate).
  #
  # No system Node/npm for agent runtimes we control: pi / context-mode via bun.
  # codex / rtk / grok / claude / beads / caveman / ponytail: official installers.
  # codex must NEVER use wrap_bun_cli — that made Codex think it was npm-managed
  # and could write-through-symlink clobber ~/.codex/packages/standalone/.../bin/codex.
  # Prefer ~/.local/bin so GUI / minimal-PATH agent shells still find tools.
  installScript = pkgs.writeShellScript "install-agent-tools" ''
    set +e
    export PATH="$HOME/.local/bin:${pkgs.bun}/bin:${pkgs.uv}/bin:${pkgs.curl}/bin:${pkgs.bash}/bin:${pkgs.python3}/bin:$HOME/.bun/bin:$HOME/.cargo/bin:/opt/zerobrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

    log() { echo "[agents] $*"; }
    ok()  { log "OK: $*"; }
    skip(){ log "skip: $*"; }
    fail(){ log "WARN (soft-fail): $*"; }

    require_bun() {
      if command -v bun >/dev/null 2>&1; then
        return 0
      fi
      fail "bun missing — expected from Nix home.packages (modules/common)"
      return 1
    }

    # Resolve symlinks without depending on GNU readlink -f (macOS).
    resolve_path() {
      local path="$1"
      local dir base target
      [ -e "$path" ] || { printf '%s\n' "$path"; return 0; }
      if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null && return 0
      fi
      if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" 2>/dev/null && return 0
      fi
      # Best-effort: one-level symlink follow.
      if [ -L "$path" ]; then
        target=$(readlink "$path" 2>/dev/null || true)
        case "$target" in
          /*) printf '%s\n' "$target" ;;
          *)
            dir=$(dirname "$path")
            printf '%s\n' "$dir/$target"
            ;;
        esac
        return 0
      fi
      printf '%s\n' "$path"
    }

    # True if path is a real native CLI binary (Mach-O / ELF), not a shell/node wrapper.
    is_native_cli() {
      local path="$1"
      local resolved kind
      [ -n "$path" ] || return 1
      [ -e "$path" ] || return 1
      [ -d "$path" ] && return 1
      resolved=$(resolve_path "$path")
      [ -x "$resolved" ] || [ -x "$path" ] || return 1
      kind=$(file -b "$resolved" 2>/dev/null || file -b "$path" 2>/dev/null || true)
      case "$kind" in
        *Mach-O*|*ELF*|*executable*)
          # Reject obvious script/text even if file says executable.
          case "$kind" in
            *script*|*text*|*ASCII*|*UTF-8*) return 1 ;;
          esac
          return 0
          ;;
      esac
      return 1
    }

    # True if this is a leftover package-manager / nix-setup bun wrapper for a CLI.
    is_legacy_pm_wrapper() {
      local path="$1"
      local resolved head
      [ -n "$path" ] || return 1
      [ -e "$path" ] || return 1
      resolved=$(resolve_path "$path")
      if is_native_cli "$resolved"; then
        return 1
      fi
      # Our own historical wrapper (see wrap_bun_cli).
      if grep -Fq 'Managed by nix-setup modules/agents' "$resolved" 2>/dev/null; then
        return 0
      fi
      if grep -Eq 'exec[[:space:]]+bun[[:space:]]+' "$resolved" 2>/dev/null; then
        return 0
      fi
      head=$(head -n 5 "$resolved" 2>/dev/null || true)
      # Do not put #!/… inside a case pattern — bash treats # as comment mid-arm
      # (breaks with "syntax error near unexpected token `bun*'").
      if printf '%s\n' "$head" | grep -Eq '#!/usr/bin/env (node|bun)|node_modules/@openai/codex|exec[[:space:]]+bun'; then
        return 0
      fi
      case "$resolved" in
        */.bun/bin/*|*/node_modules/@openai/codex/*|*/node_modules/.bin/*)
          return 0
          ;;
      esac
      # Shell/node script that is not a native binary — treat as package-manager entry.
      case "$(file -b "$resolved" 2>/dev/null || true)" in
        *script*|*text*)
          if grep -Eqi 'bun |/bun|node_modules|@openai/codex|npm install' "$resolved" 2>/dev/null; then
            return 0
          fi
          ;;
      esac
      return 1
    }

    # Ensure ~/.local/bin/<name> is a native binary (or symlink to one).
    # Prefer existing good local bin; else symlink from $source; else fail.
    ensure_local_native_bin() {
      local bin_name="$1"
      local source="$2"
      local dest="$HOME/.local/bin/$bin_name"
      mkdir -p "$HOME/.local/bin"
      if is_native_cli "$dest"; then
        return 0
      fi
      if [ -e "$dest" ] && is_legacy_pm_wrapper "$dest"; then
        log "removing legacy wrapper $dest"
        rm -f "$dest"
      fi
      if [ -n "$source" ] && is_native_cli "$source"; then
        # Always replace with a symlink we own (never write through old links).
        rm -f "$dest"
        ln -sfn "$(resolve_path "$source")" "$dest"
        chmod +x "$dest" 2>/dev/null || true
        log "linked $dest -> $(resolve_path "$source")"
        return 0
      fi
      return 1
    }

    # Global bun package + ~/.local/bin wrapper that runs the entry under bun
    # (packages ship #!/usr/bin/env node; we never put Node on PATH).
    # ONLY for pi (and similar pure-JS CLIs) — never codex/rtk/bd.
    install_bun_cli() {
      local package="$1"
      local bin_name="$2"
      require_bun || return 1
      mkdir -p "$HOME/.local/bin" "$HOME/.bun/bin"
      log "bun install -g $package"
      if ! bun install -g "$package"; then
        fail "bun install -g $package failed"
        return 1
      fi
      if [ ! -e "$HOME/.bun/bin/$bin_name" ]; then
        fail "bun installed $package but $HOME/.bun/bin/$bin_name missing"
        return 1
      fi
      wrap_bun_cli "$bin_name"
    }

    wrap_bun_cli() {
      local bin_name="$1"
      local bun_bin="$HOME/.bun/bin/$bin_name"
      local dest="$HOME/.local/bin/$bin_name"
      mkdir -p "$HOME/.local/bin"
      if [ ! -e "$bun_bin" ]; then
        return 1
      fi
      # Replace any previous symlink (e.g. asdf/npm) so we do not write through it.
      rm -f "$dest"
      # $bin_name is expanded by this shell when writing the wrapper (not Nix).
      # Do not use ''${bin_name} without escaping — Nix antiquotes ''${...}.
      printf '%s\n' \
        '#!/bin/sh' \
        '# Managed by nix-setup modules/agents — run under bun (no Node required).' \
        "exec bun \"\$HOME/.bun/bin/$bin_name\" \"\$@\"" \
        >"$dest"
      chmod +x "$dest"
      export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
      log "wrapper $dest -> bun $bun_bin"
      return 0
    }

    # --- codex helpers (standalone only; never bun/npm) ---
    codex_standalone_entrypoint() {
      local root current
      root="$HOME/.codex/packages/standalone"
      current="$root/current"
      if [ -x "$current/codex" ]; then
        printf '%s\n' "$current/codex"
        return 0
      fi
      if [ -x "$current/bin/codex" ]; then
        printf '%s\n' "$current/bin/codex"
        return 0
      fi
      return 1
    }

    codex_standalone_ok() {
      local entry
      entry=$(codex_standalone_entrypoint 2>/dev/null) || return 1
      # Standalone entry may be a tiny launcher script in some layouts; accept
      # native binary, or a non-pm script living under packages/standalone that
      # is not our bun wrapper.
      if is_native_cli "$entry"; then
        return 0
      fi
      if is_legacy_pm_wrapper "$entry"; then
        return 1
      fi
      # Non-wrapper script under standalone (official launcher) — require it runs.
      if [ -x "$entry" ] && "$entry" --version >/dev/null 2>&1; then
        case "$(resolve_path "$entry")" in
          */.codex/packages/standalone/*) return 0 ;;
        esac
      fi
      return 1
    }

    purge_legacy_codex_wrappers() {
      local p
      for p in \
        "$HOME/.local/bin/codex" \
        "$HOME/.bun/bin/codex"
      do
        if [ -e "$p" ] && is_legacy_pm_wrapper "$p"; then
          log "removing legacy codex wrapper: $p"
          rm -f "$p"
        fi
      done
      # If standalone entry itself was clobbered by write-through-symlink, drop it
      # so the official installer can replace the release cleanly.
      p=$(codex_standalone_entrypoint 2>/dev/null || true)
      if [ -n "$p" ] && is_legacy_pm_wrapper "$p"; then
        log "standalone entry clobbered by legacy wrapper — removing $p"
        rm -f "$p"
      fi
    }

    link_local_codex_to_standalone() {
      local entry dest
      entry=$(codex_standalone_entrypoint) || return 1
      dest="$HOME/.local/bin/codex"
      mkdir -p "$HOME/.local/bin"
      # Never write through an existing symlink into the package tree.
      rm -f "$dest"
      ln -sfn "$entry" "$dest"
      export PATH="$HOME/.local/bin:$PATH"
      log "linked $dest -> $entry"
      return 0
    }

    install_or_repair_codex() {
      log "installing/repairing codex via https://chatgpt.com/codex/install.sh ..."
      # Prefer non-interactive when the installer supports it.
      if CODEX_NON_INTERACTIVE=1 curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
        return 0
      fi
      if curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
        return 0
      fi
      return 1
    }

    # --- rustup (prefer official; do not install nixpkgs rustc) ---
    if command -v rustup >/dev/null 2>&1; then
      ok "rustup already present ($(rustup --version 2>/dev/null | head -1))"
    else
      log "installing rustup..."
      if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
        ok "rustup installed"
      else
        fail "rustup install failed"
      fi
    fi
    export PATH="$HOME/.cargo/bin:$PATH"

    # --- headroom via uv ---
    if command -v headroom >/dev/null 2>&1; then
      ok "headroom present ($(headroom --version 2>/dev/null | head -1 || echo unknown))"
    else
      log "installing headroom-ai via uv tool..."
      if uv tool install "headroom-ai[proxy,ml,code,mcp,evals]"; then
        ok "headroom installed"
      else
        fail "headroom uv tool install failed"
      fi
    fi

    # --- npm shim (bun) for pi package manager when real npm is absent ---
    # Pi spawns `npm install PKG --prefix ~/.pi/agent/npm`. Plain `bun "$@"` also mutates
    # CWD package.json (pollutes ~/package.json / .dotfiles with duplicate pi-extensions).
    # This Python shim: honor --prefix by chdir+bun add there; never write home package.json.
    mkdir -p "$HOME/.local/bin"
    if command -v bun >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
      if ! command -v npm >/dev/null 2>&1 \
        || grep -Fq 'Managed by nix-setup modules/agents' "$HOME/.local/bin/npm" 2>/dev/null \
        || grep -Fq 'isolate --prefix installs' "$HOME/.local/bin/npm" 2>/dev/null; then
        cat >"$HOME/.local/bin/npm" <<'NPMSHIM'
#!/usr/bin/env python3
"""Managed by nix-setup modules/agents — bun-as-npm for pi; isolate --prefix installs."""
from __future__ import annotations

import os
import subprocess
import sys


def main() -> int:
    args = sys.argv[1:]
    prefix: str | None = None
    filtered: list[str] = []
    i = 0
    while i < len(args):
        if args[i] == "--prefix" and i + 1 < len(args):
            prefix = args[i + 1]
            i += 2
            continue
        if args[i] == "--legacy-peer-deps":
            i += 1
            continue
        filtered.append(args[i])
        i += 1

    bun = "bun"
    env = os.environ.copy()
    local_bin = os.path.expanduser("~/.local/bin")
    bun_bin = os.path.expanduser("~/.bun/bin")
    env["PATH"] = os.pathsep.join(
        [local_bin, bun_bin] + env.get("PATH", "").split(os.pathsep)
    )

    if prefix:
        os.makedirs(prefix, exist_ok=True)
        if filtered and filtered[0] == "install":
            pkgs = [a for a in filtered[1:] if not a.startswith("-")]
            flags = [a for a in filtered[1:] if a.startswith("-")]
            cmd = [bun, "add", *pkgs, *flags] if pkgs else [bun, "install", *flags]
        else:
            cmd = [bun, *filtered]
        return subprocess.call(cmd, cwd=prefix, env=env)

    home = os.path.expanduser("~")
    cwd = os.getcwd()
    home_pkg = os.path.join(home, "package.json")
    cwd_pkg = os.path.join(cwd, "package.json")
    try:
        same_as_home = (
            os.path.exists(cwd_pkg)
            and os.path.exists(home_pkg)
            and os.path.samefile(cwd_pkg, home_pkg)
        )
    except OSError:
        same_as_home = False
    if cwd == home or same_as_home:
        run_dir = os.path.join(home, ".pi", "agent", "run")
        os.makedirs(run_dir, exist_ok=True)
        run_pkg = os.path.join(run_dir, "package.json")
        if not os.path.isfile(run_pkg):
            with open(run_pkg, "w", encoding="utf-8") as handle:
                handle.write('{\n  "name": "pi-agent-run",\n  "private": true\n}\n')
        cwd = run_dir
    return subprocess.call([bun, *filtered], cwd=cwd, env=env)


if __name__ == "__main__":
    raise SystemExit(main())
NPMSHIM
        chmod +x "$HOME/.local/bin/npm"
        export PATH="$HOME/.local/bin:$PATH"
        ok "npm shim → bun (prefix-isolated) at ~/.local/bin/npm"
      else
        ok "npm present ($(command -v npm))"
      fi
    else
      skip "npm shim skipped — need bun + python3"
    fi

    # Repair pollution from older pi/bun runs (duplicate pi-extensions in home package.json).
    python3 - <<'PY' || true
import json
from pathlib import Path

home = Path.home()
for path in (home / "package.json", home / ".dotfiles" / "package.json"):
    if not path.exists():
        continue
    try:
        real = path.resolve()
        data = json.loads(real.read_text())
    except Exception:
        continue
    deps = data.get("dependencies")
    if not isinstance(deps, dict) or "pi-extensions" not in deps:
        continue
    del deps["pi-extensions"]
    data["dependencies"] = deps
    real.write_text(json.dumps(data, indent=2) + "\n")
    print("stripped pi-extensions from", real)
for lock in (home / "bun.lock", home / ".dotfiles" / "bun.lock"):
    if lock.is_file():
        try:
            lock.unlink()
            print("removed", lock)
        except Exception:
            pass
PY

    # --- browser-use (uv tool → ~/.local/bin; attaches to running Chrome via CDP) ---
    # https://github.com/browser-use/browser-use — no separate Chromium required if Chrome exists.
    # Multi-device: always ensure CLI on this host so activation syncs the stack.
    if command -v browser-use >/dev/null 2>&1 || [ -x "$HOME/.local/bin/browser-use" ]; then
      export PATH="$HOME/.local/bin:$PATH"
      ok "browser-use present ($(browser-use --version 2>/dev/null | head -1 || echo ok))"
    else
      log "installing browser-use via uv tool..."
      if command -v uv >/dev/null 2>&1 && uv tool install browser-use; then
        export PATH="$HOME/.local/bin:$PATH"
        if command -v browser-use >/dev/null 2>&1 || [ -x "$HOME/.local/bin/browser-use" ]; then
          ok "browser-use installed ($(browser-use --version 2>/dev/null | head -1 || echo ok))"
        else
          fail "browser-use uv install finished but binary not on PATH"
        fi
      else
        fail "browser-use install failed — uv tool install browser-use"
      fi
    fi
    # Soft: ensure shims live under ~/.local/bin for agent PATH
    if [ -x "$HOME/.local/bin/browser-use" ]; then
      export PATH="$HOME/.local/bin:$PATH"
    fi

    # --- webwright (optional tier-4 long-horizon Playwright code-as-action) ---
    # https://github.com/microsoft/Webwright — soft-fail; skill for Pi/Claude/Codex.
    # Prefer skill symlink for agents; full CLI install best-effort.
    webwright_skill_dst="$HOME/.agents/skills/webwright"
    if [ -f "$webwright_skill_dst/SKILL.md" ]; then
      ok "webwright skill present at $webwright_skill_dst"
    else
      log "installing webwright skill (microsoft/Webwright) for multi-agent discovery..."
      mkdir -p "$HOME/.agents/skills" "$HOME/.cache/nix-setup"
      if [ ! -d "$HOME/.cache/nix-setup/Webwright/.git" ]; then
        git clone --depth 1 https://github.com/microsoft/Webwright.git \
          "$HOME/.cache/nix-setup/Webwright" 2>/dev/null \
          || fail "webwright git clone failed"
      else
        git -C "$HOME/.cache/nix-setup/Webwright" pull --ff-only 2>/dev/null || true
      fi
      if [ -d "$HOME/.cache/nix-setup/Webwright/skills/webwright" ]; then
        rm -rf "$webwright_skill_dst"
        ln -sfn "$HOME/.cache/nix-setup/Webwright/skills/webwright" "$webwright_skill_dst"
        ok "webwright skill linked → $webwright_skill_dst"
      else
        skip "webwright skill tree missing after clone"
      fi
    fi
    if command -v webwright >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
      if command -v webwright >/dev/null 2>&1; then
        ok "webwright CLI present"
      elif command -v uv >/dev/null 2>&1 \
        && [ -d "$HOME/.cache/nix-setup/Webwright" ]; then
        # Best-effort editable/tool install for CLI; soft-fail (Playwright chromium optional)
        if uv tool install --from "$HOME/.cache/nix-setup/Webwright" webwright 2>/dev/null \
          || (cd "$HOME/.cache/nix-setup/Webwright" && uv pip install -e . 2>/dev/null); then
          ok "webwright package install attempted"
        else
          skip "webwright CLI install soft-failed (skill still usable by host agents)"
        fi
      fi
    fi

    # --- claude-code (official native installer when available) ---
    if command -v claude >/dev/null 2>&1; then
      ok "claude present"
    else
      log "installing claude-code..."
      if curl -fsSL https://claude.ai/install.sh | bash; then
        ok "claude-code install attempted"
      else
        fail "claude-code install failed — install manually: https://docs.anthropic.com/en/docs/claude-code"
      fi
    fi

    # --- codex CLI (official standalone installer ONLY; never bun/npm) ---
    # https://chatgpt.com/codex/install.sh
    # Healthy = native/standalone under ~/.codex/packages/standalone + ~/.local/bin/codex
    # pointing at it. Legacy bun wrappers make Codex report CODEX_MANAGED_BY_NPM.
    purge_legacy_codex_wrappers
    export PATH="$HOME/.local/bin:$PATH"
    if codex_standalone_ok && link_local_codex_to_standalone; then
      ok "codex standalone present ($(codex --version 2>/dev/null | head -1 || echo ok))"
    else
      if install_or_repair_codex; then
        purge_legacy_codex_wrappers
        if codex_standalone_ok && link_local_codex_to_standalone; then
          ok "codex repaired ($(codex --version 2>/dev/null | head -1 || echo ok))"
        elif command -v codex >/dev/null 2>&1 && ! is_legacy_pm_wrapper "$(command -v codex)"; then
          # Installer put a non-wrapper binary on PATH even if layout differs.
          if [ ! -e "$HOME/.local/bin/codex" ] || is_legacy_pm_wrapper "$HOME/.local/bin/codex"; then
            ensure_local_native_bin codex "$(command -v codex)" || true
          fi
          export PATH="$HOME/.local/bin:$PATH"
          ok "codex install attempted ($(codex --version 2>/dev/null | head -1 || echo ok))"
        else
          fail "codex install finished but no healthy standalone entry found"
        fi
      else
        fail "codex install failed — curl -fsSL https://chatgpt.com/codex/install.sh | sh (desktop app still manual)"
      fi
    fi

    # --- grok CLI (official installer; binary is `grok`, not grok-build) ---
    # https://x.ai/cli/install.sh
    if command -v grok >/dev/null 2>&1; then
      ok "grok present ($(grok --version 2>/dev/null | head -1 || echo ok))"
    else
      log "installing grok CLI via https://x.ai/cli/install.sh ..."
      if curl -fsSL https://x.ai/cli/install.sh | bash; then
        ok "grok CLI install attempted"
      else
        fail "grok install failed — curl -fsSL https://x.ai/cli/install.sh | bash"
      fi
    fi

    # --- pi coding agent (https://pi.dev) via bun only ---
    # Official install.sh requires Node/npm and may install Node — we do not use it.
    if command -v pi >/dev/null 2>&1 || [ -e "$HOME/.bun/bin/pi" ]; then
      [ -e "$HOME/.bun/bin/pi" ] && wrap_bun_cli pi || true
      ok "pi present ($(pi --version 2>/dev/null | head -1 || echo ok))"
    else
      log "installing pi via bun (@earendil-works/pi-coding-agent)..."
      if install_bun_cli "@earendil-works/pi-coding-agent" pi; then
        ok "pi via bun ($(pi --version 2>/dev/null | head -1 || echo ok))"
      else
        fail "pi install failed — bun install -g @earendil-works/pi-coding-agent"
      fi
    fi

    # --- pi goal harness: packages, settings merge, workflow templates, model tiers ---
    # Templates from home.file: ~/.pi/agent/settings.harness.json, agents/, prompts/, skills/,
    # ~/.pi/workflows/templates/. Never touch auth.json.
    if command -v pi >/dev/null 2>&1; then
      log "pi harness: installing dynamic-workflows + MCP adapter (fail-soft)..."
      _pi_harness_shim=""
      if ! command -v npm >/dev/null 2>&1 && command -v bun >/dev/null 2>&1; then
        _pi_harness_shim=$(mktemp -d "${TMPDIR:-/tmp}/pi-harness-npm.XXXXXX")
        printf '%s\n' '#!/bin/sh' 'exec bun "$@"' >"$_pi_harness_shim/npm"
        chmod +x "$_pi_harness_shim/npm"
        export PATH="$_pi_harness_shim:$PATH"
      fi
      if pi install npm:@quintinshaw/pi-dynamic-workflows 2>/dev/null \
        || pi install npm:@quintinshaw/pi-dynamic-workflows@latest 2>/dev/null; then
        ok "pi-dynamic-workflows installed"
      else
        fail "pi-dynamic-workflows install failed — pi install npm:@quintinshaw/pi-dynamic-workflows"
      fi
      if pi install npm:pi-mcp-adapter 2>/dev/null \
        || pi install npm:@earendil-works/pi-mcp-adapter 2>/dev/null \
        || pi install npm:pi-mcp-extension 2>/dev/null; then
        ok "pi MCP adapter installed"
      else
        fail "pi MCP adapter install failed — try pi install npm:pi-mcp-adapter"
      fi
      # Web tiers: CDP/headless (optional browser path for web-browse-scout)
      if pi install git:github.com/pasky/chrome-cdp-skill 2>/dev/null \
        || pi install https://github.com/pasky/chrome-cdp-skill 2>/dev/null; then
        ok "pi chrome-cdp skill installed (web-browse-scout)"
      else
        skip "chrome-cdp skill — web-browse-scout soft-fails until installed"
      fi
      # browser-use / webwright installed earlier in activation (shared multi-device stack)
      if command -v browser-use >/dev/null 2>&1 || [ -x "$HOME/.local/bin/browser-use" ]; then
        ok "browser-use on PATH for pi harness (Chrome CDP — enable chrome://inspect/#remote-debugging if doctor fails)"
      else
        skip "browser-use missing for pi harness (see earlier install step)"
      fi
      if [ -f "$HOME/.agents/skills/webwright/SKILL.md" ]; then
        ok "webwright skill available for pi (~/.agents/skills/webwright)"
      else
        skip "webwright skill not linked"
      fi
      if [ -n "$_pi_harness_shim" ]; then
        rm -rf "$_pi_harness_shim"
      fi

      # Merge settings.harness.json → settings.json (preserve theme/lastChangelogVersion/rtk)
      python3 - <<'PY' || fail "pi settings merge failed"
import json
from pathlib import Path
home = Path.home()
agent = home / ".pi" / "agent"
settings_path = agent / "settings.json"
harness_path = agent / "settings.harness.json"
data = {}
if settings_path.is_file():
    try:
        data = json.loads(settings_path.read_text())
    except Exception:
        data = {}
if not isinstance(data, dict):
    data = {}
harness = {}
if harness_path.is_file():
    try:
        harness = json.loads(harness_path.read_text())
    except Exception:
        harness = {}
# packages: ensure required sources present
packages = data.get("packages")
if not isinstance(packages, list):
    packages = []
wanted = [
    "npm:@quintinshaw/pi-dynamic-workflows",
    "npm:pi-mcp-adapter",
    "git:github.com/pasky/chrome-cdp-skill",
]
for src in wanted:
    if not any(
        (isinstance(p, str) and src in p)
        or (isinstance(p, dict) and src in str(p.get("source", "")))
        for p in packages
    ):
        packages.append(src)
data["packages"] = packages
# skills globs
skills = data.get("skills")
if not isinstance(skills, list):
    skills = []
for s in harness.get("skills") or [
    "~/.agents/skills",
    "~/.claude/skills",
    "~/.claude/plugins/cache/claude-plugins-official/superpowers",
]:
    if s not in skills:
        skills.append(s)
# ensure goal-harness skill path
gh = str(agent / "skills")
if gh not in skills and "~/.pi/agent/skills" not in skills:
    skills.append(str(agent / "skills"))
data["skills"] = skills
# prompts + agents dirs (if settings supports)
for key in ("enableSkillCommands", "defaultThinkingLevel", "quietStartup"):
    if key in harness and key not in data:
        data[key] = harness[key]
if "compaction" in harness and "compaction" not in data:
    data["compaction"] = harness["compaction"]
# extensions: keep rtk; merge harness extensions
ext = data.get("extensions")
if not isinstance(ext, list):
    ext = []
for e in harness.get("extensions") or ["extensions/rtk.ts"]:
    if e not in ext:
        ext.append(e)
data["extensions"] = ext
agent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(data, indent=2) + "\n")
print("merged", settings_path)
PY
      ok "pi settings.harness merged into settings.json"

      # Deploy workflow templates + model-tiers (package may re-read later)
      mkdir -p "$HOME/.pi/workflows/saved" "$HOME/.pi/workflows/templates"
      if [ -d "$HOME/.pi/workflows/templates" ]; then
        # home.file already places templates; also copy JS into saved-friendly names
        for wf in goal-harness research-fanout milestone-review; do
          if [ -f "$HOME/.pi/workflows/templates/''${wf}.js" ]; then
            cp -f "$HOME/.pi/workflows/templates/''${wf}.js" "$HOME/.pi/workflows/saved/''${wf}.js" 2>/dev/null \
              || cp -f "$HOME/.pi/workflows/templates/''${wf}.js" "$HOME/.pi/workflows/''${wf}.js" 2>/dev/null \
              || true
          fi
        done
        if [ -f "$HOME/.pi/workflows/templates/model-tiers.json" ]; then
          if [ ! -f "$HOME/.pi/workflows/model-tiers.json" ]; then
            cp -f "$HOME/.pi/workflows/templates/model-tiers.json" "$HOME/.pi/workflows/model-tiers.json" || true
          fi
        fi
      fi
      ok "pi workflow templates staged under ~/.pi/workflows"

      # Soft model-tier resolve: only fill REPLACE_ME when a model catalog is visible
      python3 - <<'PY' || true
import json, re, subprocess
from pathlib import Path
home = Path.home()
tiers_path = home / ".pi" / "workflows" / "model-tiers.json"
aliases_path = home / ".pi" / "agent" / "models-aliases.json"
if not tiers_path.is_file():
    raise SystemExit(0)
try:
    document = json.loads(tiers_path.read_text())
except Exception:
    raise SystemExit(0)
catalog = ""
for command_argv in (
    ["pi", "models", "--list"],
    ["pi", "--list-models"],
    ["pi", "list"],
):
    try:
        process_result = subprocess.run(
            command_argv, capture_output=True, text=True, timeout=15
        )
        catalog += (process_result.stdout or "") + "\n" + (process_result.stderr or "")
    except Exception:
        pass

def pick_model(*needles):
    for line in catalog.splitlines():
        lowered = line.lower()
        if all(needle in lowered for needle in needles):
            match = re.search(r"([a-z0-9._-]+/[a-z0-9._:+-]+)", line, re.I)
            if match:
                return match.group(1).strip()
            return line.strip()
    return None

resolved = {}
# Prefer explicit harness defaults; only overwrite REPLACE_ME placeholders.
defaults = {
    "big": "openai/gpt-5.6-sol:ultra",
    "medium": "xai/grok-4.5:high",  # Grok always high effort
    "small": "openai/gpt-5.6-sol:low",
}
tier_map = document.get("tiers") if isinstance(document.get("tiers"), dict) else document
if not isinstance(tier_map, dict):
    print("model tiers: unexpected shape")
    raise SystemExit(0)
changed = False
for key, default_id in defaults.items():
    current = str(tier_map.get(key, ""))
    if current.startswith("REPLACE_ME") or not current:
        tier_map[key] = default_id
        resolved[key] = default_id
        changed = True
# Soft upgrade from catalog if fuzzy match looks better (optional)
for key, needles in (
    ("big", ("gpt-5.6-sol", "sol")),
    ("medium", ("grok-4.5", "grok")),
    ("small", ("gpt-5.6-sol", "sol")),
):
    found = pick_model(*needles[:1]) or pick_model(needles[-1])
    if found and key in defaults:
        # keep effort suffix from defaults when catalog omits it
        if ":" not in found and ":" in defaults[key]:
            found = found + ":" + defaults[key].split(":")[-1]
        if found != tier_map.get(key):
            # only replace if still default/placeholder
            if str(tier_map.get(key, "")).startswith("REPLACE_ME"):
                tier_map[key] = found
                resolved[key] = found
                changed = True
if "tiers" in document:
    document["tiers"] = tier_map
else:
    document = {"tiers": tier_map}
if changed:
    tiers_path.write_text(json.dumps(document, indent=2) + "\n")
    print("model tiers set:", tier_map)
else:
    print("model tiers unchanged:", tier_map)
PY
      ok "pi model-tier resolve attempted (soft)"
    else
      skip "pi harness packages — pi not on PATH"
    fi

    # --- beads (official native binary; do NOT use bun/npm @beads/bd or crates.io) ---
    # https://github.com/gastownhall/beads — install.sh → ~/.local/bin/bd
    # bun/npm package only ships a node wrapper; postinstall often fails without node.
    # crates.io "beads" is a library stub with no binary.
    if command -v bd >/dev/null 2>&1 || command -v beads >/dev/null 2>&1; then
      # If PATH still hits a broken bun/npm wrapper first, prefer real binary under ~/.local/bin
      if [ -x "$HOME/.local/bin/bd" ]; then
        export PATH="$HOME/.local/bin:$PATH"
      fi
      if bd version >/dev/null 2>&1 || bd --version >/dev/null 2>&1; then
        ok "beads present ($(bd version 2>/dev/null | head -1 || bd --version 2>/dev/null | head -1 || echo ok))"
      else
        log "bd on PATH but broken (likely bun/npm wrapper without native binary) — reinstalling..."
        rm -f "$HOME/.bun/bin/bd" 2>/dev/null || true
        if curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash; then
          export PATH="$HOME/.local/bin:$PATH"
          ok "beads reinstalled ($(bd version 2>/dev/null | head -1 || echo ok))"
        else
          fail "beads reinstall failed — curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash"
        fi
      fi
    else
      log "installing beads via official install.sh..."
      if curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash; then
        export PATH="$HOME/.local/bin:$PATH"
        ok "beads installed ($(bd version 2>/dev/null | head -1 || echo ok))"
      else
        fail "beads install failed — curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash"
      fi
    fi

    # --- rtk (official installer → ~/.local/bin; not zerobrew-only) ---
    # https://github.com/rtk-ai/rtk
    # Agent shells (Codex desktop, minimal PATH) often miss /opt/zerobrew and
    # /opt/homebrew. Always ensure a native rtk at ~/.local/bin/rtk.
    rtk_src=""
    if is_native_cli "$HOME/.local/bin/rtk"; then
      rtk_src="$HOME/.local/bin/rtk"
    elif command -v rtk >/dev/null 2>&1 && is_native_cli "$(command -v rtk)"; then
      rtk_src=$(command -v rtk)
    fi
    if [ -n "$rtk_src" ] && ensure_local_native_bin rtk "$rtk_src"; then
      export PATH="$HOME/.local/bin:$PATH"
      ok "rtk present at ~/.local/bin ($(rtk --version 2>/dev/null | head -1 || echo ok))"
    else
      log "installing rtk via official install.sh into ~/.local/bin ..."
      if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        if is_native_cli "$HOME/.local/bin/rtk"; then
          ok "rtk installed ($(rtk --version 2>/dev/null | head -1 || echo ok))"
        elif command -v rtk >/dev/null 2>&1 && ensure_local_native_bin rtk "$(command -v rtk)"; then
          ok "rtk linked to ~/.local/bin ($(rtk --version 2>/dev/null | head -1 || echo ok))"
        else
          fail "rtk install finished but ~/.local/bin/rtk missing"
        fi
      else
        # Last resort: symlink from known package managers if install.sh failed.
        for candidate in /opt/zerobrew/bin/rtk /opt/homebrew/bin/rtk /usr/local/bin/rtk; do
          if is_native_cli "$candidate" && ensure_local_native_bin rtk "$candidate"; then
            export PATH="$HOME/.local/bin:$PATH"
            ok "rtk linked from $candidate ($(rtk --version 2>/dev/null | head -1 || echo ok))"
            candidate=""
            break
          fi
        done
        if ! is_native_cli "$HOME/.local/bin/rtk"; then
          fail "rtk install failed — curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
        fi
      fi
    fi

    # --- RTK multi-agent hooks (binary already ensured above) ---
    # https://github.com/rtk-ai/rtk
    if command -v rtk >/dev/null 2>&1; then
      log "rtk init for claude / codex / cursor / pi (auto-patch where supported)..."
      rtk init -g --auto-patch 2>/dev/null && ok "rtk init claude" || fail "rtk init claude"
      rtk init -g --codex 2>/dev/null && ok "rtk init codex" || fail "rtk init codex"
      rtk init -g --agent cursor --auto-patch 2>/dev/null && ok "rtk init cursor" || fail "rtk init cursor"
      rtk init -g --agent pi --auto-patch 2>/dev/null && ok "rtk init pi" || fail "rtk init pi"
    else
      fail "rtk missing — cannot run rtk init"
    fi

    # --- tokensave (sole code graph; never codebase-memory) ---
    # https://github.com/aovestdipaperino/tokensave
    if ! command -v tokensave >/dev/null 2>&1; then
      log "installing tokensave binary..."
      if command -v brew >/dev/null 2>&1 && brew install aovestdipaperino/tap/tokensave 2>/dev/null; then
        ok "tokensave via brew"
      elif command -v cargo >/dev/null 2>&1 && cargo install tokensave --locked 2>/dev/null; then
        export PATH="$HOME/.cargo/bin:$PATH"
        ensure_local_native_bin tokensave "$(command -v tokensave)" || true
        ok "tokensave via cargo"
      else
        fail "tokensave install failed — brew install aovestdipaperino/tap/tokensave"
      fi
    else
      ok "tokensave present ($(tokensave --version 2>/dev/null | head -1 || echo ok))"
    fi
    if command -v tokensave >/dev/null 2>&1; then
      for agent in claude codex cursor pi grok; do
        if tokensave install --agent "$agent" --git-hook no 2>/dev/null; then
          ok "tokensave install --agent $agent"
        else
          fail "tokensave install --agent $agent"
        fi
      done
    fi

    # --- context-mode (bun; Node ≥22.5 alternative) ---
    # https://github.com/mksglu/context-mode
    # NEVER run `context-mode --version` here: it starts an interactive/TUI path
    # and hangs activation (no TTY progress, looks "stuck" after tokensave install).
    if command -v context-mode >/dev/null 2>&1 || [ -e "$HOME/.bun/bin/context-mode" ]; then
      if [ -e "$HOME/.bun/bin/context-mode" ] && [ ! -e "$HOME/.local/bin/context-mode" ]; then
        wrap_bun_cli context-mode || ln -sfn "$HOME/.bun/bin/context-mode" "$HOME/.local/bin/context-mode"
      fi
      export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
      ok "context-mode present ($(command -v context-mode))"
    else
      require_bun || true
      if command -v bun >/dev/null 2>&1; then
        log "installing context-mode via bun..."
        if bun install -g context-mode 2>/dev/null; then
          if [ -e "$HOME/.bun/bin/context-mode" ]; then
            wrap_bun_cli context-mode || ln -sfn "$HOME/.bun/bin/context-mode" "$HOME/.local/bin/context-mode"
          fi
          export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
          if command -v context-mode >/dev/null 2>&1; then
            ok "context-mode installed ($(command -v context-mode))"
          else
            fail "context-mode bun install finished but binary not on PATH"
          fi
        else
          fail "context-mode bun install failed"
        fi
      else
        fail "context-mode skipped — bun missing"
      fi
    fi

    # --- caveman (multi-agent skill; bun/node for installer) ---
    # https://github.com/JuliusBrussee/caveman
    caveman_marker() {
      [ -e "$HOME/.claude/skills/caveman/SKILL.md" ] \
        || [ -e "$HOME/.claude/skills/caveman/skill.md" ] \
        || [ -d "$HOME/.claude/plugins/cache/caveman" ] \
        || [ -d "$HOME/.codex/skills/caveman" ] \
        || [ -d "$HOME/.gemini/extensions/caveman" ] \
        || [ -e "$HOME/.cursor/skills/caveman/SKILL.md" ] \
        || [ -d "$HOME/.agents/skills/caveman" ] \
        || [ -d ".agents/skills/caveman" ]
    }
    if caveman_marker; then
      ok "caveman skill markers present"
    else
      log "installing caveman via https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh ..."
      # Official installer requires `node` + `npx` ≥18. This flake has no system
      # Node — session-local shims exec bun / bun x (user-approved).
      _caveman_node_shim=""
      if { ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; } \
        && command -v bun >/dev/null 2>&1; then
        _caveman_node_shim=$(mktemp -d "${TMPDIR:-/tmp}/caveman-node.XXXXXX")
        if ! command -v node >/dev/null 2>&1; then
          printf '%s\n' '#!/bin/sh' 'exec bun "$@"' >"$_caveman_node_shim/node"
          chmod +x "$_caveman_node_shim/node"
        fi
        if ! command -v npx >/dev/null 2>&1; then
          printf '%s\n' '#!/bin/sh' 'exec bun x "$@"' >"$_caveman_node_shim/npx"
          chmod +x "$_caveman_node_shim/npx"
        fi
        export PATH="$_caveman_node_shim:$PATH"
        log "using bun shims for node/npx under $_caveman_node_shim"
      fi
      if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
        if curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash; then
          if caveman_marker; then
            ok "caveman installed"
          else
            ok "caveman install script finished (markers not detected — open an agent and /caveman)"
          fi
        else
          fail "caveman install failed — curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash"
        fi
      else
        fail "caveman skipped — bun or Node ≥18 (+ npx) required"
      fi
      if [ -n "$_caveman_node_shim" ]; then
        rm -rf "$_caveman_node_shim"
      fi
    fi

    # --- ponytail (multi-agent skill; lean code generation / YAGNI) ---
    # https://github.com/DietrichGebert/ponytail
    # Complements caveman: caveman shrinks prose, ponytail shrinks generated code.
    ponytail_marker() {
      [ -e "$HOME/.claude/skills/ponytail/SKILL.md" ] \
        || [ -e "$HOME/.claude/skills/ponytail/skill.md" ] \
        || [ -d "$HOME/.claude/plugins/cache/ponytail" ] \
        || [ -d "$HOME/.codex/plugins/cache/ponytail" ] \
        || [ -d "$HOME/.codex/skills/ponytail" ] \
        || [ -e "$HOME/.cursor/skills/ponytail/SKILL.md" ] \
        || [ -d "$HOME/.agents/skills/ponytail" ] \
        || [ -d ".agents/skills/ponytail" ] \
        || [ -d "$HOME/.gemini/extensions/ponytail" ] \
        || [ -d "$HOME/.pi/agent/git/github.com/DietrichGebert/ponytail" ]
    }

    # Portable skill tree → ~/.agents/skills (Grok, Cursor, generic skill hosts).
    # Host plugins (Claude/Codex/pi) add hooks/commands; this keeps the skill readable everywhere.
    install_ponytail_skill_files() {
      local dest_root="$1"
      local skill name url
      [ -n "$dest_root" ] || return 1
      for skill in ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help; do
        mkdir -p "$dest_root/$skill" || return 1
        url="https://raw.githubusercontent.com/DietrichGebert/ponytail/main/skills/$skill/SKILL.md"
        if ! curl -fsSL "$url" -o "$dest_root/$skill/SKILL.md"; then
          fail "ponytail: failed to fetch $skill/SKILL.md"
          return 1
        fi
      done
      return 0
    }

    if ponytail_marker; then
      ok "ponytail skill markers present"
    else
      log "installing ponytail (DietrichGebert/ponytail) ..."
      _ponytail_any=0

      # Claude Code plugin (marketplace + install)
      if command -v claude >/dev/null 2>&1; then
        if claude plugin marketplace add DietrichGebert/ponytail 2>/dev/null \
          || claude plugin marketplace list 2>/dev/null | grep -qi ponytail; then
          if claude plugin install ponytail@ponytail -s user 2>/dev/null \
            || claude plugin install ponytail@ponytail 2>/dev/null; then
            ok "ponytail: claude plugin installed"
            _ponytail_any=1
          else
            skip "ponytail: claude plugin install failed (marketplace may need interactive trust)"
          fi
        else
          skip "ponytail: claude marketplace add failed"
        fi
      fi

      # Codex plugin
      if command -v codex >/dev/null 2>&1; then
        if codex plugin marketplace add DietrichGebert/ponytail 2>/dev/null \
          || codex plugin marketplace list 2>/dev/null | grep -qi ponytail; then
          if codex plugin add ponytail@ponytail 2>/dev/null \
            || codex plugin add ponytail --marketplace ponytail 2>/dev/null; then
            ok "ponytail: codex plugin installed"
            _ponytail_any=1
          else
            skip "ponytail: codex plugin add failed"
          fi
        else
          skip "ponytail: codex marketplace add failed"
        fi
      fi

      # pi package extension (needs npm for git installs; shim with bun when missing)
      if command -v pi >/dev/null 2>&1; then
        _ponytail_pi_shim=""
        if ! command -v npm >/dev/null 2>&1 && command -v bun >/dev/null 2>&1; then
          _ponytail_pi_shim=$(mktemp -d "${TMPDIR:-/tmp}/ponytail-pi.XXXXXX")
          # pi's git install runs `npm install`; bun is npm-compatible enough here.
          printf '%s\n' '#!/bin/sh' 'exec bun "$@"' >"$_ponytail_pi_shim/npm"
          chmod +x "$_ponytail_pi_shim/npm"
          export PATH="$_ponytail_pi_shim:$PATH"
        fi
        if pi install git:github.com/DietrichGebert/ponytail 2>/dev/null \
          || pi install https://github.com/DietrichGebert/ponytail 2>/dev/null \
          || pi install npm:@dietrichgebert/ponytail 2>/dev/null; then
          ok "ponytail: pi package installed"
          _ponytail_any=1
        else
          skip "ponytail: pi install failed (needs npm or bun shim; portable skills still work)"
        fi
        if [ -n "$_ponytail_pi_shim" ]; then
          rm -rf "$_ponytail_pi_shim"
        fi
      fi

      # skills CLI (global) — same bun→node shims as caveman when Node missing
      _ponytail_node_shim=""
      if { ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; } \
        && command -v bun >/dev/null 2>&1; then
        _ponytail_node_shim=$(mktemp -d "${TMPDIR:-/tmp}/ponytail-node.XXXXXX")
        if ! command -v node >/dev/null 2>&1; then
          printf '%s\n' '#!/bin/sh' 'exec bun "$@"' >"$_ponytail_node_shim/node"
          chmod +x "$_ponytail_node_shim/node"
        fi
        if ! command -v npx >/dev/null 2>&1; then
          printf '%s\n' '#!/bin/sh' 'exec bun x "$@"' >"$_ponytail_node_shim/npx"
          chmod +x "$_ponytail_node_shim/npx"
        fi
        export PATH="$_ponytail_node_shim:$PATH"
      fi
      if command -v npx >/dev/null 2>&1; then
        if npx --yes skills add DietrichGebert/ponytail -g --all 2>/dev/null; then
          ok "ponytail: skills CLI global install"
          _ponytail_any=1
        else
          skip "ponytail: skills CLI install failed"
        fi
      fi
      if [ -n "$_ponytail_node_shim" ]; then
        rm -rf "$_ponytail_node_shim"
      fi

      # Always seed portable skill files under ~/.agents/skills (and project if present)
      mkdir -p "$HOME/.agents/skills"
      if install_ponytail_skill_files "$HOME/.agents/skills"; then
        ok "ponytail: skill files in ~/.agents/skills"
        _ponytail_any=1
      fi
      if [ -d ".agents/skills" ] || [ -d ".agents" ]; then
        mkdir -p ".agents/skills"
        if install_ponytail_skill_files ".agents/skills"; then
          ok "ponytail: skill files in .agents/skills"
          _ponytail_any=1
        fi
      fi

      if [ "$_ponytail_any" -eq 1 ]; then
        if ponytail_marker; then
          ok "ponytail installed"
        else
          ok "ponytail install finished (open agent and /ponytail)"
        fi
      else
        fail "ponytail install failed — see https://github.com/DietrichGebert/ponytail#install"
      fi
    fi

    # --- beads multi-agent setup (binary already ensured above) ---
    if command -v bd >/dev/null 2>&1; then
      for setup_target in claude codex cursor; do
        if bd setup "$setup_target" 2>/dev/null; then
          ok "bd setup $setup_target"
        else
          skip "bd setup $setup_target (optional / project-local)"
        fi
      done
    fi

    # --- purge codebase-memory + wire shared MCP (context7: no API key) ---
    log "purging codebase-memory MCP entries; ensuring headroom/tokensave/context-mode/context7..."
    python3 - <<'PY' || fail "MCP config reconcile failed"
import json, os, re, shutil
from pathlib import Path

home = Path.home()
local_bin = home / ".local" / "bin"

def which(name):
    for d in [local_bin, home / ".bun" / "bin", home / ".cargo" / "bin",
              Path("/opt/homebrew/bin"), Path("/usr/local/bin")]:
        p = d / name
        if p.is_file() or p.is_symlink():
            return str(p)
    for d in os.environ.get("PATH", "").split(":"):
        if not d:
            continue
        p = Path(d) / name
        if p.is_file() or p.is_symlink():
            return str(p)
    return None

tokensave = which("tokensave") or str(local_bin / "tokensave")
headroom = which("headroom") or str(local_bin / "headroom")
ctx_mode = which("context-mode")
bun = which("bun")

def drop_cm(d):
    changed = False
    for k in list(d.keys()):
        if "codebase-memory" in k.lower():
            del d[k]
            changed = True
    return changed

def merge_mcp_json(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {}
    if path.is_file():
        try:
            data = json.loads(path.read_text())
        except Exception:
            data = {}
    if not isinstance(data, dict):
        data = {}
    key = "mcpServers"
    if "servers" in data and "mcpServers" not in data:
        key = "servers"
    servers = data.setdefault(key, {})
    if not isinstance(servers, dict):
        servers = {}
        data[key] = servers
    changed = drop_cm(servers)
    desired = {}
    if which("tokensave"):
        desired["tokensave"] = {"command": tokensave, "args": ["serve"]}
    if which("headroom"):
        desired["headroom"] = {"command": headroom, "args": ["mcp", "serve"]}
    if ctx_mode:
        desired["context-mode"] = {"command": ctx_mode}
    # context7 free tier — no API key
    desired["context7"] = {"url": "https://mcp.context7.com/mcp"}
    for name, spec in desired.items():
        if servers.get(name) != spec:
            servers[name] = spec
            changed = True
    if changed or not path.is_file():
        path.write_text(json.dumps(data, indent=2) + "\n")
        print("updated", path)

merge_mcp_json(home / ".claude" / ".mcp.json")
merge_mcp_json(home / ".cursor" / "mcp.json")
# Pi goal harness MCP (absolute commands preferred)
merge_mcp_json(home / ".pi" / "agent" / "mcp.json")

for claude_json in [home / ".claude" / ".claude.json", home / ".claude.json"]:
    if not claude_json.is_file():
        continue
    try:
        data = json.loads(claude_json.read_text())
        touched = False
        if isinstance(data.get("mcpServers"), dict):
            if drop_cm(data["mcpServers"]):
                touched = True
            desired = {
                "tokensave": {"command": tokensave, "args": ["serve"]},
                "headroom": {"command": headroom, "args": ["mcp", "serve"]},
                "context7": {"url": "https://mcp.context7.com/mcp"},
            }
            if ctx_mode:
                desired["context-mode"] = {"command": ctx_mode}
            for name, spec in desired.items():
                if data["mcpServers"].get(name) != spec:
                    data["mcpServers"][name] = spec
                    touched = True
        projects = data.get("projects")
        if isinstance(projects, dict):
            for proj in projects.values():
                if isinstance(proj, dict) and isinstance(proj.get("mcpServers"), dict):
                    if drop_cm(proj["mcpServers"]):
                        touched = True
        if touched:
            bak = Path(str(claude_json) + ".bak-nix-setup")
            if not bak.exists():
                shutil.copy2(claude_json, bak)
            claude_json.write_text(json.dumps(data, indent=2) + "\n")
            print("updated", claude_json)
    except Exception as e:
        print("skip", claude_json, e)

def patch_toml(path, is_grok=False):
    if not path.is_file():
        return
    text = path.read_text()
    original = text
    text = re.sub(
        r"\n\[mcp_servers\.codebase-memory-mcp\][^\[]*",
        "\n",
        text,
        flags=re.MULTILINE,
    )
    text = text.replace(
        "prefer codebase-memory-mcp (search_graph, trace_path, get_code_snippet, query_graph, search_code) over grep/file-read; run index_repository first if the project is not indexed.",
        "prefer tokensave (tokensave_context, tokensave_search, callers/impact) over grep/file-read and Explore agents; run tokensave init/sync if the project is not indexed. Do not use codebase-memory.",
    )
    blocks = []
    if which("tokensave") and "[mcp_servers.tokensave]" not in text:
        blocks.append(
            f'[mcp_servers.tokensave]\ncommand = {json.dumps(tokensave)}\nargs = ["serve"]\n'
        )
    if which("headroom") and "[mcp_servers.headroom]" not in text:
        blocks.append(
            f'[mcp_servers.headroom]\ncommand = {json.dumps(headroom)}\nargs = ["mcp", "serve"]\n'
        )
    if ctx_mode and "[mcp_servers.context-mode]" not in text:
        blocks.append(f'[mcp_servers.context-mode]\ncommand = {json.dumps(ctx_mode)}\n')
    if "[mcp_servers.context7]" not in text:
        if is_grok:
            blocks.append('[mcp_servers.context7]\nurl = "https://mcp.context7.com/mcp"\n')
        elif bun:
            blocks.append(
                f'[mcp_servers.context7]\ncommand = {json.dumps(bun)}\n'
                f'args = ["x", "-y", "@upstash/context7-mcp"]\n'
            )
        else:
            blocks.append(
                '[mcp_servers.context7]\ncommand = "npx"\n'
                'args = ["-y", "@upstash/context7-mcp"]\n'
            )
    if blocks:
        if not text.endswith("\n"):
            text += "\n"
        text += "\n" + "\n".join(blocks)
    if text != original:
        bak = path.with_suffix(path.suffix + ".bak-nix-setup")
        if not bak.exists():
            shutil.copy2(path, bak)
        path.write_text(text)
        print("updated", path)

patch_toml(home / ".codex" / "config.toml", is_grok=False)
patch_toml(home / ".grok" / "config.toml", is_grok=True)
print("MCP reconcile done")
PY

    exit 0
  '';
in
{
  home.packages = with pkgs; [
    # uv / bun / curl / python for agent installers (bun replaces node/npm)
    uv
    bun
    curl
    python3
  ];

  # Pi goal harness templates (modules/agents/pi/) → ~/.pi/agent and workflow templates.
  # settings.json is NOT force-overwritten: ship settings.harness.json for activation merge (Task 8).
  # Never manage ~/.pi/agent/auth.json.
  home.file = {
    ".pi/agent/AGENTS.md".source = ./pi/AGENTS.global.md;
    # mcp.json written by activation (absolute binary paths) — not home.file
    ".pi/agent/mcp.harness.json".source = ./pi/mcp.json;
    ".pi/agent/extensions/sandbox.json".source = ./pi/sandbox.json;
    ".pi/agent/models-aliases.json".source = ./pi/models-aliases.json;
    ".pi/agent/settings.harness.json".source = ./pi/settings.json;
    ".pi/agent/agent-types.json".source = ./pi/agent-types.json;
    ".pi/agent/README-harness.md".source = ./pi/README.md;
    ".pi/agent/docs" = {
      source = ./pi/docs;
      recursive = true;
    };
    ".pi/agent/agents" = {
      source = ./pi/agents;
      recursive = true;
    };
    ".pi/agent/prompts" = {
      source = ./pi/prompts;
      recursive = true;
    };
    ".pi/agent/skills/goal-harness" = {
      source = ./pi/skills/goal-harness;
      recursive = true;
    };
    ".pi/agent/templates/project" = {
      source = ./pi/templates/project;
      recursive = true;
    };
    ".pi/workflows/templates" = {
      source = ./pi/workflows;
      recursive = true;
    };
  };

  home.activation.installAgentTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "=== agent tools activation (fail-soft; shared stack: rtk/tokensave/headroom/context-mode/context7/caveman) ==="
    ${installScript} || echo "[agents] activation script exited non-zero (ignored)"
  '';
}

