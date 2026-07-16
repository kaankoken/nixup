# Nix Multi-Machine Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a flake-based nix-darwin + home-manager setup that installs Kaan’s developer toolchain on 2 Apple Silicon Macs and 1 Linux host, with zerobrew for macOS GUIs, stow-managed configs in a separate `.dotfiles` repo, and a smoke script that proves the machine is good.

**Architecture:** One flake (`nix-setup`) exposes `darwinConfigurations` (nix-darwin + home-manager) for each Mac and `homeConfigurations` for Linux. Shared modules own packages and shell binaries; app configs stay in `~/.dotfiles` via GNU stow. Agent tools and zerobrew install via fail-soft activation scripts. Homebrew remains until smoke is green, then cut over.

**Tech Stack:** Nix flakes, nixpkgs-unstable, nix-darwin, home-manager, nushell scripts, zerobrew (experimental Homebrew-compatible), rustup, uv, GNU stow

**Spec:** @docs/superpowers/specs/2026-07-16-nix-multi-machine-design.md  
**User prefs (RTK):** When running shell via agents, prefer prefixing with `rtk` if available (`rtk` is optional in smoke). No `RTK.md` lives in this repo — do not search for it as a required file.

**Plan review gates (must hold for Subagent-Driven):**
- Human STOP before Nix install and before `darwin-rebuild` / first switch
- Full inlined code for zerobrew, agents, bootstrap, smoke (no “copy from tree”)
- `rtk` optional in smoke; PATH built as one ordered list (not repeated `prepend`)
- Ghostty via zerobrew/brew only (not also `pkgs.ghostty` unless nixpkgs is the sole channel)
- Commit `flake.lock` after first successful eval
- Dead-tool prune: **out of scope for this plan** (paths only; prune later)

**Current repo state (read before Task 1):** A partial scaffold already exists under `~/Desktop/personal/nix-setup` (flake, modules, hosts, scripts, README) and some `.dotfiles` path edits. Treat existing files as **drafts**: open them, compare to each task’s “Write” steps, **fix or replace** so the file matches the plan, then commit. Do not invent a second parallel layout.

**Machine facts (this Mac):**
- Hostname: `kaan-macmini`
- User: `legolas`
- Arch: `aarch64-darwin`
- Nix: may not be installed yet
- Dotfiles: `~/.dotfiles` (separate git repo)

---

### Task 1: Confirm git + baseline commit of scaffold (or init)

**Files:**
- Verify: entire `nix-setup` tree
- Create if missing: `.gitignore`

**Step 1: Check git status**

Run:

```bash
cd ~/Desktop/personal/nix-setup
git status
ls -la
```

Expected: repo exists (or empty git). List of files including `flake.nix` or not.

**Step 2: Ensure generated local state is ignored**

Create/overwrite `.gitignore`:

```gitignore
# Nix
result
result-*
.direnv/
.pre-commit-config.yaml.bak

# Editor / OS
.DS_Store
*.swp
*~

# Local secrets and generated agent state (never commit)
*.pem
.env
.env.*
/.tokensave/
/.beads/
```

**Step 3: Baseline commit if uncommitted**

Run:

```bash
cd ~/Desktop/personal/nix-setup
git check-ignore -v .beads .tokensave
git add .gitignore README.md docs flake.nix hosts modules scripts spec.md todo.md
git status
git commit -m "chore: baseline nix-setup scaffold and design docs"
```

Expected: `.beads/` and `.tokensave/` are ignored, only the named scaffold paths are staged, and the commit succeeds (or reports “nothing to commit” if already clean). Do not use `git add -A` for this baseline.

---

### Task 2: Flake skeleton evaluates hosts

**Files:**
- Create/replace: `flake.nix`
- Create/replace: `hosts/kaan-macmini/default.nix`
- Create/replace: `hosts/mac-2/default.nix`
- Create/replace: `hosts/linux/default.nix`
- Create/replace: `modules/common/default.nix` (minimal stub OK)
- Create/replace: `modules/shell/default.nix` (minimal stub OK)
- Create/replace: `modules/agents/default.nix` (minimal stub OK)
- Create/replace: `modules/darwin/default.nix` (minimal stub OK)
- Create/replace: `modules/darwin/home.nix` (minimal stub OK)
- Create/replace: `modules/darwin/zerobrew.nix` (minimal stub OK)
- Create/replace: `modules/linux/default.nix` (minimal stub OK)

