# Consilium Report

## Question

After `PR1` has already landed in `main` and production has been restored, should `PR2` be opened directly from `031-moltis-reliability-diagnostics`, or should it be rebuilt as a narrower carrier?

## Execution Mode

Mode A: parallel expert review with architect, SRE, DevOps/CI, GitOps, QA, security, and Moltis domain perspectives.

## Evidence

- `PR1` runtime carrier has already landed in `main` and production was redeployed successfully from `main`.
- Authoritative live validation succeeded:
  - `memory_search` completed successfully and returned `/server`
  - live runtime config uses `provider = "ollama"` and `model = "nomic-embed-text"`
  - `OLLAMA_API_KEY` is present in the running `moltis` container
  - `gemini-3-flash-preview:cloud` is visible through the live Ollama health path
- `031-moltis-reliability-diagnostics` still differs from `origin/main` by a mixed-scope change set spanning 95 files, including runtime scripts, workflows, tests, and documentation.
- The Speckit contract already scopes `PR2` to deferred RCA/consilium/rules/lessons/spec work after successful live verification.

## Expert Opinions

### Architect
- Do not open `PR2` directly from this branch.
- Use a fresh docs-only carrier from verified `main` so the change set matches the intent of post-incident closure.

### SRE
- The production incident is already closed at runtime.
- `PR2` should now preserve evidence and lessons, not re-expand rollout blast radius.

### DevOps / CI
- A docs-only carrier keeps CI/review noise low and avoids retesting unrelated runtime/workflow deltas under a misleading PR label.

### GitOps / Delivery
- Change scope should mirror delivery intent.
- If the intent is “deferred documentation/process layer”, the carrier must be narrow and `main`-based.

### QA
- A mixed branch makes it hard to prove that `PR2` is only retrospective/process work.
- A docs-only carrier is the easiest path to clear review and validation.

### Security / Governance
- Opening `PR2` straight from the current branch risks smuggling runtime-affecting files behind a docs/process label.
- A narrow carrier materially reduces blast radius and audit ambiguity.

### Moltis Domain
- `PR1 -> main -> deploy -> live verify` already closed the live embedding/Ollama incident.
- `PR2` should capture learnings, not continue runtime remediation under the same carrier.

## Root Cause Analysis

- Primary root cause: after `PR1` landed, the remaining branch delta stayed too broad to qualify as the promised deferred documentation/process layer.
- Contributing factors:
  - the feature branch accumulated runtime hardening, browser/search work, workflow updates, and tests alongside incident documentation
  - the production policy requires `main` as the canonical landing root
  - the post-incident contract now demands a clean separation between runtime remediation and retrospective artifacts
- Confidence: High

## Solution Options

1. Open `PR2` directly from `031-moltis-reliability-diagnostics`
Pros: fastest mechanically.
Cons: misleading scope, higher review risk, larger blast radius.

2. Create a fresh docs-only carrier from verified `main`
Pros: clean review scope, matches Speckit contract, safer rollback.
Cons: requires explicit allowlist selection.

3. Cherry-pick only docs commits into a fresh `main`-based branch
Pros: preserves some history while staying narrow.
Cons: commit boundaries may still need cleanup.

4. Recreate only the final docs/process artifacts on a fresh `main`-based branch
Pros: smallest clean diff.
Cons: loses some intermediate artifact history.

5. Leave the branch as evidence only and defer `PR2`
Pros: zero immediate merge risk.
Cons: leaves post-incident documentation incomplete.

## Recommended Plan

1. Treat `T056` as complete because `PR1`, canonical deploy, and live verification have already succeeded.
2. Build a fresh docs-only `PR2` carrier from verified `main`.
3. Include only RCA, consilium, rules, runbook, lessons, and Speckit reconciliation artifacts in that carrier.
4. Keep runtime/workflow/test deltas out of `PR2`; land them later as separate reviewed work if still needed.

## Rollback Plan

- If a runtime-affecting file appears in the `PR2` carrier, discard that carrier and rebuild it from `main` with a stricter allowlist.

## Verification Checklist

- [ ] `PR2` base is verified `main`
- [ ] `PR2` diff contains only docs/process artifacts
- [ ] no `scripts/`, `tests/`, `.github/`, `docker-compose*`, `config/`, or runtime code changes enter the carrier
- [ ] Speckit artifacts match the actual landing strategy
