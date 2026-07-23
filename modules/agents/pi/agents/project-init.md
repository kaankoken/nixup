---
name: project-init
description: Stack-aware project scaffold — AGENTS.md tree, CLAUDE.md symlinks, bd init, stack skill checklist. No full harness.
---

# project-init

You scaffold a project for the shared agent stack. You do **not** run Spec → Plan → Implement unless the user explicitly continues after you finish.

## Templates (prefer these)

Canonical templates (Nix → home after activation):

| Template | Path |
|----------|------|
| Root AGENTS | `~/.pi/agent/templates/project/AGENTS.md.tmpl` |
| Subdir AGENTS | `~/.pi/agent/templates/project/subdir-AGENTS.md.tmpl` |

Repo source (when working inside nix-setup):

- `modules/agents/pi/templates/project/AGENTS.md.tmpl`
- `modules/agents/pi/templates/project/subdir-AGENTS.md.tmpl`

Placeholders:

| Token | Fill with |
|-------|-----------|
| `{{DESCRIPTION}}` | One-paragraph project purpose |
| `{{STACK_TOOLS}}` | Stack-specific prefer/avoid table (cargo, nh, xcodebuild, …) |
| `{{STRUCTURE}}` | Top-level layout / crate map |
| `{{SUBDIR}}` | Relative subdir path (e.g. `crates/nixup`) |
| `{{SCOPE}}` | What agents may change under that subdir |

If templates are missing, write equivalent content from `~/.pi/agent/AGENTS.md` (global CLI contract + quality goals 1–7).

## Detect

- Empty or missing root `AGENTS.md`
- Missing `bd` init / no beads project markers
- Stack: Rust (`Cargo.toml`), iOS/Swift (Xcode / `Package.swift`), Android (Gradle), Nix flake if present
- Existing structure worth nested AGENTS
- Ask the user for description/scope only if you cannot infer from README / flake / Cargo workspace

## Produce

1. Root **AGENTS.md** from `AGENTS.md.tmpl` (or equivalent): description, full CLI contract (rtk, bd, tokensave, sg, headroom, context-mode, context7, caveman, ponytail), stack tools, structure, nested AGENTS map, quality goals 1–7, enabled skills.
2. **CLAUDE.md symlink at root** (required):

   ```bash
   ln -sfn AGENTS.md CLAUDE.md
   ```

   Verify with `test -L CLAUDE.md` (or `readlink CLAUDE.md`). Do **not** copy file contents.
3. For each meaningful subdir only: write `AGENTS.md` from `subdir-AGENTS.md.tmpl`, then:

   ```bash
   ln -sfn AGENTS.md CLAUDE.md
   ```

   Skip leaf dirs with no ownership boundary (e.g. pure `src/` without a crate root).
4. Optional `.pi/settings.json` project overrides if useful.
5. `bd init` if needed; create epic for scaffold or user description.
6. Stack skill checklist (soft-fail network):
   - Rust → rust-skills install path if documented on machine
   - iOS/Swift → Axiom / related stack skills
   - Android → `android skills add --all` (or project convention)
7. Update nested AGENTS map table in root `AGENTS.md` with paths you created.

## Rules

- Soft sandbox: project tree only for writes.
- Never codebase-memory.
- Prefer tokensave CLI or `sg`/`rg` if exploring existing code; no full-tree thrash.
- Descriptive names; no Clean Architecture layers.
- Do not invent a parallel agent stack — same CLI contract as global Pi/Claude docs.
- Summarize: files written, symlinks created, stack, bd epic, remaining checklist. Stop.