**Step 1: Write `flake.nix`**

Full content:

```nix
{
  description = "Kaan's multi-machine nix-darwin + home-manager setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      mkSpecialArgs = system: {
        inherit self;
        flakeInputs = { inherit nixpkgs nix-darwin home-manager; };
      };

      sharedHomeModules = [
        ./modules/common
        ./modules/shell
        ./modules/agents
      ];

      mkDarwin =
        {
          hostName,
          hostPath,
          system ? "aarch64-darwin",
          user ? "legolas",
        }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = mkSpecialArgs system // { inherit hostName user; };
          modules = [
            ./modules/darwin
            hostPath
            home-manager.darwinModules.home-manager
            {
              nixpkgs.hostPlatform = system;
              networking.hostName = hostName;
              users.users.${user} = {
                name = user;
                home = "/Users/${user}";
              };
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = mkSpecialArgs system // { inherit hostName user; };
                users.${user} = {
                  imports = sharedHomeModules ++ [ ./modules/darwin/home.nix ];
                  home.username = user;
                  home.homeDirectory = "/Users/${user}";
                  home.stateVersion = "25.05";
                };
              };
            }
          ];
        };

      mkLinuxHome =
        {
          hostName,
          user ? "legolas",
          system ? "x86_64-linux",
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          extraSpecialArgs = mkSpecialArgs system // { inherit hostName user; };
          modules = sharedHomeModules ++ [
            ./modules/linux
            ./hosts/linux
            {
              home.username = user;
              home.homeDirectory = "/home/${user}";
              home.stateVersion = "25.05";
            }
          ];
        };
    in
    {
      darwinConfigurations.kaan-macmini = mkDarwin {
        hostName = "kaan-macmini";
        hostPath = ./hosts/kaan-macmini;
      };

      darwinConfigurations.mac-2 = mkDarwin {
        hostName = "mac-2";
        hostPath = ./hosts/mac-2;
      };

      homeConfigurations."legolas@linux" = mkLinuxHome {
        hostName = "linux";
        system = "x86_64-linux";
      };

      formatter = lib.genAttrs [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (
        system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style
      );
    };
}
```

**Step 2: Minimal host modules**

`hosts/kaan-macmini/default.nix`:

```nix
{ lib, ... }:
{
  networking.hostName = lib.mkForce "kaan-macmini";
  networking.computerName = lib.mkForce "Kaan's Mac mini";
  networking.localHostName = lib.mkForce "kaan-macmini";
}
```

`hosts/mac-2/default.nix`:

```nix
{ lib, ... }:
{
  networking.hostName = lib.mkDefault "mac-2";
  networking.localHostName = lib.mkDefault "mac-2";
  networking.computerName = lib.mkDefault "mac-2";
}
```

`hosts/linux/default.nix`:

```nix
{ ... }:
{
  home.sessionVariables.NIX_HOST = "linux";
}
```

**Step 3: Minimal module stubs** (replace with real content in later tasks if already full — keep working versions)

`modules/common/default.nix` (minimal until Task 3):

```nix
{ pkgs, ... }:
{
  # Do NOT set home.stateVersion here — only in flake.nix user / homeConfiguration blocks.
  # Do NOT set nixpkgs.config here when home-manager.useGlobalPkgs = true (set on darwin / Linux pkgs import).
  home.packages = [ pkgs.hello ];
}
```

