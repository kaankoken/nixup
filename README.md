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

**Pure Nix flakes only see tracked files.** After sync, personal `hosts/inventory.nix` and `hosts/<id>/` exist on disk but are gitignored, so pure eval would fall back to the example inventory. `nixup apply` / `bootstrap` force-stage those paths for the switch, then unstage them (nothing is committed). Prefer not committing personal hosts. CI always uses the example inventory.

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
sudo nix run nix-darwin -- switch --flake .#my-mac
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
| **Nix** | CLI: nushell, starship, stow, neovim, **zellij** ([kaankoken/zellij](https://github.com/kaankoken/zellij) fork — kitty image protocol + yazi), **yazi**, atuin, lazygit, git UX (`difftastic`, `mergiraf`, `git-filter-repo`), modern CLIs (rg/fd/eza/…), Rust helpers (`bacon`, `cargo-nextest`; toolchain via rustup), **uv**, bun, zola, git, gh, cloudflared, fonts. **GUI (Darwin):** `ghostty-bin`, `zed-editor`, `signal-desktop`, `slack`, `whatsapp-for-mac` |
| **Zerobrew → Homebrew fallback** (Mac) | **`rtk`**, **`mole`**: `zb install` then `brew install`. **`aerospace`**: `zb` then `brew install --cask nikitabobko/tap/aerospace`. Soft-fail if both fail |
| **uv** | **headroom** — `uv tool install "headroom-ai[proxy,ml,code,mcp,evals]"` (modules/agents) |
| **Manual** | Microsoft Outlook, Codex desktop |
| **Activation** | rustup, claude-code, **codex-cli** (bun), beads, **grok**, **pi** (bun; https://pi.dev) — **no Node/npm** |

### Sources of truth

| Tool | Install path |
|------|----------------|
| rtk | zerobrew (`zb install rtk`) — not Nix |
| mole | zerobrew (`zb install mole`) — not Nix |
| aerospace | zb if indexed; else **`brew install --cask nikitabobko/tap/aerospace`** |
| headroom | **uv** only |
| pi / codex | **bun** global (`bun install -g …`); wrappers in `~/.local/bin` run under bun — **no Node/npm** |
| Ghostty / Zed / Signal / Slack / WhatsApp | Nix home packages |
| zellij | Flake input [kaankoken/zellij](https://github.com/kaankoken/zellij) (`main`) via `overlays.default` |
| Outlook | Manual |

Do **not** use `pkgs.ghostty` (Linux GTK) or `pkgs.zed` (unrelated data lake).

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
- **release** — multi-target binaries; Docker `ghcr.io/<owner>/nixup:<semver|latest>`; Homebrew formula (needs `HOMEBREW_DEPLOY_KEY`)
- **nightly** — rolling GitHub prerelease binaries + `ghcr.io/<owner>/nixup:nightly`

## Homebrew migration

1. Install **zerobrew** first (Mac hard dependency): `curl -fsSL https://zerobrew.rs/install | bash`
2. Apply flake and get `nixup smoke --strict` green for **required** tools (includes `zb` on Darwin)
3. Confirm `which nu rg nvim` prefer Nix profiles over Homebrew
4. Uninstall overlapping brew formulas **only after** green smoke
5. Uninstall leftover Homebrew **casks** only after confirming Nix/manual apps work

## Notes

- **Determinate Nix:** `nix.enable = false` in nix-darwin so activation does not fight Determinate’s daemon.
- **Darwin apply** runs `sudo -H <nix> run nix-darwin -- switch …` (nix-darwin requires root for system activation). Your account needs passwordless or interactive sudo; `nix` is invoked by absolute path so sudo’s secure_path is fine.
- **Personal hosts** are gitignored; apply force-stages `hosts/inventory.nix` + host dirs so flake eval can see `darwinConfigurations.<your-host>`, then unstages.
- `home.stateVersion` is set only in `flake.nix`.
- **GUI apps:** Nix home packages where possible; Outlook manual; smoke `optional_apps` only checks presence.
- **Codex desktop** is out of scope; install manually. CLI `codex` is covered by agents activation via **bun** (not npm/node).
- **grok** binary name is `grok` (from x.ai install script), not `grok-build`.
- **zerobrew (`zb`)** first for **rtk / mole / aerospace**; if zb cannot resolve a package, fall back to **Homebrew** (`brew` on PATH or `/opt/homebrew/bin/brew`). AeroSpace: `brew install --cask nikitabobko/tap/aerospace`.
- **headroom:** uv only (`modules/agents`); smoke lists it as optional.
- **rtk / mole / aerospace:** optional in smoke; installed by zerobrew activation, not Nix.
- **Secrets** stay outside this flake (keychain / existing logins).
- **Docker image** ships the `nixup` binary only (no Nix daemon inside the image).
- **Pure flakes** only see tracked files: personal generated hosts stay gitignored; stage them for a local pure eval, or use the example inventory (CI does).

## License

Licensed under either of

- MIT license ([LICENSE-MIT](LICENSE-MIT))
- Apache License 2.0 ([LICENSE-APACHE](LICENSE-APACHE))

at your option. Unless you explicitly state otherwise, any contribution
intentionally submitted for inclusion in this work shall be dual-licensed as
above, without any additional terms or conditions.
