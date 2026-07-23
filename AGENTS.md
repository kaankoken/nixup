@RTK.md

# Shared agent tooling (all agents)

Same stack for Claude Code, Codex, Cursor, Grok, pi, and anything new.
Do **not** invent a parallel workflow per agent.

## Ownership

| Piece | Owner |
|-------|--------|
| **Packages / MCP installers / `sg` wrapper** | this flake (`modules/common`, `modules/agents`) |
| **Global agent instruction files** | **`.dotfiles/agent-stack/`** (stow/symlink, not Nix) |
| **This file** | project-local rules when working in nix-setup |

Global hosts load the stack via symlinks:

```bash
~/.dotfiles/agent-stack/link.sh
# -> ~/.agents/AGENTS.md, ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md,
#    ~/.grok/Agents.md, ~/AGENTS.md, ~/.cursor/rules/shared-agent-stack.mdc
```

Do **not** reintroduce codebase-memory into host `AGENTS.md` files. Re-run
`link.sh` if `bd setup codex` rewrites `~/.codex/AGENTS.md`.

These tools are on PATH via this flake’s home-manager packages (`modules/common`)
plus agent installers (`modules/agents`). Prefer them over stock Unix / ad-hoc
alternatives. Prefix shell with **`rtk`** when running them (see `RTK.md`).

## Layers (use in this order of preference)

| Layer | Tool | How |
|-------|------|-----|
| Shell output | **RTK** | Prefix shell with `rtk` (or rely on RTK hooks). See `RTK.md`. |
| Tasks / memory | **beads (`bd`)** | Durable work: `bd ready`, `bd update --claim`, `bd close`. Not ad-hoc markdown TODOs when tracking matters. |
| Traffic compress | **headroom** | Prefer launching via `headroom wrap claude\|codex\|cursor` when available. MCP: `headroom_compress` / retrieve. |
| Code structure | **tokensave only** | Code exploration: `tokensave_context`, search, callers, impact. **Never codebase-memory.** |
| Tool/MCP flood | **context-mode** | Large reads, logs, web fetches → `ctx_execute` / sandbox tools. Prefer over dumping raw MCP output. |
| Structural edits | **ast-grep** (`sg` alias) | AST search/rewrite over regex `sed`/`perl`. TokenSave may call it when on PATH. |
| External docs | **context7** | Library/API docs (no API key required for free tier). Do not invent APIs. |
| Output brevity | **caveman** | Terse agent prose when the skill is installed (`/caveman` or session default). |
| Code minimalism | **ponytail** | YAGNI / reuse / stdlib-first code generation (`/ponytail` or session default). Complements caveman — prose vs code. |

## Local CLI toolkit (prefer these)

Installed by Nix home packages. **Agents must use these** instead of legacy
equivalents when the job fits. Do not invent parallel tools or call Homebrew
copies when the Nix profile binary exists.

### Prefer / avoid

| Job | Prefer | Avoid |
|-----|--------|--------|
| Content search | **`rg`** (ripgrep) | `grep -r`, recursive `find`+`grep` |
| File name search | **`fd`** | `find` (unless you need find predicates `fd` lacks) |
| Directory listing | **`eza`** | plain `ls` when you need tree/long/git metadata |
| File preview in shell | **`bat`** | `cat`/`less` for source (pager is already `bat`) |
| Simple string replace in files | **`sd`** | `sed -i` for straightforward s/old/new |
| AST / structural code search-replace | **`ast-grep`** or **`sg`** | multi-file `sed`/`perl` on code structure |
| Disk usage | **`dust`** | `du -sh` |
| Process list | **`procs`** | `ps aux` |
| JSON | **`jq`** | hand-rolled parsers |
| GitHub | **`gh`** | raw `curl` to api.github.com when `gh` covers it |
| Python tooling | **`uv`** | bare `pip`/`pipx` for project/tool installs |
| JS CLIs in this setup | **`bun`** | system `node`/`npm` for packages we control (pi, context-mode) |
| Rust checks | **`bacon`**, **`cargo nextest`** | long unfiltered `cargo test` loops when nextest/bacon fit |
| Nix rebuild / search | **`nh`**, **`nom`** | raw `nixos-rebuild` / noisy `nix build` without nom when `nh` works |
| Semantic structural diff | **`difft`** (difftastic) | huge unified diffs when structure matters |
| Editor | **`nvim`** | only when an editor is actually required |

### Discovery order (code)

1. **tokensave MCP** — symbols, callers, impact, context (always first for code structure).
2. **`rg` / `fd` / `ast-grep`** — string literals, paths, AST patterns tokensave cannot answer.
3. Targeted file reads — not whole-repo thrashing.
4. **Never** codebase-memory-mcp.