`modules/shell/default.nix`:

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [ nushell starship ];
}
```

`modules/agents/default.nix` (empty activation for now):

```nix
{ ... }:
{
  # filled in Task 5
}
```

`modules/darwin/default.nix`:

```nix
{ lib, pkgs, user, hostName, ... }:
{
  imports = [ ./zerobrew.nix ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" user ];
  nixpkgs.config.allowUnfree = true;

  system.primaryUser = user;

  users.users.${user}.shell = pkgs.nushell;
  environment.shells = with pkgs; [ bashInteractive zsh nushell ];
  environment.systemPackages = with pkgs; [ nushell git vim ];

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];

  programs.zsh.enable = true;
  security.pam.services.sudo_local.touchIdAuth = true;
  system.stateVersion = 5;

  networking.computerName = lib.mkDefault hostName;
  networking.localHostName = lib.mkDefault hostName;
}
```

`modules/darwin/home.nix`:

```nix
{ ... }: { }
```

`modules/darwin/zerobrew.nix` (noop until Task 4):

```nix
{ ... }: { }
```

`modules/linux/default.nix`:

```nix
{ ... }: { }
```

**Step 4: Check for Nix and stop at the install gate if it is missing**

Run:

```bash
nix --version
```

If this prints a version, continue to Step 5.

If Nix is missing, **STOP and ask the user for explicit confirmation** before running the installer. Explain that the following command downloads code, requests `sudo`, creates `/nix`, and installs a system daemon:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Do not run it until the user confirms. After an approved install, open a new shell if needed and run `nix --version`; expected: version printed.

**Step 5: Evaluate flake (does not apply system yet)**

Run:

```bash
cd ~/Desktop/personal/nix-setup
nix flake show
nix build .#darwinConfigurations.kaan-macmini.system --dry-run
```

Expected: flake shows `darwinConfigurations.kaan-macmini`, `mac-2`, `homeConfigurations."legolas@linux"`. Dry-run resolves without eval errors. If nerd-fonts attrs fail, fix names against current nixpkgs (`nix search nixpkgs nerd-fonts`).

**Step 6: Commit skeleton + lockfile**

After a successful eval, `flake.lock` must exist (created by the first `nix flake show` / `nix build`). Commit it with the skeleton:

```bash
cd ~/Desktop/personal/nix-setup
test -f flake.lock
git add flake.nix flake.lock hosts modules
git commit -m "feat: multi-host flake skeleton with module stubs"
```

If eval could not run yet (Nix not installed, user deferred install), commit without `flake.lock` and add a note in the commit body; re-run this step and commit `flake.lock` as soon as the first eval succeeds (do not leave lock uncommitted after Task 10).

---

### Task 3: Common packages + shell modules

**Files:**
- Replace: `modules/common/default.nix`
- Replace: `modules/shell/default.nix`

**Step 1: Write full `modules/common/default.nix`**

```nix
{ config, lib, pkgs, ... }:
let
  optionalPkg = name: lib.optional (pkgs ? ${name}) pkgs.${name};
  modernCli = with pkgs; [
    stow
    git
    gh
    neovim
    zellij
    atuin
    lazygit
    ripgrep
    fd
    eza
    zoxide
    bat
    dust
    sd
    delta
    procs
    uv
    bun
    zola
    jq
    curl
    wget
    tree
    unzip
    gnutar
  ];
  rtkPkgs = optionalPkg "rtk";
in
{
  home.packages = modernCli ++ rtkPkgs;

  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "bat";
  };

  home.activation.checkDotfilesStow = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.config/nushell/config.nu" ]; then
      echo "WARNING: ~/.config/nushell/config.nu missing — clone .dotfiles and run: stow ."
    fi
  '';
}
```

**Step 2: Write full `modules/shell/default.nix`**

Do **not** enable `programs.nushell` / `programs.starship` (they write configs and fight stow).

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nushell
    starship
  ];

  home.sessionVariables = {
    SHELL = "${pkgs.nushell}/bin/nu";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/.radicle/bin"
  ];
}
```

**Step 3: Re-evaluate**

```bash
cd ~/Desktop/personal/nix-setup
nix build .#darwinConfigurations.kaan-macmini.system --dry-run
```

Expected: success (may download). Fix any unknown package attrs.

**Step 4: Commit**

```bash
git add modules/common/default.nix modules/shell/default.nix
git commit -m "feat: common CLI packages and shell binaries (stow-friendly)"
```

---

### Task 4: Darwin system + zerobrew/mole activation

**Files:**
- Replace: `modules/darwin/default.nix` (if not already full from Task 2)
- Replace: `modules/darwin/home.nix`
- Replace: `modules/darwin/zerobrew.nix`

