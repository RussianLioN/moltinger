#!/usr/bin/env bash
# Repair a deploy-managed dirty checkout on the remote host and emit the drift snapshot path.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  gitops-repair-managed-checkout.sh \
    --ssh-user <user> \
    --ssh-host <host> \
    --deploy-path <path> \
    --backup-path <path> \
    --target-ref <ref> \
    --target-sha <sha> \
    --run-id <id> \
    --repository <owner/repo>

  gitops-repair-managed-checkout.sh <ssh-target> <deploy-path> <backup-path> <target-ref> <target-sha> <run-id> <repository>
EOF
}

SSH_TARGET=""
SSH_USER=""
SSH_HOST=""
DEPLOY_PATH=""
BACKUP_PATH=""
TARGET_REF=""
TARGET_SHA=""
RUN_ID=""
REPOSITORY=""

if [[ $# -gt 0 && "$1" == --* ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ssh-user)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                SSH_USER="$2"
                shift 2
                ;;
            --ssh-host)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                SSH_HOST="$2"
                shift 2
                ;;
            --deploy-path)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                DEPLOY_PATH="$2"
                shift 2
                ;;
            --backup-path)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                BACKUP_PATH="$2"
                shift 2
                ;;
            --target-ref)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                TARGET_REF="$2"
                shift 2
                ;;
            --target-sha)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                TARGET_SHA="$2"
                shift 2
                ;;
            --run-id)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                RUN_ID="$2"
                shift 2
                ;;
            --repository)
                [[ $# -ge 2 ]] || { usage; exit 64; }
                REPOSITORY="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                usage
                exit 64
                ;;
        esac
    done
else
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
fi

if [[ -n "$SSH_USER" || -n "$SSH_HOST" ]]; then
    SSH_TARGET="${SSH_USER}@${SSH_HOST}"
fi

if [[ -z "$SSH_TARGET" || "$SSH_TARGET" == @* || "$SSH_TARGET" == *@ ]]; then
    usage
    exit 64
fi

if [[ -z "$DEPLOY_PATH" || -z "$BACKUP_PATH" || -z "$TARGET_REF" || -z "$TARGET_SHA" || -z "$RUN_ID" || -z "$REPOSITORY" ]]; then
    usage
    exit 64
fi

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
STRAY_OAUTH_SOURCE="config/oauth_tokens.json"
STRAY_OAUTH_DIR="data/oauth-config"
STRAY_OAUTH_DEST="$STRAY_OAUTH_DIR/oauth_tokens.json"

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

evacuate_stray_oauth_store() {
    local source_owner conflict_path

    if [ ! -f "$STRAY_OAUTH_SOURCE" ]; then
        return 0
    fi

    source_owner="$(stat -c '%u:%g' "$STRAY_OAUTH_SOURCE")"
    if [ ! -d "$STRAY_OAUTH_DIR" ]; then
        mkdir -p "$STRAY_OAUTH_DIR"
        chown "$source_owner" "$STRAY_OAUTH_DIR"
        chmod 700 "$STRAY_OAUTH_DIR"
    fi

    if [ -f "$STRAY_OAUTH_DEST" ]; then
        if cmp -s "$STRAY_OAUTH_SOURCE" "$STRAY_OAUTH_DEST"; then
            rm -f "$STRAY_OAUTH_SOURCE"
            printf 'note: removed duplicate stray OAuth token store %s because %s already exists\n' \
                "$STRAY_OAUTH_SOURCE" \
                "$STRAY_OAUTH_DEST" >&2
            return 0
        fi

        conflict_path="$STRAY_OAUTH_DIR/oauth_tokens.recovered.${SNAPSHOT_STAMP}.json"
        mv "$STRAY_OAUTH_SOURCE" "$conflict_path"
        chmod 600 "$conflict_path"
        printf 'note: moved stray OAuth token store %s to %s because %s already existed with different contents\n' \
            "$STRAY_OAUTH_SOURCE" \
            "$conflict_path" \
            "$STRAY_OAUTH_DEST" >&2
        return 0
    fi

    mv "$STRAY_OAUTH_SOURCE" "$STRAY_OAUTH_DEST"
    chmod 600 "$STRAY_OAUTH_DEST"
    printf 'note: moved stray OAuth token store %s to %s before checkout repair\n' \
        "$STRAY_OAUTH_SOURCE" \
        "$STRAY_OAUTH_DEST" >&2
}

evacuate_stray_oauth_store

git fetch --depth=1 origin "$TARGET_REF" >&2
git checkout --force "$TARGET_REF" >&2
git reset --hard "$TARGET_SHA" >&2
git clean -fd -- docker-compose.yml docker-compose.prod.yml config scripts systemd >&2

printf '%s\n' "$ARCHIVE_FILE"
REMOTE_EOF
)"

printf '%s\n' "$DRIFT_SNAPSHOT"
