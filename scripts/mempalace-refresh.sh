#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mempalace-common.sh
source "$SCRIPT_DIR/mempalace-common.sh"

LIST_ONLY=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list-only)
                LIST_ONLY=true
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"

    if [[ "$LIST_ONLY" == true ]]; then
        collect_curated_corpus_paths
        return 0
    fi

    ensure_bootstrap_ready
    acquire_refresh_lock

    log_info "Rebuilding curated MemPalace corpus snapshot"
    rebuild_curated_corpus_snapshot

    rm -rf "$MEMPALACE_BUILD_PATH"
    mkdir -p "$MEMPALACE_BUILD_PATH"

    log_info "Initializing curated corpus metadata in $MEMPALACE_CORPUS_DIR"
    # mempalace==3.0.0 still prompts for room approval during `init` even with `--yes`.
    # Accept the default generated layout so refresh stays non-interactive and deterministic.
    printf '\n' | run_mempalace "$MEMPALACE_BUILD_PATH" init "$MEMPALACE_CORPUS_DIR" --yes

    log_info "Mining curated project memory into $MEMPALACE_BUILD_PATH"
    run_mempalace "$MEMPALACE_BUILD_PATH" mine "$MEMPALACE_CORPUS_DIR" --wing "$MEMPALACE_DEFAULT_WING" --agent "$MEMPALACE_DEFAULT_AGENT"

    if ! path_has_entries "$MEMPALACE_BUILD_PATH"; then
        die "MemPalace build output is empty: $MEMPALACE_BUILD_PATH"
    fi

    swap_built_palace

    local file_count
    file_count="$(collect_curated_corpus_paths | wc -l | tr -d ' ')"
    log_info "MemPalace refresh complete"
    log_info "indexed_files=$file_count"
    log_info "palace_path=$MEMPALACE_PALACE_PATH"
}

main "$@"
