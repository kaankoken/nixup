---
description: Alias of /goal — start the full Pi goal harness
argument-hint: "[goal text]"
---
# /harness — Pi Goal Harness (alias of /goal)

You are the **parent orchestrator** for the Pi multi-model goal harness. Execute the steps below in order. Do not invent a parallel process.

## 1. Bind the goal

- **If user arguments are present** (`$@` non-empty): goal text = `$@`
- **Otherwise**: use the **default 7 quality rules**:
  1. No errors, no warnings, no test failures.
  2. No warning suppressions in production (test-only allows with reason OK).
  3. Everything wired — no stubs, TODO/TBD/FIXME, unfinished tasks.
  4. Use mandated skills (superpowers + stack + caveman + ponytail).
  5. Latest dependencies — verify on the web; do not trust training data or local context-mode alone.
  6. Complete all superpowers-derived spec/plan tasks.
  7. Specs, plans, goals, updates tracked in **bd** as source of truth.

State the bound goal clearly at the start of the session.

## 2. Load skills

1. Load and follow **using-superpowers** (process engine for brainstorm → plan → implement → review → PR).
2. Load and follow the **goal-harness** skill (`~/.pi/agent/skills/goal-harness` or project skills) for phases, gates N, model pools, nested research rules, bd, and CLI contract.

## 3. Project init gate

If the project is **empty** or **not initted** (missing root `AGENTS.md`, missing `bd` init / harness markers, or no meaningful project scaffold):

- Run **project-init** first (agent type `project-init` or stack-aware scaffold path from goal-harness).
- Do **not** start Spec/Plan until init completes.
- User can force scaffold-only later via `/init`.

## 4. Start outer harness workflow

Start the **outer goal-harness workflow** via **pi-dynamic-workflows**:

- Prefer saved/template workflow name **`goal-harness`** with args `{ idea/goal, cwd }`.
- Phases: Init → Spec → Plan → BiteSize → Implement → Milestone → PR.
- Runtime primitives: `agent`, `parallel`, `phase`, `gate`, `retry`, `verify`, `isolation: "worktree"`.
- Superpowers owns *how*; dynamic-workflows owns *spawn/orchestration*. Do not run two competing full harness chains.

## 5. bd is source of truth

- Create/update a **bd epic** for this goal; phase issues under it.
- Store goal text on the epic; claim/close issues as work progresses.
- Markdown under `docs/superpowers/…` is **export only**, not SoT.
- Prefer `bd ready`, `bd update --claim`, `bd close`, comments for FAIL/block.

## 6. Large ideas → nested research fan-out

When the idea is **large** (multi-subsystem, greenfield feature, deep recon, or user asks for high/ultra effort):

- The phase lead **must author a nested research workflow** (template **`research-fanout`** or inline `parallel` of specialized scouts).
- Do **not** thrash alone reading the whole repo in one context.
- Parallel scout agentTypes (narrow jobs):
  | Agent | Focus | Tools |
  |-------|--------|--------|
  | `code-graph-scout` | Structure, callers, impact | tokensave MCP or CLI |
  | `code-search-scout` | AST/symbols/patterns | `sg` / ast-grep, `rg` |
  | `docs-scout` | Library/API truth | context7 |
  | `web-scout` | Latest versions / ecosystem (goal #5) | web |
  | `stack-scout` | Rust / iOS / Android conventions | stack skills |

Synthesize scout results → then draft spec/plan. Reviewers are **different** agent types from producers.

## 7. Review gates (N)

| Gate | Producer | Reviewer | N |
|------|----------|----------|---|
| Spec | `spec-writer` | `spec-reviewer` | 3 |
| Plan | `plan-writer` | `plan-reviewer` | 3 |
| Bite-size | `bite-size-writer` | `bite-size-reviewer` | 2 |
| Milestone | implementers + multi-review | `code-reviewer` / organizer | 3 |

On FAIL: feed reviewer `feedback`/`blocking` back to producer. After N failures: **stop and escalate to human** with findings.

## 8. Implement, milestone, PR

- Implement: parallel **worktree** implementers from bd tasks; SDD + TDD + ponytail + stack skills auto.
- Milestone: multi-angle review workflow (`milestone-review`); verification-before-completion.
- PR: `pr-opener` via `gh` after PASS; body includes goal checklist + bd links.

## 9. CLI contract (always)

Prefer: `rtk`, `bd`, tokensave, `sg`/ast-grep, headroom, context-mode, context7, caveman, ponytail.  
**Never** codebase-memory. Soft sandbox: project + worktrees + agent CLIs + needed network only.

## Arguments

User goal override (if any):

```
${@:-}
```

If the block above is empty, use the default 7 quality rules.
