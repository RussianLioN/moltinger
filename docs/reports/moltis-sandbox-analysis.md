# Moltis Sandbox in Docker Container: Research Report

**Date**: 2026-02-16
**Purpose**: Analyze whether Moltis should use its sandbox feature when running inside a Docker container

---

## Executive Summary

**RECOMMENDATION: Enable Moltis sandbox (mode = "all") when running in Docker.**

The Docker socket mount (`/var/run/docker.sock`) is already present in the current deployment configuration. This means the security boundary has already been crossed - Moltis container has **practical root access** to the host Docker daemon. Disabling the sandbox feature does NOT improve security; it merely adds risk by allowing commands to run directly in the Moltis container itself.

**Key Finding**: Container isolation (Docker) and sandbox isolation (Moltis sandbox) serve different purposes:
- **Docker container**: Isolates Moltis from the host system
- **Moltis sandbox**: Isolates LLM-generated commands from Moltis itself

---

## Current Security Posture Analysis

| Security Layer | Current State | Security Value |
|----------------|---------------|----------------|
| Docker socket mount | MOUNTED | **Already breached** - container has host Docker access |
| Privileged mode | ENABLED | **Additional risk** - container has extended capabilities |
| Moltis sandbox | DISABLED | **No isolation** between LLM commands and Moltis process |

**Assessment**: The Docker socket mount is the dominant security factor. Once mounted, disabling Moltis sandbox does NOT improve security - it actually INCREASES risk.

---

## Defense in Depth Analysis

**Without Moltis Sandbox** (current configuration):
```
Untrusted LLM Command → Moltis Process (CAN BE COMPROMISED) → Host System
```

**With Moltis Sandbox** (recommended):
```
Untrusted LLM Command → Ephemeral Sandbox Container (DISPOSABLE) → Moltis Process → Host System
```

**Key Difference**: Sandbox adds an isolation boundary between untrusted LLM commands and the Moltis process itself.

---

## Performance Considerations

| Operation | Without Sandbox | With Sandbox |
|-----------|----------------|--------------|
| Command execution | ~10-50ms | ~200-500ms |
| Memory footprint | Shared with Moltis | Additional ~50-200MB per session |

**Optimization**: Session-scoped containers avoid startup overhead for repeated commands.

---

## Pros/Cons Matrix

### Enabling Moltis Sandbox (mode = "all")

**Pros**:
- Isolates untrusted LLM commands from Moltis process
- Prevents commands from reading Moltis memory (API keys, sessions)
- Ephemeral containers limit attack persistence
- Network can be disabled for additional security

**Cons**:
- Additional container startup overhead (~200-500ms)
- Additional memory usage (~50-200MB per session)
- Does NOT reduce Docker socket access risk (already exposed)

### Docker-in-Docker Considerations

**Is it redundant?**
- **NO** - Container isolation and sandbox isolation serve different purposes

**Is it excessive?**
- **NO** - The overhead is justified for untrusted LLM code execution

---

## Final Recommendation

### Recommended Configuration

```toml
[tools.exec.sandbox]
mode = "all"           # Enable sandbox for all commands
scope = "session"      # Reuse container per session (performance)
backend = "auto"       # Auto-detect backend (Docker on Linux)
no_network = true      # Disable network access (security)
workspace_mount = "ro" # Mount workspace read-only (security)

# Resource limits (optional but recommended)
[tools.exec.sandbox.resource_limits]
memory_limit = "512M"
cpu_quota = 0.5
pids_max = 100
```

### Reasoning

1. **Defense in Depth**: Docker socket mount is already present - Moltis container has practical root access. Disabling sandbox does NOT improve security; it removes an isolation layer.

2. **Protect Moltis Process**: Sandbox prevents untrusted LLM commands from accessing Moltis memory (API keys, session data) and configuration.

3. **Limit Persistence**: Ephemeral sandbox containers are destroyed after command completion, limiting attacker persistence.

4. **Manageable Overhead**: Session-scoped containers reduce startup overhead to once per session.

---

## Conclusion

**Should we enable sandbox when Moltis runs in Docker?**
- **YES** - The Docker socket mount is already present; disabling sandbox does NOT improve security and actually INCREASES risk.

**Bottom Line**: Enable Moltis sandbox (`mode = "all"`) for defense in depth. The performance overhead is manageable with session-scoped containers, and the security benefit is significant given that the Docker socket is already mounted.
