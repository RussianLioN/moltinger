# Research: Moltis Live Codex Update Telegram Runtime Gap

## Decision 1: Remote user-facing `codex-update` must stay advisory-only

**Decision**: For Telegram and other sandboxed user-facing Moltis surfaces, `codex-update` is treated as an advisory/notification capability, not as a direct server-side executor of local Codex update workflows.

**Rationale**:
- `034` already recorded this as the product correction.
- Current live/runtime evidence showed that Telegram sessions can advertise the skill while lacking the filesystem visibility needed for safe host-path execution assumptions.
- The user-facing surface must not imply that the server can update the user's local Codex installation.

**Alternatives considered**:
- Keep the existing "always run canonical runtime immediately" skill contract everywhere.
  Rejected because it conflicts with the remote Telegram safety boundary and reintroduces execution drift.

## Decision 2: Remote UAT must classify contract drift separately from transport leakage

**Decision**: Authoritative Telegram UAT should continue to distinguish at least these failure families:
- `Activity log` / internal activity leakage
- host-path leakage
- `codex-update` false negative
- remote `codex-update` execution-contract violation

**Rationale**:
- False negatives and `Activity log` leakage are related but not identical defects.
- A reply can be semantically wrong without leaking `Activity log`.
- A reply can stay textually clean while the Telegram transport still emits `Activity log` separately.

**Alternatives considered**:
- Collapse all user-facing failures into one generic semantic error.
  Rejected because it obscures the remaining repo-owned vs upstream-owned boundary.

## Decision 3: Operator/local execution remains valid, but only as a surface-specific path

**Decision**: The existing canonical runtime (`make codex-update` / `moltis-codex-update-run.sh`) remains valid for trusted operator/local surfaces that genuinely have `/server` visibility and writable runtime state.

**Rationale**:
- `023` still owns the repo-side runtime implementation.
- Removing operator execution guidance entirely would break legitimate local/admin workflows.
- The defect is not the existence of the runtime; it is the incorrect assumption that every remote Telegram surface can safely use it.

**Alternatives considered**:
- Remove all references to the canonical runtime from skill and docs.
  Rejected because it would erase valid operator guidance instead of splitting surfaces correctly.

## Live Re-check Note (2026-03-28)

Authoritative production re-check was run via GitHub Actions:

- workflow: `Telegram Remote UAT On-Demand`
- run: `23692971306`
- message: `Что с новыми версиями codex?`
- outcome: `failed`
- stage: `wait_reply`
- failure: `bot_no_response`

Interpretation:

- this run did **not** reconfirm the earlier `codex-update` semantic false-negative or `Activity log` leakage;
- shared remote production failed earlier on reply delivery/settling, so semantic codex-specific checks were not reached;
- repo-owned carrier fixes in this branch are still valid, but the current live production gap remains upstream/runtime or operational until a later authoritative run reaches a real reply.
