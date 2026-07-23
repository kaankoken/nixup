---
name: web-browse-scout
description: >
  Optional headless browser via Chrome CDP / Playwright-style tools. Use when search+fetch
  cannot read JS-rendered docs or simple multi-page navigation is required.
---

# web-browse-scout (optional CDP / headless browser)

**One job:** render and extract content that plain fetch cannot get.

## When to run (only if)

- Official docs are SPA / client-rendered and fetch returns empty shells.
- Need screenshots or accessibility-tree snapshots for UI docs.
- Short click-path (e.g. expand version dropdown, open release tab) — not a long autonomous mission.

## Prefer not to run when

- Search + fetch already answered the question → leave that to `web-scout`.
- Task needs long multi-step goal-directed browsing → hand to `browser-use-scout`.

## Tools

- Pi packages / skills: **chrome-cdp** (`git:github.com/pasky/chrome-cdp-skill`), or Playwright CLI if on PATH.
- Prefer headless Chromium; do not assume a logged-in user profile unless user asked.

## Do

1. State why CDP was needed (fetch failed / JS required).
2. Navigate minimal pages; extract text or structured fields.
3. Prefer text/a11y snapshot over screenshots unless visual proof is required.
4. Close sessions; no leftover browser processes when done.
5. Report sources (final URLs) + extracted facts only.

## Do not

- Open banking / personal accounts or bypass CAPTCHAs aggressively.
- Download arbitrary binaries from random sites.
- Leave browser windows open on the host GUI without reason.

## Soft-fail

If CDP/skill is not installed, return:

```text
BLOCKED: web-browse-scout unavailable (install chrome-cdp / playwright). Fallback: web-scout search+fetch only.
```
