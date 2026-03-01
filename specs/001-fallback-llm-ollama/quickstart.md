# Quick Start: Fallback LLM with Ollama Sidecar

**Feature**: 001-fallback-llm-ollama
**Time to Deploy**: ~30 minutes

## Prerequisites

- Docker and Docker Compose installed
- OLLAMA_API_KEY (get from https://ollama.com)
- Server with 4+ CPUs, 8GB+ RAM available

## Quick Deploy

### Step 1: Add Ollama API Key

```bash
# Create secrets directory if not exists
mkdir -p secrets

# Add Ollama API key
echo "your-ollama-api-key-here" > secrets/ollama_api_key.txt
chmod 600 secrets/ollama_api_key.txt
```

### Step 2: Update Configuration

```bash
# Update moltis.toml (already done if following speckit workflow)
# Ensure [providers.ollama] is enabled with:
#   enabled = true
#   base_url = "http://ollama:11434"
#   model = "gemini-3-flash-preview:cloud"
```

### Step 3: Deploy

```bash
# Validate configuration
./scripts/preflight-check.sh

# Deploy stack
docker compose -f docker-compose.prod.yml up -d

# Verify Ollama is running
curl http://localhost:11434/api/tags
```

### Step 4: Verify Failover

```bash
# Check circuit breaker state
cat /tmp/moltis-llm-state.json | jq .

# Simulate GLM failure (test mode)
# docker compose -f docker-compose.prod.yml exec moltis ...
```

## Configuration Options

### Minimal (Recommended)

```yaml
# docker-compose.prod.yml - add this service
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama-fallback
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
    environment:
      OLLAMA_HOST: 0.0.0.0
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - monitoring

volumes:
  ollama-data:
```

### With Cloud API Key

```yaml
services:
  ollama:
    # ... (as above)
    environment:
      OLLAMA_HOST: 0.0.0.0
      OLLAMA_API_KEY_FILE: /run/secrets/ollama_api_key
    secrets:
      - ollama_api_key

secrets:
  ollama_api_key:
    file: ./secrets/ollama_api_key.txt
```

## Verification Checklist

- [ ] Ollama container running: `docker ps | grep ollama`
- [ ] Health check passing: `curl http://localhost:11434/api/tags`
- [ ] Moltis can reach Ollama: `docker compose exec moltis curl http://ollama:11434/api/tags`
- [ ] Circuit breaker state file exists: `ls /tmp/moltis-llm-state.json`
- [ ] Failover config valid: `grep -A5 '\[failover\]' config/moltis.toml`

## Troubleshooting

### Ollama not starting

```bash
# Check logs
docker logs ollama-fallback

# Common issues:
# - Insufficient memory: Increase Docker memory limit
# - Port conflict: Change port mapping
```

### Cold start timeout

```bash
# First model load takes ~60s
# Increase start_period in healthcheck:
start_period: 120s
```

### API key not working

```bash
# Verify secret file
cat secrets/ollama_api_key.txt

# Check secret is mounted
docker compose exec ollama cat /run/secrets/ollama_api_key
```

## Next Steps

1. **Monitor**: Check Prometheus metrics at http://localhost:9090
2. **Test failover**: Simulate GLM outage and verify switch to Ollama
3. **Alert setup**: Configure AlertManager for failover notifications

## Rollback

```bash
# Disable Ollama provider
# In config/moltis.toml:
# [providers.ollama]
# enabled = false

# Stop Ollama container
docker compose -f docker-compose.prod.yml stop ollama

# Remove Ollama service (optional)
docker compose -f docker-compose.prod.yml rm -f ollama
```
