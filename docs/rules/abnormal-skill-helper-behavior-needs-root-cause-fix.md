# Abnormal Skill Or Helper Behavior Needs Root-Cause Fix

If a skill, helper, workflow, or repo-managed command behaves unexpectedly, treat it as a first-class defect.

Examples:

- the helper hangs or takes unexpectedly long without a clear contract
- output contradicts the declared boundary or next-step contract
- a tool reports partial success but leaves ambiguous state
- the assistant starts improvising manual git/PR/publish actions because the intended workflow felt unreliable
- user-facing reports drift away from the requested format even though a project rule exists

## Required response

1. Stop normal task continuation at the abnormal boundary.
2. Run the lessons pre-check and then RCA.
3. Record the defect as an issue or explicit follow-up if it is not already tracked.
4. Fix the source contract in the owning layer:
   - source instructions
   - rule file
   - helper/workflow script
   - skill/command source
   - regression test
5. Resume the broader task only after the defect is either:
   - fixed, or
   - explicitly reclassified as a separate follow-up by the user.

## No-workaround rule

- Do not use a manual workaround as a substitute for fixing the broken skill/helper path.
- Do not normalize "we finished the task manually" as success if the official workflow contract was the thing that failed.
- A reversible hygiene action is allowed only when:
  - the user explicitly asked for it, and
  - it is clearly labeled as temporary mitigation, not resolution.

If temporary mitigation is used, it must still produce:

1. RCA
2. follow-up issue
3. dedicated fix lane when shared contracts are involved

## Rationale

Workflows that require ad hoc operator improvisation are already broken. If the broken path is left in place, the same failure returns in the next session with a different symptom.