**Step 1: Darwin home extras**

Ghostty is **zerobrew/brew-only** (cask list below). Do not also pull `pkgs.ghostty` here — avoids two competing installs. Aerospace: prefer nixpkgs when present; zerobrew/brew is the fallback in the activation script.

`modules/darwin/home.nix`:

```nix
{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs ? aerospace) pkgs.aerospace;
}
```

**Step 2: Full zerobrew module**

Write the complete file below; do not replace it with a reference to the current working tree.

**Codex desktop (v1):** not in the cask list — install manually if needed; document as known gap. CLI `codex` is handled by the agents module.

```nix
{
  lib,
  pkgs,
  user,
  ...
}:
let
  # GUI / cask-style tools Nix does not own cleanly.
  # Applied via zerobrew when available; brew fallback during parallel migration.
  formulas = [
    "rtk"
  ];

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

  installScript = pkgs.writeShellScript "zerobrew-activate" ''
    set +e
    export PATH="/opt/zerobrew/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    log() { echo "[zerobrew] $*"; }
    fail(){ log "WARN (soft-fail): $*"; }

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
          brew list --cask "$name" >/dev/null 2>&1 || brew install --cask "$name" || fail "brew cask $name failed"
        else
          brew list "$name" >/dev/null 2>&1 || brew install "$name" || fail "brew $name failed"
        fi
      else
        fail "no zerobrew/brew to install $name"
      fi
    }

    ${formulaInstalls}
    ${caskInstalls}

    # mole (mac-only cleanup)
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

    # aerospace fallback if not from nixpkgs
    if ! command -v aerospace >/dev/null 2>&1; then
      log "aerospace missing — trying package manager..."
      if command -v brew >/dev/null 2>&1; then
        brew list --cask nikitabobko/tap/aerospace >/dev/null 2>&1 \
          || brew install --cask nikitabobko/tap/aerospace \
          || fail "aerospace not installed"
      else
        fail "aerospace not installed"
      fi
    fi

    exit 0
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "=== zerobrew / GUI package activation (fail-soft) ==="
    if id "${user}" >/dev/null 2>&1; then
      sudo -u "${user}" ${installScript} || echo "[zerobrew] activation soft-failed"
    else
      ${installScript} || true
    fi
  '';
}
```

**Step 3: Ensure `modules/darwin/default.nix` imports zerobrew and sets shell/fonts** (Task 2 full version).

**Step 4: Dry-run again**

```bash
nix build .#darwinConfigurations.kaan-macmini.system --dry-run
```

Expected: success.

**Step 5: Commit**

```bash
git add modules/darwin
git commit -m "feat: nix-darwin system, fonts, zerobrew/mole activation"
```

---

### Task 5: Agent installers (fail-soft)

**Files:**
- Replace: `modules/agents/default.nix`

**Step 1: Write agents module**

Behavior (must match design):

| Tool | Install |
|------|---------|
| rustup | `curl https://sh.rustup.rs \| sh -s -- -y --no-modify-path` if missing |
| headroom | `uv tool install "headroom-ai[proxy,ml,code,mcp,evals]"` |
| claude | official install.sh if missing |
| codex | `npm i -g @openai/codex` if npm present |
| grok / grok-build | detect only; soft-fail message |
| beads/bd | npm or cargo soft try |
| radicle | official install script soft |
| rtk | detect; soft message if missing |

Write the complete file below. It uses `home.activation` with `lib.hm.dag.entryAfter [ "writeBoundary" ]` and makes every installer fail-soft:

```nix
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

    # --- grok-build / grok CLI ---
    if command -v grok >/dev/null 2>&1 || command -v grok-build >/dev/null 2>&1; then
      ok "grok tooling present"
    else
      fail "grok-build not found — install via official xAI / grok-build channel when available"
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
```

**Step 2: Dry-run**

```bash
nix build .#darwinConfigurations.kaan-macmini.system --dry-run
```

**Step 3: Commit**

```bash
git add modules/agents/default.nix
git commit -m "feat: fail-soft agent tool activation (rustup, headroom, claude, …)"
```

