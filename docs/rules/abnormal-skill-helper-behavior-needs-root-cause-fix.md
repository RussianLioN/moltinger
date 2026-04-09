# Abnormal Skill Or Helper Behavior Needs Root-Cause Fix

If a repo-owned skill, helper, workflow, instruction surface, or repo-managed command behaves unexpectedly, treat it as a first-class defect.

This rule is for **repo-owned contract failures** such as:

- source instructions and generated instruction drift
- helper or workflow scripts with ambiguous or contradictory behavior
- skill or command guidance that pushes the session into workaround-style execution
- operator-facing response formats that violate an explicit project rule

It is **not** a rule that every external or transient failure must invent a local root-fix. Remote outages, auth expiry, connector instability, rate limits, or other third-party incidents still require evidence and classification, but they only require a local source-contract fix when a repo-owned layer caused, amplified, or failed to contain the problem.

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

## Ownership boundary

`Fix the source contract in the owning layer` means:

- fix the repo-owned layer that created the broken expectation, or
- if the failure is external/transient, record the RCA and owner classification without inventing a fake local contract fix.

Examples of repo-owned owning layers:

- source instructions
- generated instructions
- rule files
- helper/workflow scripts
- skill or command source
- regression tests

## Rationale

Workflows that require ad hoc operator improvisation are already broken. If the broken path is left in place, the same failure returns in the next session with a different symptom.
