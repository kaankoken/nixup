# nix-setup

Declarative developer environment for **2× Apple Silicon Macs** (nix-darwin + home-manager) and **1× Linux** (home-manager only).

App configs live in a separate repo ([`.dotfiles`](https://github.com/kaankoken/.dotfiles)) and are applied with **GNU stow**. This flake owns packages, shell binary/env hooks, and installers for agent tools.

Automation is the **`nixup`** Rust CLI. **`nixup.toml` is the source of truth for devices**: run `nixup hosts sync` to create `hosts/<id>/` modules and `hosts/inventory.nix` that `flake.nix` imports.

Personal **`nixup.toml` is gitignored** (template: `nixup.toml.example`).  
`nixup hosts sync` writes **`hosts/inventory.nix`** and **`hosts/<id>/default.nix`** (also gitignored except the public `my-mac` / `my-linux` examples). Keep private URLs only in your local `nixup.toml`.

**Pure flakes only see tracked files.** After sync, either `git add` the generated hosts for a local pure eval (without committing), or rely on the example inventory in CI. Do not commit personal host modules or `inventory.nix`.

## Install `nixup`

```bash
cargo install --path crates/nixup
# or: cargo run -p nixup -- --help
```

## Quick start (this machine / your own)

```bash
cd /path/to/nix-setup

# 1) Personal config (not committed)
cp nixup.toml.example nixup.toml
# edit [[hosts]] / [smoke] / [defaults]

# 2) Create host modules + inventory from config
nixup hosts sync --yes

# 3) Day-0 / day-2
nixup bootstrap --yes
nixup apply --yes
nixup smoke --strict
nixup doctor
nixup hosts            # list config + whether hosts/<id> exists
nixup status
nixup update --yes
nixup stow --clone
```

Global flags: `--flake PATH`, `--config PATH`, `--yes` / `-y`, `--verbose`.

### Third parties / other flakes

1. `cp nixup.toml.example nixup.toml` and edit `[[hosts]]`.
2. `nixup hosts sync --yes` → creates `hosts/<id>/default.nix` + `hosts/inventory.nix`.
3. `flake.nix` already maps inventory → `darwinConfigurations` / `homeConfigurations`.
4. `nixup apply --yes` / `nixup bootstrap --yes`.

CI falls back to `hosts/inventory.example.nix` when personal `inventory.nix` is missing.

## Package split

| Channel | What |
|---------|------|
| **Nix** | nushell, starship, stow, neovim, zellij, atuin, lazygit, modern CLIs (rg/fd/eza/…), uv, bun, zola, git, gh, rtk (if packaged), fonts, aerospace (if packaged) |
| **Zerobrew** (Mac, fail-soft; brew fallback during migration) | ghostty, zed, signal, slack, whatsapp, microsoft-outlook, mole, rtk fallback |
| **Activation** | rustup, headroom (`uv tool install "headroom-ai[proxy,ml,code,mcp,evals]"`), claude-code, **codex-cli**, beads, radicle, **grok** (`curl -fsSL https://x.ai/cli/install.sh \| bash`) |

**Ghostty** is **zerobrew/brew cask only** — not installed via `pkgs.ghostty` (avoids dual installs).

## Layout

```
flake.nix                 # imports hosts/inventory.nix (or inventory.example.nix)
nixup.toml.example        # public template
nixup.toml                # personal (gitignored)
hosts/<id>/               # created by: nixup hosts sync (personal: gitignored)
hosts/inventory.nix       # generated (gitignored)
hosts/inventory.example.nix
hosts/my-mac my-linux/    # public examples for CI
crates/nixup*             # Rust CLI
modules/{common,shell,agents,darwin,linux}/
.github/workflows/
```

## CI

- **verify-flake** — Linux + macOS: `nix flake show` + eval of host outputs (no switch)
- **verify-rust** — path-filtered: fmt, clippy `-D warnings`, cargo-deny, nextest
- **fixtures** — golden CLI checks
- **release / nightly** — multi-target binaries; Docker (GHCR); Homebrew formula (needs `HOMEBREW_DEPLOY_KEY`)

## Homebrew migration

1. Apply flake and get `nixup smoke --strict` green for **required** tools  
2. Confirm `which nu rg nvim` prefer Nix profiles over Homebrew  
3. Uninstall overlapping brew formulas **only after** green smoke  
4. Keep brew/zerobrew for GUI leftovers if needed  

## Known gaps

- **Outlook / WhatsApp / Signal / Slack**: best-effort cask names; may need App Store / vendor install  
- **Codex desktop (v1)**: **not** managed by this flake — install manually  
- **grok**: binary is `grok` (not `grok-build`)  
- **zerobrew**: experimental — brew used as fallback  
- **rtk**: optional in smoke  
- **Secrets**: not managed  
- **Docker image**: ships `nixup` only (no Nix runtime inside the image)

## Notes

- **Determinate Nix:** `nix.enable = false` in nix-darwin so activation does not fight Determinate’s daemon.  
- Prefer applying as your user with a login that can sudo, or preserve `PATH`/`HOME` under sudo.  
- `home.stateVersion` is set only in `flake.nix`  

## Docs

- nixup design: `docs/superpowers/specs/2026-07-16-nixup-design.md`  
- Multi-machine design: `docs/superpowers/specs/2026-07-16-nix-multi-machine-design.md`  
- Spec: `spec.md` · Todo: `todo.md`
