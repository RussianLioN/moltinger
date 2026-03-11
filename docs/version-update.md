# Version Update Process

This document defines the safe way to update Moltis versions in this repository.

## Current Version

Check the tracked version defaults:

```bash
make version-check
```

## Production Rule

Production Moltis updates are git-based and backup-safe only.

Allowed:

- update `docker-compose.yml` and `docker-compose.prod.yml` in git
- commit and push the version change
- deploy only after fresh backup + restore-check pass

Forbidden:

- `sed -i` edits on the server
- ad-hoc image pulls without a matching pre-update backup
- rollout when restore-check has not passed for the same backup

## Required Update Flow

1. Change the tracked image version in:
   - `docker-compose.yml`
   - `docker-compose.prod.yml`
2. Commit the change in git.
3. Capture a fresh pre-update backup.
4. Run restore-check against that fresh backup.
5. Only then roll out the updated Moltis container.

Preferred operator runbook:

- [moltis-backup-safe-update.md](/Users/rl/coding/moltinger-z8m-1-moltis-backup-rollback-baseline/docs/runbooks/moltis-backup-safe-update.md)

## Manual Server Helper

```bash
./scripts/backup-moltis-enhanced.sh --json backup
BACKUP_FILE="$(cat .last-moltis-backup)"
./scripts/backup-moltis-enhanced.sh restore-check "$BACKUP_FILE"
./scripts/deploy.sh --json moltis deploy
```

## GitHub Actions Path

`.github/workflows/deploy.yml` is expected to:

- create a fresh pre-update backup
- validate restore readiness of that backup
- block deploy if restore readiness fails

## Rollback Expectations

If the update regresses, rollback must preserve:

- backup reference
- restore-check reference
- pre/post image references
- pre/post health
- rollback reason

Runtime audit paths:

- `data/moltis/audit/restore-checks/`
- `data/moltis/audit/rollback-evidence/`

## References

- [deployment-strategy.md](/Users/rl/coding/moltinger-z8m-1-moltis-backup-rollback-baseline/docs/deployment-strategy.md)
- [disaster-recovery.md](/Users/rl/coding/moltinger-z8m-1-moltis-backup-rollback-baseline/docs/disaster-recovery.md)
