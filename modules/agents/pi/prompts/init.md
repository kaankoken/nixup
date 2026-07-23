---
description: Stack-aware project scaffold only (no full goal harness)
argument-hint: "[optional project description]"
---
# /init — Project scaffold

You run **project-init only**. Do **not** start the full goal harness (no Spec → Plan → Implement → PR) unless the user explicitly asks to continue after scaffold.

## Goal of this command

Make the current directory a stack-aware agent-ready project:

1. Detect empty/not-initted state and what already exists.
2. Infer or ask for a short **project description** (args if present: `$@`).
3. Detect stack markers:
   - Rust: `Cargo.toml`, workspace members
   - iOS/Swift: `*.xcodeproj`, `Package.swift`, SwiftUI markers
   - Android: `build.gradle*`, `settings.gradle*`, Compose markers
   - Nix/flake if present (document, do not invent parallel agent stacks)
4. Write **root `AGENTS.md`** with:
   - Project description
   - Shared CLI contract (rtk, bd, tokensave, sg, headroom, context-mode, context7, caveman, ponytail)
   - Stack-specific tools
   - Repo structure map
   - Nested AGENTS map
   - Default 7 quality rules
   - Skills enabled for this project
5. `ln -sfn AGENTS.md CLAUDE.md` at root (always symlink).
6. For meaningful subdirs: nested `AGENTS.md` + `CLAUDE.md` → sibling `AGENTS.md`.
7. Optional project `.pi/settings.json` overrides only if useful.
8. `bd init` if needed; create a light epic for "project scaffold" or the given description.
9. Note stack skill installs as a checklist (rust-skills / Axiom / `android skills add --all`) — soft-fail if network.

## Constraints

- Soft sandbox: project tree + agent CLIs; no arbitrary home writes.
- **Never** codebase-memory.
- Prefer `project-init` agentType when spawning a child; otherwise do the scaffold inline.
- Prefer tokensave/`sg` for structure when exploring existing code; do not thrash the whole tree.
- When done: summarize files created, stack detected, bd epic id, and remaining checklist items. Stop unless user says continue with `/goal` or `/harness`.

## Arguments

Optional description / scope:

```
${@:-}
```
