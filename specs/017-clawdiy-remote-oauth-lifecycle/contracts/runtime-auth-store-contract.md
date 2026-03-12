# Contract: Runtime Auth Store

## Purpose

Define the authoritative runtime boundary for Clawdiy `openai-codex` auth.

## Contract

- Clawdiy MUST have one documented persistent auth-store root for provider auth artifacts.
- The auth store MUST survive container restart.
- The auth store MUST be writable by the runtime user and MUST NOT rely on ad hoc manual edits after each deploy.
- The repo MAY manage metadata about the auth store, but MUST NOT commit the live OAuth artifact to git.
- Validation MUST distinguish:
  - metadata present, runtime auth absent
  - runtime auth present but unreadable
  - runtime auth present and verified

## Failure Semantics

- Missing or unreadable runtime auth store quarantines `codex-oauth`.
- Missing runtime auth store MUST NOT mark baseline Clawdiy health as failed by itself.
