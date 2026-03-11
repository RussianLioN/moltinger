# Contract: Production-Aware Remote UAT

## Purpose

Define the operator-facing contract for the authoritative production-aware remote UAT flow, its artifacts, and the optional secondary diagnostic decision point.

## Trigger Contract

- The authoritative remote UAT flow is manual and opt-in.
- The canonical production-aware verdict path is Telegram Web.
- Blocking PR and main CI remain hermetic-only; this remote check is not promoted to a blocking gate.
- Production transport mode remains polling before, during, and after the check.
- Periodic production schedulers remain disabled by default.

## Authoritative Verdict Contract

Each authoritative run MUST produce one structured result with:

- target environment
- trigger source
- authoritative path
- production transport mode at time of run
- final verdict
- execution stage
- deterministic failure classification for failed runs
- attribution evidence sufficient to confirm or reject current-run request/reply linkage
- review-safe diagnostic context

## Failure Classification Contract

The authoritative Telegram Web path MUST distinguish at least these classes:

- `missing_session_state`
- `ui_drift`
- `chat_open_failure`
- `stale_chat_noise`
- `send_failure`
- `bot_no_response`

Each failed run MUST include:

- `failure.code`
- `failure.stage`
- `failure.summary`
- `failure.actionability`
- `failure.fallback_relevant`

## Attribution Contract

A passing authoritative run requires evidence that:

- the probe send belongs to the current run
- the attributed reply occurs after the sent probe boundary
- unrelated prior chat noise is excluded from attribution

If that evidence cannot be established, the authoritative verdict MUST fail rather than pass ambiguously.

## Artifact Contract

The review artifact MUST remain suitable for operator review and RCA:

- machine-readable JSON
- safe for routine sharing inside the operations workflow
- includes enough context to compare failing and post-fix rerun outcomes
- excludes or redacts sensitive credentials, tokens, or private session material

## Secondary Diagnostic Contract

- Optional fallback diagnostics MAY be requested only after the authoritative Telegram Web verdict is known.
- Secondary diagnostics MUST NOT replace Telegram Web as the source of truth for the authoritative verdict.
- Secondary diagnostics MUST record whether prerequisites were available and whether the result changes the later decision on enabling fallback support in production.

## Rerun Contract

After a probe fix or root-cause narrowing step, operators MUST be able to rerun the same authoritative remote UAT flow and compare:

- previous failure classification
- new verdict
- before/after attribution evidence
- updated decision on whether fallback remains necessary
