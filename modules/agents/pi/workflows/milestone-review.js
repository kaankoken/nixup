/**
 * Multi-angle milestone code review with verification.
 * Runtime globals: agent, parallel, phase, gate, verify, log, args, cwd
 *
 * args: { goal?: string, scope?: string, diffHint?: string }
 */
export const meta = {
  name: 'milestone-review',
  description:
    'Parallel multi-angle code review (correctness, tests, ponytail, stack) plus verify; returns { ok, feedback, blocking }',
  phases: [{ title: 'Review' }, { title: 'Verify' }, { title: 'Synthesize' }],
}

const reviewArgs = typeof args === 'object' && args !== null ? args : {}
const goalText =
  typeof reviewArgs.goal === 'string'
    ? reviewArgs.goal
    : typeof reviewArgs.idea === 'string'
      ? reviewArgs.idea
      : 'milestone review'
const scopeText = reviewArgs.scope
  ? String(reviewArgs.scope)
  : reviewArgs.diffHint
    ? String(reviewArgs.diffHint)
    : 'current worktree / branch diff vs main'
const workingDirectory = typeof cwd === 'string' ? cwd : '.'

phase('Review')
log('milestone-review: ' + goalText)

const reviewContext =
  'Goal: ' +
  goalText +
  '\nScope: ' +
  scopeText +
  '\nCwd: ' +
  workingDirectory +
  '\nReturn JSON only: { "ok": boolean, "feedback": string, "blocking": string[] }\n' +
  'Use tokensave/sg/CLI; never codebase-memory. Read-mostly.\n\n'

const reviewAngles = await parallel([
  () =>
    agent(
      reviewContext +
        'Angle: CORRECTNESS — logic bugs, edge cases, regressions, error handling.',
      {
        agentType: 'code-reviewer',
        tier: 'big',
        label: 'review-correctness',
      },
    ),
  () =>
    agent(
      reviewContext +
        'Angle: TESTS — coverage of new behavior, missing cases, flaky patterns, verify commands.',
      {
        agentType: 'code-reviewer',
        tier: 'big',
        label: 'review-tests',
      },
    ),
  () =>
    agent(
      reviewContext +
        'Angle: PONYTAIL — overbuild, dead code, speculative APIs, YAGNI violations.',
      {
        agentType: 'code-reviewer',
        tier: 'big',
        label: 'review-ponytail',
      },
    ),
  () =>
    agent(
      reviewContext +
        'Angle: STACK — Rust/iOS/Android conventions and project AGENTS.md compliance.',
      {
        agentType: 'code-reviewer',
        tier: 'big',
        label: 'review-stack',
      },
    ),
])

phase('Verify')
// Cross-check the combined review text when verify() is available at runtime.
let verificationResult = null
const combinedReviewText = reviewAngles
  .map(function (angle, angleIndex) {
    return '### Angle ' + (angleIndex + 1) + '\n' + String(angle || '')
  })
  .join('\n\n')

try {
  verificationResult = await verify(combinedReviewText, {
    reviewers: 2,
    threshold: 0.5,
    lens: 'Are blocking findings real and still present in the scoped diff?',
  })
} catch (verifyError) {
  // verify may be unavailable or throw; fall through to synthesis.
  log('milestone-review: verify skipped or failed; synthesizing angles only')
  verificationResult = { real: true, note: 'verify unavailable', error: String(verifyError) }
}

phase('Synthesize')
const synthesizePrompt =
  'You are milestone-organizer. Merge these parallel review JSON/text results into ONE final JSON object:\n' +
  '{ "ok": boolean, "feedback": string, "blocking": string[] }\n' +
  'ok=true only if no real blocking defects remain. Deduplicate blocking items.\n' +
  'Verification votes (if any): ' +
  String(JSON.stringify(verificationResult)) +
  '\n\nReviews:\n' +
  combinedReviewText

const reviewResultSchema = {
  type: 'object',
  properties: {
    ok: { type: 'boolean' },
    feedback: { type: 'string' },
    blocking: { type: 'array', items: { type: 'string' } },
  },
  required: ['ok', 'feedback', 'blocking'],
}

const finalReview = await agent(synthesizePrompt, {
  agentType: 'milestone-organizer',
  tier: 'big',
  label: 'milestone-synthesize',
  schema: reviewResultSchema,
})

const finalOk =
  typeof finalReview === 'object' && finalReview !== null ? !!finalReview.ok : false
const finalFeedback =
  typeof finalReview === 'object' && finalReview !== null
    ? String(finalReview.feedback || '')
    : String(finalReview || '')
const finalBlocking =
  typeof finalReview === 'object' &&
  finalReview !== null &&
  Array.isArray(finalReview.blocking)
    ? finalReview.blocking
    : []

return {
  ok: finalOk,
  value: finalReview,
  angles: reviewAngles,
  verification: verificationResult,
  feedback: finalFeedback,
  blocking: finalBlocking,
}
