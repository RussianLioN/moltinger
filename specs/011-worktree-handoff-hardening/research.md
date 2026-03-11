# Research: Worktree Handoff Hardening

## Decision 1: Reuse the existing worktree helper and command workflow

- **Decision**: Extend the existing `command-worktree` and `scripts/worktree-ready.sh` contract instead of introducing a new workflow layer.
- **Rationale**: The defect is about boundary enforcement and handoff semantics inside an existing workflow. Reusing the current helper and command surface keeps one operator-facing contract.
- **Alternatives considered**:
  - Build a separate handoff orchestrator: rejected because it would duplicate boundary logic and make contract drift more likely.
  - Fix only the prompt instructions: rejected because helper output, tests, and instructions must agree.
- **Library**: No new library. Existing repository shell tooling is sufficient.

## Decision 2: Keep short pending intent and rich downstream intent separate

- **Decision**: Preserve a concise pending summary for quick scanning, but formalize a separate richer Phase B seed payload or equivalent structured carrier for complex downstream requests.
- **Rationale**: The current single-line summary is useful as a headline but too lossy for rich requests such as Speckit startup. Separate carriers let the workflow stay readable without dropping critical downstream constraints.
- **Alternatives considered**:
  - Expand `pending_summary` until it holds everything: rejected because it blurs quick-scan and full-context roles.
  - Keep only the current one-line summary: rejected because it loses important boundaries, defaults, and exact feature descriptions.
- **Library**: No new library. This is a contract design choice.

## Decision 3: Treat create and attach as the same boundary class

- **Decision**: Apply the same hard stop-after-Phase-A contract to both create and attach flows.
- **Rationale**: The operator risk is the same once Phase A succeeds: the originating session can incorrectly continue downstream work if boundary semantics are inconsistent across flows.
- **Alternatives considered**:
  - Harden create only: rejected because attach would remain a loophole.
  - Permit attach to continue locally: rejected because it undermines a single operational rule.
- **Library**: No new library. Existing helper and tests already cover both flows.

## Decision 4: Keep manual handoff as the default safe path

- **Decision**: Preserve manual handoff as default and keep automatic Codex or terminal launch opt-in only.
- **Rationale**: Manual handoff is the lowest-risk boundary because it makes the session transition explicit and observable.
- **Alternatives considered**:
  - Launch Codex or terminal automatically by default: rejected because it weakens operator control and increases failure surface.
  - Remove automatic launch entirely: rejected because opt-in launch remains useful for operators who explicitly request it.
- **Library**: No new library. Current launch mechanisms remain optional integrations.

## Decision 5: Make regression coverage realistic and prompt-shaped

- **Decision**: Require regression scenarios based on long, structured downstream requests, especially Speckit startup flows.
- **Rationale**: The defect appears in realistic mixed requests, not only trivial create flows. Coverage must mirror actual operator usage to prevent silent drift.
- **Alternatives considered**:
  - Cover only short prompts: rejected because it would miss the lossy-handoff failure mode.
  - Rely on manual UAT only: rejected because the contract can drift without automated regression signals.
- **Library**: No new library. Existing shell unit tests and fixture patterns are sufficient.