---

### Task 6: Linux home + second Mac host sanity

**Files:**
- Verify: `hosts/mac-2/default.nix`, `hosts/linux/default.nix`, `modules/linux/default.nix`
- Modify: `modules/linux/default.nix` for rtk hint

**Step 1: Linux module**

```nix
{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [ xdg-utils ];

  home.activation.linuxRtkHint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v rtk >/dev/null 2>&1; then
      echo "[linux] rtk not on PATH — install from https://www.rtk-ai.app/ if needed"
    fi
  '';
}
```

**Step 2: Evaluate Linux HM config**

```bash
cd ~/Desktop/personal/nix-setup
nix build '.#homeConfigurations."legolas@linux".activationPackage' --dry-run
```

Expected: success (or note aarch64 if that machine is ARM — document in README).

**Step 3: Commit**

```bash
git add modules/linux hosts
git commit -m "feat: linux home-manager host and mac-2 placeholder"
```

---

### Task 7: Bootstrap + smoke scripts

**Files:**
- Create/replace: `scripts/bootstrap.nu`
- Create/replace: `scripts/smoke.nu`

**Step 1: `scripts/bootstrap.nu`**

Write the complete file below. Its interactive confirmation is required before any install or switch:

```nu
#!/usr/bin/env nu
# Day-0 bootstrap for nix-setup
# Usage: nu scripts/bootstrap.nu [--host kaan-macmini]

def main [
  --host: string = "kaan-macmini"  # flake host attr (darwin) or ignore for linux
  --linux                              # use home-manager instead of darwin-rebuild
  --linux-attr: string = "legolas@linux"
] {
  # scripts/ lives under repo root
  let repo_root = (
    if ($env | get -o FILE_PWD) != null {
      $env.FILE_PWD | path dirname
    } else {
      $env.PWD
    }
  )

  print $"=== nix-setup bootstrap ==="
  print $"repo: ($repo_root)"
  print $"host: ($host)"

  print "This script may download installers, request sudo, and change system/user configuration."
  let approval = (input "Continue? [y/N] " | str trim | str downcase)
  if $approval not-in ["y" "yes"] {
    print "Cancelled before system changes."
    return
  }

  # 1) Ensure Nix
  if (which nix | is-empty) {
    print "Nix not found. Installing via Determinate Systems installer..."
    print "(You will be prompted for sudo / admin)"
    ^curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | ^sh -s -- install
    print "Nix install finished. Open a new shell or source nix profile, then re-run this script."
    print "  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish  # or bash equivalent"
    return
  } else {
    print $"Nix OK: (^nix --version | str trim)"
  }

  # 2) Apply flake
  cd $repo_root
  if $linux {
    print $"Applying home-manager: .#($linux_attr)"
    if (which home-manager | is-empty) {
      print "Installing home-manager into user profile (one-time)..."
      ^nix run home-manager/master -- switch --flake $".#($linux_attr)"
    } else {
      ^home-manager switch --flake $".#($linux_attr)"
    }
  } else {
    print $"Applying nix-darwin: .#($host)"
    ^nix run nix-darwin -- switch --flake $".#($host)"
  }

  # 3) Dotfiles reminder
  let dotfiles = ($env.HOME | path join ".dotfiles")
  if not ($dotfiles | path exists) {
    print "Clone dotfiles next:"
    print "  git clone git@github.com:kaankoken/.dotfiles.git ~/.dotfiles"
  } else {
    print $"Dotfiles found at ($dotfiles)"
    print "Apply stow from that repo:"
    print "  cd ~/.dotfiles; stow ."
  }

  print ""
  print "Then run smoke tests:"
  print $"  nu ($repo_root)/scripts/smoke.nu"
  print $"  nu ($repo_root)/scripts/smoke.nu --strict"
}
```

**Step 2: `scripts/smoke.nu`**

Write the complete file below. `rtk` is optional because nixpkgs only provides it conditionally and the Linux path is advisory; `--strict` must only enforce tools this plan guarantees on every host:

