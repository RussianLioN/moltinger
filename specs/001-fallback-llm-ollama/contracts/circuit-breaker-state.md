# Contract: Circuit Breaker State File

**Feature**: 001-fallback-llm-ollama
**Version**: 1.0.0

## Overview

JSON schema for circuit breaker state file at `/tmp/moltis-llm-state.json`.

## Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["current_provider", "circuit_state", "failure_count", "last_check"],
  "properties": {
    "current_provider": {
      "type": "string",
      "enum": ["glm", "ollama"],
      "description": "Currently active LLM provider"
    },
    "circuit_state": {
      "type": "string",
      "enum": ["closed", "open", "half-open"],
      "description": "Circuit breaker state"
    },
    "failure_count": {
      "type": "integer",
      "minimum": 0,
      "maximum": 3,
      "description": "Consecutive failures for current provider"
    },
    "success_count": {
      "type": "integer",
      "minimum": 0,
      "description": "Consecutive successes (only in half-open state)"
    },
    "last_failure": {
      "type": ["string", "null"],
      "format": "date-time",
      "description": "Timestamp of last failure"
    },
    "last_success": {
      "type": ["string", "null"],
      "format": "date-time",
      "description": "Timestamp of last success"
    },
    "last_check": {
      "type": "string",
      "format": "date-time",
      "description": "Timestamp of last health check"
    },
    "last_switch": {
      "type": ["string", "null"],
      "format": "date-time",
      "description": "Timestamp of last provider switch"
    },
    "open_since": {
      "type": ["string", "null"],
      "format": "date-time",
      "description": "When circuit opened (null if closed)"
    }
  }
}
```

## Example States

### Normal Operation (GLM active)
```json
{
  "current_provider": "glm",
  "circuit_state": "closed",
  "failure_count": 0,
  "success_count": null,
  "last_failure": null,
  "last_success": "2026-03-01T12:00:00Z",
  "last_check": "2026-03-01T12:00:05Z",
  "last_switch": null,
  "open_since": null
}
```

### GLM Failed, Ollama Active
```json
{
  "current_provider": "ollama",
  "circuit_state": "open",
  "failure_count": 3,
  "success_count": null,
  "last_failure": "2026-03-01T11:55:00Z",
  "last_success": "2026-03-01T11:55:10Z",
  "last_check": "2026-03-01T12:00:00Z",
  "last_switch": "2026-03-01T11:55:00Z",
  "open_since": "2026-03-01T11:55:00Z"
}
```

### Recovery in Progress
```json
{
  "current_provider": "ollama",
  "circuit_state": "half-open",
  "failure_count": 0,
  "success_count": 1,
  "last_failure": "2026-03-01T11:55:00Z",
  "last_success": "2026-03-01T12:00:00Z",
  "last_check": "2026-03-01T12:00:05Z",
  "last_switch": "2026-03-01T11:55:00Z",
  "open_since": null
}
```

## File Operations

### Read State
```bash
read_state() {
    local state_file="/tmp/moltis-llm-state.json"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        # Return default state
        echo '{"current_provider":"glm","circuit_state":"closed","failure_count":0,"last_check":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    fi
}
```

### Write State (with locking)
```bash
write_state() {
    local state_file="/tmp/moltis-llm-state.json"
    local state="$1"

    # Use flock for atomic writes
    (
        flock -x 200
        echo "$state" > "$state_file"
    ) 200>"${state_file}.lock"
}
```

## State Transitions

| From | To | Condition |
|------|----|-----------|---|
| closed | open | failure_count >= 3 |
| open | half-open | 60s elapsed since open |
| half-open | closed | success_count >= 2 |
| half-open | open | Any failure |

## Metrics Export

State file changes should update Prometheus metrics:
```
moltis_circuit_state{provider="glm"} 0  # 0=closed
moltis_llm_failures_total{provider="glm"} 3
```
