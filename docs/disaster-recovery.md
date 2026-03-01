# Disaster Recovery: LLM Failover Runbook

**Version**: 1.0
**Last Updated**: 2026-03-01
**Related Feature**: 001-fallback-llm-ollama

---

## Overview

This runbook describes the LLM failover system for Moltis, which provides automatic fallback from GLM-5 (Z.ai) to Ollama Cloud (Gemini-3-flash-preview) when the primary provider is unavailable.

### Failover Chain

```
GLM-5 (Z.ai) → Ollama Gemini → Google Gemini
     ↓              ↓               ↓
  Primary       Fallback #1     Fallback #2
```

---

## Circuit Breaker States

The failover system uses a circuit breaker pattern with three states:

| State | Description | Provider |
|-------|-------------|----------|
| `CLOSED` | Normal operation | GLM-5 (Primary) |
| `OPEN` | Failover active | Ollama Gemini |
| `HALF-OPEN` | Testing recovery | GLM-5 (testing) |

### State Transitions

```
CLOSED ──(3 failures)──> OPEN ──(5 min)──> HALF-OPEN
   ↑                                            │
   └──────────(success)─────────────────────────┘
                    │
            (failure)──> back to OPEN
```

---

## Monitoring

### Prometheus Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `llm_provider_available` | Gauge | 1=available, 0=unavailable per provider |
| `llm_fallback_triggered_total` | Counter | Total failover events |
| `llm_request_duration_seconds` | Histogram | Request latency by provider |
| `moltis_circuit_state` | Gauge | Circuit breaker state (0=CLOSED, 1=OPEN, 2=HALF-OPEN) |

### Check Current State

```bash
# On production server
cat /tmp/moltis-llm-state.json | jq .

# Expected output:
{
  "state": "CLOSED",
  "primary_provider": "glm",
  "active_provider": "glm",
  "consecutive_failures": 0,
  "last_check": "2026-03-01T12:00:00Z",
  "last_failover": null
}
```

### Health Check Script

```bash
# Check all LLM providers
./scripts/health-monitor.sh --once --json

# Check Ollama specifically
./scripts/ollama-health.sh --json
```

---

## Alert Response

### Alert: GLMProviderDown

**Severity**: Warning
**Meaning**: GLM API is unhealthy, failover may trigger soon

**Actions**:
1. Check GLM API status: https://status.zhipu.ai/
2. Verify network connectivity to api.z.ai
3. Monitor circuit breaker state
4. Prepare for potential failover

### Alert: CircuitBreakerOpen

**Severity**: Critical
**Meaning**: Failover is active, using Ollama fallback

**Actions**:
1. Verify Ollama is healthy: `./scripts/ollama-health.sh`
2. Check Ollama container: `docker logs ollama-fallback`
3. Monitor GLM recovery
4. Review logs for root cause

### Alert: AllLLMProvidersDown

**Severity**: Critical
**Meaning**: Both GLM and Ollama are unavailable

**Immediate Actions**:
1. Check server network connectivity
2. Verify Docker containers are running: `docker ps`
3. Check Ollama container: `docker logs ollama-fallback --tail 100`
4. Restart Ollama if needed: `docker compose restart ollama`
5. Escalate to on-call engineer

---

## Recovery Procedures

### Manual Failover to Ollama

If you need to manually switch to Ollama:

```bash
# On production server
cd /opt/moltinger

# Update state file to force failover
echo '{"state":"OPEN","primary_provider":"glm","active_provider":"ollama","consecutive_failures":3,"last_check":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","last_failover":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > /tmp/moltis-llm-state.json

# Verify
cat /tmp/moltis-llm-state.json
```

### Force Recovery to GLM

After GLM is confirmed healthy:

```bash
# Reset circuit breaker to CLOSED state
echo '{"state":"CLOSED","primary_provider":"glm","active_provider":"glm","consecutive_failures":0,"last_check":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","last_failover":null}' > /tmp/moltis-llm-state.json

# Verify
cat /tmp/moltis-llm-state.json
```

### Restart Ollama Container

```bash
# Check Ollama status
docker logs ollama-fallback --tail 50

# Restart if unhealthy
docker compose restart ollama

# Wait for health check
sleep 60

# Verify
./scripts/ollama-health.sh
```

---

## Troubleshooting

### Issue: Ollama Container Not Starting

**Symptoms**: `docker ps` shows ollama container restarting

**Diagnosis**:
```bash
# Check logs
docker logs ollama-fallback --tail 100

# Check resource limits
docker stats ollama-fallback --no-stream

# Check disk space
df -h /var/lib/docker
```

**Solutions**:
- If OOM killed: Increase memory limit in docker-compose.prod.yml
- If disk full: Clean up Docker volumes
- If API error: Verify OLLAMA_API_KEY secret

### Issue: Ollama API Timeout

**Symptoms**: Health checks timing out, `curl: (28) Operation timed out`

**Diagnosis**:
```bash
# Test API directly
curl -v http://localhost:11434/api/tags

# Check network
docker exec ollama-fallback curl -v http://localhost:11434/api/tags
```

**Solutions**:
- Check if Ollama is downloading model (first run)
- Verify no firewall blocking port 11434
- Restart container if stuck

### Issue: State File Corruption

**Symptoms**: Circuit breaker behaving unexpectedly

**Diagnosis**:
```bash
# Check state file
cat /tmp/moltis-llm-state.json

# Validate JSON
cat /tmp/moltis-llm-state.json | jq .
```

**Solution**:
```bash
# Reset to default state
echo '{"state":"CLOSED","primary_provider":"glm","active_provider":"glm","consecutive_failures":0,"last_check":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","last_failover":null}' > /tmp/moltis-llm-state.json
```

---

## Escalation

### When to Escalate

- AllLLMProvidersDown alert fires
- Failover not recovering after 15 minutes
- Ollama container repeatedly crashing
- Unknown errors in circuit breaker logs

### Contact Information

| Role | Contact |
|------|---------|
| Primary On-Call | @your-on-call |
| Backup | @backup-engineer |
| Escalation | @team-lead |

---

## Post-Incident

After resolving an incident:

1. **Document**: Update this runbook with any new findings
2. **Review**: Analyze Prometheus metrics for the incident period
3. **Improve**: Identify and implement preventive measures
4. **Report**: Create incident report in `docs/LESSONS-LEARNED.md`

---

## References

- [Circuit Breaker Pattern](https://martinfowler.com/bliki/CircuitBreaker.html)
- [Ollama Documentation](https://github.com/ollama/ollama)
- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [SESSION_SUMMARY.md](/SESSION_SUMMARY.md) - Current project status
