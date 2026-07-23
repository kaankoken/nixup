# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy for shell commands.
Part of the shared agent stack — see `AGENTS.md` for tokensave, beads, headroom, context-mode, etc.

## Rule

Always prefix shell commands with `rtk` (or rely on RTK PreToolUse hooks after `rtk init`).

Examples:

```bash
rtk git status
rtk cargo test
rtk cargo clippy
rtk npm run build
rtk pytest -q
```

## Meta Commands

```bash
rtk gain            # Token savings analytics
rtk gain --history  # Recent command savings history
rtk proxy <cmd>     # Run raw command without filtering
rtk discover        # Missed savings opportunities
```

## Multi-agent hooks

```bash
rtk init -g --auto-patch           # Claude Code
rtk init -g --codex                # Codex (AGENTS.md + RTK.md)
rtk init -g --agent cursor --auto-patch
rtk init -g --agent pi --auto-patch
```

Grok and other agents without a dedicated RTK hook: follow this file + `AGENTS.md` and prefix shell with `rtk` manually.

## Verification

```bash
rtk --version
rtk gain
which rtk
```

> **Name collision**: crates.io also has an unrelated `rtk`. If `rtk gain` fails, reinstall from https://github.com/rtk-ai/rtk (or this flake’s agents module).
