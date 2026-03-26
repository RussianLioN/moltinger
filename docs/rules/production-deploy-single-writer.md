# Rule: Production Deploy Single Writer

For remote production mutations on `ainetic.tech` (`/opt/moltinger*`), only one deploy writer is allowed at a time.

Mandatory requirements:

1. All production-mutating GitHub workflows must share one target-scoped concurrency group.
2. Lock name must be stable and tied to remote target (host/path), not branch name.
3. Any active-root symlink update must migrate legacy non-symlink paths before `ln -sfn`.
4. Active-root mutation logic must live in one versioned script entrypoint, not duplicated inline across workflow YAML files.
5. Tracked Moltis deploy orchestration must live in one versioned script entrypoint, not duplicated across `deploy.yml` and `uat-gate.yml`.
6. Live runtime provenance attestation must live in one versioned script entrypoint and remain a blocking part of tracked deploy success.
7. Periodic drift detection must call the shared runtime attestation entrypoint instead of inlining remote container provenance logic in workflow YAML.
8. Scheduled drift attestation must be marker-driven: compare live runtime to deployed markers under the active root, not to repository HEAD or the workflow's current `${github.sha}`.

Implementation baseline:

- Lock group: `prod-remote-ainetic-tech-opt-moltinger`
- Shared entrypoint: `scripts/update-active-deploy-root.sh`
- Shared tracked deploy entrypoint: `scripts/run-tracked-moltis-deploy.sh`
- Shared runtime attestation entrypoints:
  - `scripts/moltis-runtime-attestation.sh`
  - `scripts/ssh-run-moltis-runtime-attestation.sh`
- Guard pattern:
  - `if [ -e "$ACTIVE" ] && [ ! -L "$ACTIVE" ]; then mv "$ACTIVE" "$ACTIVE.legacy-<timestamp>"; fi`
  - `ln -sfn "$TARGET" "$ACTIVE"`
  - `test -L "$ACTIVE"` and `test "$(readlink "$ACTIVE")" = "$TARGET"`
