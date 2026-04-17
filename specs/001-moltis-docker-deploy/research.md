# Research Findings: Moltis Docker Deployment

**Date**: 2026-02-14
**Source**: [Full Report](../../docs/reports/moltis-deployment-research.md)

## Executive Summary

Research completed via deep documentation analysis from https://docs.moltis.org/. All technical unknowns resolved. Ready for implementation.

---

## Resolved Unknowns

### 1. Reverse Proxy Choice

**Decision**: Traefik (existing deployment)

**Rationale**: User already has Traefik deployed on ainetic.tech server. No need for additional proxy.

**Configuration**: Labels-based routing with automatic TLS via Let's Encrypt.

**Alternatives Considered**:
- Nginx — rejected: requires manual TLS management
- Caddy — rejected: unnecessary with existing Traefik

---

### 2. LLM Provider Chain

**Decision**: Primary `openai-codex::gpt-5.4` with ordered fallback `ollama -> anthropic -> glm::glm-5.1`

**Rationale**: Moltis should keep Codex as the preferred coding model while preserving an explicit failover chain. Legacy Z.ai API-key usage is no longer acceptable outside IDE-only coding flows, so GLM remains only as the final fallback via the official BigModel endpoint.

**Final GLM Endpoint**: `https://open.bigmodel.cn/api/coding/paas/v4`

**Configuration**:
```toml
[providers.openai-codex]
enabled = true

[providers.ollama]
enabled = true

[providers.anthropic]
enabled = true

[providers.openai]
enabled = true
alias = "glm"
base_url = "https://open.bigmodel.cn/api/coding/paas/v4"
model = "glm-5.1"
models = ["glm-5.1"]

[failover]
fallback_models = [
  "ollama::gemini-3-flash-preview:cloud",
  "anthropic::claude-sonnet-4-20250514",
  "glm::glm-5.1",
]
```

**Alternatives Considered**:
- Z.ai Coding API keys — rejected: provider policy no longer allows non-IDE API-key usage without account risk
- GLM as primary provider — rejected: operational policy now reserves GLM for final fallback only
- Local-only LLM — rejected: hardware constraints and weaker coding quality for the primary lane

---

### 3. Container Updates

**Decision**: Watchtower for automatic updates

**Rationale**: Zero-maintenance updates with daily checks.

**Configuration**:
```yaml
watchtower:
  image: containrrr/watchtower
  environment:
    - WATCHTOWER_CLEANUP=true
    - WATCHTOWER_POLL_INTERVAL=86400
    - WATCHTOWER_LABEL_ENABLE=true
```

**Alternatives Considered**:
- Manual updates — rejected: maintenance burden
- CI/CD pipeline — rejected: overkill for single container

---

### 4. Backup Strategy

**Decision**: Cron-based daily backup with 7-day retention

**Rationale**: Simple, reliable, sufficient for single-server deployment.

**Implementation**:
- Script: `/usr/local/bin/backup-moltis.sh`
- Schedule: Daily at 3 AM
- Retention: 7 days
- Storage: `/var/backups/moltis/`

**Alternatives Considered**:
- No backup — rejected: data loss risk
- Off-site replication — rejected: unnecessary complexity
- Volume snapshots — rejected: filesystem-dependent

---

### 5. Authentication

**Decision**: MOLTIS_PASSWORD environment variable

**Rationale**: Simplest setup for cloud deployment, skips setup code flow.

**Security**:
- Password hashed with Argon2id
- Session cookies: 30-day expiry
- Rate limiting: 5 attempts/60s

**Alternatives Considered**:
- Setup code flow — rejected: requires terminal access
- Passkey only — rejected: password sufficient for initial setup

---

### 6. Docker Socket Security

**Decision**: Mount with documented security warning

**Rationale**: Required for sandboxed command execution.

**Security Warning**:
> Mounting Docker socket gives container full access to Docker daemon, equivalent to root access on host.

**Mitigation**: Use only official Moltis image from `ghcr.io/moltis-org/moltis`

---

## Libraries & Tools Selected

| Tool | Version | Why Chosen |
|------|---------|------------|
| Moltis | latest | Official AI assistant image |
| Watchtower | latest | Industry standard for auto-updates |
| Traefik | 3.x | Already deployed, automatic TLS |

---

## Best Practices Applied

1. **Environment Variables**: Sensitive data via `.env` file (gitignored)
2. **Volume Permissions**: UID 1000 for moltis user
3. **Health Checks**: `/health` endpoint for monitoring
4. **TLS**: Let's Encrypt via Traefik
5. **Resource Limits**: Configurable in moltis.toml

---

## Open Questions

**None** — All unknowns resolved through research.

---

## References

- Docker Deployment: https://docs.moltis.org/docker.html
- Configuration: https://docs.moltis.org/configuration.html
- Authentication: https://docs.moltis.org/authentication.html
- Sandbox: https://docs.moltis.org/sandbox.html
