# Pi Goal Harness templates

Nix-owned templates for the Pi multi-model **goal harness**. Home-manager deploys
these into the live Pi directories. Do **not** overwrite `~/.pi/agent/auth.json`.

## What deploys where

Home-manager `home.file` in `modules/agents/default.nix`. **Never** manages `auth.json`.

| Source (this tree) | Destination |
|--------------------|-------------|
| `settings.json` | `~/.pi/agent/settings.harness.json` (**merge source** — not a blind overwrite of live `settings.json`) |
| `mcp.json` | `~/.pi/agent/mcp.harness.json` (activation merges absolute paths into live `mcp.json`) |
| `sandbox.json` | `~/.pi/agent/extensions/sandbox.json` (project may add `.pi/sandbox.json`) |
| `models-aliases.json` | `~/.pi/agent/models-aliases.json` |
| `AGENTS.global.md` | `~/.pi/agent/AGENTS.md` |
| `README.md` | `~/.pi/agent/README-harness.md` |
| `agents/` | `~/.pi/agent/agents/` (recursive) |
| `prompts/` | `~/.pi/agent/prompts/` (recursive) |
| `skills/goal-harness/` | `~/.pi/agent/skills/goal-harness/` |
| `templates/project/` | `~/.pi/agent/templates/project/` (AGENTS scaffold for `project-init`) |
| `workflows/` | `~/.pi/workflows/templates/` (activation installs/saves into package-specific paths) |

### Settings merge strategy

1. Nix deploys `settings.harness.json` (canonical harness defaults).
2. Activation **merges** packages/skills into existing `~/.pi/agent/settings.json`.
3. Preserves `lastChangelogVersion`, user theme, and local extensions (e.g. rtk).

Live Pi home layout:

```text
~/.pi/agent/          # settings, MCP, sandbox, agents, prompts, skills, templates, extensions
~/.pi/workflows/      # pi-dynamic-workflows saved workflows + model-tiers.json
```

## Packages (settings / install-time)

| Package | Role |
|---------|------|
| **`@quintinshaw/pi-dynamic-workflows`** | Spawn/orchestration runtime |
| **`pi-mcp-adapter`** | MCP client for tokensave/headroom/context-mode/context7 |
| **`git:github.com/DietrichGebert/ponytail`** | Ponytail skills for Pi (`pi install git:…/ponytail`) |
| **`git:…/chrome-cdp-skill`** | Optional CDP for `web-browse-scout` |

## Skills paths (deduped)

1. `~/.agents/skills` — portable skills (superpowers, android, …)  
2. `!~/.agents/skills/ponytail` / `ponytail-*` — exclude portable copies so **package** ponytail wins  
3. `~/.pi/agent/skills` — harness-only (`goal-harness`)

Do **not** list `~/.claude/skills` or Claude plugin caches (collision flood). Project `.agents/skills` may still override package when present (Pi project > package).

Also required on PATH: `rtk`, `bd`, `tokensave`, `sg`/`ast-grep`, `headroom`, `context-mode`, `browser-use`.

## Models

`auth.json` is empty until you log in. In pi:

```text
/login
```

Authenticate Anthropic (Claude Code / fable / opus), OpenAI (gpt-5.6-sol), and xAI (grok-4.5) as needed. Then models from `enabledModels` become available.

## MCP (no codebase-memory)

See `mcp.json`: **tokensave**, **headroom**, **context-mode**, **context7** only.

## Web / browser tiers

| Tier | Agent | Default? | Install |
|------|--------|----------|---------|
| Search + fetch | `web-scout` | Yes | search + curl |
| CDP / headless | `web-browse-scout` | `includeBrowse` | chrome-cdp skill |
| Browser-use | `browser-use-scout` | `includeBrowserUse` | **nix:** `uv tool install browser-use` (Chrome CDP) |
| Webwright | `webwright-scout` | `includeWebwright` | **nix:** skill `~/.agents/skills/webwright` |

See `docs/web-and-browser.md`.

Child agents may lack host MCP — use CLI fallbacks. See [docs/child-tools.md](docs/child-tools.md).

## Project-init templates

| File | Use |
|------|-----|
| `templates/project/AGENTS.md.tmpl` | Root AGENTS (`{{DESCRIPTION}}`, `{{STACK_TOOLS}}`, `{{STRUCTURE}}`) |
| `templates/project/subdir-AGENTS.md.tmpl` | Nested AGENTS (`{{SUBDIR}}`, `{{SCOPE}}`) |

`project-init` always creates `CLAUDE.md` as `ln -sfn AGENTS.md CLAUDE.md`.

## Smoke after activation

```bash
# From nix-setup repo (or any PATH that has the script)
./scripts/smoke-pi-harness.sh

# Or manually:
pi --version
rtk --version
bd version || bd --version || beads --version
tokensave --version
headroom --version
test -f ~/.pi/agent/settings.json
test -f ~/.pi/agent/mcp.json
pi list
# soft: dynamic-workflows / pi-dynamic should appear in pi list after package install
```

Manual interactive checks (human):

1. Empty tmp git repo → `pi` → `/init` or `/goal "tiny hello lib"`.
2. Non-trivial idea → nested research agents visible in `/workflows`.
3. `bd` epic/issues created for the harness run.
4. Abort before PR if desired.

## Design

Full design: [docs/superpowers/specs/2026-07-23-pi-goal-harness-design.md](../../../docs/superpowers/specs/2026-07-23-pi-goal-harness-design.md)

## Layout

```text
modules/agents/pi/
  README.md
  settings.json
  mcp.json
  sandbox.json
  models-aliases.json
  AGENTS.global.md
  agents/                 # role markdown
  prompts/                # /goal /harness /init
  skills/goal-harness/
  templates/project/      # AGENTS.md.tmpl, subdir-AGENTS.md.tmpl
  docs/child-tools.md
  workflows/              # goal-harness.js, research-fanout.js, …
```
