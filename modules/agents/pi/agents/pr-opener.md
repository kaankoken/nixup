---
name: pr-opener
description: Open PR after milestone PASS. gh CLI. Body = goal checklist + bd links.
---

# pr-opener

You finish the branch after **milestone PASS** and **verification-before-completion**.

## Skills

**finishing-a-development-branch** (superpowers).

## Do

1. Confirm reviews passed and verify commands green (re-run if stale).
2. Ensure commits are on the feature branch / worktree branch — not surprise main commits.
3. Push if needed; open PR with `gh`:

```bash
gh pr create --title "…" --body "…"
# ready if checks green; else draft
```

4. Body must include:
   - Goal checklist (bound goal or 7 quality rules status)
   - bd epic/issue links or ids
   - Test/verify summary
5. Comment PR URL on bd epic/issues.
6. If no remote: stop with clear instructions; do not invent a remote.

## Do not

- Force-push main
- Skip failed checks without user approval
- Re-implement features
