#!/usr/bin/env bash
# Sync the GitOps-managed deploy surface from the current checkout to the remote host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    cat >&2 <<'EOF'
Usage:
  gitops-sync-managed-surface.sh \
    --ssh-user <user> \
    --ssh-host <host> \
    --deploy-path <path> \
    [--project-root <path>] \
    [--dry-run]
EOF
}

notice() {
    echo "::notice::$*"
}

warn() {
    echo "::warning::$*"
}

error() {
    echo "::error::$*" >&2
}

shell_quote() {
    printf '%q' "$1"
}

SSH_USER=""
SSH_HOST=""
DEPLOY_PATH=""
SOURCE_ROOT="$PROJECT_ROOT"
DRY_RUN=false

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
        --dry-run)
            DRY_RUN=true
            shift
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

if [[ "$DRY_RUN" != "true" ]]; then
    bash "$SCRIPT_DIR/prod-mutation-guard.sh" \
        --action "gitops-sync-managed-surface" \
        --target-host "$SSH_HOST" \
        --target-path "$DEPLOY_PATH"
fi

run_local() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '+'
        for arg in "$@"; do
            printf ' %q' "$arg"
        done
        printf '\n'
        return 0
    fi

    "$@"
}

run_remote() {
    local remote_cmd="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '+ ssh %q %s\n' "$SSH_TARGET" "$remote_cmd"
        return 0
    fi

    ssh "$SSH_TARGET" "$remote_cmd"
}

sync_file() {
    local local_path="$1"
    local remote_path="$2"

    if [[ ! -f "$local_path" ]]; then
        error "Required managed file is missing: $local_path"
        exit 1
    fi

    run_local scp "$local_path" "${SSH_TARGET}:${remote_path}"
}

sync_directory_contents() {
    local local_dir="$1"
    local remote_dir="$2"
    local empty_notice="$3"
    local -a entries=()

    if [[ ! -d "$local_dir" ]]; then
        warn "Managed directory is missing locally: $local_dir"
        return 0
    fi

    while IFS= read -r -d '' entry; do
        entries+=("$entry")
    done < <(find "$local_dir" -mindepth 1 -maxdepth 1 ! -name '.*' -print0)

    if [[ ${#entries[@]} -eq 0 ]]; then
        notice "$empty_notice"
        return 0
    fi

    run_remote "mkdir -p $(shell_quote "$remote_dir")"
    run_local scp -r "${entries[@]}" "${SSH_TARGET}:${remote_dir}/"
}

align_remote_shell_entrypoints() {
    local manifest_path="$SOURCE_ROOT/scripts/manifest.json"
    local -a remote_paths=()
    local remote_cmd="chmod +x"

    if [[ ! -f "$manifest_path" ]]; then
        warn "scripts/manifest.json not found; skipping remote shell entrypoint chmod alignment"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        error "jq is required to align remote shell entrypoint permissions"
        exit 1
    fi

    while IFS= read -r script_name; do
        [[ -n "$script_name" ]] || continue
        remote_paths+=("$DEPLOY_PATH/scripts/$script_name")
    done < <(jq -r '.scripts | to_entries[] | select(.value.entrypoint == true and (.key | endswith(".sh"))) | .key' "$manifest_path")

    if [[ ${#remote_paths[@]} -eq 0 ]]; then
        return 0
    fi

    for remote_path in "${remote_paths[@]}"; do
        remote_cmd+=" $(shell_quote "$remote_path")"
    done
    remote_cmd+=" 2>/dev/null || true"

    run_remote "$remote_cmd"
}

cleanup_runtime_managed_auth_files() {
    local remote_cmd="rm -f"
    local runtime_file

    for runtime_file in provider_keys.json oauth_tokens.json credentials.json; do
        remote_cmd+=" $(shell_quote "$DEPLOY_PATH/config/$runtime_file")"
    done

    run_remote "$remote_cmd"
}

notice "Syncing GitOps-managed deploy surface from $SOURCE_ROOT to ${SSH_TARGET}:${DEPLOY_PATH}"

sync_file "$SOURCE_ROOT/docker-compose.yml" "$DEPLOY_PATH/docker-compose.yml"
sync_file "$SOURCE_ROOT/docker-compose.prod.yml" "$DEPLOY_PATH/docker-compose.prod.yml"

run_remote "mkdir -p $(shell_quote "$DEPLOY_PATH/config")"
sync_directory_contents "$SOURCE_ROOT/config" "$DEPLOY_PATH/config" "No config files to sync"
cleanup_runtime_managed_auth_files

run_remote "mkdir -p $(shell_quote "$DEPLOY_PATH/scripts")"
sync_directory_contents "$SOURCE_ROOT/scripts" "$DEPLOY_PATH/scripts" "No scripts to sync"
align_remote_shell_entrypoints

sync_directory_contents "$SOURCE_ROOT/systemd" "$DEPLOY_PATH/systemd" "No systemd units to sync"

notice "GitOps-managed deploy surface synced successfully"
