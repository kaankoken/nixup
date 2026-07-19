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
  # No system Node/npm: JS CLIs (pi, codex, …) install via bun and run under bun.
  # Wrappers in ~/.local/bin exec: bun ~/.bun/bin/<name> …
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
      printf '%s\n' \
        '#!/bin/sh' \
        '# Managed by nix-setup modules/agents — run under bun (no Node required).' \
        "exec bun \"\$HOME/.bun/bin/${bin_name}\" \"\$@\"" \
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

    # --- codex-cli (bun global; no npm/node) ---
    if command -v codex >/dev/null 2>&1; then
      # Prefer bun wrapper if global bin exists
      [ -e "$HOME/.bun/bin/codex" ] && wrap_bun_cli codex || true
      ok "codex present"
    else
      log "installing codex-cli via bun..."
      if install_bun_cli "@openai/codex" codex; then
        ok "codex-cli via bun ($(codex --version 2>/dev/null | head -1 || echo ok))"
      else
        fail "codex-cli: bun install failed — desktop app is still manual"
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

    # --- beads ---
    # Prefer cargo (native). bun package needs a trusted postinstall to fetch the binary.
    if command -v bd >/dev/null 2>&1 || command -v beads >/dev/null 2>&1; then
      ok "beads present"
    else
      log "installing beads..."
      if command -v cargo >/dev/null 2>&1 && cargo install beads 2>/dev/null; then
        ok "beads via cargo"
      elif require_bun && bun install -g @beads/bd && bun pm -g trust @beads/bd 2>/dev/null; then
        # re-install so postinstall can download native bd
        bun install -g @beads/bd 2>/dev/null || true
        wrap_bun_cli bd || true
        if command -v bd >/dev/null 2>&1 || [ -x "$HOME/.local/bin/bd" ]; then
          ok "beads via bun"
        else
          fail "beads bun postinstall incomplete — try: cargo install beads"
        fi
      else
        fail "beads install failed — cargo install beads"
      fi
    fi

    # --- rtk: Darwin via zerobrew activation; not Nix ---
    if command -v rtk >/dev/null 2>&1; then
      ok "rtk present ($(rtk --version 2>/dev/null | head -1 || echo ok))"
    else
      fail "rtk missing — on Mac: zerobrew (`zb install rtk`); on Linux: https://github.com/rtk-ai/rtk"
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
