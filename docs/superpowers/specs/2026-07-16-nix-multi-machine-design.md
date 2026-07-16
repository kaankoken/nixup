# Nix multi-machine setup — Design

**Date:** 2026-07-16  
**Author:** Kaan (with Grok)  
**Status:** Approved

## Problem

Developer tools and agent configs are duplicated across 2 Apple Silicon Macs and 1 Linux machine. Manual copying is done; we need a declarative, repeatable sync path without abandoning the existing `.dotfiles` + stow workflow.

## Goals

1. Declarative packages + managed shell/env on all three hosts
2. App configs stay in `~/.dotfiles` managed by **stow**
3. **Nix-first** for CLIs; **zerobrew** for macOS GUI/casks Nix does poorly
4. Agent tools via **idempotent official installers** (fail-soft)
5. Parallel Homebrew → cutover after smoke tests
6. Path + dead-tool distill of `.dotfiles`
7. Verifiable with `scripts/smoke.nu`

## Non-goals (v1)

- Full Home Manager ownership of app configs
- Secrets in the flake
- NixOS on Linux
- Immediate Homebrew removal
- Redesigning nvim/zellij layouts

## Decisions

| Topic | Choice |
|--------|--------|
| Ownership | Packages + shell/env in Nix; configs in `.dotfiles` + stow |
| Linux | Distro + Nix; home-manager only |
| Macs | Both `aarch64-darwin`; nix-darwin + home-manager |
| Package split | Nix-first hybrid |
| Agents | Activation / official installers; fail-soft |
| Architecture | Multi-host flake + shared modules |
| Brew migration | Parallel then cutover |
| Dotfiles | Path fixes + dead-tool prune |
| Nix installer | Determinate preferred on macOS |

## Architecture

- **Repo:** `nix-setup` flake
- **Outputs:** 2× `darwinConfigurations`, 1× `homeConfigurations`
- **Modules:** `common`, `shell`, `agents`, `darwin` (incl. zerobrew/mole), `linux`
- **Hosts:** `kaan-macmini`, `mac-2` (placeholder hostname), `linux` (placeholder)
- **Outside Nix:** `.dotfiles` app configs via stow

## Package channels

### Nix (all hosts)

nushell, starship, stow, neovim, zellij, atuin, lazygit, ripgrep, fd, eza, zoxide, bat, dust, sd, delta, procs, uv, git, gh, bun, zola, rtk (if in nixpkgs)

### Darwin / Nix

Nerd fonts; aerospace (nix or zerobrew); nu in `/etc/shells` + user shell

### Zerobrew (macOS)

ghostty, zed, signal, slack, whatsapp, outlook (if cask), codex desktop (if available), mole, rtk fallback

### Activation installers

| Tool | Channel |
|------|---------|
| rust | rustup (not nixpkgs rustc) |
| headroom | `uv tool install "headroom-ai[proxy,ml,code,mcp,evals]"` |
| claude-code, codex-cli, grok-build, beads, radicle | official installers |

## Success criteria

- Flake applies cleanly on all three machines
- Smoke script green for required tools
- Daily shell/agents work without Homebrew for declared tools
- Ghostty uses Nix-provided `nu`

## Risks

Zerobrew experimental; optional GUI casks may be missing; agent installer URLs drift; PATH brew vs nix conflicts — mitigated by soft-fail activation, parallel brew, smoke checks, path distill.
