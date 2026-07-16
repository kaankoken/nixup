# nix-setup

Declarative multi-machine developer environment:

- **macOS:** nix-darwin + home-manager (Apple Silicon)
- **Linux:** home-manager only

App configs live in a separate [`.dotfiles`](https://github.com/kaankoken/.dotfiles) repo and are applied with **GNU stow**. This flake owns packages, shell/env hooks, and agent installers.

Automation is the **`nixup`** Rust CLI.

## Model

| Piece | Role | In git? |
|-------|------|---------|
| `nixup.toml` | **Source of truth** for your devices | No (gitignored) |
| `nixup.toml.example` | Public template | Yes |
| `nixup hosts sync` | Generates host modules + inventory from config | — |
| `hosts/<id>/default.nix` | Generated host module | No (except examples) |
| `hosts/inventory.nix` | Generated map imported by `flake.nix` | No (gitignored) |
| `hosts/inventory.example.nix` | CI / third-party fallback | Yes |
| `hosts/my-mac/`, `hosts/my-linux/` | Example modules matching the example inventory | Yes |
| `modules/*` | Shared packages, shell, agents, darwin, linux | Yes |

**Do not hand-edit personal host modules as the long-term source of truth.** Edit `nixup.toml`, then re-run `nixup hosts sync`.

**Pure Nix flakes only see tracked files.** After sync, personal `hosts/inventory.nix` and `hosts/<id>/` exist on disk but are gitignored, so pure eval falls back to the example inventory unless you temporarily `git add -f` them for a local build. Prefer not committing personal hosts. CI always uses the example inventory.

## Install `nixup`

```bash
cargo install --path crates/nixup
# or: cargo run -p nixup -- --help
```

## Quick start

```bash
cd /path/to/nix-setup

# 1) Personal config (not committed)
cp nixup.toml.example nixup.toml
# edit [[hosts]], [smoke], [defaults]

# 2) Materialize hosts from config (generated files stay local / gitignored)
nixup hosts sync --yes

# 3) Day-0 / day-2
nixup bootstrap --yes
nixup apply --yes
nixup smoke --strict
nixup doctor
nixup hosts              # config entries + whether hosts/<id> exists
nixup status
nixup update --yes
nixup stow --clone
```

Global flags: `--flake PATH`, `--config PATH`, `--yes` / `-y`, `--verbose`.

### Without the CLI (example inventory only)

Repo ships example flake attrs for CI and exploration:

```bash
nix flake show
# Linux
nix run home-manager/master -- switch --flake .#"you@linux"
# macOS
nix run nix-darwin -- switch --flake .#my-mac
```

Replace these with your own hosts via `nixup.toml` + `nixup hosts sync`.

### Third parties

1. `cp nixup.toml.example nixup.toml` and edit `[[hosts]]`.
2. `nixup hosts sync --yes` → writes local `hosts/<id>/default.nix` + `hosts/inventory.nix`.
3. `flake.nix` maps inventory → `darwinConfigurations` / `homeConfigurations` (falls back to `inventory.example.nix` when personal inventory is absent).
4. `nixup apply --yes` / `nixup bootstrap --yes`.

## Package split

| Channel | What |
|---------|------|
| **Nix** | nushell, starship, stow, neovim, zellij, atuin, lazygit, modern CLIs (rg/fd/eza/…), uv, bun, zola, git, gh, rtk (if packaged), fonts, aerospace (if packaged) |
| **Zerobrew** (Mac, fail-soft; brew fallback during migration) | ghostty, zed, signal, slack, whatsapp, microsoft-outlook, mole, rtk fallback |
| **Activation** | rustup, headroom (`uv tool install "headroom-ai[proxy,ml,code,mcp,evals]"`), claude-code, **codex-cli**, beads, radicle, **grok** (`curl -fsSL https://x.ai/cli/install.sh \| bash`) |

**Ghostty** is **zerobrew/brew cask only** — not installed via `pkgs.ghostty` (avoids dual installs).

## Layout

```
flake.nix                      # inventory.nix if present, else inventory.example.nix
nixup.toml.example             # public template
nixup.toml                     # personal (gitignored)
hosts/inventory.example.nix    # committed — CI / template
hosts/my-mac/ my-linux/        # committed — example host modules
hosts/inventory.nix            # generated (gitignored)
hosts/<your-id>/               # generated (gitignored)
modules/{common,shell,agents,darwin,linux}/
crates/nixup*                  # Rust CLI
scripts/archived/              # former Nu bootstrap/smoke
.github/workflows/
```

## CI

- **verify-flake** — Linux + macOS: `nix flake show` + eval of **example** hosts (`my-mac`, `you@linux`); no switch
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
- **Pure flake + personal hosts**: generated inventory is gitignored; pure eval uses examples unless you stage generated files locally

## Notes

- **Determinate Nix:** `nix.enable = false` in nix-darwin so activation does not fight Determinate’s daemon.
- Prefer applying as your user with a login that can sudo, or preserve `PATH`/`HOME` under sudo.
- `home.stateVersion` is set only in `flake.nix`.
