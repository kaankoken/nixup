{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Fail-soft installer helpers run during home-manager activation.
  # Official channels change — keep commands documented and soft.
  installScript = pkgs.writeShellScript "install-agent-tools" ''
    set +e
    export PATH="${pkgs.uv}/bin:${pkgs.curl}/bin:${pkgs.bash}/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    log() { echo "[agents] $*"; }
    ok()  { log "OK: $*"; }
    skip(){ log "skip: $*"; }
    fail(){ log "WARN (soft-fail): $*"; }

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

    # --- codex-cli ---
    if command -v codex >/dev/null 2>&1; then
      ok "codex present"
    else
      log "installing codex-cli (npm if available)..."
      if command -v npm >/dev/null 2>&1; then
        npm install -g @openai/codex && ok "codex-cli via npm" || fail "codex npm install failed"
      else
        fail "codex-cli: npm not found — install Node/npm or Codex desktop separately"
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

    # --- beads ---
    if command -v bd >/dev/null 2>&1 || command -v beads >/dev/null 2>&1; then
      ok "beads present"
    else
      log "installing beads..."
      if command -v npm >/dev/null 2>&1 && npm install -g @beads/bd 2>/dev/null; then
        ok "beads via npm"
      elif command -v cargo >/dev/null 2>&1 && cargo install beads 2>/dev/null; then
        ok "beads via cargo"
      else
        fail "beads install failed — install manually from project docs"
      fi
    fi

    # --- radicle (experimental) ---
    if command -v rad >/dev/null 2>&1; then
      ok "radicle present"
    else
      log "installing radicle (experimental)..."
      if curl -sSf https://radicle.xyz/install | sh -s -- --no-modify-path 2>/dev/null; then
        ok "radicle install attempted"
      else
        fail "radicle install failed (experimental — optional)"
      fi
    fi

    # --- rtk fallback if not provided by nixpkgs ---
    if command -v rtk >/dev/null 2>&1; then
      ok "rtk present ($(rtk --version 2>/dev/null | head -1 || echo ok))"
    else
      fail "rtk missing — on Mac use zerobrew/brew; on Linux install from https://www.rtk-ai.app/"
    fi

    exit 0
  '';
in
{
  home.packages = with pkgs; [
    # uv needed for headroom; curl for installers
    uv
    curl
  ];

  home.activation.installAgentTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "=== agent tools activation (fail-soft) ==="
    ${installScript} || echo "[agents] activation script exited non-zero (ignored)"
  '';
}
