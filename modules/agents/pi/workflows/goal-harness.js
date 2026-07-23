/**
 * Outer Pi goal harness: init → research+spec → plan → bite-size → implement → milestone → PR.
 * Runtime globals (pi-dynamic-workflows VM): agent, parallel, phase, gate, workflow, log, args, cwd
 * Determinism: no Date/Math.random/require/import/fs/network in this script.
 *
 * args: {
 *   idea?: string, goal?: string, prompt?: string,
 *   skipInit?: boolean,
 *   forceResearch?: boolean,
 *   tasks?: string[]   // optional pre-split implement tasks
 * }
 */
export const meta = {
  name: 'goal-harness',
  description: 'Full superpowers goal harness with review gates (N=3/3/2/3), research fan-out, worktree implement, PR',
  phases: [
    { title: 'Init' },
    { title: 'Spec' },
    { title: 'Plan' },
    { title: 'BiteSize' },
    { title: 'Implement' },
    { title: 'Milestone' },
    { title: 'PR' },
  ],
}

const harnessArgs = typeof args === 'object' && args !== null ? args : {}
const boundGoal =
  typeof harnessArgs.idea === 'string' && harnessArgs.idea.length > 0
    ? harnessArgs.idea
    : typeof harnessArgs.goal === 'string' && harnessArgs.goal.length > 0
      ? harnessArgs.goal
      : typeof harnessArgs.prompt === 'string' && harnessArgs.prompt.length > 0
        ? harnessArgs.prompt
        : [
            'Default quality bar:',
            '1) No errors/warnings/test failures',
            '2) No prod warning suppressions',
            '3) Everything wired (no stubs/TODO)',
            '4) Mandated skills (superpowers+stack+caveman+ponytail)',
            '5) Latest deps verified on the web',
            '6) Complete superpowers spec/plan tasks',
            '7) bd is source of truth',
          ].join(' ')

const workingDirectory = typeof cwd === 'string' ? cwd : '.'
const forceResearch = harnessArgs.forceResearch === true
const skipInit = harnessArgs.skipInit === true

// Heuristic: long multi-clause goals or explicit force → nested research.
// (No Math.random; pure string length / keyword signals.)
const goalLooksLarge =
  forceResearch ||
  boundGoal.length > 280 ||
  boundGoal.indexOf('\n') !== -1 ||
  /\b(and|also|plus|migrate|refactor|rewrite|multi|across|entire|whole)\b/i.test(
    boundGoal,
  )

const reviewResultSchema = {
  type: 'object',
  properties: {
    ok: { type: 'boolean' },
    feedback: { type: 'string' },
    blocking: { type: 'array', items: { type: 'string' } },
  },
  required: ['ok', 'feedback', 'blocking'],
}

function parseReviewPayload(reviewValue) {
  if (reviewValue && typeof reviewValue === 'object') {
    // Nested milestone-review return shape: { ok, value, feedback, blocking }
    if (
      reviewValue.value !== undefined &&
      (reviewValue.ok === true || reviewValue.ok === false)
    ) {
      return {
        ok: !!reviewValue.ok,
        feedback: String(reviewValue.feedback || ''),
        blocking: Array.isArray(reviewValue.blocking)
          ? reviewValue.blocking
          : [],
      }
    }
    return {
      ok: !!reviewValue.ok,
      feedback: String(reviewValue.feedback || ''),
      blocking: Array.isArray(reviewValue.blocking)
        ? reviewValue.blocking
        : [],
    }
  }
  const text = String(reviewValue || '')
  // Best-effort: look for "ok": false/true in free text.
  if (/"ok"\s*:\s*false/i.test(text)) {
    return { ok: false, feedback: text, blocking: [text] }
  }
  if (/"ok"\s*:\s*true/i.test(text)) {
    return { ok: true, feedback: text, blocking: [] }
  }
  // Default fail-closed if unparsable.
  return {
    ok: false,
    feedback: 'Unparsable reviewer output; treat as FAIL.\n' + text,
    blocking: ['Reviewer did not return valid {ok, feedback, blocking} JSON'],
  }
}

function formatFeedback(reviewPayload) {
  const blockingList =
    reviewPayload.blocking && reviewPayload.blocking.length
      ? '\nBlocking:\n- ' + reviewPayload.blocking.join('\n- ')
      : ''
  return String(reviewPayload.feedback || '') + blockingList
}

