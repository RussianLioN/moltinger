#!/usr/bin/env bash
# Compare the GitOps-managed deploy surface against the remote host in one SSH roundtrip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    cat >&2 <<'EOF'
Usage:
  gitops-check-managed-surface.sh \
    --ssh-user <user> \
    --ssh-host <host> \
    --deploy-path <path> \
    [--project-root <path>] \
    [--state-file <path>]
EOF
}

notice() {
    echo "::notice::$*"
}

error() {
    echo "::error::$*" >&2
}

shell_quote() {
    printf '%q' "$1"
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

SSH_USER=""
SSH_HOST=""
DEPLOY_PATH=""
SOURCE_ROOT="$PROJECT_ROOT"
STATE_FILE=""

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
        --project-root)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            SOURCE_ROOT="$2"
            shift 2
            ;;
        --state-file)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            STATE_FILE="$2"
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

if [[ -z "$SSH_USER" || -z "$SSH_HOST" || -z "$DEPLOY_PATH" ]]; then
    usage
    exit 64
fi

if [[ ! -d "$SOURCE_ROOT" ]]; then
    error "Project root does not exist: $SOURCE_ROOT"
    exit 1
fi

SOURCE_ROOT="$(cd "$SOURCE_ROOT" && pwd)"
SSH_TARGET="${SSH_USER}@${SSH_HOST}"

manifest_file="$(mktemp)"
cleanup() {
    rm -f "$manifest_file"
}
trap cleanup EXIT

manifest_count=0
compose_count=0
config_count=0
script_count=0
systemd_count=0

append_manifest_entry() {
    local relative_path="$1"
    local absolute_path="$2"
    local bucket="$3"

    if [[ ! -f "$absolute_path" ]]; then
        error "Required managed file is missing locally: $absolute_path"
        exit 1
    fi

    printf '%s\t%s\n' "$relative_path" "$(sha256_file "$absolute_path")" >> "$manifest_file"
    manifest_count=$((manifest_count + 1))

    case "$bucket" in
        compose) compose_count=$((compose_count + 1)) ;;
        config) config_count=$((config_count + 1)) ;;
        scripts) script_count=$((script_count + 1)) ;;
        systemd) systemd_count=$((systemd_count + 1)) ;;
    esac
}

append_optional_manifest_entry() {
    local relative_path="$1"
    local absolute_path="$2"
    local bucket="$3"

    [[ -f "$absolute_path" ]] || return 0
    append_manifest_entry "$relative_path" "$absolute_path" "$bucket"
}

append_top_level_directory_files() {
    local relative_dir="$1"
    local absolute_dir="$2"
    local bucket="$3"
    local absolute_path relative_path

    [[ -d "$absolute_dir" ]] || return 0

    while IFS= read -r absolute_path; do
        [[ -n "$absolute_path" ]] || continue
        relative_path="${relative_dir}/$(basename "$absolute_path")"
        append_manifest_entry "$relative_path" "$absolute_path" "$bucket"
    done < <(find "$absolute_dir" -mindepth 1 -maxdepth 1 -type f | LC_ALL=C sort)
}

append_manifest_entry "docker-compose.yml" "$SOURCE_ROOT/docker-compose.yml" "compose"
append_manifest_entry "docker-compose.prod.yml" "$SOURCE_ROOT/docker-compose.prod.yml" "compose"
append_manifest_entry "config/moltis.toml" "$SOURCE_ROOT/config/moltis.toml" "config"
append_optional_manifest_entry "config/mcp-servers.json" "$SOURCE_ROOT/config/mcp-servers.json" "config"
append_top_level_directory_files "scripts" "$SOURCE_ROOT/scripts" "scripts"
append_top_level_directory_files "systemd" "$SOURCE_ROOT/systemd" "systemd"

notice "Managed surface manifest: compose=$compose_count config=$config_count scripts=$script_count systemd=$systemd_count total=$manifest_count"
notice "Fetching remote hashes in one SSH roundtrip from ${SSH_TARGET}:${DEPLOY_PATH}"

emit_remote_script() {
    local manifest_path="$1"

    printf 'set -euo pipefail\n'
    printf 'DEPLOY_PATH=%s\n' "$(shell_quote "$DEPLOY_PATH")"
    cat <<'REMOTE_HEADER'
while IFS=$'\t' read -r relative_path local_hash; do
    remote_path="$DEPLOY_PATH/$relative_path"
    if [[ -f "$remote_path" ]]; then
        remote_hash="$(sha256sum "$remote_path" | awk '{print $1}')"
    else
        remote_hash="NOT_FOUND"
    fi

    printf '%s\t%s\t%s\n' "$relative_path" "$local_hash" "$remote_hash"
done <<'MANAGED_SURFACE_MANIFEST'
REMOTE_HEADER
    cat "$manifest_path"
    printf 'MANAGED_SURFACE_MANIFEST\n'
}

remote_results="$(emit_remote_script "$manifest_file" | ssh "$SSH_TARGET" 'bash -seu')"

pending_sync=false
compliant_count=0
pending_count=0
missing_count=0

while IFS=$'\t' read -r relative_path local_hash remote_hash; do
    [[ -n "$relative_path" ]] || continue

    if [[ "$remote_hash" == "NOT_FOUND" ]]; then
        notice "$relative_path not found on server (will be created during deploy)"
        pending_sync=true
        pending_count=$((pending_count + 1))
        missing_count=$((missing_count + 1))
        continue
    fi

    if [[ "$local_hash" != "$remote_hash" ]]; then
        notice "$relative_path pending sync (git desired state differs from deployed server file)"
        echo "  Local:  $local_hash"
        echo "  Server: $remote_hash"
        pending_sync=true
        pending_count=$((pending_count + 1))
        continue
    fi

    notice "$relative_path compliant ✅"
    compliant_count=$((compliant_count + 1))
done <<< "$remote_results"

notice "Managed surface summary: compared=$manifest_count compliant=$compliant_count pending=$pending_count missing_on_server=$missing_count"

if [[ -n "$STATE_FILE" ]]; then
    cat > "$STATE_FILE" <<EOF
PENDING_SYNC=$pending_sync
COMPARED_FILES=$manifest_count
COMPLIANT_COUNT=$compliant_count
PENDING_COUNT=$pending_count
MISSING_COUNT=$missing_count
EOF
fi
