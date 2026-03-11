# Feature Specification: Production-Aware Remote UAT Hardening

**Feature Branch**: `011-remote-uat-hardening`  
**Created**: 2026-03-09  
**Status**: Draft  
**Input**: User description: "Create a feature for production-aware remote UAT hardening of Moltinger Telegram live checks."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Decision-Grade Post-Deploy Verdict (Priority: P1)

An operator runs one manual post-deploy verification flow and receives one authoritative verdict for the real Telegram user path, with Telegram Web as the primary verdict route.

**Why this priority**: This is the core user value. Operators need one trusted answer to whether the deployed production service works now through the real Telegram user path without changing production transport mode.

**Independent Test**: After a deploy, an operator runs the production-aware check against production and receives one comparable artifact that either proves success with attributable request/reply evidence or fails with a deterministic named failure class and next-step guidance.

**Acceptance Scenarios**:

1. **Given** production is deployed and the Telegram Web path is runnable, **When** the operator runs the authoritative remote UAT check, **Then** the system returns one passing artifact with attributable sent-message and reply evidence for that run.
2. **Given** production is deployed and the Telegram Web path fails during execution, **When** the operator runs the authoritative remote UAT check, **Then** the system returns one failing artifact with a deterministic failure class instead of an ambiguous timeout-only outcome.
3. **Given** production remains in polling mode, **When** the operator runs the remote UAT check, **Then** the check validates the deployed service without requiring or implying webhook migration.

---

### User Story 2 - Deterministic Diagnostics and Review-Safe Evidence (Priority: P1)

An operator inspects the remote UAT output and can immediately tell whether the failure came from send failure, Telegram Web UI drift, stale chat noise, missing login or session state, chat-open failure, or bot no-response, without exposing sensitive operational data in routine artifacts.

**Why this priority**: A red remote UAT signal is only operationally useful if it narrows the problem quickly enough to drive remediation or RCA without guesswork.

**Independent Test**: Simulate or reproduce each major failure class and confirm the resulting artifact names the failure category, the stage reached, the diagnostic context needed for review, and a recommended next action for the operator.

**Acceptance Scenarios**:

1. **Given** the operator reviews a failed run, **When** the artifact is opened, **Then** it identifies the failure class, the execution stage, the relevant diagnostic context, and the recommended next action for that class.
2. **Given** the chat contains unrelated recent activity, **When** the operator runs the remote check, **Then** the result distinguishes stale or noisy chat conditions from an actual bot reply for the current run.
3. **Given** Telegram Web cannot be used because login state is missing or invalid, **When** the operator runs the remote check, **Then** the result reports missing login or session state explicitly instead of masking it as a generic failure.

---

### User Story 3 - Manual Operator Workflow and Proof of Value (Priority: P2)

An operator follows one documented post-deploy workflow from deploy completion to verdict review to rerun, without undocumented steps, background schedulers, or CI ambiguity.

**Why this priority**: The feature is only valuable if the operator can use it consistently as a live operational signal rather than as a loose collection of scripts and docs.

**Independent Test**: Review the workflow entrypoints, acceptance evidence, and rerun procedure and confirm the feature remains manual/on-demand, non-blocking for PR/main CI, and comparable across before/after runs.

**Acceptance Scenarios**:

1. **Given** a deploy has completed and production health is green, **When** the operator follows the documented flow, **Then** the same authoritative trigger, artifact format, and rerun semantics are used end to end.
2. **Given** a PR or main-branch validation run, **When** the CI pipeline executes, **Then** the production-aware live check is not treated as a blocking hermetic gate.
3. **Given** an operator compares a before artifact and an after artifact, **When** they review the rerun evidence, **Then** they can tell whether the change fixed the issue, narrowed the root cause, or left the same failure class in place.

---

### User Story 4 - Secondary MTProto Cross-Check (Priority: P2)

An operator can use an optional secondary diagnostic lane when the Telegram Web path is unavailable, but the feature does not require that fallback for MVP and does not weaken Telegram Web as the authoritative path.

**Why this priority**: Telegram Web must remain the source of truth, but operators still need a disciplined way to decide later whether a fallback is worth enabling on production.

**Independent Test**: When the primary Telegram Web path is unavailable, the operator can trigger an optional diagnostic path or fallback assessment that preserves the primary verdict and records whether further fallback enablement is justified.

**Acceptance Scenarios**:

1. **Given** the Telegram Web path is unavailable for environmental reasons, **When** the operator requests additional diagnostics, **Then** the system provides an optional secondary diagnostic result without replacing Telegram Web as the authoritative verdict.
2. **Given** the Telegram Web path is repaired or the root cause is narrowed sufficiently, **When** the operator reviews the post-fix evidence, **Then** the team can make an explicit decision on whether production fallback support is still needed.

---

### Edge Cases

