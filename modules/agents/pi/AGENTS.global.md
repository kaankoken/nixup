# Pi agent — global CLI contract and quality bar

Shared stack for Pi goal harness. Align with Claude/Codex/Grok agent stack.
Do **not** invent a parallel workflow. **Never** wire or use codebase-memory.

## Layers (preference order)

| Layer | Tool | How |
|-------|------|-----|
| Shell output | **RTK** (`rtk`) | Prefix shell with `rtk` (or RTK hooks). See `RTK.md`. |
| Tasks / memory | **beads (`bd`)** | SoT for harness: `bd ready`, `bd update --claim`, `bd close`. Not ad-hoc markdown TODOs when tracking matters. |
| Traffic compress | **headroom** | Prefer `headroom wrap …` when available. MCP: compress / retrieve. |
| Code structure | **tokensave only** | `tokensave_context`, search, callers, impact. **Never codebase-memory.** |
| Tool/MCP flood | **context-mode** | Large reads, logs, web fetches → sandbox / `ctx_execute`. Prefer over dumping raw MCP output. |
| Structural edits | **ast-grep** (`sg`) | AST search/rewrite over regex `sed`/`perl`. |
| External docs | **context7** | Library/API docs (free tier; no API key). Do not invent APIs. |
| Web (default) | **search + fetch** (`web-scout`) | Search skill / `curl` for versions & primary sources (goal #5). |
| Web (optional) | **CDP / headless** (`web-browse-scout`) | JS-rendered pages; chrome-cdp / Playwright. |
| Web (heavy) | **browser-use** (`browser-use-scout`) | Multi-step via `browser-use` CLI + Chrome CDP; nix installs CLI. |
| Web (long-horizon) | **Webwright** (`webwright-scout`) | Code-as-action Playwright scripts; skill `~/.agents/skills/webwright`. |
| Output brevity | **caveman** | Terse agent prose (`/caveman` or session default). |
| Code minimalism | **ponytail** | YAGNI / reuse / stdlib-first (`/ponytail` or session default). |

### Web escalation (do not skip tiers)

1. **web-scout** — search API + HTTP fetch (default in research-fanout).  
2. **web-browse-scout** — CDP/headless when pages need a real browser.  
3. **browser-use-scout** — multi-step via browser-use + running Chrome.  
4. **webwright-scout** — long-horizon code-as-action (rerunnable Playwright).

Details: `~/.pi/agent/docs/web-and-browser.md` (or repo `modules/agents/pi/docs/web-and-browser.md`).

## Discovery order (code)

1. **tokensave MCP** — symbols, callers, impact, context (always first for structure).
2. **`sg` / `ast-grep`**, then `rg` / `fd` — AST patterns, literals, paths tokensave cannot answer.
3. Targeted file reads — not whole-repo thrashing.
4. **Never** codebase-memory-mcp.

If MCP is unavailable in a child agent, fall back to CLI: `tokensave`, `sg`, `rtk rg`.

## MCP (Pi)

Pi has no built-in MCP; adapter package required. Servers:

- **tokensave** — sole code graph
- **headroom** — traffic compress
- **context-mode** — large outputs
- **context7** — external library docs

Do **not** install or call codebase-memory.

## Default global goal (7 quality rules)

Used when `/goal` or `/harness` is invoked **without** override text:

1. No errors, no warnings, no test failures.
2. No warning suppressions in production (test-only allows with reason OK).
3. Everything wired — no stubs, TODO/TBD/FIXME, unfinished tasks.
4. Use mandated skills (superpowers + stack + caveman + ponytail).
5. Latest dependencies — verify on the web; do not trust training data or local context-mode alone.
6. Complete all superpowers-derived spec/plan tasks.
7. Specs, plans, goals, updates tracked in **bd** as source of truth.

Override: pass text after `/goal` or `/harness`.

## Harness entry

| Command | Behavior |
|---------|----------|
| `/goal [text]` | Start full harness; goal = text or default 7 rules |
| `/harness [text]` | Alias of `/goal` |
| `/init` | Force project scaffold without full harness |

Orchestration runtime: **pi-dynamic-workflows**. Superpowers is the process engine.
bd is source of truth; markdown under `docs/superpowers/…` is export only.

## Prefer / avoid (local toolkit)

| Job | Prefer | Avoid |
|-----|--------|--------|
| Content search | `rg` (via `rtk`) | recursive `grep` |
| File names | `fd` | `find` (unless needed) |
| AST search/edit | `sg` / `ast-grep` | multi-file `sed` on code structure |
| Code graph | tokensave MCP | codebase-memory, thrashy full-tree reads |
| Tasks | `bd` | orphan markdown TODOs for harness work |
| Shell noise | `rtk` | raw unbounded dumps |
| Huge MCP/logs | context-mode | pasting walls of text |
| Docs | context7 | inventing APIs from memory |

## Sandbox (soft)

Allow: project tree, harness worktrees, `~/.local/bin` and agent CLIs, network
for registries + model APIs + context7 + gh.

Deny: arbitrary home/system writes outside project/worktree.

See `sandbox.json`. Project `.pi/sandbox.json` wins on merge when present.
