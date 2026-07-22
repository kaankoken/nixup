{
  lib,
  pkgs,
  user,
  ...
}:
let
  # Prefer zerobrew; fall back to Homebrew when zb cannot resolve a formula.
  # - mole: https://github.com/tw93/mole           (homebrew/core)
  # - aerospace: https://github.com/nikitabobko/AeroSpace
  #   (cask: nikitabobko/tap/aerospace — not in zb’s core index → brew fallback)
  #
  # rtk: official curl install in modules/agents (not zerobrew).
  # GUI apps (Ghostty/Zed/Signal/…) live in modules/darwin/home.nix via Nix.
  # headroom is uv tool install — see modules/agents.
  formulas = [
    "mole"
  ];

  formulaInstalls = lib.concatMapStrings (name: ''
    run_pkg "${name}"
  '') formulas;

  userHome = "/Users/${user}";

  installScript = pkgs.writeShellScript "zerobrew-activate" ''
    set -e
    # Caller must set HOME to the real user (not /var/root).
    export HOME="''${HOME:-${userHome}}"
    export USER="''${USER:-${user}}"
    # Common Homebrew prefixes on Apple Silicon / Intel.
    export PATH="/opt/zerobrew/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:/etc/profiles/per-user/${user}/bin:$PATH"

    log() { echo "[zerobrew] $*"; }
    die() { log "ERROR: $*"; exit 1; }

    if [ "$(id -u)" -eq 0 ]; then
      die "refusing to run package installs as root — should be invoked as ${user}"
    fi

    resolve_zb() {
      if command -v zb >/dev/null 2>&1; then
        command -v zb
        return 0
      fi
      if command -v zerobrew >/dev/null 2>&1; then
        command -v zerobrew
        return 0
      fi
      return 1
    }

    resolve_brew() {
      if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
      fi
      for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
          echo "$candidate"
          return 0
        fi
      done
      return 1
    }

    ensure_zerobrew() {
      if resolve_zb >/dev/null; then
        log "zerobrew present: $(resolve_zb)"
        return 0
      fi

      log "zerobrew missing — installing (hard dependency)..."

      if command -v curl >/dev/null 2>&1; then
        log "trying official installer: https://zerobrew.rs/install"
        if curl -fsSL https://zerobrew.rs/install | bash; then
          export PATH="/opt/zerobrew/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
          if resolve_zb >/dev/null; then
            log "zerobrew installed via official installer"
            return 0
          fi
        else
          log "official installer failed; trying cargo fallback..."
        fi
      fi

      if command -v cargo >/dev/null 2>&1; then
        log "trying cargo install --git https://github.com/lucasgelfond/zerobrew"
        if cargo install --git https://github.com/lucasgelfond/zerobrew; then
          export PATH="$HOME/.cargo/bin:$PATH"
          if resolve_zb >/dev/null; then
            log "zerobrew installed via cargo"
            return 0
          fi
        fi
      fi

      die "zerobrew is required but not installed. Install manually: curl -fsSL https://zerobrew.rs/install | bash"
    }

    # brew install with optional --cask; soft-fail.
    brew_install() {
      local brew_bin="$1"
      shift
      log "brew fallback: $brew_bin $*"
      if "$brew_bin" "$@"; then
        return 0
      fi
      return 1
    }

    ensure_zerobrew
    ZB="$(resolve_zb)" || die "zerobrew binary not found after ensure"
    log "using: $ZB"
    BREW="$(resolve_brew || true)"
    if [ -n "''${BREW:-}" ]; then
      log "brew fallback available: $BREW"
    else
      log "brew not on PATH — zb-only installs (no Homebrew fallback)"
    fi

    # Soft-fail: missing formulas must not brick activation.
    # Order: already present → zb → brew formula.
    run_pkg() {
      local name="$1"
      if command -v "$name" >/dev/null 2>&1; then
        log "skip $name (already on PATH: $(command -v "$name"))"
        return 0
      fi
      log "install: $name (zb)"
      if $ZB install "$name"; then
        log "ok: $name via zerobrew"
        return 0
      fi
      log "zb could not install $name"
      if [ -n "''${BREW:-}" ]; then
        if brew_install "$BREW" install "$name"; then
          log "ok: $name via brew"
          return 0
        fi
      fi
      log "WARN: $name not installed"
      case "$name" in
        mole) log "hint: https://github.com/tw93/mole" ;;
      esac
    }

    ${formulaInstalls}

    # aerospace: third-party cask nikitabobko/tap/aerospace
    ensure_aerospace() {
      if command -v aerospace >/dev/null 2>&1; then
        log "skip aerospace (already on PATH: $(command -v aerospace))"
        return 0
      fi
      log "install: aerospace (zb → brew cask)"
      if $ZB install aerospace 2>/dev/null; then
        log "ok: aerospace via zerobrew"
        return 0
      fi
      log "zb has no aerospace formula (third-party tap)"
      if [ -n "''${BREW:-}" ]; then
        # Official install path from https://github.com/nikitabobko/AeroSpace
        if brew_install "$BREW" install --cask nikitabobko/tap/aerospace; then
          log "ok: aerospace via brew cask nikitabobko/tap/aerospace"
          return 0
        fi
        # Older / alternate form
        if brew_install "$BREW" install --cask aerospace; then
          log "ok: aerospace via brew cask aerospace"
          return 0
        fi
      else
        log "brew not available for aerospace fallback"
      fi
      log "WARN: aerospace not installed"
      log "hint: brew install --cask nikitabobko/tap/aerospace"
      return 0
    }

    ensure_aerospace

    log "zerobrew activation complete (mole/aerospace: zb then brew; rtk/headroom via agents)"
    exit 0
  '';
in
{
  # postActivation runs as root under `sudo darwin-rebuild`. Must re-exec as the
  # real user with -H so zb uses /Users/<user>, not /var/root.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "=== zerobrew activation (mole, aerospace; brew fallback) ==="
    if id "${user}" >/dev/null 2>&1; then
      sudo -u "${user}" -H \
        env HOME="${userHome}" USER="${user}" LOGNAME="${user}" \
        ${installScript}
    else
      echo "[zerobrew] ERROR: user ${user} not found" >&2
      exit 1
    fi
  '';
}
