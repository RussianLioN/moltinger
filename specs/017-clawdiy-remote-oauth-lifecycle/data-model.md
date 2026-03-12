# Data Model: Clawdiy Remote OAuth Runtime Lifecycle

## Entities

### Auth Metadata Gate

Purpose:
- Repo-controlled metadata rendered from GitHub Secrets and deploy workflow.

Fields:
- `provider`
- `auth_type`
- `granted_scopes`
- `allowed_models`
- `rollout_gate`
- `enabled`

Notes:
- This entity proves declared intent and policy, not real upstream readiness.

### Runtime Auth Store

Purpose:
- Persistent Clawdiy-local storage read by OpenClaw for `codex-oauth` authentication.

Fields:
- `store_root`
- `auth_profiles_path`
- `owner_uid_gid`
- `persistence_class`
- `last_bootstrap_method`
- `last_verified_at`

Notes:
- Must survive container restart and must be distinct from git-tracked config.

### Provider Activation State

Purpose:
- Explicit runtime config state indicating whether `codex-oauth` is actually selectable and bound to intended model routing.

Fields:
- `provider_name`
- `activation_source`
- `configured_models`
- `default_model`
- `status`

### Repeat-Auth Evidence

Purpose:
- Durable operator/audit record of bootstrap or rotation.

Fields:
- `timestamp`
- `operator_method`
- `runtime_store_target`
- `metadata_gate_snapshot`
- `result`
- `notes`

### Post-Auth Canary Result

Purpose:
- Runtime proof that `gpt-5.4` executed successfully after auth and activation.

Fields:
- `timestamp`
- `provider`
- `model`
- `runtime_store_version`
- `scope_check`
- `execution_result`
- `evidence_path`

## State Transitions

1. `metadata_declared`
2. `runtime_auth_absent`
3. `runtime_auth_bootstrapped`
4. `provider_activated`
5. `canary_passed`
6. `promoted`

Blocked/quarantine states:

- `metadata_only`
- `runtime_store_invalid`
- `provider_inactive`
- `scope_mismatch`
- `canary_failed`
