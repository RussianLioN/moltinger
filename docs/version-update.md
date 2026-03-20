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

Current tracked-helper contract in this branch:

- `./scripts/moltis-version.sh` enforces a pinned tracked version for the managed production path
- if operators intentionally validate `latest`, that is an upstream/dev/UAT path, not the default tracked production contract in git

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

## Regular Safe Update With User Confirmation

Use `.github/workflows/moltis-update-proposal.yml` for regular update checks.

Workflow contract:

1. Runs on schedule or manual dispatch.
2. Reads official latest release from `moltis-org/moltis`.
3. Normalizes release tag to GHCR runtime tag (`vX.Y.Z -> X.Y.Z`).
4. Verifies `ghcr.io/moltis-org/moltis:<tag>` is pullable.
5. Creates or updates a PR against `main` with pinned compose changes only.
6. Does not deploy directly.

User flow:

1. Receive notification with PR link.
2. Approve and merge PR when ready.
3. Existing hardened `Deploy Moltis` pipeline handles backup-safe rollout.

Optional email delivery secrets for proposal workflow:

- `SMTP_SERVER`
- `SMTP_PORT` (optional, default `465`)
- `SMTP_USERNAME`
- `SMTP_PASSWORD`
- `MOLTIS_UPDATE_NOTIFY_EMAIL`
- `MOLTIS_UPDATE_NOTIFY_FROM` (optional)

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

Current rollback contract:

- first attempt: return to the previous deployed image if it is known
- fallback: restore from the latest verified backup
- not a supported contract: rollback to an arbitrary operator-selected version tag
- if state or schema compatibility is uncertain, prefer verified restore over image-only rollback

## References

- [deployment-strategy.md](deployment-strategy.md)
- [disaster-recovery.md](disaster-recovery.md)
