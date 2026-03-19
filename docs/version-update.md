# Version Update Process

This document defines the safe way to update Moltis versions in this repository.

## Current Version

Check the tracked version defaults:

```bash
make version-check
./scripts/moltis-version.sh version
```

## Production Rule

Production Moltis updates are git-based and backup-safe only.

The tracked version must point to a published GHCR container tag, not only to a GitHub release tag.
Use GHCR tag format without a leading `v` (for example `0.10.18`, not `v0.10.18`).

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

- [moltis-backup-safe-update.md](runbooks/moltis-backup-safe-update.md)

## Manual Server Helper

```bash
./scripts/backup-moltis-enhanced.sh --json backup
BACKUP_FILE="$(cat data/moltis/.last-moltis-backup)"
./scripts/backup-moltis-enhanced.sh restore-check "$BACKUP_FILE"
./scripts/deploy.sh --json moltis deploy
```

## GitHub Actions Path

`.github/workflows/deploy.yml` is expected to:

- create a fresh pre-update backup
- validate restore readiness of that backup
- deploy the git-tracked version only
- allow only production target in workflow_dispatch
- keep manual version input blank by default (tracked git version is source of truth)
- block deploy if restore readiness fails

`.github/workflows/uat-gate.yml` is expected to:

- resolve the tracked version from git via `scripts/moltis-version.sh`
- avoid manual version input
- deploy only through `./scripts/deploy.sh --json moltis deploy`

## Rollback Expectations

If the update regresses, rollback must preserve:

- backup reference
- restore-check reference
- pre/post image references
- pre/post health
- rollback reason

Runtime audit paths:

- `data/moltis/.last-deployed-image`
- `data/moltis/.last-moltis-backup`
- `data/moltis/.last-moltis-restore-check`
- `data/moltis/audit/restore-checks/`
- `data/moltis/audit/rollback-evidence/`

## References

- [deployment-strategy.md](deployment-strategy.md)
- [disaster-recovery.md](disaster-recovery.md)
