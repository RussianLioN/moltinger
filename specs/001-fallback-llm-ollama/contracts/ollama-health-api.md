# Contract: Ollama Health API

**Feature**: 001-fallback-llm-ollama
**Version**: 1.0.0

## Overview

Health check endpoint for Ollama container used by circuit breaker.

## Endpoint

### GET /api/tags

List available models - used as health check endpoint.

**Request**:
```http
GET http://localhost:11434/api/tags
```

**Success Response** (200 OK):
```json
{
  "models": [
    {
      "name": "gemini-3-flash-preview:cloud",
      "modified_at": "2026-03-01T12:00:00Z",
      "size": 0,
      "digest": "abc123"
    }
  ]
}
```

**Error Response** (503 Service Unavailable):
```json
{
  "error": "service unavailable"
}
```

## Health Check Implementation

```bash
#!/bin/bash
# scripts/ollama-health.sh

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
TIMEOUT="${OLLAMA_HEALTH_TIMEOUT:-5}"

check_ollama_health() {
    local response
    response=$(curl -sf --max-time "$TIMEOUT" "${OLLAMA_URL}/api/tags" 2>/dev/null)

    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "healthy"
        return 0
    else
        echo "unhealthy"
        return 1
    fi
}

# For sourcing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_ollama_health
fi
```

## Usage in Docker Compose

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s  # Cold start tolerance
```

## Metrics

| Metric | Type | Description |
|--------|------|-------------|
| ollama_health_check_total | counter | Total health checks |
| ollama_health_check_failures | counter | Failed health checks |
| ollama_health_check_duration_seconds | histogram | Health check latency |

## Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Healthy | Continue |
| 1 | Unhealthy | Trigger circuit breaker |
| 2 | Timeout | Retry with backoff |
| 3 | Connection refused | Ollama not running |
