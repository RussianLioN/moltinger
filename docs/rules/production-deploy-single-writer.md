# Rule: Production Deploy Single Writer

For remote production mutations on `ainetic.tech` (`/opt/moltinger*`), only one deploy writer is allowed at a time.

Mandatory requirements:

1. All production-mutating GitHub workflows must share one target-scoped concurrency group.
2. Lock name must be stable and tied to remote target (host/path), not branch name.
3. Any active-root symlink update must migrate legacy non-symlink paths before `ln -sfn`.
4. Active-root mutation logic must live in one versioned script entrypoint, not duplicated inline across workflow YAML files.
5. Tracked Moltis deploy orchestration must live in one versioned script entrypoint, not duplicated across `deploy.yml` and `uat-gate.yml`.

Implementation baseline:

- Lock group: `prod-remote-ainetic-tech-opt-moltinger`
- Shared entrypoint: `scripts/update-active-deploy-root.sh`
- Shared tracked deploy entrypoint: `scripts/run-tracked-moltis-deploy.sh`
- Guard pattern:
  - `if [ -e "$ACTIVE" ] && [ ! -L "$ACTIVE" ]; then mv "$ACTIVE" "$ACTIVE.legacy-<timestamp>"; fi`
  - `ln -sfn "$TARGET" "$ACTIVE"`
  - `test -L "$ACTIVE"` and `test "$(readlink "$ACTIVE")" = "$TARGET"`
