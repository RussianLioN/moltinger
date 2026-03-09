# Clawdiy Rollback Runbook

**Status**: Operational draft for feature `001-clawdiy-agent-platform`
**Last Updated**: 2026-03-09
**Scope**: Roll back or disable Clawdiy while preserving Moltinger health and Clawdiy audit evidence

## Purpose

Use this runbook when Clawdiy itself is the problem and Moltinger must remain available.

This runbook is intentionally narrow:

- it does cover Clawdiy deploy regressions, auth regressions that require rollback, and bad handoff changes
- it does not cover Moltinger-wide outages
- it does not treat GPT-5.4 / Codex OAuth as baseline runtime critical; that capability may remain disabled after rollback

## When To Use It

Run rollback when one of these is true:

- Clawdiy deploy or restart isolation smoke fails
- Clawdiy health endpoint stays non-200 after deploy
- handoff contract changes break Clawdiy and redeploy-forward is riskier than revert
- Clawdiy auth rotation leaves the runtime unstable or fail-open

Prefer `repeat-auth` over rollback when the runtime is healthy and only Telegram or provider auth is degraded.

## Safety Rules

- Do not touch Moltinger secrets or Moltinger state during a Clawdiy-only rollback.
- Do not delete audit files before rollback.
- Do not run an ad-hoc restore if `./scripts/deploy.sh --json clawdiy rollback` can recover cleanly.
- Do not enable GPT-5.4 / Codex OAuth during incident response unless that capability is the explicit rollback target.

## Pre-Rollback Snapshot

Capture these first:

```bash
./scripts/deploy.sh --json clawdiy status | jq .
./scripts/health-monitor.sh --once --json | jq .
./scripts/clawdiy-smoke.sh --json --stage same-host | jq .
```

Optional, depending on the incident:

```bash
./scripts/clawdiy-smoke.sh --json --stage handoff | jq .
./scripts/clawdiy-smoke.sh --json --stage auth | jq .
docker logs clawdiy --tail 200
docker logs traefik --tail 200 | grep -i clawdiy
```

## Primary Procedure

### 1. Trigger rollback

```bash
./scripts/deploy.sh --json clawdiy rollback | jq .
```

Expected result:

- `status="success"`
- `action="rollback"`
- `details.rollback_evidence_file` is present
- health is either `rolled_back` or `disabled`

### 2. Validate rollback evidence

```bash
./scripts/clawdiy-smoke.sh --json --stage rollback-evidence | jq .
```

This must prove:

- rollback reason was recorded
- backup reference exists
- Moltinger health remained `200`
- resulting mode is `rolled_back` or `disabled`
- evidence manifest finished with `status="completed"`

### 3. Validate resulting runtime

If Clawdiy rolled back to a previous image:

```bash
./scripts/clawdiy-smoke.sh --json --stage same-host | jq .
```

Always confirm Moltinger:

```bash
curl -fsS http://127.0.0.1:13131/health
```

## Result Modes

### Rolled Back

Use this when a previous good image exists.

Expected outcome:

- Clawdiy is running again
- same-host smoke passes
- rollback evidence points to the archive used for recovery

### Disabled

Use this when no valid previous image exists or keeping Clawdiy offline is safer.

Expected outcome:

- Clawdiy is stopped
- Moltinger remains healthy
- rollback evidence still exists and explains why Clawdiy was disabled

Disabled mode is acceptable. Do not force a broken Clawdiy back online just to avoid an incident note.

## Backup and Restore Checks

List or verify the latest backup:

```bash
LATEST=$(ls -t /var/backups/moltis/daily/moltis_* /var/backups/moltis/weekly/moltis_* /var/backups/moltis/monthly/moltis_* 2>/dev/null | head -1)
./scripts/backup-moltis-enhanced.sh verify "$LATEST"
```

Only use a backup for restore if all of these are present:

- `backup-metadata.json`
- `config/clawdiy`
- `data/clawdiy/state`
- `data/clawdiy/audit`
- `clawdiy-evidence-manifest.json`
- `.clawdiy.included == true` in backup metadata

If any are missing, stop. Partial Clawdiy restore is blocked by default.

## Escalation Triggers

Escalate instead of retrying blindly when:

- rollback evidence smoke fails
- Moltinger health changes during Clawdiy rollback
- latest backup fails verification
- Clawdiy rollback completes but handoff evidence is corrupted or missing
- runtime is healthy but policy/registry drift keeps re-breaking the next deploy

## Operator Closeout

Do not close the incident until:

- rollback command output is saved
- latest rollback evidence path is recorded
- latest verified backup path is recorded
- Moltinger health is confirmed
- Clawdiy is either healthy again or intentionally disabled
- next action is explicit:
  - redeploy fixed Clawdiy
  - keep disabled pending fix
  - proceed to repeat-auth
