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
  # No system Node/npm for agent runtimes we control: pi installs via bun.
  # codex / rtk / grok / claude / beads / caveman: official curl|sh installers.
  # Wrappers in ~/.local/bin for bun CLIs: exec bun ~/.bun/bin/<name> …
  installScript = pkgs.writeShellScript "install-agent-tools" ''
    set +e
    export PATH="${pkgs.bun}/bin:${pkgs.uv}/bin:${pkgs.curl}/bin:${pkgs.bash}/bin:$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$PATH"

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

    # Global bun package + ~/.local/bin wrapper that runs the entry under bun
    # (packages ship #!/usr/bin/env node; we never put Node on PATH).
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

    # --- codex CLI (official installer; not bun) ---
    # https://chatgpt.com/codex/install.sh
    if command -v codex >/dev/null 2>&1; then
      ok "codex present ($(codex --version 2>/dev/null | head -1 || echo ok))"
    else
      log "installing codex via https://chatgpt.com/codex/install.sh ..."
      if curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        ok "codex install attempted ($(codex --version 2>/dev/null | head -1 || echo ok))"
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

    # --- rtk (official installer; not zerobrew) ---
    # https://github.com/rtk-ai/rtk
    if command -v rtk >/dev/null 2>&1; then
      ok "rtk present ($(rtk --version 2>/dev/null | head -1 || echo ok))"
    else
      log "installing rtk via official install.sh..."
      if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        ok "rtk install attempted ($(rtk --version 2>/dev/null | head -1 || echo ok))"
      else
        fail "rtk install failed — curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
      fi
    fi

    # --- caveman (multi-agent skill; not a PATH CLI) ---
    # https://github.com/JuliusBrussee/caveman
    # Installer needs Node ≥18; safe to re-run. No system Node in this flake — soft-fail.
    caveman_marker() {
      [ -e "$HOME/.claude/skills/caveman/SKILL.md" ] \
        || [ -e "$HOME/.claude/skills/caveman/skill.md" ] \
        || [ -d "$HOME/.codex/skills/caveman" ] \
        || [ -d "$HOME/.gemini/extensions/caveman" ] \
        || [ -e "$HOME/.cursor/skills/caveman/SKILL.md" ] \
        || [ -d "$HOME/.agents/skills/caveman" ]
    }
    if caveman_marker; then
      ok "caveman skill markers present"
    else
      log "installing caveman via https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh ..."
      if command -v node >/dev/null 2>&1 || command -v bun >/dev/null 2>&1; then
        # Prefer real node if present; otherwise try with bun on PATH (install may still need node).
        if curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash; then
          if caveman_marker; then
            ok "caveman installed"
          else
            ok "caveman install script finished (markers not detected — open an agent and /caveman)"
          fi
        else
          fail "caveman install failed — needs Node ≥18: curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash"
        fi
      else
        fail "caveman skipped — Node ≥18 required by installer (not provided by this flake)"
      fi
    fi

    exit 0
  '';
in
{
  home.packages = with pkgs; [
    # uv / bun / curl for agent installers (bun replaces node/npm)
    uv
    bun
    curl
  ];

  home.activation.installAgentTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "=== agent tools activation (fail-soft; bun not node) ==="
    ${installScript} || echo "[agents] activation script exited non-zero (ignored)"
  '';
}
