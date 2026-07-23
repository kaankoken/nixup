# Child tools & MCP inheritance (pi-dynamic-workflows)

## Caveat

**pi-dynamic-workflows subagents may not inherit host MCP extensions.**

What usually still works in children:

- Skills, prompts, and project/`~/.pi/agent` `AGENTS.md`
- Coding tools / toolsets the runtime exposes
- Shell (`bash` / `rtk`) when allowed by sandbox

What often **does not** appear unless the package is configured for tool inheritance:

- Host MCP servers: **tokensave**, **headroom**, **context-mode**, **context7**

Do not assume `tokensave_context` (or other MCP tool names) exist in a scout/implementer child. Treat missing MCP as normal, not a hard failure of the research phase.

## Mandatory CLI fallbacks

Documented in agent prompts (`code-graph-scout`, `code-search-scout`, `implementer`, …) and `AGENTS.global.md`:

```bash
# Code graph (tokensave binary — same graph as MCP)
rtk tokensave …          # or: tokensave <cmd>
tokensave --help         # confirm CLI is on PATH

# Structural search / edit
sg -p 'PATTERN' -l <lang>
# or
ast-grep -p 'PATTERN' -l <lang>

# Literals / paths when graph is wrong tool
rtk rg …
rtk fd …
```

| Need | Prefer if MCP present | Fallback |
|------|----------------------|----------|
| Symbols / callers / impact | tokensave MCP | `tokensave` CLI via `rtk` |
| AST / rewrites | (none required) | `sg` / `ast-grep` |
| Huge tool dumps | headroom / context-mode MCP | write temp files; summarize; avoid pasting walls |
| Library docs | context7 MCP | context7 CLI/web if available; else official docs URL |
| Web default | search skill MCP | `web-scout`: search skill CLI + `rtk curl` / `curl` |
| Web CDP | chrome-cdp tools | `web-browse-scout`: soft-fail if package missing |
| Web heavy | browser-use / Playwright | `browser-use-scout`: `uv`/`playwright` CLI; soft-fail if missing |

Web tier docs: `docs/web-and-browser.md`.

## Parent orchestrator responsibility

1. Prefer **parent** session for MCP-heavy work when children lack tools.
2. In nested research workflows, tell scouts explicitly: *if MCP missing, use CLI immediately*.
3. Soft-fail missing `sg` with a warning; hard-fail missing `bd` at harness start (install hint).
4. Activation smoke: `scripts/smoke-pi-harness.sh` checks CLIs + settings/mcp; package listing is soft-warn.

## Experimental check (after install)

After activation and package install, run a tiny workflow (or ad-hoc child) that:

1. Lists files in cwd via bash.
2. If a tokensave MCP tool exists, call it; else run `tokensave --help` or `rtk tokensave --help`.

Record whether MCP tools appeared. If not, keep CLI paths in scout prompts (current default).

## Related

- Skill: `~/.pi/agent/skills/goal-harness` — “Child MCP caveat”
- Global contract: `~/.pi/agent/AGENTS.md`
- Design: `docs/superpowers/specs/2026-07-23-pi-goal-harness-design.md` (§ MCP / tools in children)
