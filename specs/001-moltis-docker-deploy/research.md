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

**Decision**: Primary `openai-codex::gpt-5.4` with single ordered fallback `ollama`

**Rationale**: Moltis should keep Codex as the preferred coding model while preserving one explicit failover lane through Ollama Cloud. Legacy Z.ai API-key usage is no longer acceptable outside IDE-only coding flows, and the tracked runtime/deploy contract no longer activates Anthropic or GLM fallback lanes.

**Configuration**:
```toml
[providers.openai-codex]
enabled = true

[providers.ollama]
enabled = true
model = "gemini-3-flash-preview:cloud"
alias = "ollama"
api_key = "${OLLAMA_API_KEY}"

[failover]
fallback_models = [
  "ollama::gemini-3-flash-preview:cloud",
]
```

**Alternatives Considered**:
- Z.ai Coding API keys — rejected: provider policy no longer allows non-IDE API-key usage without account risk
- Anthropic or GLM active fallback lanes — rejected: current operator policy leaves only Ollama Cloud as the tracked fallback surface
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
