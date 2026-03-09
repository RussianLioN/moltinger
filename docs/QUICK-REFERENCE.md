# Quick Reference

## Runtime Surface

| Surface | Moltinger | Clawdiy |
|---------|-----------|---------|
| Web UI | `https://moltis.ainetic.tech` | `https://clawdiy.ainetic.tech` |
| Telegram | `@moltinger_bot` | `@clawdiy_bot` |
| Telegram mode | managed by Moltinger runtime | phase-1 long polling |
| Role | coordinator | coder |
| Runtime | Moltis | OpenClaw |

## Source Of Truth

- Secrets: GitHub Secrets
- Main runtime env mirror: `/opt/moltinger/.env`
- Clawdiy runtime env mirror: `/opt/moltinger/clawdiy/.env`
- Agent registry: `config/fleet/agents-registry.json`
- Fleet policy: `config/fleet/policy.json`
- Git topology registry: `docs/GIT-TOPOLOGY-REGISTRY.md`
- Reviewed topology intent: `docs/GIT-TOPOLOGY-INTENT.yaml`

## Git Topology

```bash
scripts/git-topology-registry.sh status
scripts/git-topology-registry.sh check
scripts/git-topology-registry.sh refresh --write-doc
```

Use the topology registry before cleanup worktree/branch actions and after manual git topology changes.

## Core Commands

### Clawdiy deploy

```bash
./scripts/preflight-check.sh --ci --target clawdiy --json
./scripts/deploy.sh --json clawdiy deploy
./scripts/clawdiy-smoke.sh --json --stage same-host
```

This is the first live OpenClaw launch step for Clawdiy.
If `fleet-internal` is missing on the first rollout, use `deploy-clawdiy.yml` or `deploy.sh` to create it through GitOps; do not bootstrap it manually over SSH.

### Inter-agent handoff

```bash
./scripts/clawdiy-smoke.sh --json --stage handoff
```

### Auth checks

```bash
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider telegram --json
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider codex-oauth --json
./scripts/clawdiy-smoke.sh --json --stage auth
```

### Recovery

```bash
./scripts/deploy.sh --json clawdiy rollback
./scripts/clawdiy-smoke.sh --json --stage rollback-evidence
./scripts/backup-moltis-enhanced.sh verify /var/backups/moltis/daily/<archive>
```

### Future-node readiness

```bash
./scripts/clawdiy-smoke.sh --json --stage extraction-readiness
```

## Rollout Rules

- Same-host first, remote-node later.
- Inter-agent transport is private authenticated HTTP JSON.
- Telegram is human ingress only and stays in long-polling mode for phase 1.
- `gpt-5.4` through OpenAI Codex OAuth is a rollout gate, not a baseline deploy prerequisite.
- Clawdiy must stay healthy even when Codex-backed capability is disabled.

## Operator Pointers

- Deploy strategy: `docs/deployment-strategy.md`
- Validation path: `specs/001-clawdiy-agent-platform/quickstart.md`
- Clawdiy deploy runbook: `docs/runbooks/clawdiy-deploy.md`
- Clawdiy repeat-auth runbook: `docs/runbooks/clawdiy-repeat-auth.md`
- Clawdiy rollback runbook: `docs/runbooks/clawdiy-rollback.md`
- Handoff incident runbook: `docs/runbooks/fleet-handoff-incident.md`
- Git topology registry: `docs/GIT-TOPOLOGY-REGISTRY.md`
- Worktree hotfix playbook: `docs/WORKTREE-HOTFIX-PLAYBOOK.md`
- Session context: `SESSION_SUMMARY.md`
