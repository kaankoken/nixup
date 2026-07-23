/**
 * Nested research fan-out for large brainstorm/plan phases.
 * Runtime globals (pi-dynamic-workflows): agent, parallel, phase, log, args, cwd
 *
 * args: {
 *   idea: string,
 *   focusPaths?: string|string[],
 *   includeStack?: boolean,        // default true
 *   includeBrowse?: boolean,       // default false — CDP / headless (web-browse-scout)
 *   includeBrowserUse?: boolean,   // default false — heavy browser-use scout
 *   includeWebwright?: boolean,    // default false — long-horizon Webwright code-as-action
 * }
 */
export const meta = {
  name: 'research-fanout',
  description:
    'Parallel scouts (code, docs, web search+fetch, optional CDP, browser-use, webwright, stack) then synthesize',
  phases: [{ title: 'Research' }, { title: 'Synthesize' }],
}

const researchArgs = typeof args === 'object' && args !== null ? args : {}
const ideaText =
  typeof researchArgs.idea === 'string' && researchArgs.idea.length > 0
    ? researchArgs.idea
    : typeof researchArgs.goal === 'string'
      ? researchArgs.goal
      : String(researchArgs.prompt || researchArgs || 'unspecified idea')
const focusPaths = researchArgs.focusPaths
  ? Array.isArray(researchArgs.focusPaths)
    ? researchArgs.focusPaths.join(', ')
    : String(researchArgs.focusPaths)
  : '(whole project as needed)'
const includeStack = researchArgs.includeStack !== false
const includeBrowse = researchArgs.includeBrowse === true
const includeBrowserUse = researchArgs.includeBrowserUse === true
const includeWebwright = researchArgs.includeWebwright === true

phase('Research')
log(
  'research-fanout: scouting for: ' +
    ideaText +
    ' | browse=' +
    includeBrowse +
    ' browserUse=' +
    includeBrowserUse +
    ' webwright=' +
    includeWebwright,
)

const scoutPromptPrefix =
  'Idea: ' +
  ideaText +
  '\nFocus paths: ' +
  focusPaths +
  '\nWorking directory: ' +
  (typeof cwd === 'string' ? cwd : '.') +
  '\nMCP may be unavailable — use CLI fallbacks (tokensave, sg, rtk rg, curl). ' +
  'Never use codebase-memory. Read-only. Return a compact structured report.\n' +
  'Web tiers: prefer web-scout (search+fetch); CDP=web-browse-scout; heavy=browser-use-scout.\n\n'

const scoutThunks = [
  () =>
    agent(
      scoutPromptPrefix +
        'Map modules, deps, callers, and impact via tokensave (MCP or CLI).',
      {
        agentType: 'code-graph-scout',
        tier: 'medium',
        label: 'code-graph-scout',
      },
    ),
  () =>
    agent(
      scoutPromptPrefix +
        'AST/symbol/pattern search for related code via sg and rg.',
      {
        agentType: 'code-search-scout',
        tier: 'medium',
        label: 'code-search-scout',
      },
    ),
  () =>
    agent(
      scoutPromptPrefix +
        'Confirm external library/API truth via context7; do not invent APIs.',
      {
        agentType: 'docs-scout',
        tier: 'small',
        label: 'docs-scout',
      },
    ),
  () =>
    agent(
      scoutPromptPrefix +
        'DEFAULT web tier: search API + HTTP fetch for latest package/tool versions and ecosystem (goal #5). No CDP unless you document fetch failure.',
      {
        agentType: 'web-scout',
        tier: 'small',
        label: 'web-scout',
      },
    ),
]

if (includeBrowse) {
  scoutThunks.push(() =>
    agent(
      scoutPromptPrefix +
        'OPTIONAL CDP/headless: open JS-rendered docs or short click-paths only. Prefer text/a11y snapshot. Soft-fail if chrome-cdp missing.',
      {
        agentType: 'web-browse-scout',
        tier: 'medium',
        label: 'web-browse-scout',
      },
    ),
  )
}

if (includeBrowserUse) {
  scoutThunks.push(() =>
    agent(
      scoutPromptPrefix +
        'HEAVY browser-use: multi-step via browser-use CLI + running Chrome CDP. Soft-fail if CLI/Chrome remote debugging missing.',
      {
        agentType: 'browser-use-scout',
        tier: 'medium',
        label: 'browser-use-scout',
      },
    ),
  )
}

if (includeWebwright) {
  scoutThunks.push(() =>
    agent(
      scoutPromptPrefix +
        'TIER-4 Webwright: long-horizon code-as-action Playwright (rerunnable scripts/logs). Soft-fail if ~/.agents/skills/webwright missing.',
      {
        agentType: 'webwright-scout',
        tier: 'medium',
        label: 'webwright-scout',
      },
    ),
  )
}

if (includeStack) {
  scoutThunks.push(() =>
    agent(
      scoutPromptPrefix +
        'Report Rust / iOS Axiom / Android stack conventions relevant to this idea.',
      {
        agentType: 'stack-scout',
        tier: 'small',
        label: 'stack-scout',
      },
    ),
  )
}

const scoutReports = await parallel(scoutThunks)

phase('Synthesize')
const synthesisPrompt =
  'Synthesize the following parallel research reports into one brief for the next producer ' +
  '(spec-writer or plan-writer). Deduplicate, highlight conflicts, list concrete files/APIs, ' +
  'and call out open questions.\n\nIdea: ' +
  ideaText +
  '\n\n--- REPORTS ---\n' +
  scoutReports
    .map(function (report, reportIndex) {
      return '### Scout ' + (reportIndex + 1) + '\n' + String(report || '(empty)')
    })
    .join('\n\n')

const researchBrief = await agent(synthesisPrompt, {
  tier: 'medium',
  label: 'research-synthesize',
})

return {
  idea: ideaText,
  focusPaths: focusPaths,
  scoutReports: scoutReports,
  brief: researchBrief,
}