String / path search is fine with `rg`/`fd` **after** (or when) tokensave is the wrong tool (error strings, configs, non-code, missing index). Prefer `rtk rg …` / `rtk fd …` so output stays compressed.

### Structural edits

```bash
# search
rtk ast-grep -p 'PATTERN' -l rust
# or
rtk sg -p 'PATTERN' -l rust

# rewrite (review the diff; do not blind-write production without checks)
rtk ast-grep -p 'OLD' -r 'NEW' -l rust
```

Use **ast-grep** when renaming symbols, changing call shapes, or matching syntax.
Use **`sd`/`rg`** only for plain text. Do not regex-sed across an AST-shaped change.

### Examples

```bash
rtk rg -n 'TODO|FIXME' -g '!**/target/**'
rtk fd -e rs -e nix
rtk eza -la --git
rtk bat -n path/to/file.rs
rtk sd 'old_name' 'new_name' path/to/file.rs
rtk jq '.dependencies' package.json
rtk dust -d 2 .
rtk procs
rtk gh pr view
rtk uv tool list
```

### Git UX (already wired)

- Diff: **difftastic** (`difft`) / **delta** via git config where set.
- Merge: **mergiraf** as merge driver where configured.
- History rewrite (rare): **git-filter-repo** — only with explicit human intent.

Do not reconfigure git from agent sessions unless asked.

## Tokensave is the only code graph

- Prefer tokensave MCP over Explore agents, raw `grep`/`rg` for **symbol** lookup, and full-file thrashing.
- `rg`/`fd` are still required for literals, paths, and non-indexed trees — just not as the primary code graph.
- If the project is not indexed: `tokensave init` then `tokensave sync`.
- **Do not use codebase-memory-mcp** (removed from this setup).

## Shell

```bash
rtk git status
rtk cargo test
rtk cargo clippy
rtk cargo nextest run
# escape hatch (full output + tracking)
rtk proxy <cmd>
```

Host shells: **nushell** is the human default on this machine; agents may use bash/sh for portability. Prefer the modern binaries above either way.

## Nix rebuilds (human + agent)

```bash
nh darwin switch . -H <host>   # or nh home switch
nh search <pkg>
# nom is used by nh for pretty builds; standalone:
nom build ...
```

## Verification (smoke)

```bash
rtk --version && rtk gain
bd version || bd --version
headroom --version
tokensave --version
command -v context-mode
ast-grep --version || sg --version
rg --version
fd --version
eza --version
bat --version
sd --version
jq --version
nh --version
# skills (not PATH binaries): markers under ~/.agents/skills or host plugins
test -f ~/.agents/skills/caveman/SKILL.md || test -d ~/.claude/plugins/cache/caveman
test -f ~/.agents/skills/ponytail/SKILL.md
```

## Caveman vs ponytail

| Skill | Shrinks | Invoke |
|-------|---------|--------|
| **caveman** | Agent **prose** (output tokens) | `/caveman [lite\|full\|ultra]` |
| **ponytail** | Generated **code** (diffs / over-build) | `/ponytail [lite\|full\|ultra\|off]` |

Use both. Do not treat them as alternatives.

## Headroom wrap

```bash
headroom wrap claude
headroom wrap codex
# cursor: headroom wrap cursor  (prints/configures as supported)
```

Do not configure a second “primary” code-intelligence MCP alongside tokensave.

## Browser / web (shared stack)

| Tier | Tool | Install |
|------|------|---------|
| Search+fetch | agents / curl | always |
| CDP short | chrome-cdp (soft) | pi install |
| Heavy live | **browser-use** | `modules/agents` → `uv tool install browser-use` |
| Long-horizon | **Webwright** skill | `~/.agents/skills/webwright` (activation clone) |

Chrome remote debugging for browser-use: `chrome://inspect/#remote-debugging`.

## Pi goal harness

Pi uses the **same** stack above — not a parallel toolkit. Templates and roles live under [`modules/agents/pi/`](modules/agents/pi/) and deploy to `~/.pi/agent/` (never `auth.json`).

| Entry | Behavior |
|-------|----------|
| `/goal [text]` | Full multi-model harness (superpowers + **pi-dynamic-workflows** + bd) |
| `/harness [text]` | Alias of `/goal` |
| `/init` | Project scaffold only (`project-init` + AGENTS templates) |

Smoke after activation: `scripts/smoke-pi-harness.sh`. Design: `docs/superpowers/specs/2026-07-23-pi-goal-harness-design.md`. Child MCP caveat: `modules/agents/pi/docs/child-tools.md`.