// --- Init -------------------------------------------------------------------
phase('Init')
log('goal-harness: goal bound')
if (!skipInit) {
  await agent(
    'You are project-init. Assess whether ' +
      workingDirectory +
      ' needs stack-aware scaffold (AGENTS.md, CLAUDE.md symlink, bd). ' +
      'If already initted, say so and list markers. If not, scaffold only. ' +
      'Goal context: ' +
      boundGoal +
      '\nDo not start Spec/Plan/Implement.',
    {
      agentType: 'project-init',
      tier: 'medium',
      label: 'project-init',
    },
  )
}

// Create / update bd epic via a cheap agent (shell tools in subagent).
await agent(
  'Using bd as SoT: ensure an epic exists for this harness goal and phase issues ' +
    '(Spec, Plan, BiteSize, Implement, Milestone, PR). Store goal text on the epic.\n' +
    'Goal:\n' +
    boundGoal +
    '\nCwd: ' +
    workingDirectory +
    '\nIf bd missing, report install hint and fail clearly.',
  {
    tier: 'small',
    label: 'bd-epic-bootstrap',
  },
)

// --- Spec -------------------------------------------------------------------
phase('Spec')
let researchBrief = ''
if (goalLooksLarge) {
  log('goal-harness: large idea → research-fanout')
  // Nested saved workflow when available; fallback is inline parallel via agent types.
  let researchResult = null
  try {
    researchResult = await workflow('research-fanout', {
      idea: boundGoal,
      includeStack: true,
    })
  } catch (researchWorkflowError) {
    log('goal-harness: research-fanout workflow unavailable; inline parallel scouts')
    const inlineReports = await parallel([
      () =>
        agent('Map structure/impact via tokensave for: ' + boundGoal, {
          agentType: 'code-graph-scout',
          tier: 'medium',
          label: 'inline-graph',
        }),
      () =>
        agent('AST/symbol search for: ' + boundGoal, {
          agentType: 'code-search-scout',
          tier: 'medium',
          label: 'inline-search',
        }),
      () =>
        agent('Library/API docs via context7 for: ' + boundGoal, {
          agentType: 'docs-scout',
          tier: 'small',
          label: 'inline-docs',
        }),
      () =>
        agent('Latest versions / ecosystem for: ' + boundGoal, {
          agentType: 'web-scout',
          tier: 'small',
          label: 'inline-web',
        }),
      () =>
        agent('Stack conventions for: ' + boundGoal, {
          agentType: 'stack-scout',
          tier: 'small',
          label: 'inline-stack',
        }),
    ])
    researchResult = {
      brief: inlineReports.join('\n\n---\n\n'),
      scoutReports: inlineReports,
    }
  }
  researchBrief =
    researchResult && researchResult.brief
      ? String(researchResult.brief)
      : String(researchResult || '')
}

const specGate = await gate(
  async function (previousFeedback, attemptNumber) {
    const feedbackBlock = previousFeedback
      ? '\n\nPrevious review feedback (attempt ' +
        attemptNumber +
        '):\n' +
        previousFeedback
      : ''
    return await agent(
      'Write the design/spec for this goal using brainstorming.\nGoal:\n' +
        boundGoal +
        '\n\nResearch brief (may be empty for small goals):\n' +
        researchBrief +
        feedbackBlock +
        '\nUpdate bd Spec issue when done. Do not implement.',
      {
        agentType: 'spec-writer',
        tier: 'big',
        label: 'spec-writer-a' + attemptNumber,
      },
    )
  },
  async function (specValue) {
    const reviewRaw = await agent(
      'Review this design/spec. Return JSON only {ok, feedback, blocking}.\n\n' +
        String(specValue || ''),
      {
        agentType: 'spec-reviewer',
        tier: 'big',
        label: 'spec-reviewer',
        schema: reviewResultSchema,
      },
    )
    const reviewPayload = parseReviewPayload(reviewRaw)
    return {
      ok: reviewPayload.ok,
      feedback: formatFeedback(reviewPayload),
    }
  },
  { attempts: 3 },
)

if (!specGate.ok) {
  return {
    ok: false,
    phase: 'Spec',
    escalate: true,
    message: 'Spec gate failed after N=3; escalate to human',
    feedback: formatFeedback(parseReviewPayload(specGate.value)),
    value: specGate,
  }
}
const approvedSpec = specGate.value

