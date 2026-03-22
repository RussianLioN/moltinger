#!/usr/bin/env bash
set -euo pipefail

RUNTIME_HOME="${MOLTIS_RUNTIME_HOME:-/home/moltis/.moltis}"
APPLY_CHANGES=false

usage() {
    cat <<'EOF'
Usage: moltis-runtime-context-cleanup.sh [--runtime-home <path>] [--apply]

Safely remove known stale Moltis runtime-test artifacts from ~/.moltis without
touching active session, memory, or provider state.

Default mode is dry-run and emits a JSON report to stdout.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime-home)
            RUNTIME_HOME="${2:-}"
            shift 2
            ;;
        --apply)
            APPLY_CHANGES=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-runtime-context-cleanup.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -d "$RUNTIME_HOME" ]]; then
    echo "moltis-runtime-context-cleanup.sh: runtime home not found: $RUNTIME_HOME" >&2
    exit 2
fi

collect_candidates() {
    {
        find "$RUNTIME_HOME" -mindepth 1 -maxdepth 1 -type d -name 'oauth-runtime-test-*' -print
        if [[ -d "$RUNTIME_HOME/oauth-config" ]]; then
            find "$RUNTIME_HOME/oauth-config" -maxdepth 1 -type f -name '*.runtime-test.bak' -print
        fi
    } | LC_ALL=C sort -u
}

is_allowed_candidate() {
    local candidate="$1"
    case "$candidate" in
        "$RUNTIME_HOME"/oauth-runtime-test-*|"$RUNTIME_HOME"/oauth-config/*.runtime-test.bak)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mapfile -t CANDIDATES < <(collect_candidates)
REMOVED=()
SKIPPED=()

if $APPLY_CHANGES; then
    for candidate in "${CANDIDATES[@]}"; do
        if is_allowed_candidate "$candidate"; then
            rm -rf -- "$candidate"
            REMOVED+=("$candidate")
        else
            SKIPPED+=("$candidate")
        fi
    done
fi

json_escape() {
    local value="${1-}"
    awk -v s="$value" 'BEGIN {
        gsub(/\\/,"\\\\",s)
        gsub(/"/,"\\\"",s)
        gsub(/\t/,"\\t",s)
        gsub(/\r/,"\\r",s)
        gsub(/\n/,"\\n",s)
        printf "%s", s
    }'
}

json_print_array() {
    local item first=true
    printf '['
    for item in "$@"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '"'
        json_escape "$item"
        printf '"'
    done
    printf ']'
}

print_report() {
    local mode="$1"

    printf '{\n'
    printf '  "runtime_home": "'
    json_escape "$RUNTIME_HOME"
    printf '",\n'
    printf '  "mode": "'
    json_escape "$mode"
    printf '",\n'
    printf '  "candidates": '
    json_print_array "${CANDIDATES[@]}"
    printf ',\n'
    printf '  "candidate_count": %s,\n' "${#CANDIDATES[@]}"
    printf '  "removed": '
    json_print_array "${REMOVED[@]}"
    printf ',\n'
    printf '  "removed_count": %s,\n' "${#REMOVED[@]}"
    printf '  "skipped": '
    json_print_array "${SKIPPED[@]}"
    printf ',\n'
    printf '  "skipped_count": %s\n' "${#SKIPPED[@]}"
    printf '}\n'
}

print_report "$([[ "$APPLY_CHANGES" == true ]] && echo apply || echo dry-run)"