- What happens when Telegram Web is reachable but the expected chat cannot be opened or verified as the active chat?
- What happens when the message composer is present but the sent probe cannot be confirmed in the chat timeline?
- What happens when the chat contains unrelated inbound or outbound traffic close to the probe window?
- What happens when Telegram Web UI changes enough that selectors or visible state checks no longer match the expected interface?
- What happens when login state exists as a file but no longer represents a usable authenticated session?
- What happens when the bot receives the message but produces no attributable reply before timeout?
- What happens when production remains healthy at the HTTP level while the Telegram user path is red?
- What happens when an optional fallback diagnostic path is unavailable because production does not have the required fallback prerequisites configured?
- What happens when two operators try to run the same shared production-aware check at the same time?
- What happens when debug artifacts would expose Telegram Web state details, raw message content, or `TELEGRAM_TEST_*` material that should not appear in routine review outputs?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide one manual, on-demand post-deploy remote UAT flow that answers whether the deployed production service works now through the real Telegram user path.
- **FR-002**: System MUST use Telegram Web as the primary authoritative verdict path for this feature.
- **FR-003**: System MUST preserve production Telegram polling mode and MUST NOT require webhook migration as part of this feature.
- **FR-004**: System MUST keep the remote UAT check manual and opt-in rather than a blocking PR or main CI gate.
- **FR-005**: System MUST NOT re-enable periodic production auto-monitors or continuous production message spam by default.
- **FR-006**: System MUST produce one structured JSON result suitable for operator review and RCA for every completed run, including failed runs.
- **FR-007**: System MUST provide provable request/reply attribution for passing runs so operators can distinguish the current run from stale chat activity.
- **FR-008**: System MUST classify failures into deterministic diagnostic categories that distinguish, at minimum, send failure, Telegram Web UI drift, stale chat noise, missing login or session state, chat-open failure, and bot no-response.
- **FR-009**: System MUST report the stage reached before failure and the diagnostic context relevant to that stage.
- **FR-010**: System MUST include operator-facing next-step guidance in the result so the operator can distinguish rerun, login refresh, application investigation, or secondary cross-check actions.
- **FR-011**: System MUST support reproduction of the current production-aware Telegram Web failure and preserve enough evidence to confirm whether the probe was fixed or the root cause was narrowed.
- **FR-012**: System MUST support a post-fix rerun of the authoritative remote UAT path using the same operational model so the team can compare before/after evidence.
- **FR-013**: System MUST serialize or otherwise guard shared production-aware runs so one operator run does not corrupt or invalidate another operator's verdict.
- **FR-014**: System MUST keep fallback or secondary diagnostic paths optional and MUST NOT make them an MVP prerequisite for a usable authoritative Telegram Web verdict.
- **FR-015**: System MUST allow operators to decide, only after Telegram Web remediation or root-cause narrowing, whether production fallback support is still necessary.
- **FR-016**: System MUST keep routine artifacts and diagnostics safe for review by excluding or redacting sensitive operational data that should not appear in normal outputs.
- **FR-017**: System MUST distinguish between operator-safe artifacts and restricted debug-only diagnostics when deeper investigation is needed.
- **FR-018**: System MUST align runbook guidance, execution triggers, and artifact interpretation so operators have one documented manual workflow for post-deploy verification.

### Key Entities *(include if feature involves data)*

- **RemoteUATRun**: One manual production-aware verification attempt with trigger context, timestamps, final verdict, and execution stage.
- **DiagnosticArtifact**: Structured JSON output for a run containing verdict, failure classification, attribution evidence, and review-safe context.
- **AttributionEvidence**: Run-specific evidence used to prove the sent probe and the observed reply belong to the same execution window rather than stale chat noise.
- **FailureClassification**: Normalized failure taxonomy that identifies the specific remote UAT failure mode and the stage where it occurred.
- **FallbackAssessment**: Optional secondary diagnostic outcome used only to support later decisions about whether production fallback capability remains necessary.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can run one manual post-deploy remote UAT check and receive a verdict artifact without needing to alter production transport mode.
- **SC-002**: 100% of failed authoritative Telegram Web runs produce a named deterministic failure class instead of an ambiguous undifferentiated failure result.
- **SC-003**: 100% of passing authoritative Telegram Web runs include enough attribution evidence for an operator to verify that the observed reply belongs to the current run.
- **SC-004**: Documentation, workflow entrypoints, and artifact fields remain aligned closely enough that an operator can complete the post-deploy verification flow without undocumented steps.
- **SC-005**: PR and main CI remain hermetic-only for blocking gates, and the remote production-aware live check remains manual/opt-in throughout the MVP scope.
- **SC-006**: Production remains on polling mode before and after adopting this feature.
- **SC-007**: The team can rerun the authoritative remote UAT after a probe fix or root-cause narrowing step and compare the resulting evidence to the original failing run.
