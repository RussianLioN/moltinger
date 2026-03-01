# Contract: Moltis Failover Configuration

**Feature**: 001-fallback-llm-ollama
**Version**: 1.0.0

## Overview

TOML configuration schema for Moltis failover settings in `config/moltis.toml`.

## Configuration Schema

### Provider Configuration

```toml
# Primary provider (GLM via Z.ai)
[providers.openai]
enabled = true                    # MUST be true
api_key = "${GLM_API_KEY}"        # Environment variable
model = "glm-5"                   # Primary model
base_url = "https://api.z.ai/api/coding/paas/v4"
alias = "glm"                     # Short name for failover config

# Fallback provider (Ollama)
[providers.ollama]
enabled = true                    # MUST be true for failover
base_url = "http://ollama:11434"  # Docker service name
model = "gemini-3-flash-preview:cloud"  # Cloud model
alias = "ollama"                  # Short name
api_key = "${OLLAMA_API_KEY}"     # Optional: for cloud models
```

### Failover Configuration

```toml
[failover]
enabled = true                                      # Enable failover
primary_provider = "glm"                            # Primary provider alias
fallback_models = [                                 # Ordered fallback list
    "ollama::gemini-3-flash-preview:cloud"
]
health_check_interval = "5s"                        # Health check interval
failure_threshold = 3                               # Failures before switch
recovery_timeout = "60s"                            # Time before retry
success_threshold = 2                               # Successes to recover
```

## Configuration Validation

### Required Fields

| Section | Field | Type | Required | Default |
|---------|-------|------|----------|---------|
| providers.openai | enabled | bool | ✅ | false |
| providers.openai | api_key | string | ✅ | - |
| providers.openai | model | string | ✅ | - |
| providers.ollama | enabled | bool | ✅ | false |
| providers.ollama | base_url | string | ✅ | - |
| failover | enabled | bool | ✅ | false |
| failover | fallback_models | array | ✅ | [] |

### Validation Rules

1. At least one provider must have `enabled = true`
2. If `failover.enabled = true`, `fallback_models` must not be empty
3. All provider aliases in `fallback_models` must match defined providers
4. API keys must reference environment variables (not hardcoded)

## Example Configurations

### Minimal (GLM only, no failover)
```toml
[providers.openai]
enabled = true
api_key = "${GLM_API_KEY}"
model = "glm-5"
base_url = "https://api.z.ai/api/coding/paas/v4"

[providers.ollama]
enabled = false

[failover]
enabled = false
fallback_models = []
```

### Full (GLM + Ollama failover)
```toml
[providers.openai]
enabled = true
api_key = "${GLM_API_KEY}"
model = "glm-5"
base_url = "https://api.z.ai/api/coding/paas/v4"
alias = "glm"

[providers.ollama]
enabled = true
base_url = "http://ollama:11434"
model = "gemini-3-flash-preview:cloud"
alias = "ollama"
api_key = "${OLLAMA_API_KEY}"

[failover]
enabled = true
primary_provider = "glm"
fallback_models = ["ollama::gemini-3-flash-preview:cloud"]
health_check_interval = "5s"
failure_threshold = 3
recovery_timeout = "60s"
```

## CI/CD Validation

### Preflight Check Script
```bash
#!/bin/bash
# Validate Ollama configuration

CONFIG_FILE="config/moltis.toml"

# Check Ollama is enabled
if grep -q '^\[providers.ollama\]' "$CONFIG_FILE"; then
    OLLAMA_ENABLED=$(grep -A1 '^\[providers.ollama\]' "$CONFIG_FILE" | grep 'enabled' | awk '{print $3}')

    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        echo "✅ Ollama provider enabled"

        # Check API key secret exists
        if [[ ! -f "secrets/ollama_api_key.txt" ]]; then
            echo "❌ Missing secrets/ollama_api_key.txt"
            exit 1
        fi

        # Check failover is configured
        if ! grep -q 'fallback_models.*ollama' "$CONFIG_FILE"; then
            echo "⚠️ Ollama enabled but not in fallback_models"
        fi
    fi
fi
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| GLM_API_KEY | ✅ | Z.ai API key |
| OLLAMA_API_KEY | ⚠️ | Ollama cloud API key (if using cloud models) |

## Secrets Files

| File | Content | Permissions |
|------|---------|-------------|
| secrets/glm_api_key.txt | GLM API key | 600 |
| secrets/ollama_api_key.txt | Ollama API key | 600 |
