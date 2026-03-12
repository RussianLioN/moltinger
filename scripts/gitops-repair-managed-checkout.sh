#!/bin/bash
# Repair a deploy-managed dirty checkout on the remote host and emit the drift snapshot path.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: gitops-repair-managed-checkout.sh <ssh-target> <deploy-path> <backup-path> <target-ref> <target-sha> <run-id> <repository>
EOF
}

if [[ $# -ne 7 ]]; then
    usage
    exit 64
fi

SSH_TARGET="$1"
DEPLOY_PATH="$2"
BACKUP_PATH="$3"
TARGET_REF="$4"
TARGET_SHA="$5"
RUN_ID="$6"
REPOSITORY="$7"

DRIFT_SNAPSHOT="$(
ssh "$SSH_TARGET" bash -seuo pipefail -s -- \
    "$DEPLOY_PATH" \
    "$BACKUP_PATH" \
    "$TARGET_REF" \
    "$TARGET_SHA" \
    "$RUN_ID" \
    "$REPOSITORY" <<'REMOTE_EOF'
DEPLOY_PATH="$1"
BACKUP_PATH="$2"
TARGET_REF="$3"
TARGET_SHA="$4"
RUN_ID="$5"
REPOSITORY="$6"

cd "$DEPLOY_PATH"

SNAPSHOT_DIR="$BACKUP_PATH/gitops-drift"
SNAPSHOT_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SNAPSHOT_PREFIX="run_${RUN_ID}_${SNAPSHOT_STAMP}"
META_FILE="$SNAPSHOT_DIR/${SNAPSHOT_PREFIX}.meta.txt"
DIFF_FILE="$SNAPSHOT_DIR/${SNAPSHOT_PREFIX}.diff.patch"
ARCHIVE_FILE="$SNAPSHOT_DIR/${SNAPSHOT_PREFIX}.tar.gz"

mkdir -p "$SNAPSHOT_DIR"

{
    echo "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "repository=$REPOSITORY"
    echo "workflow_run=$RUN_ID"
    echo "target_ref=$TARGET_REF"
    echo "target_sha=$TARGET_SHA"
    echo "current_branch=$(git rev-parse --abbrev-ref HEAD)"
    echo "current_sha=$(git rev-parse HEAD)"
    echo "--- git status --short ---"
    git status --short
} > "$META_FILE"

git diff --binary -- docker-compose.yml docker-compose.prod.yml config scripts systemd > "$DIFF_FILE" || true
tar --ignore-failed-read -czf "$ARCHIVE_FILE" docker-compose.yml docker-compose.prod.yml config scripts systemd

git fetch --depth=1 origin "$TARGET_REF"
git checkout --force "$TARGET_REF"
git reset --hard "$TARGET_SHA"
git clean -fd -- docker-compose.yml docker-compose.prod.yml config scripts systemd

printf '%s\n' "$ARCHIVE_FILE"
REMOTE_EOF
)"

printf '%s\n' "$DRIFT_SNAPSHOT"
