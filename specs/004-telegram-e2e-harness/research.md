# Research: On-Demand Telegram E2E Harness

## Decision 1: Synthetic transport over existing Moltis HTTP API

- **Decision**: Use `/api/auth/login` + `/api/v1/chat` in synthetic mode.
- **Rationale**: Existing tests already validate these endpoints and auth cookie pattern.
- **Alternatives considered**:
  - Direct Telegram webhook injection: unstable and currently blocked by 303/login redirect route behavior.
  - Direct Bot API outbound test only: does not satisfy user->Moltis message path requirement.

## Decision 2: Manual Verdict artifact-first

- **Decision**: Do not enforce semantic assertions in MVP; output full execution artifact with observed response.
- **Rationale**: Operator wants to inspect and tune skills interactively from chat sessions.
- **Alternatives considered**:
  - strict contains/regex pass-fail in MVP
  - CI-hard blocking checks

## Decision 3: Deferred real_user mode

- **Decision**: Expose `real_user` mode contract with explicit deferred diagnostics.
- **Rationale**: Preserves future extensibility without introducing MTProto complexity into MVP.
- **Alternatives considered**:
  - Immediate MTProto implementation (higher security/ops overhead)
  - Omitting real_user mode entirely (causes future interface churn)

## Decision 4: Security and observability

- **Decision**: Redact sensitive values and include structured context metadata (HTTP codes, attempts, timeout) in artifact.
- **Rationale**: Enables safe debugging and reproducibility.
- **Alternatives considered**:
  - raw verbose logging (rejected due to credential leakage risk)
