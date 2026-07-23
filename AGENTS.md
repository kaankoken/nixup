@RTK.md

# Shared agent tooling (all agents)

Same stack for Claude Code, Codex, Cursor, Grok, pi, and anything new.
Do **not** invent a parallel workflow per agent.

## Layers (use in this order of preference)

| Layer | Tool | How |
|-------|------|-----|
| Shell output | **RTK** | Prefix shell with `rtk` (or rely on RTK hooks). See `RTK.md`. |
| Tasks / memory | **beads (`bd`)** | Durable work: `bd ready`, `bd update --claim`, `bd close`. Not ad-hoc markdown TODOs when tracking matters. |
| Traffic compress | **headroom** | Prefer launching via `headroom wrap claude\|codex\|cursor` when available. MCP: `headroom_compress` / retrieve. |
| Code structure | **tokensave only** | Code exploration: `tokensave_context`, search, callers, impact. **Never codebase-memory.** |
| Tool/MCP flood | **context-mode** | Large reads, logs, web fetches → `ctx_execute` / sandbox tools. Prefer over dumping raw MCP output. |
| Structural edits | **ast-grep (`sg`)** | AST search/rewrite over regex sed. TokenSave may call it when on PATH. |
| External docs | **context7** | Library/API docs (no API key required for free tier). Do not invent APIs. |
| Output brevity | **caveman** | Terse agent prose when the skill is installed (`/caveman` or session default). |

## Tokensave is the only code graph

- Prefer tokensave MCP over Explore agents, raw `grep`/`rg` for symbol lookup, and full-file thrashing.
- If the project is not indexed: `tokensave init` then `tokensave sync`.
- **Do not use codebase-memory-mcp** (removed from this setup).

## Shell

```bash
rtk git status
rtk cargo test
rtk cargo clippy
# escape hatch (full output + tracking)
rtk proxy <cmd>
```

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
sg --version || ast-grep --version
nh --version
```

## Headroom wrap

```bash
headroom wrap claude
headroom wrap codex
# cursor: headroom wrap cursor  (prints/configures as supported)
```

Do not configure a second “primary” code-intelligence MCP alongside tokensave.
