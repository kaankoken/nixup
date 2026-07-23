# Web & browser capability (Pi goal harness)

Four tiers. **Always start lower.** Escalate only when needed.

| Tier | Agent type | Default in research-fanout? | Backend (nix-setup activation) |
|------|------------|----------------------------|--------------------------------|
| **1. Search + fetch** | `web-scout` | **Yes** (always) | Search skill / `curl` / `rtk curl` |
| **2. CDP / headless** | `web-browse-scout` | `includeBrowse: true` | chrome-cdp skill (soft) |
| **3. Browser-use** | `browser-use-scout` | `includeBrowserUse: true` | **`uv tool install browser-use`** (activation; multi-device). Chrome CDP. |
| **4. Webwright** | `webwright-scout` | `includeWebwright: true` | Skill `~/.agents/skills/webwright` from microsoft/Webwright; CLI soft |

## research-fanout args

```js
{
  idea: string,
  focusPaths?: string | string[],
  includeStack?: boolean,       // default true
  includeBrowse?: boolean,      // default false — CDP scout
  includeBrowserUse?: boolean,  // default false — browser-use + Chrome
  includeWebwright?: boolean,   // default false — long-horizon Webwright
}
```

Goal-harness may set flags when SPA-heavy (`includeBrowse`), deep interactive web (`includeBrowserUse`), or long-horizon / rerunnable automation (`includeWebwright`).

## Env / secrets

| Variable | Use |
|----------|-----|
| `BRAVE_API_KEY` | Brave Search skill (if used) |
| Other search keys | Per installed skill README |
| Browser-use LLM keys | As required by browser-use config (prefer existing subscription routing) |

Never commit keys. Do not put secrets in agent markdown.

## Activation / multi-device (modules/agents)

| Tool | Activation behavior |
|------|---------------------|
| **browser-use** | `uv tool install browser-use` if missing → `~/.local/bin/browser-use` |
| **webwright skill** | clone microsoft/Webwright → symlink `~/.agents/skills/webwright` |
| **webwright CLI** | soft `uv tool install --from` clone (optional) |
| **chrome-cdp** | soft `pi install git:github.com/pasky/chrome-cdp-skill` |

- **No separate Chromium** for browser-use if Google Chrome exists (CDP).
- Webwright’s own docs may still pull Playwright Chromium for isolated runs — soft-fail if not needed.
- Chrome session: `chrome://inspect/#remote-debugging` when `browser-use doctor` fails.

### Smoke

```bash
browser-use --version
browser-use doctor
test -f ~/.agents/skills/webwright/SKILL.md && echo webwright skill OK
```

## Related

- Agent prompts: `agents/web-scout.md`, `web-browse-scout.md`, `browser-use-scout.md`
- Child tools: `docs/child-tools.md`
- Global contract: `AGENTS.global.md`
