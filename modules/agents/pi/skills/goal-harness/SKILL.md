---
name: goal-harness
description: >
  Orchestrate the Pi multi-model goal harness. Use when user runs /goal or /harness,
  or starts end-to-end feature work. Creates outer workflow, nested research workflows
  for large brainstorm/plan, review gates with N retries, bd tracking, worktree implement, PR.
---

# Goal harness

Process engine: **superpowers**. Spawn runtime: **pi-dynamic-workflows**. Named roles: agentTypes under `~/.pi/agent/agents/`. Do not run two competing full harness chains.

## Default goal (override via /goal or /harness args)

1. No errors, no warnings, no test failures.
2. No warning suppressions in production (test-only OK with reason).
3. Everything wired — no stubs, TODO/TBD/FIXME, unfinished work.
4. Mandated skills: superpowers + stack + caveman + ponytail.
5. Latest dependencies — verify on the web (not training data alone).
6. Complete all superpowers-derived spec/plan tasks.
7. Specs, plans, goals, updates tracked in **bd** (SoT). Markdown export is optional.

## Phases

| # | Phase | Superpowers | Producer | Reviewer | Model tier |
|---|--------|-------------|----------|----------|------------|
| 0 | Init | project scaffold | `project-init` | — | medium |
| 1 | Spec | **brainstorming** | `spec-writer` + scouts | `spec-reviewer` | big |
| 2 | Plan | **writing-plans** | `plan-writer` + scouts | `plan-reviewer` | big |
| 3 | BiteSize | rewrite until small | `bite-size-writer` | `bite-size-reviewer` | big |
| 4 | Implement | **SDD**, TDD, **using-git-worktrees**, ponytail, stack | `implementer`(s) | light optional | medium |
| 5 | Milestone | **requesting-code-review**, verification-before-completion, ponytail-review | multi `code-reviewer` | `milestone-organizer` gate | big |
| 6 | PR | **finishing-a-development-branch** | `pr-opener` | — | small |

**Bug path:** **systematic-debugging** may start a research workflow (repro / bisect / callers) before plan → implement → review.

Outer template: `goal-harness` workflow. Nested templates: `research-fanout`, `milestone-review`.

## When idea is large — nested research (required)

Judge scope: **small** | **large**. Large = multi-subsystem, greenfield feature, broad recon, or high/ultra effort.

If large, phase lead **authors a workflow** (do not solo-read the whole repo):