// --- Plan -------------------------------------------------------------------
phase('Plan')
const planGate = await gate(
  async function (previousFeedback, attemptNumber) {
    const feedbackBlock = previousFeedback
      ? '\n\nPrevious review feedback (attempt ' +
        attemptNumber +
        '):\n' +
        previousFeedback
      : ''
    return await agent(
      'Write an incremental implementation plan (writing-plans) from this approved spec.\n\n' +
        String(approvedSpec || '') +
        '\n\nGoal:\n' +
        boundGoal +
        feedbackBlock +
        '\nUpdate bd Plan issue. Do not implement.',
      {
        agentType: 'plan-writer',
        tier: 'big',
        label: 'plan-writer-a' + attemptNumber,
      },
    )
  },
  async function (planValue) {
    const reviewRaw = await agent(
      'Review this plan. Return JSON only {ok, feedback, blocking}.\n\n' +
        String(planValue || ''),
      {
        agentType: 'plan-reviewer',
        tier: 'big',
        label: 'plan-reviewer',
        schema: reviewResultSchema,
      },
    )
    const reviewPayload = parseReviewPayload(reviewRaw)
    return {
      ok: reviewPayload.ok,
      feedback: formatFeedback(reviewPayload),
    }
  },
  { attempts: 3 },
)

if (!planGate.ok) {
  return {
    ok: false,
    phase: 'Plan',
    escalate: true,
    message: 'Plan gate failed after N=3; escalate to human',
    value: planGate,
  }
}
const approvedPlan = planGate.value

// --- BiteSize ---------------------------------------------------------------
phase('BiteSize')
const biteSizeGate = await gate(
  async function (previousFeedback, attemptNumber) {
    const feedbackBlock = previousFeedback
      ? '\n\nPrevious review feedback (attempt ' +
        attemptNumber +
        '):\n' +
        previousFeedback
      : ''
    return await agent(
      'Split this plan into bite-sized implementable tasks for bd + worktrees.\n\n' +
        String(approvedPlan || '') +
        feedbackBlock,
      {
        agentType: 'bite-size-writer',
        tier: 'big',
        label: 'bite-size-writer-a' + attemptNumber,
      },
    )
  },
  async function (tasksValue) {
    const reviewRaw = await agent(
      'Review task sizing. Return JSON only {ok, feedback, blocking}.\n\n' +
        String(tasksValue || ''),
      {
        agentType: 'bite-size-reviewer',
        tier: 'big',
        label: 'bite-size-reviewer',
        schema: reviewResultSchema,
      },
    )
    const reviewPayload = parseReviewPayload(reviewRaw)
    return {
      ok: reviewPayload.ok,
      feedback: formatFeedback(reviewPayload),
    }
  },
  { attempts: 2 },
)

if (!biteSizeGate.ok) {
  return {
    ok: false,
    phase: 'BiteSize',
    escalate: true,
    message: 'Bite-size gate failed after N=2; escalate to human',
    value: biteSizeGate,
  }
}
const biteSizedTasks = biteSizeGate.value

// --- Implement --------------------------------------------------------------
phase('Implement')
// Prefer explicit args.tasks; otherwise ask a small agent to list one-line tasks from bite-size output.
let taskList = Array.isArray(harnessArgs.tasks) ? harnessArgs.tasks.slice() : null
if (!taskList || taskList.length === 0) {
  const listed = await agent(
    'Extract a JSON array of short task title strings from this bite-size plan. ' +
      'Return ONLY a JSON array of strings, no markdown.\n\n' +
      String(biteSizedTasks || ''),
    {
      tier: 'small',
      label: 'task-list-extract',
    },
  )
  if (Array.isArray(listed)) {
    taskList = listed.map(String)
  } else {
    try {
      const parsed = JSON.parse(String(listed))
      taskList = Array.isArray(parsed) ? parsed.map(String) : [String(listed)]
    } catch (parseError) {
      taskList = [String(listed || biteSizedTasks || 'implement goal')]
    }
  }
}

// Cap parallel implement fan-out to avoid runaway cost (orchestrator still sequential if one task).
const maxParallelImplement = 8
const implementSlice = taskList.slice(0, maxParallelImplement)

