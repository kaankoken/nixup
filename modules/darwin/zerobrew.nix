{
  lib,
  pkgs,
  user,
  ...
}:
let
  # GUI / cask-style tools. Fail-soft. Never run brew as root (HOME=/var/root breaks Homebrew).
  formulas = [ "rtk" ];

  # Codex desktop: v1 skip (manual). CLI codex is agents module.
  casks = [
    "ghostty"
    "zed"
    "signal"
    "slack"
    "whatsapp"
    "microsoft-outlook"
  ];

  formulaInstalls = lib.concatMapStrings (name: ''
    run_pkg formula "${name}"
  '') formulas;

  caskInstalls = lib.concatMapStrings (name: ''
    run_pkg cask "${name}"
  '') casks;

  userHome = "/Users/${user}";

  installScript = pkgs.writeShellScript "zerobrew-activate" ''
    set +e
    # Caller must set HOME to the real user (not /var/root).
    export HOME="''${HOME:-${userHome}}"
    export USER="''${USER:-${user}}"
    export PATH="/opt/zerobrew/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:/etc/profiles/per-user/${user}/bin:$PATH"
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_ENV_HINTS=1

    log() { echo "[zerobrew] $*"; }
    fail(){ log "WARN (soft-fail): $*"; }

    if [ "$(id -u)" -eq 0 ]; then
      fail "refusing to run package installs as root — should be invoked as ${user}"
      exit 0
    fi

    ensure_zerobrew() {
      if command -v zb >/dev/null 2>&1 || command -v zerobrew >/dev/null 2>&1; then
        log "zerobrew present"
        return 0
      fi
      log "zerobrew not found — attempting cargo install (experimental)..."
      if command -v cargo >/dev/null 2>&1; then
        cargo install --git https://github.com/lucasgelfond/zerobrew 2>/dev/null && return 0
      fi
      fail "install zerobrew manually: https://github.com/lucasgelfond/zerobrew"
      return 1
    }

    ZB=""
    if command -v zb >/dev/null 2>&1; then ZB="zb"
    elif command -v zerobrew >/dev/null 2>&1; then ZB="zerobrew"
    fi

    if [ -z "$ZB" ]; then
      ensure_zerobrew
      if command -v zb >/dev/null 2>&1; then ZB="zb"
      elif command -v zerobrew >/dev/null 2>&1; then ZB="zerobrew"
      fi
    fi

    run_pkg() {
      local kind="$1"
      local name="$2"
      if [ -n "$ZB" ]; then
        if [ "$kind" = "cask" ]; then
          $ZB install --cask "$name" 2>/dev/null || $ZB install "$name" 2>/dev/null || fail "zb could not install $name"
        else
          $ZB install "$name" 2>/dev/null || fail "zb could not install $name"
        fi
      elif command -v brew >/dev/null 2>&1; then
        if [ "$kind" = "cask" ]; then
          if brew list --cask "$name" >/dev/null 2>&1; then
            log "cask already installed: $name"
          else
            brew install --cask "$name" || fail "brew cask $name failed"
          fi
        else
          if brew list "$name" >/dev/null 2>&1; then
            log "formula already installed: $name"
          else
            brew install "$name" || fail "brew $name failed"
          fi
        fi
      else
        fail "no zerobrew/brew to install $name"
      fi
    }

    ${formulaInstalls}
    ${caskInstalls}

    if command -v mole >/dev/null 2>&1; then
      log "mole present"
    else
      log "installing mole..."
      if [ -n "$ZB" ]; then
        $ZB install mole 2>/dev/null || true
      fi
      if ! command -v mole >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
        brew install tw93/tap/mole 2>/dev/null || brew install mole 2>/dev/null || true
      fi
      if ! command -v mole >/dev/null 2>&1; then
        curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash || fail "mole install failed"
      fi
    fi

    if ! command -v aerospace >/dev/null 2>&1; then
      log "aerospace missing — trying package manager..."
      if command -v brew >/dev/null 2>&1; then
        brew list --cask nikitabobko/tap/aerospace >/dev/null 2>&1 \
          || brew install --cask nikitabobko/tap/aerospace \
          || fail "aerospace not installed"
      else
        fail "aerospace not installed"
      fi
    else
      log "aerospace present"
    fi

    exit 0
  '';
in
{
  # postActivation runs as root under `sudo darwin-rebuild`. Must re-exec as the
  # real user with -H so Homebrew uses /Users/<user>, not /var/root.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "=== zerobrew / GUI package activation (fail-soft) ==="
    if id "${user}" >/dev/null 2>&1; then
      sudo -u "${user}" -H \
        env HOME="${userHome}" USER="${user}" LOGNAME="${user}" \
            HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 \
        ${installScript} \
        || echo "[zerobrew] activation soft-failed"
    else
      echo "[zerobrew] user ${user} not found — skip"
    fi
  '';
}
