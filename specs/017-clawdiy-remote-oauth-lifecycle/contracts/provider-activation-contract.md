# Contract: Provider Activation And Canary

## Purpose

Define when `codex-oauth` / `gpt-5.4` is considered ready.

## Contract

- `codex-oauth` MUST be explicitly configured as a runtime provider, not only inferred from auth profile presence.
- Required scopes MUST include `api.responses.write`.
- Allowed model list MUST include `gpt-5.4` for this rollout stage.
- Promotion requires:
  - metadata gate pass
  - runtime auth store verified
  - provider activation verified
  - post-auth canary pass

## Failure Semantics

- Scope mismatch keeps provider quarantined.
- Provider inactive keeps provider quarantined even if auth store exists.
- Canary failure keeps provider quarantined and records evidence for repeat-auth or rollback.
