# Consilium Report

## Question
What is the minimal safe way to close `T048` so Moltis production runtime provenance cannot silently drift away from tracked intent, while keeping the eventual move to immutable release roots realistic and low-risk?

## Execution Mode
Mode B (parallel expert review plus local evidence synthesis)

## Evidence
- [scripts/run-tracked-moltis-deploy.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/run-tracked-moltis-deploy.sh) already records deploy markers and aligns the server checkout, but without a shared live provenance attestation the workflow can still prove transport more strongly than container origin.
- [scripts/deploy.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/deploy.sh) already verifies `/server`, runtime-config mount source, and writable runtime config during deploy, which means the repo already knows the right invariants.
- [.github/workflows/gitops-drift-detection.yml](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/.github/workflows/gitops-drift-detection.yml) historically focused on file-hash drift and therefore could miss a live container whose mount sources no longer matched the intended runtime provenance.
- [docs/rca/2026-03-21-moltis-openai-oauth-runtime-drift.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-03-21-moltis-openai-oauth-runtime-drift.md) proved that OAuth was not lost; the live container had drifted off the correct `/server` and runtime-config mounts.
- [docs/reports/consilium/2026-03-22-moltis-config-durability-hardening.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/reports/consilium/2026-03-22-moltis-config-durability-hardening.md) already recommended immutable release roots plus runtime attestation as the long-term answer, but did not yet land the shared attestation contract.
- [docs/knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md) already treats `/opt/moltinger-active` as the canonical automation root, which makes it the right provenance anchor for the attestation contract.

## Expert Opinions
### Architect / GitOps
- Opinion: Close `T048` in two layers, not one jump.
- Key points: land a shared runtime attestation contract now; describe immutable release roots as the next explicit rollout phase instead of mixing a topology migration into the same production hardening slice.

### SRE
- Opinion: Periodic drift checks must attest live container provenance, not only hash synced files.
- Key points: compare actual `/server` mount source, runtime-config mount source and writability, recorded deploy metadata, live git SHA/ref, live binary version, and health.

### DevOps / CI
- Opinion: The attestation contract must live in versioned scripts and be consumed by workflows through shared entrypoints.
- Key points: `run-tracked-moltis-deploy.sh` should block success on attestation; `gitops-drift-detection.yml` should use a dedicated SSH wrapper rather than inline remote shell composition; scheduled drift must compare against deployed markers, not branch HEAD.

### Security / Runtime State
- Opinion: Provenance hardening must not re-centralize OAuth state into git.
- Key points: keep OAuth and provider keys outside git in runtime-config, but fail closed if the live mount source or writability diverges from the contract.

### QA / UAT
- Opinion: Semantic chat proof and provenance proof are different checks and both are needed.
- Key points: keep canonical smoke/UAT for provider/model behavior, but make provenance attestation the lower-level guard that catches “healthy but wrong runtime” failures before semantic probes mislead operators.

## Root Cause Analysis
- Primary root cause: production runtime provenance remained partially implicit, so a live container could detach from tracked `/server` and runtime-config intent while still presenting a superficially healthy service.
- Contributing factors:
  - file-hash drift checks were weaker than container-mount provenance checks;
  - deploy recorded metadata but did not yet treat post-deploy attestation as a blocking contract;
  - the current mutable checkout root makes silent drift possible unless the active root and live container are explicitly tied together.
- Confidence: High.

## Solution Options
1. Keep current file-hash drift detection only. Low effort, high repeat risk.
2. Jump straight to immutable release roots in this branch. Best long-term topology, but too risky for a mixed design-and-hardening slice on shared production.
3. Add shared runtime attestation now and leave file hashes as secondary diagnostics. Best minimal-safe step.
4. Add only more UAT smoke coverage. Useful, but still misses wrong-mount provenance failures.
5. Add attestation plus a phase-2 release-root plan with explicit future host layout. Best balance of safety and durability.

## Recommended Plan
1. Land a shared `moltis-runtime-attestation.sh` contract that proves live `/server`, runtime-config source/writability, runtime-home mount presence, recorded deploy metadata, live git SHA/ref, live version, and health.
2. Make `run-tracked-moltis-deploy.sh` block final success until that attestation passes.
3. Make `gitops-drift-detection.yml` call the same attestation contract through a shared SSH wrapper and treat file-hash drift as secondary evidence, not primary provenance proof.
4. Keep scheduled drift marker-driven by reading expected SHA/ref/version from deployed markers on the active root, not from `${{ github.sha }}`.
5. Document the future immutable release-root layout as a dedicated phase-2 migration, with `/opt/moltinger-active` continuing to be the authoritative live-root pointer.

## Rollback Plan
- Revert the attestation/wrapper/workflow commit if a false-positive blocks valid deploys.
- Keep deploy markers, runtime config, and `~/.moltis` untouched by the rollback; this slice changes verification and documentation, not durable state layout.
- Fall back to the previous tracked deploy plus canonical smoke path while analyzing the attestation false-positive.

## Verification Checklist
- [x] Shared runtime attestation script exists in `scripts/`
- [x] Tracked deploy blocks success on attestation
- [x] Periodic drift detection uses the shared SSH wrapper for attestation
- [x] Immutable release roots are documented as the next explicit phase, not silently implied
