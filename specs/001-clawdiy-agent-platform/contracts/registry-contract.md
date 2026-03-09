# Contract: Fleet Registry

**Feature**: 001-clawdiy-agent-platform  
**Purpose**: Define the phase-1 Git-managed registry for permanent agents.

## Canonical File

Planned canonical registry file:

```text
config/fleet/agents-registry.json
```

## Required Top-Level Fields

```json
{
  "schema_version": "v1",
  "updated_at": "2026-03-09T12:00:00Z",
  "agents": []
}
```

## Agent Entry Shape

Each entry must contain:

- `agent_id`
- `display_name`
- `role`
- `runtime_engine`
- `internal_endpoint`
- `public_endpoints`
- `capabilities`
- `allowed_callers`
- `reachability`
- `policy_version`

## Example Entry

```json
{
  "agent_id": "clawdiy",
  "display_name": "Clawdiy",
  "role": "coder",
  "runtime_engine": "openclaw",
  "internal_endpoint": "http://clawdiy:18789/internal/v1",
  "public_endpoints": {
    "web": "https://clawdiy.ainetic.tech",
    "telegram": "@clawdiy_bot"
  },
  "capabilities": [
    "coding.orchestration",
    "task.execution",
    "provider.auth.check"
  ],
  "allowed_callers": [
    "moltinger",
    "coordinator"
  ],
  "reachability": "reachable",
  "policy_version": "git:abc1234"
}
```

## Registry Rules

- One entry per canonical `agent_id`
- `reachability=quarantined` removes the agent from normal routing
- Registry changes are Git-managed and deployed through CI/CD
- No runtime may invent its own canonical identity outside this file