```nu
#!/usr/bin/env nu
# Smoke-test declared tooling. Default: report all. --strict: non-zero if required missing.

def is_mac [] {
  (uname | get kernel-name) == "Darwin"
}

def check_cmd [name: string, required: bool = true] {
  let found = (which $name | is-not-empty)
  if $found {
    let path = (which $name | get 0.path)
    { name: $name, ok: true, required: $required, detail: $path }
  } else {
    { name: $name, ok: false, required: $required, detail: "MISSING" }
  }
}

def main [
  --strict  # exit 1 if any required tool is missing
] {
  mut checks = []

  let required = [
    "nu" "starship" "stow" "git" "gh"
    "nvim" "zellij" "atuin" "lazygit"
    "rg" "fd" "eza" "zoxide" "bat" "dust" "sd" "delta" "procs"
    "uv" "bun" "zola"
    "rustc" "cargo"
  ]

  for name in $required {
    $checks = ($checks | append (check_cmd $name true))
  }

  # Soft / agent tools
  for name in ["rtk" "headroom" "claude" "codex" "bd" "beads" "rad" "grok" "grok-build"] {
    $checks = ($checks | append (check_cmd $name false))
  }

  if (is_mac) {
    for name in ["aerospace" "mole"] {
      $checks = ($checks | append (check_cmd $name false))
    }
    # GUI apps: check Applications bundle roughly
    for app in ["Ghostty" "Zed" "Signal" "Slack" "WhatsApp"] {
      let path = $"/Applications/($app).app"
      let ok = ($path | path exists)
      $checks = ($checks | append {
        name: $"app:($app)"
        ok: $ok
        required: false
        detail: (if $ok { $path } else { "MISSING" })
      })
    }
  }

  print "=== smoke results ==="
  for row in $checks {
    let mark = (if $row.ok { "OK  " } else { "FAIL" })
    let req = (if $row.required { "req" } else { "opt" })
    print $"($mark) [($req)] ($row.name) — ($row.detail)"
  }

  # PATH provenance hints
  print ""
  print "=== which (PATH provenance) ==="
  for name in ["nu" "rg" "nvim" "uv" "starship"] {
    if (which $name | is-not-empty) {
      print $"($name): (which $name | get 0.path)"
    }
  }

  let failed_req = ($checks | where {|r| (not $r.ok) and $r.required })
  let failed_opt = ($checks | where {|r| (not $r.ok) and (not $r.required) })

  print ""
  print $"Required missing: ($failed_req | length)"
  print $"Optional missing: ($failed_opt | length)"

  if $strict and ($failed_req | length) > 0 {
    print "STRICT mode: failing due to required tools missing"
    exit 1
  }
}
```

**Step 3: Run smoke against current (pre-Nix-apply) machine**

```bash
nu ~/Desktop/personal/nix-setup/scripts/smoke.nu
```

Expected: script runs; some required tools may FAIL until switch (e.g. eza/bat/dust). That’s OK — records baseline.

**Step 4: Commit**

```bash
git add scripts
git commit -m "feat: bootstrap and smoke scripts"
```

---

### Task 8: README + known gaps

**Files:**
- Create/replace: `README.md`
- Update: `todo.md`

**Step 1: README must document**

- Host table (`kaan-macmini`, `mac-2`, `legolas@linux`)  
- Day-0 Mac commands  
- Day-0 Linux commands  
- Package split (Nix / zerobrew / activation)  
- Homebrew parallel cutover steps  
- Known gaps (Outlook/WhatsApp/Signal casks, **codex desktop manual**, grok-build, experimental zerobrew, rtk on Linux, dead-tool prune later)  

**Step 2: Commit**

```bash
git add README.md todo.md
git commit -m "docs: README host apply guide and migration notes"
```

---

### Task 9: Dotfiles path distill (separate repo)

**Scope:** path fixes + Ghostty resolver only. **Dead-tool prune** (removing wezterm/tmux leftovers, unused configs) is **out of scope** for this plan — track as follow-up, do not expand this task.

**Files (in `~/.dotfiles`):**
- Create: `bin/nu-for-ghostty`
- Modify: `.config/ghostty/config`
- Modify: `.config/nushell/config.nu`
- Modify: `.config/nushell/env.nu`
- Optional: `README.md` path notes

