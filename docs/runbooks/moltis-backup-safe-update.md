# Moltis Backup-Safe Update Runbook

**Status**: Operational draft for backup-safe Moltis updates
**Last Updated**: 2026-03-15
**Scope**: Backup-safe Moltis image/version changes with mandatory pre-update backup, restore-check, and rollback evidence

## Purpose

Use this runbook for any Moltis version bump or container refresh that changes the running image on `ainetic.tech`.

This flow exists to prevent a "successful" update from leaving production without a provable rollback path.

## Version Policy

Upstream Moltis supports both:

- `latest` as a quickstart/default image path
- release-based images on upstream releases

Operational policy in this repository:

- local/dev/UAT may intentionally use `latest` or an explicit release tag
- production should prefer an explicit upstream release tag
- `latest` is not a rollback target
- rollback is defined here as "previous deployed image or verified restore", not "any operator-chosen tag"

## Non-Negotiable Rules

- Do not update Moltis by editing files directly on the server.
- Do not use `sed` on the server to bump image tags.
- Do not pin a GitHub release tag unless the matching GHCR container tag is actually published.
- Do not keep a leading `v` in tracked GHCR tags (use `0.10.18`, not `v0.10.18`).
- Do not pull or restart a new Moltis image without a fresh pre-update backup.
- Do not continue rollout if restore-check fails for that fresh backup.
- Do not treat "previous image exists" as sufficient rollback evidence by itself.
- Do not downgrade tracked version through normal deploy flow; use explicit rollback path.

## Required Evidence

Before the update is allowed to continue, you must have all of:

- a fresh backup archive reference
- a successful restore-check reference for that same backup
- the pre-update running image reference
- the target git change that will introduce the new version

During rollback, preserve:

- rollback reason
- backup reference used for recovery
- restore-check reference tied to that backup
- pre-rollback image and health
- post-rollback image and health

Runtime evidence locations:

- restore-check evidence: `data/moltis/audit/restore-checks/restore-check-*.json`
- rollback evidence: `data/moltis/audit/rollback-evidence/rollback-*.json`
- latest deployed image pointer: `data/moltis/.last-deployed-image`
- latest backup pointer: `data/moltis/.last-moltis-backup`
- latest restore-check pointer: `data/moltis/.last-moltis-restore-check`

## Preferred Update Path

### 1. Select the target version

Preferred production choice: an explicit upstream release tag.

Allowed upstream/dev choice: `latest`, but only when used intentionally and with the same backup-safe evidence path.

### 2. Change version in git

Update the tracked compose defaults in git, not on the server shell, when you are promoting a release-tag change through the normal production path.

Files:

- `docker-compose.yml`
- `docker-compose.prod.yml`
### 3. Capture fresh backup

Server-side helper:

```bash
./scripts/backup-moltis-enhanced.sh --json backup
```

The backup must include:

- `config/`
- `data/`
- `.env`
- `docker-compose.yml`
- `docker-compose.prod.yml`
- `backup-metadata.json`

### 4. Run restore-check before deploy

```bash
BACKUP_FILE="$(cat data/moltis/.last-moltis-backup)"
./scripts/backup-moltis-enhanced.sh restore-check "$BACKUP_FILE"
```

The rollout is blocked unless restore-check passes.

### 5. Roll out the new container

Preferred helper:

```bash
./scripts/deploy.sh --json moltis deploy
```

GitHub Actions path:

- `.github/workflows/deploy.yml`
- `workflow_dispatch` target is production-only
- release-tag deploy is allowed only when tag SHA matches current `origin/main` HEAD
- manual version input defaults to blank and must equal tracked git version if provided
- tracked version regression versus currently running semver image is blocked
- backup step must finish successfully
- restore-readiness validation must finish successfully
- only then may the new Moltis image be pulled and started
- `.github/workflows/uat-gate.yml`
- UAT must resolve the tracked version from git, not from manual input
- UAT deploy must go through `./scripts/deploy.sh --json moltis deploy`

## Rollback Path

If the update regresses:

```bash
./scripts/deploy.sh --json moltis rollback
```

Expected outcomes:

- rollback evidence file is written under `data/moltis/audit/rollback-evidence/`
- resulting mode is either `rolled_back` or `restored_from_backup`
- Moltis health returns to `200`

Important limits:

- If there is no previous image reference, rollback falls back to restore from the latest verified backup.
- This runbook does not define rollback as "pick any historical version and start it".
- If state, schema, or protocol compatibility is uncertain, prefer verified restore over image-only rollback.

## Stop Conditions

Stop the update and fix the gap first if any of the following is true:

- backup archive is missing `.env`
- backup archive is missing either compose file
- restore-check fails
- latest backup pointer and restore-check pointer refer to different update attempts
- rollback evidence cannot be written
- the operator is relying on `latest` as an implicit rollback target

## Closeout

An update is not complete until:

- Moltis health returns `200`
- external health via Traefik returns `200` or `401`
- the fresh backup path is recorded
- the matching restore-check evidence path is recorded
- rollback evidence exists if rollback occurred

## References

- [version-update.md](../version-update.md)
- [deployment-strategy.md](../deployment-strategy.md)
- [disaster-recovery.md](../disaster-recovery.md)