const implementResults = await parallel(
  implementSlice.map(function (taskTitle, taskIndex) {
    return function () {
      return agent(
        'Implement this single task in a git worktree (SDD, TDD, ponytail, stack skills auto).\n' +
          'Claim/close bd for the task.\n' +
          'Task ' +
          (taskIndex + 1) +
          '/' +
          implementSlice.length +
          ': ' +
          taskTitle +
          '\n\nGoal:\n' +
          boundGoal +
          '\n\nFull bite-size context:\n' +
          String(biteSizedTasks || ''),
        {
          agentType: 'implementer',
          tier: 'medium',
          isolation: 'worktree',
          label: 'implementer-' + (taskIndex + 1),
        },
      )
    }
  }),
)

// --- Milestone --------------------------------------------------------------
phase('Milestone')
const milestoneGate = await gate(
  async function (previousFeedback, attemptNumber) {
    if (previousFeedback) {
      await agent(
        'Fix blocking review findings in worktrees, then re-verify. Attempt ' +
          attemptNumber +
          '.\nFindings:\n' +
          previousFeedback +
          '\nGoal:\n' +
          boundGoal,
        {
          agentType: 'implementer',
          tier: 'medium',
          isolation: 'worktree',
          label: 'milestone-fix-a' + attemptNumber,
        },
      )
    }

    let milestoneResult = null
    try {
      milestoneResult = await workflow('milestone-review', {
        goal: boundGoal,
        scope: 'implemented work for this harness run',
      })
    } catch (milestoneWorkflowError) {
      log('goal-harness: milestone-review workflow unavailable; sequential code-reviewer')
      milestoneResult = await agent(
        'Milestone review for goal:\n' +
          boundGoal +
          '\nImplement results:\n' +
          implementResults.map(String).join('\n---\n') +
          '\nReturn JSON {ok, feedback, blocking}.',
        {
          agentType: 'milestone-organizer',
          tier: 'big',
          label: 'milestone-organizer-a' + attemptNumber,
        },
      )
    }
    return milestoneResult
  },
  async function (milestoneValue) {
    // If value already looks like a review object, use it; else run code-reviewer.
    let reviewPayload = parseReviewPayload(milestoneValue)
    if (
      milestoneValue &&
      typeof milestoneValue === 'object' &&
      (milestoneValue.ok === true || milestoneValue.ok === false)
    ) {
      reviewPayload = parseReviewPayload(milestoneValue)
    } else if (
      milestoneValue &&
      typeof milestoneValue === 'object' &&
      milestoneValue.value !== undefined
    ) {
      reviewPayload = parseReviewPayload(milestoneValue.value)
    }
    // Secondary pass when still ambiguous.
    if (
      !reviewPayload.ok &&
      reviewPayload.blocking[0] &&
      reviewPayload.blocking[0].indexOf('Unparsable') === 0
    ) {
      const reviewRaw = await agent(
        'Confirm milestone PASS/FAIL. Return JSON {ok, feedback, blocking}.\n\n' +
          String(JSON.stringify(milestoneValue)),
        {
          agentType: 'code-reviewer',
          tier: 'big',
          label: 'milestone-code-reviewer',
          schema: reviewResultSchema,
        },
      )
      reviewPayload = parseReviewPayload(reviewRaw)
    }
    return {
      ok: reviewPayload.ok,
      feedback: formatFeedback(reviewPayload),
    }
  },
  { attempts: 3 },
)

if (!milestoneGate.ok) {
  return {
    ok: false,
    phase: 'Milestone',
    escalate: true,
    message: 'Milestone review failed after N=3; escalate to human',
    implementResults: implementResults,
    value: milestoneGate,
  }
}

// --- PR ---------------------------------------------------------------------
phase('PR')
const pullRequestResult = await agent(
  'Open a PR after milestone PASS (finishing-a-development-branch). ' +
    'Use gh. Body: goal checklist + bd links + verify summary.\nGoal:\n' +
    boundGoal +
    '\nMilestone:\n' +
    String(milestoneGate.value || ''),
  {
    agentType: 'pr-opener',
    tier: 'small',
    label: 'pr-opener',
  },
)

return {
  ok: true,
  goal: boundGoal,
  researchUsed: goalLooksLarge,
  spec: approvedSpec,
  plan: approvedPlan,
  tasks: biteSizedTasks,
  implementResults: implementResults,
  milestone: milestoneGate.value,
  pullRequest: pullRequestResult,
}