**Step 1: Ghostty resolver script**

`~/.dotfiles/bin/nu-for-ghostty`:

```sh
#!/bin/sh
for candidate in \
  "/etc/profiles/per-user/$USER/bin/nu" \
  "$HOME/.nix-profile/bin/nu" \
  "/run/current-system/sw/bin/nu" \
  "/opt/homebrew/bin/nu" \
  "/usr/local/bin/nu"
do
  if [ -x "$candidate" ]; then
    exec "$candidate" -l \
      --config "$HOME/.config/nushell/config.nu" \
      --env-config "$HOME/.config/nushell/env.nu" "$@"
  fi
done
exec nu -l --config "$HOME/.config/nushell/config.nu" --env-config "$HOME/.config/nushell/env.nu" "$@"
```

```bash
chmod +x ~/.dotfiles/bin/nu-for-ghostty
```

**Step 2: Ghostty config**

Set:

```
command = /Users/legolas/.dotfiles/bin/nu-for-ghostty
```

**Step 3: Set Nushell PATH with explicit Nix-first precedence**

In `.config/nushell/config.nu`, construct one ordered list. Do not call `prepend` repeatedly: each later call inserts at the front and would let Homebrew win.

```nu
let managed_paths = ([
    $"/etc/profiles/per-user/($env.USER)/bin"
    $"($env.HOME)/.nix-profile/bin"
    "/run/current-system/sw/bin"
    "/opt/homebrew/bin"
    "/usr/local/bin"
] | where {|p| $p | path exists })

$env.PATH = ($managed_paths | append $env.PATH | uniq)
```

This makes the user Nix profile win, followed by the other Nix profiles, then Homebrew migration paths, then the original PATH. Remove the broken `/opt/homebrew/bin/nvim` path prepend. Guard optional goenv/asdf/ruby.

**Step 4: Atuin init stub**

In `env.nu`: if atuin missing, write a stub `init.nu` so `source` in config.nu never fails.

**Step 5: Verify shell still starts (pre-Nix)**

```bash
/opt/homebrew/bin/nu -c 'source ~/.config/nushell/env.nu; source ~/.config/nushell/config.nu; print "ok"'
~/.dotfiles/bin/nu-for-ghostty -c 'print "wrapper ok"'
/opt/homebrew/bin/nu -c 'source ~/.config/nushell/env.nu; $env.PATH | where {|p| $p =~ "nix-profile|current-system|homebrew" } | to text'
```

Expected: both startup commands print `ok`. **Pre-Nix:** only Homebrew/usr paths may appear (profiles do not exist yet — OK). **Post-apply (Task 10):** Nix profile paths must appear **before** `/opt/homebrew/bin` in the filtered list.

**Step 6: Commit in dotfiles repo**

```bash
cd ~/.dotfiles
git add bin/nu-for-ghostty .config/ghostty/config .config/nushell/config.nu .config/nushell/env.nu README.md
git commit -m "fix: Nix-first paths and Ghostty nu resolver for nix-setup"
```

Only commit files from this task; leave unrelated dirty files alone unless user asks.

---

### Task 10: First real apply on kaan-macmini

**Files:** none (system apply)

**Step 1: Run non-mutating preflight checks**

```bash
nix --version
nix build .#darwinConfigurations.kaan-macmini.system --dry-run
```

Expected: Nix prints a version and the dry-run resolves without evaluation errors.

**Step 2: Stop for explicit human approval**

**STOP. Do not apply the configuration yet.** Show the user the exact command below and explain that it may download packages, request `sudo`, change system/user configuration, run fail-soft network installers, and alter the login shell. Wait for explicit confirmation before continuing.

**Step 3: Apply nix-darwin after approval**

```bash
cd ~/Desktop/personal/nix-setup
nix run nix-darwin -- switch --flake .#kaan-macmini
```

Expected: build + activate succeeds. Activation may print `[agents]` / `[zerobrew]` soft warnings — OK.

If eval error: fix package attr / nix-darwin option, commit fix, re-run.

**Step 4: Stow dotfiles**

```bash
cd ~/.dotfiles && stow .
```

