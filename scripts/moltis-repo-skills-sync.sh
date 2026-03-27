#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SOURCE_ROOT="${MOLTIS_REPO_SKILLS_SOURCE_ROOT:-/server/skills}"
TARGET_ROOT="${MOLTIS_RUNTIME_SKILLS_ROOT:-/home/moltis/.moltis/skills}"
MANIFEST_PATH="${MOLTIS_RUNTIME_SKILLS_MANIFEST:-}"
MANIFEST_EXPLICIT=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options]

Sync Git-tracked repo skills into the runtime-discovered Moltis skills directory.

Options:
  --source-root PATH   Source directory that contains repo skill folders (default: $SOURCE_ROOT)
  --target-root PATH   Runtime-discovered target directory (default: $TARGET_ROOT)
  --manifest PATH      File that tracks repo-managed installed skills
                       (default: <dirname(target-root)>/.repo-managed-skills.txt)
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

read_manifest() {
    local manifest="$1"
    if [[ ! -f "$manifest" ]]; then
        return 0
    fi

    grep -v '^[[:space:]]*$' "$manifest" || true
}

sync_skill() {
    local source_dir="$1"
    local target_dir="$2"
    local skill_name="$3"
    local staging_root="$4"
    local staging_dir="$staging_root/$skill_name"

    mkdir -p "$staging_dir"
    cp -a "$source_dir/." "$staging_dir/"

    rm -rf "$target_dir/$skill_name"
    mv "$staging_dir" "$target_dir/$skill_name"
}

main() {
    parse_args "$@"

    SOURCE_ROOT="$(normalize_path "$SOURCE_ROOT")"
    TARGET_ROOT="$(normalize_path "$TARGET_ROOT")"
    if [[ $MANIFEST_EXPLICIT -eq 0 && -z "$MANIFEST_PATH" ]]; then
        MANIFEST_PATH="$(dirname "$TARGET_ROOT")/.repo-managed-skills.txt"
    fi
    MANIFEST_PATH="$(normalize_path "$MANIFEST_PATH")"

    if [[ ! -d "$SOURCE_ROOT" ]]; then
        log_error "Source root does not exist: $SOURCE_ROOT"
        exit 1
    fi

    mkdir -p "$TARGET_ROOT"
    mkdir -p "$(dirname "$MANIFEST_PATH")"

    local staging_root
    staging_root="$(mktemp -d "$TARGET_ROOT/.repo-sync.XXXXXX")"
    trap 'rm -rf "$staging_root"' EXIT

    local -a previous_managed=()
    local manifest_entry
    while IFS= read -r manifest_entry; do
        previous_managed+=("$manifest_entry")
    done < <(read_manifest "$MANIFEST_PATH")

    local -a current_managed=()
    local -a skill_dirs=()
    local skill_dir
    shopt -s nullglob
    for skill_dir in "$SOURCE_ROOT"/*; do
        [[ -d "$skill_dir" ]] || continue
        [[ -f "$skill_dir/SKILL.md" ]] || continue
        skill_dirs+=("$skill_dir")
    done
    shopt -u nullglob

    if [[ ${#skill_dirs[@]} -gt 1 ]]; then
        IFS=$'\n' skill_dirs=($(printf '%s\n' "${skill_dirs[@]}" | sort))
        unset IFS
    fi

    local skill_name
    for skill_dir in "${skill_dirs[@]}"; do
        skill_name="$(basename "$skill_dir")"
        current_managed+=("$skill_name")
        sync_skill "$skill_dir" "$TARGET_ROOT" "$skill_name" "$staging_root"
    done

    for skill_name in "${previous_managed[@]}"; do
        if ! path_is_listed "$skill_name" "${current_managed[@]}"; then
            rm -rf "$TARGET_ROOT/$skill_name"
        fi
    done

    : >"$MANIFEST_PATH"
    if [[ ${#current_managed[@]} -gt 0 ]]; then
        printf '%s\n' "${current_managed[@]}" >"$MANIFEST_PATH"
    fi
}

main "$@"
