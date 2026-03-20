# Docker Compose Structure Documentation

**Feature**: 001-docker-deploy-improvements
**Last Updated**: 2026-02-28

## Overview

The `docker-compose.yml` uses YAML anchors to reduce duplication and ensure consistent configuration across services. This document explains the anchor patterns and how to use them.

---

## YAML Anchors

YAML anchors allow you to define reusable blocks of configuration that can be referenced throughout the file. This follows the DRY (Don't Repeat Yourself) principle.

### Anchor Syntax

```yaml
# Define anchor with &name
x-anchor-name: &anchor-name
  key: value

# Reference anchor with *name
service:
  <<: *anchor-name
  extra_key: extra_value
```

---

## Defined Anchors

### x-common-env

Common environment variables shared across all Moltis services.

```yaml
x-common-env: &common-env
  # Network configuration
  MOLTIS_HOST: 0.0.0.0
  MOLTIS_NO_TLS: true
  MOLTIS_BEHIND_PROXY: true
```

**Purpose**: These settings configure Moltis to:
- Listen on all interfaces (`0.0.0.0`)
- Disable built-in TLS (handled by Traefik)
- Trust proxy headers for correct client IP detection

**Usage**:
```yaml
services:
  moltis:
    environment:
      <<: *common-env
      MOLTIS_PORT: 13131  # Service-specific override
```

### x-healthcheck

Standard health check configuration for containers.

```yaml
x-healthcheck: &healthcheck
  test: ["CMD", "curl", "-f", "http://localhost:13131/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

**Parameters**:
| Parameter | Value | Description |
|-----------|-------|-------------|
| `test` | curl health endpoint | HTTP health check command |
| `interval` | 30s | Time between checks |
| `timeout` | 10s | Max time for check to complete |
| `retries` | 3 | Failures before unhealthy |
| `start_period` | 10s | Grace period on container start |

**Usage**:
```yaml
services:
  moltis:
    healthcheck:
      <<: *healthcheck
```

### x-logging

Standardized logging configuration for all containers.

```yaml
x-logging: &logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

**Parameters**:
| Parameter | Value | Description |
|-----------|-------|-------------|
| `driver` | json-file | Docker's default JSON log driver |
| `max-size` | 10m | Max size per log file |
| `max-file` | 3 | Number of rotated files to keep |

**Total log storage**: 10MB x 3 files = 30MB per container

**Usage**:
```yaml
services:
  moltis:
    logging:
      <<: *logging
```

---

## Complete Service Example

Here's how all anchors come together in a service definition:

```yaml
services:
  moltis:
    image: ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-v1.7.0}
    container_name: moltis
    restart: unless-stopped
    privileged: true
    networks:
      - ainetic_net
    ports:
      - "13131:13131"
      - "13132:13132"
    volumes:
      - ${MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}:/home/moltis/.config/moltis
      - ./data:/home/moltis/.moltis
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      <<: *common-env           # Anchor: common environment
      MOLTIS_PORT: 13131
      MOLTIS_PASSWORD_FILE: /run/secrets/moltis_password
      TELEGRAM_BOT_TOKEN_FILE: /run/secrets/telegram_bot_token
      TELEGRAM_ALLOWED_USERS: ${TELEGRAM_ALLOWED_USERS}
      TAVILY_API_KEY_FILE: /run/secrets/tavily_api_key
      GLM_API_KEY_FILE: /run/secrets/glm_api_key
    secrets:
      - moltis_password
      - telegram_bot_token
      - tavily_api_key
      - glm_api_key
    healthcheck:
      <<: *healthcheck          # Anchor: health check config
    logging:
      <<: *logging              # Anchor: logging config
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.moltis.rule=Host(`moltis.ainetic.tech`)"
      - "com.centurylinklabs.watchtower.enable=true"
```

Production note:

- `./config/` remains the Git-synced static source of truth
- `${MOLTIS_RUNTIME_CONFIG_DIR}` is the writable live config/auth directory used by the container
- prepare it before restart/deploy with `scripts/prepare-moltis-runtime-config.sh`

---

## Adding New Services

When adding a new service, apply the appropriate anchors:

### Service with Health Endpoint

```yaml
services:
  myservice:
    image: myservice:latest
    environment:
      <<: *common-env
      MY_SERVICE_PORT: 8080
    healthcheck:
      <<: *healthcheck
    logging:
      <<: *logging
```

### Service Without Health Endpoint (e.g., worker)

```yaml
services:
  worker:
    image: worker:latest
    environment:
      <<: *common-env
    logging:
      <<: *logging
    # No healthcheck - worker doesn't expose HTTP
```

### Service with Custom Health Check

```yaml
services:
  custom:
    image: custom:latest
    environment:
      <<: *common-env
    healthcheck:
      <<: *healthcheck
      test: ["CMD", "curl", "-f", "http://localhost:9000/health"]
    logging:
      <<: *logging
```

---

## Development vs Production Differences

### Development Overrides (`docker-compose.override.yml`)

Create an override file for local development:

```yaml
# docker-compose.override.yml
# Automatically loaded by docker compose

services:
  moltis:
    environment:
      <<: *common-env
      MOLTIS_DEBUG: true
      MOLTIS_LOG_LEVEL: debug
    volumes:
      # Mount source code for hot reload
      - ./src:/app/src
    # No Traefik in development
    labels: []
```

### Production Configuration

Production settings are in the main `docker-compose.yml`:

- **Resource limits**: Add `deploy.resources` section
- **Restart policy**: `unless-stopped`
- **Traefik labels**: Enabled for routing
- **Watchtower**: Enabled for auto-updates

```yaml
# Production-only additions
services:
  moltis:
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M
```

---

## Modifying Anchors

### Adding a New Environment Variable

1. Add to the anchor definition:
```yaml
x-common-env: &common-env
  MOLTIS_HOST: 0.0.0.0
  MOLTIS_NO_TLS: true
  MOLTIS_BEHIND_PROXY: true
  NEW_VARIABLE: default_value  # Add here
```

2. All services using `<<: *common-env` automatically inherit it.

### Overriding Anchor Values

To override a value from an anchor:

```yaml
services:
  moltis:
    environment:
      <<: *common-env
      MOLTIS_NO_TLS: false  # Override: enable TLS
```

### Extending Anchors

You can extend anchors for service-specific variants:

```yaml
x-common-env: &common-env
  MOLTIS_HOST: 0.0.0.0
  MOLTIS_NO_TLS: true

x-common-env-tls: &common-env-tls
  <<: *common-env
  MOLTIS_NO_TLS: false
  MOLTIS_CERT_FILE: /certs/cert.pem
  MOLTIS_KEY_FILE: /certs/key.pem
```

---

## Anchor Reference Card

| Anchor | Purpose | Applies To |
|--------|---------|------------|
| `x-common-env` | Network/proxy settings | All Moltis services |
| `x-healthcheck` | Container health config | HTTP-exposed services |
| `x-logging` | Log rotation settings | All containers |

---

## Troubleshooting

### Anchor Not Resolving

**Symptom**: `<<: *anchor` appears literally in config

**Solution**: Ensure anchor is defined before use. YAML processes top-to-bottom.

```yaml
# WRONG - anchor used before defined
services:
  app:
    environment:
      <<: *common-env  # Error: anchor not found

x-common-env: &common-env
  KEY: value

# CORRECT - anchor defined first
x-common-env: &common-env
  KEY: value

services:
  app:
    environment:
      <<: *common-env  # Works!
```

### Merge Key Behavior

The `<<` merge key has specific behavior:

```yaml
# Anchor values
<<: *common-env
KEY_A: value_a

# If anchor contains KEY_A, the inline value wins
# Result: KEY_A = value_a (inline overrides anchor)
```

### Validating Compose File

Always validate after modifying:

```bash
# Check syntax
docker compose config --quiet

# View resolved config (with anchors expanded)
docker compose config
```

---

## Best Practices

1. **Define anchors at the top** - Before `services:` section
2. **Use descriptive names** - `x-common-env` not `x-env`
3. **Document anchor purpose** - Add comments explaining each anchor
4. **Validate after changes** - Run `docker compose config --quiet`
5. **Keep anchors focused** - Each anchor should have a single purpose
6. **Don't over-anchor** - Only anchor truly shared configuration

---

## Related Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Main compose file with anchors |
| `docker-compose.override.yml` | Local development overrides |
| `config/backup/backup.conf` | Backup configuration |
| `config/prometheus/prometheus.yml` | Prometheus configuration |