| Agent type | Focus | Tools bias | When |
|------------|--------|------------|------|
| `code-graph-scout` | modules, callers, impact | tokensave MCP **or CLI** | always (large) |
| `code-search-scout` | AST / symbols / patterns | `sg`, `rg` | always (large) |
| `docs-scout` | library/API truth | context7 | always (large) |
| `web-scout` | **search + fetch** (goal #5) | Brave/search skill, `curl`/`rtk curl` | **always** (large) |
| `web-browse-scout` | headless **CDP** / short click-path | chrome-cdp skill | `includeBrowse: true` or JS docs |
| `browser-use-scout` | multi-step **browser-use** (Chrome CDP) | `browser-use` CLI (nix/uv) | `includeBrowserUse: true` or user/ultra |
| `webwright-scout` | long-horizon **code-as-action** | Webwright skill (`~/.agents/skills/webwright`) | `includeWebwright: true` |
| `stack-scout` | Rust / Axiom / Android conventions | stack skills | default on |

**Web tiers:** search+fetch → CDP → browser-use → Webwright (long-horizon scripts). See `docs/web-and-browser.md`.

Pattern: `phase('Research')` → `parallel` scouts → synthesize → produce → `gate` with different reviewer agentType.

Same rule for Plan when multi-area:

```text
workflow('research-fanout', {
  idea, focusPaths,
  includeBrowse: false,       // SPA / short CDP
  includeBrowserUse: false,   // live Chrome browser-use
  includeWebwright: false,    // long-horizon Playwright scripts
})
```

## Review gates (N)

Use `gate(producer, validator, { attempts: N })` (or sequential produce/review with clear PASS/FAIL).

| Gate | N |
|------|---|
| Spec | **3** |
| Plan | **3** |
| Bite-size | **2** |
| Milestone code review | **3** |

Reviewer return shape only:

```json
{ "ok": true, "feedback": "...", "blocking": [] }
```

FAIL with attempts remaining → producer revises with feedback. Attempts exhausted → **escalate to human** with blocking list. Never re-use the same agent type as both producer and reviewer for a gate.

## Model pools (first available wins)

| Role | Chain (Pi id) | Effort |
|------|----------------|--------|
| Spec / plan / bite-size / milestone review | `openai/gpt-5.6-sol` → `anthropic/claude-fable-5` → `anthropic/claude-opus-4-8` | sol **ultra**; fable **max**; opus **high** |
| Implement | `xai/grok-4.5:high` → `openai/gpt-5.6-sol:high` → `anthropic/claude-opus-4-8:high` | **high** |
| Research scouts | tier `small` = sol:low; `medium` = **grok:high** | scouts may use sol:low; if Grok is used, always **:high** |

**Grok rule:** any use of Grok **must** be `xai/grok-4.5:high` (or equivalent high effort). Never spawn Grok on low/medium/off.

Auth: Anthropic via **Claude Code** account; OpenAI via **GPT** account; xAI via **Grok** account.

Tier map: `~/.pi/workflows/model-tiers.json`. Aliases: `~/.pi/agent/models-aliases.json`.

## bd (source of truth)

| Event | Action |
|-------|--------|
| Harness start | Epic + phase issues; store goal text |
| Spec/plan/bite-size done | Update issues; optional link export paths |
| Implement | `bd update --claim` / `bd close` per task |
| Review FAIL | Comment + block / reopen |
| PR opened | Link URL on epic/issues |

Prefer: `bd ready`, `bd update --claim`, `bd close`. Fail harness start if `bd` missing (install hint).

## CLI contract

| Prefer | Avoid |
|--------|--------|
| `rtk` shell prefix | unbounded dumps |
| `bd` | orphan markdown TODOs for harness work |
| tokensave (MCP or CLI) | codebase-memory, full-tree thrash |
| `sg` / ast-grep | multi-file sed on structure |
| headroom / context-mode | pasting walls of tool output |
| context7 | inventing APIs from memory |
| caveman | verbose agent prose |
| ponytail | over-engineered / speculative code |

## Child MCP caveat

**pi-dynamic-workflows subagents may not inherit host MCP extensions.** Skills, prompts, and AGENTS.md still load; coding tools and toolsets still work. Tokensave/headroom/context7 MCP tools may be **missing** in children.

**Fallback (mandatory in scout/implementer prompts):**

```bash
rtk tokensave …   # or: tokensave <cmd>
sg -p 'PATTERN' -l <lang>
rtk rg …
```

If MCP tools are absent, use CLI immediately — do not fail the research phase.

## Implement / worktree / PR

- All harness feature work in **git worktrees** (`isolation: "worktree"` + using-git-worktrees). No direct main dirty for features.
- Auto-load stack skills from markers (Cargo.toml → rust-skills; Swift/Xcode → Axiom; Android gradle → android skills).
- Milestone PASS + verification-before-completion → `pr-opener` with `gh` (ready if checks green, else draft).

## Entry points

| Command | Behavior |
|---------|----------|
| `/goal [text]` | Full harness; goal = text or default 7 |
| `/harness [text]` | Alias of `/goal` |
| `/init` | Scaffold only |

Interactive pi is default; harness only when those commands run.

## Design pointer

Full architecture: repo path `docs/superpowers/specs/2026-07-23-pi-goal-harness-design.md` when working inside nix-setup; else `~/.pi/agent/README-harness.md`.
