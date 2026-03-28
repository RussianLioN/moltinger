# Data Model: Moltis Live Codex Update Telegram Runtime Gap

## Entities

### RemoteCodexUpdateSurface

- `surface_name`: user-facing surface identifier such as Telegram
- `sandbox_visible_runtime`: whether host/runtime paths are actually readable from that surface
- `contract_mode`: expected mode for the surface (`advisory-only`, `notification-only`, or operator execution)
- `allowed_reply_capabilities`: safe reply classes for that surface

### OperatorCodexUpdateSurface

- `surface_name`: trusted operator/local surface identifier
- `canonical_runtime_access`: whether `/server` and writable runtime state are available
- `allowed_execution_path`: approved canonical runtime entrypoint for the surface

### TelegramSemanticVerdict

- `failure_code`: semantic classification such as `semantic_activity_leak`, `semantic_host_path_leak`, `semantic_codex_update_false_negative`, or remote contract violation
- `observed_reply`: sanitized reply text or relevant semantic artifact
- `actionability`: operator-facing next-step classification
- `recommended_action`: follow-up guidance for rerun or escalation

### ResidualRuntimeGap

- `symptom`: remaining live symptom after repo-owned carrier changes
- `ownership`: `repo-owned` or `upstream-owned`
- `closure_condition`: what must be true before the symptom can be considered resolved
- `evidence_source`: RCA, UAT artifact, or live runtime observation supporting the classification
