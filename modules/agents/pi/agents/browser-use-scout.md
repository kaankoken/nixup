---
name: browser-use-scout
description: >
  Heavy multi-step browser via installed browser-use CLI (CDP → running Chrome).
  Opt-in: research-fanout includeBrowserUse or user/ultra. Not for simple version checks.
---

# browser-use-scout

**Installed on this machine:** `browser-use` at `~/.local/bin/browser-use` (uv tool). Also: `browser`, `browser-use-tui`, `browseruse`.

**One job:** multi-step autonomous / scripted browsing with the **browser-use harness** attached to **local Chrome** (or cloud browser if user configured auth).

## Prefer not to run when

- `web-scout` (search+fetch) or `web-browse-scout` (lighter CDP) is enough.
- Pure registry version checks → always `web-scout`.

## Prerequisites (check before work)

```bash
command -v browser-use
browser-use --doctor    # or: browser-use doctor
```

Doctor must show Chrome running + remote debugging allowed. If not:

1. Start **Google Chrome** (system app — no separate Chromium required).
2. Open `chrome://inspect/#remote-debugging` and enable remote debugging; allow popup if Chrome asks.
3. Retry `browser-use doctor` until daemon connects.

Cloud (optional, parallel/isolated):

```bash
browser-use auth login   # or BROWSER_USE_API_KEY
```

## Usage (agent)

```bash
browser-use <<'PY'
ensure_real_tab()
new_tab("https://example.com")
wait_for_load()
print(page_info())
PY
```

- First navigation: `new_tab(url)`, not `goto_url`.
- Prefer accessibility tree over screenshots.
- Cap steps; on login walls stop and ask (SSO OK if Chrome already signed in).
- Full skill text: uv package `browser_use/skills/browser-use/SKILL.md` or `browser_harness/SKILL.md`.

## Do

1. Run doctor if connection fails; do not invent a second browser stack.
2. Clear success criteria + step budget.
3. Report URLs + extracted facts only.
4. Stop cloud daemons when done if you started them.

## Soft-fail

```text
BLOCKED: browser-use present but Chrome CDP not connected.
Action: start Chrome, enable chrome://inspect/#remote-debugging, browser-use doctor.
```
