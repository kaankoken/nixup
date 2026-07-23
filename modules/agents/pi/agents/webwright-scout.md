---
name: webwright-scout
description: >
  Optional long-horizon web tasks via Microsoft Webwright (code-as-action Playwright scripts).
  Use when includeWebwright is true or multi-step web work should become a rerunnable script.
  Complements browser-use (live CDP); does not replace search+fetch or short CDP.
---

# webwright-scout (tier 4 — optional)

**One job:** long-horizon browser work as **code-as-action** — write/run/repair Playwright scripts in a workspace (logs + screenshots), not a sticky live session.

## Prefer browser-use instead when

- Driving **already-open Chrome** with user profile / remote debugging.
- Short interactive multi-step without needing a reusable script.

## Prefer webwright when

- Task should leave a **rerunnable** `final_script.py` / trajectory.
- Long multi-site flows (research, forms, multi-page extraction).
- Host agent (Pi/Claude/Codex) can drive the Webwright skill loop.

## Install (synced by nix-setup activation)

- Skill: `~/.agents/skills/webwright` → clone of microsoft/Webwright `skills/webwright`
- Optional CLI: `webwright` / `python -m webwright.run.cli` if package install succeeded
- Playwright: Webwright’s install may want Chromium; system Chrome can work if configured — soft-fail if missing

Upstream: https://github.com/microsoft/Webwright

## How to run

1. Ensure skill is discoverable (`~/.agents/skills` on Pi skills path — already in settings.harness).
2. Follow skill `SKILL.md`: scaffold workspace, plan, instrumented Playwright runs under `final_runs/`.
3. Or CLI (if present):

```bash
# example shape — see package docs for current flags
python -m webwright.run.cli -c base.yaml -t "<task>" -o /tmp/webwright-out
```

4. Return: summary + paths to script/trajectory/screenshots. Do not dump full trajectories into chat.

## Soft-fail

```text
BLOCKED: webwright skill/CLI unavailable.
Activation: modules/agents installs skill under ~/.agents/skills/webwright.
Manual: git clone microsoft/Webwright && ln -s skills/webwright ~/.agents/skills/webwright
```
