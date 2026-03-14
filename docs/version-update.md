# Version Update Process

This document defines the safe way to update Moltis versions in this repository.

## Upstream Version Model

Official Moltis upstream supports both:

- `ghcr.io/moltis-org/moltis:latest` as a quickstart/default image path
- release-based images published on each upstream release

Project policy for this repository:

- `latest` is acceptable for local/dev/UAT or explicit operator validation
- production should prefer an explicit upstream release tag recorded in git
- `latest` is never treated as a rollback target
- rollback is not documented here as "return to any operator-chosen tag"

## Current Version

Check the tracked version defaults:

```bash
make version-check
```

## Production Rule

Production Moltis updates are backup-safe only.

Preferred production path:

- record an explicit upstream release tag in git
- deploy that tracked change only after fresh backup + restore-check pass

Operator exception path:

- `workflow_dispatch` may intentionally test `latest` or a specific upstream release
- this does not change the rollback contract described below

Allowed:

- update `docker-compose.yml` and `docker-compose.prod.yml` in git
- commit and push the version change
- deploy only after fresh backup + restore-check pass

Forbidden:

- `sed -i` edits on the server
- ad-hoc image pulls without a matching pre-update backup
- rollout when restore-check has not passed for the same backup

## Required Update Flow

1. Choose the target image version:
   - preferred for production: explicit upstream release tag
   - allowed by upstream for local/dev/UAT: `latest`
2. If using the preferred production path, change the tracked image version in:
   - `docker-compose.yml`
   - `docker-compose.prod.yml`
3. Commit the change in git.
4. Capture a fresh pre-update backup.
5. Run restore-check against that fresh backup.
6. Only then roll out the updated Moltis container.

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

Current rollback contract:

- first attempt: return to the previous deployed image if it is known
- fallback: restore from the latest verified backup
- not a supported contract: rollback to an arbitrary operator-selected version tag
- if state or schema compatibility is uncertain, prefer verified restore over image-only rollback

## References

- [deployment-strategy.md](/Users/rl/coding/moltinger-z8m-1-moltis-backup-rollback-baseline/docs/deployment-strategy.md)
- [disaster-recovery.md](/Users/rl/coding/moltinger-z8m-1-moltis-backup-rollback-baseline/docs/disaster-recovery.md)
