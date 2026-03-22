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

to_json_array() {
    if [[ $# -eq 0 ]]; then
        printf '[]'
        return
    fi

    printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

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

jq -n \
    --arg runtime_home "$RUNTIME_HOME" \
    --arg mode "$([[ "$APPLY_CHANGES" == true ]] && echo apply || echo dry-run)" \
    --argjson candidates "$(to_json_array "${CANDIDATES[@]}")" \
    --argjson removed "$(to_json_array "${REMOVED[@]}")" \
    --argjson skipped "$(to_json_array "${SKIPPED[@]}")" \
    '{
        runtime_home: $runtime_home,
        mode: $mode,
        candidates: $candidates,
        candidate_count: ($candidates | length),
        removed: $removed,
        removed_count: ($removed | length),
        skipped: $skipped,
        skipped_count: ($skipped | length)
    }'