**Step 5: Smoke**

```bash
nu ~/Desktop/personal/nix-setup/scripts/smoke.nu
nu ~/Desktop/personal/nix-setup/scripts/smoke.nu --strict
```

Expected: required tools OK. If not, install missing via module fix or temporary brew, re-apply.

**Step 6: Manual checks**

- Open Ghostty → lands in nu + starship  
- `which nu rg nvim uv` → prefer `/etc/profiles/per-user/legolas` or nix store paths  
- `claude --version` / `headroom --version` / `rustc --version` soft OK  

**Step 7: Document apply result in todo**

Update `todo.md` checkboxes; commit if changed:

```bash
cd ~/Desktop/personal/nix-setup
git add todo.md
git commit -m "docs: mark kaan-macmini first apply status"
```

---

### Task 11: Brew cutover notes (no mass uninstall without green smoke)

**Files:**
- Modify: `README.md` section “Homebrew migration”

**Step 1: After smoke --strict is green**, list overlapping brew formulas:

```bash
brew list --formula
```

Candidates to remove later (only if Nix provides them):  
`nushell starship neovim ripgrep fd zoxide atuin lazygit zellij uv bun zola stow rtk` etc.

**Step 2: Do NOT run mass uninstall in this task unless user explicitly confirms.** Add exact cutover commands as a README subsection.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: brew cutover checklist after green smoke"
```

---

### Task 12: Second Mac + Linux checklist (docs only unless machine present)

**Files:**
- Modify: `README.md`

**Step 1: Document rename procedure for mac-2**

```bash
scutil --get LocalHostName
# edit flake.nix darwinConfigurations attr + hosts/mac-2 hostName to match
nix run nix-darwin -- switch --flake .#<real-name>
```

**Step 2: Document Linux**

```bash
# set system = "aarch64-linux" in flake if needed
nix run home-manager/master -- switch --flake .#legolas@linux
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: second Mac and Linux apply checklists"
```

---

## Done when

- [ ] `nix flake show` lists all three hosts  
- [ ] `flake.lock` committed after first successful eval  
- [ ] `darwin-rebuild`/`nix run nix-darwin -- switch` works on kaan-macmini (after human approval)  
- [ ] `scripts/smoke.nu --strict` passes required tools (`rtk` optional)  
- [ ] Ghostty uses resolver → Nix nu when available  
- [ ] `.dotfiles` path commit exists  
- [ ] README covers apply + gaps + brew cutover + codex desktop manual  
- [ ] No secrets in flake  

---

## Pre-flight review checklist (re-run after plan edits)

| Gate | Status |
|------|--------|
| Task 1: no `git add -A`; ignore `.beads`/`.tokensave` | OK (only as prohibition text) |
| Task 2: STOP before Nix install | OK |
| Tasks 4–5/7: full inlined code | OK |
| Task 4: Ghostty not dual-sourced via nixpkgs + cask | OK (aerospace nix optional only) |
| Task 4: codex desktop explicit v1 skip | OK |
| Smoke: `rtk` optional; required list has no rtk | OK |
| Task 9: PATH one ordered list (`managed_paths`) | OK |
| Task 9: dead-tool out of scope | OK |
| Task 9: pre-Nix PATH expectation doesn’t require Nix dirs | OK |
| Task 10: STOP before switch | OK |
| `flake.lock` commit step | OK |
| Task 11: no mass brew uninstall without confirm | OK |
| `home.stateVersion` only in flake user blocks | OK |
| RTK.md not a required path in-repo | OK |

**Review verdict (2026-07-16, Grok loop):** **Ready for Subagent-Driven.** Remaining risks are operational (sudo, network installers, nix-darwin option churn), not plan gaps.

---

## Execution handoff

Plan reviewed and ready for Subagent-Driven (pending your go).

Saved: `docs/plans/2026-07-16-nix-multi-machine.md`.

**Options:**

1. **Subagent-Driven (this session)** — fresh subagent per task, review between tasks  
2. **Parallel Session** — separate session with `executing-plans`

Say **1** or **2** when you want execution to start. Do not start Task 10 apply without your explicit OK at that gate.
