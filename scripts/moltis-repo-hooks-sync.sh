#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SOURCE_ROOT="${MOLTIS_REPO_HOOKS_SOURCE_ROOT:-/server/.moltis/hooks}"
TARGET_ROOT="${MOLTIS_RUNTIME_PROJECT_HOOKS_ROOT:-/home/moltis/.moltis/.moltis/hooks}"
MANIFEST_PATH="${MOLTIS_RUNTIME_PROJECT_HOOKS_MANIFEST:-}"
MANIFEST_EXPLICIT=0
PRUNE_UNMANAGED="${MOLTIS_RUNTIME_HOOKS_PRUNE_UNMANAGED:-0}"
STAGING_ROOT=""

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options]

Sync Git-tracked repo-managed Moltis hook bundles into the runtime-discovered
project hooks directory.

Options:
  --source-root PATH   Source directory that contains repo hook folders
                       (default: $SOURCE_ROOT)
  --target-root PATH   Runtime-discovered target directory
                       (default: $TARGET_ROOT)
  --manifest PATH      File that tracks repo-managed installed hooks
                       (default: <dirname(target-root)>/.repo-managed-hooks.txt)
  --prune-unmanaged    Remove runtime hooks that are not present in source root
                       (default: disabled unless MOLTIS_RUNTIME_HOOKS_PRUNE_UNMANAGED=1)
  -h, --help           Show this help
EOF
}

log_error() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
}

normalize_path() {
    local path="$1"
    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done
    printf '%s\n' "$path"
}

path_is_listed() {
    local needle="$1"
    shift
    local entry
    for entry in "$@"; do
        if [[ "$entry" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source-root)
                [[ $# -ge 2 ]] || {
                    log_error "--source-root requires a value"
                    exit 2
                }
                SOURCE_ROOT="$2"
                shift 2
                ;;
            --target-root)
                [[ $# -ge 2 ]] || {
                    log_error "--target-root requires a value"
                    exit 2
                }
                TARGET_ROOT="$2"
                shift 2
                ;;
            --manifest)
                [[ $# -ge 2 ]] || {
                    log_error "--manifest requires a value"
                    exit 2
                }
                MANIFEST_PATH="$2"
                MANIFEST_EXPLICIT=1
                shift 2
                ;;
            --prune-unmanaged)
                PRUNE_UNMANAGED=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 2
                ;;
        esac
    done
}

cleanup_staging_root() {
    if [[ -n "${STAGING_ROOT:-}" ]]; then
        rm -rf "$STAGING_ROOT"
    fi
}

read_manifest() {
    local manifest="$1"
    if [[ ! -f "$manifest" ]]; then
        return 0
    fi

    grep -v '^[[:space:]]*$' "$manifest" || true
}

sync_hook() {
    local source_dir="$1"
    local target_dir="$2"
    local hook_name="$3"
    local staging_root="$4"
    local staging_dir="$staging_root/$hook_name"

    mkdir -p "$staging_dir"
    cp -a "$source_dir/." "$staging_dir/"

    rm -rf "$target_dir/$hook_name"
    mv "$staging_dir" "$target_dir/$hook_name"
}

main() {
    parse_args "$@"

    SOURCE_ROOT="$(normalize_path "$SOURCE_ROOT")"
    TARGET_ROOT="$(normalize_path "$TARGET_ROOT")"
    if [[ $MANIFEST_EXPLICIT -eq 0 && -z "$MANIFEST_PATH" ]]; then
        MANIFEST_PATH="$(dirname "$TARGET_ROOT")/.repo-managed-hooks.txt"
    fi
    MANIFEST_PATH="$(normalize_path "$MANIFEST_PATH")"

    if [[ ! -d "$SOURCE_ROOT" ]]; then
        log_error "Source root does not exist: $SOURCE_ROOT"
        exit 1
    fi

    mkdir -p "$TARGET_ROOT"
    mkdir -p "$(dirname "$MANIFEST_PATH")"

    STAGING_ROOT="$(mktemp -d "$TARGET_ROOT/.repo-sync.XXXXXX")"
    trap cleanup_staging_root EXIT

    local -a previous_managed=()
    local manifest_entry
    while IFS= read -r manifest_entry; do
        previous_managed+=("$manifest_entry")
    done < <(read_manifest "$MANIFEST_PATH")

    local -a current_managed=()
    local -a hook_dirs=()
    local hook_dir
    shopt -s nullglob
    for hook_dir in "$SOURCE_ROOT"/*; do
        [[ -d "$hook_dir" ]] || continue
        [[ -f "$hook_dir/HOOK.md" ]] || continue
        hook_dirs+=("$hook_dir")
    done
    shopt -u nullglob

    if [[ ${#hook_dirs[@]} -gt 1 ]]; then
        IFS=$'\n' hook_dirs=($(printf '%s\n' "${hook_dirs[@]}" | sort))
        unset IFS
    fi

    local hook_name
    for hook_dir in "${hook_dirs[@]}"; do
        hook_name="$(basename "$hook_dir")"
        current_managed+=("$hook_name")
        sync_hook "$hook_dir" "$TARGET_ROOT" "$hook_name" "$STAGING_ROOT"
    done

    for hook_name in "${previous_managed[@]}"; do
        if ! path_is_listed "$hook_name" "${current_managed[@]}"; then
            rm -rf "$TARGET_ROOT/$hook_name"
        fi
    done

    if [[ "$PRUNE_UNMANAGED" == "1" ]]; then
        local -a runtime_hook_dirs=()
        local runtime_hook_dir runtime_hook_name
        shopt -s nullglob
        for runtime_hook_dir in "$TARGET_ROOT"/*; do
            [[ -d "$runtime_hook_dir" ]] || continue
            [[ -f "$runtime_hook_dir/HOOK.md" ]] || continue
            runtime_hook_dirs+=("$runtime_hook_dir")
        done
        shopt -u nullglob

        for runtime_hook_dir in "${runtime_hook_dirs[@]}"; do
            runtime_hook_name="$(basename "$runtime_hook_dir")"
            if ! path_is_listed "$runtime_hook_name" "${current_managed[@]}"; then
                rm -rf "$runtime_hook_dir"
            fi
        done
    fi

    : >"$MANIFEST_PATH"
    if [[ ${#current_managed[@]} -gt 0 ]]; then
        printf '%s\n' "${current_managed[@]}" >"$MANIFEST_PATH"
    fi
}

main "$@"
