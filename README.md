# nix-setup

Declarative developer environment for **Apple Silicon Macs** (nix-darwin + home-manager) and **Linux** (home-manager only).

App configs live in a separate repo ([`.dotfiles`](https://github.com/kaankoken/.dotfiles)) and are applied with **GNU stow**. This flake owns packages, shell binary/env hooks, and installers for agent tools.

Host map lives in `hosts/inventory.nix` when present, otherwise `hosts/inventory.example.nix` (CI / third-party template). Example hosts: `my-mac`, `my-linux`.

## Quick start (macOS)

```bash
# 1) Install Nix (Determinate) — requires sudo; confirm before running
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2) Clone and apply (example attr — replace after you add real hosts)
cd ~/path/to/nix-setup
nix flake show
nix run nix-darwin -- switch --flake .#my-mac

# 3) Dotfiles
cd ~/.dotfiles && stow .

# 4) Smoke test
nu scripts/smoke.nu
nu scripts/smoke.nu --strict
```

Or: `nu scripts/bootstrap.nu --host my-mac` (prompts before system changes).

## Quick start (Linux)

```bash
nix run home-manager/master -- switch --flake .#"you@linux"
nu scripts/smoke.nu
```

## Package split

| Channel | What |
|---------|------|
| **Nix** | nushell, starship, stow, neovim, zellij, atuin, lazygit, modern CLIs, uv, bun, zola, git, gh, fonts, … |
| **Zerobrew** (Mac, fail-soft) | ghostty, zed, signal, slack, whatsapp, outlook, mole, … |
| **Activation** | rustup, headroom, claude-code, codex-cli, beads, radicle, grok |

## Layout

```
flake.nix
hosts/inventory.example.nix   # CI / template
hosts/my-mac/ my-linux/       # example host modules
modules/{common,shell,agents,darwin,linux}/
scripts/{bootstrap.nu,smoke.nu}
```

Personal host modules and `hosts/inventory.nix` are **not** part of the public tree — generate them later with `nixup hosts sync` (see second commit / README after CLI lands).
