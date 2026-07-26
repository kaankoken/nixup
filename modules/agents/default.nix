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
  # No system Node/npm for agent runtimes we control: context-mode via bun.
  # codex / rtk / grok / claude / beads / caveman / ponytail: official installers.
  # codex must NEVER use wrap_bun_cli — that made Codex think it was npm-managed
  # and could write-through-symlink clobber ~/.codex/packages/standalone/.../bin/codex.
  # Prefer ~/.local/bin so GUI / minimal-PATH agent shells still find tools.
  # OMP binary only — configuration belongs to ~/.dotfiles/omp (not Nix home.file).
  installOmpScript = pkgs.writeShellScript "install-omp" (
    builtins.readFile ./scripts/install-omp.sh
  );
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
    # ONLY for pure-JS CLIs that are not standalone-installed — never codex/rtk/bd.
    install_bun_cli() {
      local package="$1"
      local bin_name="$2"
      require_bun || return 1
      mkdir -p "$HOME/.local/bin" "$HOME/.bun/bin"
      log "bun install -g $package"
      # Isolate from ~/package.json which makes bun -g land in ~/node_modules
      if ! ( cd /tmp && bun install -g "$package" ); then
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

    # Pi binary installer removed (Stage 4 complete; OMP only).

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

    # Repair leftover package.json deps from retired agent installers.
    python3 - <<'PY' || true
import json
from pathlib import Path

STRIP_DEPS = (
    "pi-extensions",
    "@earendil-works/pi-coding-agent",
    "pi-coding-agent",
)
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
    if not isinstance(deps, dict):
        continue
    stripped = [k for k in STRIP_DEPS if k in deps]
    if not stripped:
        continue
    for key in stripped:
        del deps[key]
    data["dependencies"] = deps
    real.write_text(json.dumps(data, indent=2) + "\n")
    print("stripped", ", ".join(stripped), "from", real)
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

    # OMP binary only. Configuration belongs to ~/.dotfiles/omp.
    # Provider order: ZeroBrew → Homebrew can1357/tap/omp → https://omp.sh/install
    if ${installOmpScript}; then
      ok "omp present ($(omp --version 2>/dev/null | head -1 || echo ok))"
    else
      fail "omp install failed — ZeroBrew → Homebrew can1357/tap/omp → https://omp.sh/install"
    fi


pm @beads/bd or crates.io) ---
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
      log "rtk init for claude / codex / cursor (auto-patch where supported)..."
      rtk init -g --auto-patch 2>/dev/null && ok "rtk init claude" || fail "rtk init claude"
      rtk init -g --codex 2>/dev/null && ok "rtk init codex" || fail "rtk init codex"
      rtk init -g --agent cursor --auto-patch 2>/dev/null && ok "rtk init cursor" || fail "rtk init cursor"
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
      for agent in claude codex cursor grok; do
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
        _caveman_node_shim=$(mktemp -d "''${TMPDIR:-/tmp}/caveman-node.XXXXXX")
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
    }

    # Portable skill tree → ~/.agents/skills (Grok, Cursor, generic skill hosts).
    # Host plugins (Claude/Codex) add hooks/commands; this keeps the skill readable everywhere.
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

      # skills CLI (global) — same bun→node shims as caveman when Node missing
      _ponytail_node_shim=""
      if { ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; } \
        && command -v bun >/dev/null 2>&1; then
        _ponytail_node_shim=$(mktemp -d "''${TMPDIR:-/tmp}/ponytail-node.XXXXXX")
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

      # Portable skill files for multi-agent hosts.
      mkdir -p "$HOME/.agents/skills"
      if install_ponytail_skill_files "$HOME/.agents/skills"; then
        ok "ponytail: skill files in ~/.agents/skills (portable)"
        _ponytail_any=1
      fi
      # Drop accidental project copies that cause Skill conflicts in this repo
      if [ -d ".agents/skills" ]; then
        for _pt in ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help; do
          if [ -e ".agents/skills/$_pt" ]; then
            rm -rf ".agents/skills/$_pt"
            log "removed project .agents/skills/$_pt (use ~/.agents/skills)"
          fi
        done
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

  # OMP configuration is owned by ~/.dotfiles/omp (not Nix home.file).
  home.file = { };

  home.activation.installAgentTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "=== agent tools activation (fail-soft; shared stack: rtk/tokensave/headroom/context-mode/context7/caveman) ==="
    ${installScript} || echo "[agents] activation script exited non-zero (ignored)"
  '';
}

