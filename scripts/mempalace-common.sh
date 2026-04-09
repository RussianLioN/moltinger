#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${MEMPALACE_PROJECT_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"

MEMPALACE_VERSION="${MEMPALACE_VERSION_OVERRIDE:-3.0.0}"
MEMPALACE_STATE_ROOT="${MEMPALACE_STATE_ROOT_OVERRIDE:-${XDG_DATA_HOME:-$HOME/.local/share}/moltinger/mempalace}"
MEMPALACE_HOME="${MEMPALACE_HOME_OVERRIDE:-$MEMPALACE_STATE_ROOT/home}"
MEMPALACE_CONFIG_DIR="${MEMPALACE_HOME}/.mempalace"
MEMPALACE_CONFIG_FILE="${MEMPALACE_CONFIG_DIR}/config.json"
MEMPALACE_VENV_DIR="${MEMPALACE_STATE_ROOT}/venv"
MEMPALACE_VENV_BIN="${MEMPALACE_VENV_DIR}/bin"
MEMPALACE_CLI="${MEMPALACE_VENV_BIN}/mempalace"
MEMPALACE_PYTHON="${MEMPALACE_VENV_BIN}/python"
MEMPALACE_PALACE_PATH="${MEMPALACE_PALACE_PATH_OVERRIDE:-${MEMPALACE_STATE_ROOT}/palace}"
MEMPALACE_BUILD_PATH="${MEMPALACE_BUILD_PATH_OVERRIDE:-${MEMPALACE_STATE_ROOT}/palace.build}"
MEMPALACE_PREVIOUS_PATH="${MEMPALACE_PREVIOUS_PATH_OVERRIDE:-${MEMPALACE_STATE_ROOT}/palace.previous}"
MEMPALACE_LOCK_DIR="${MEMPALACE_LOCK_DIR_OVERRIDE:-${MEMPALACE_STATE_ROOT}/refresh.lock}"
MEMPALACE_TMP_ROOT="${MEMPALACE_TMP_ROOT_OVERRIDE:-${PROJECT_ROOT}/.tmp/mempalace}"
MEMPALACE_CORPUS_DIR="${MEMPALACE_CORPUS_DIR_OVERRIDE:-${MEMPALACE_TMP_ROOT}/corpus}"
MEMPALACE_CORPUS_MANIFEST="${MEMPALACE_CORPUS_MANIFEST_OVERRIDE:-${PROJECT_ROOT}/scripts/mempalace-corpus.txt}"
MEMPALACE_DEFAULT_WING="${MEMPALACE_DEFAULT_WING_OVERRIDE:-moltinger}"
MEMPALACE_DEFAULT_AGENT="${MEMPALACE_DEFAULT_AGENT_OVERRIDE:-moltinger-mempalace}"

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

write_wrapper_config() {
    mkdir -p "$MEMPALACE_CONFIG_DIR"
    cat >"$MEMPALACE_CONFIG_FILE" <<EOF
{
  "palace_path": "${MEMPALACE_PALACE_PATH}",
  "collection_name": "mempalace_drawers"
}
EOF
}

mempalace_current_version() {
    "$MEMPALACE_PYTHON" - <<'PY'
import importlib.metadata
print(importlib.metadata.version("mempalace"))
PY
}

run_mempalace() {
    local palace_path="$1"
    shift

    HOME="$MEMPALACE_HOME" \
    MEMPALACE_PALACE_PATH="$palace_path" \
    "$MEMPALACE_CLI" --palace "$palace_path" "$@"
}

path_has_entries() {
    local target_path="$1"
    local first_entry

    [[ -d "$target_path" ]] || return 1
    first_entry="$(find "$target_path" -mindepth 1 -print -quit 2>/dev/null || true)"
    [[ -n "$first_entry" ]]
}

ensure_bootstrap_ready() {
    [[ -x "$MEMPALACE_CLI" ]] || die "MemPalace wrapper is not bootstrapped. Run ./scripts/mempalace-bootstrap.sh first."
    [[ -x "$MEMPALACE_PYTHON" ]] || die "MemPalace python runtime is missing. Run ./scripts/mempalace-bootstrap.sh first."

    write_wrapper_config

    local current_version
    current_version="$(mempalace_current_version 2>/dev/null || true)"
    [[ "$current_version" == "$MEMPALACE_VERSION" ]] || die "MemPalace version drift detected (expected ${MEMPALACE_VERSION}, got ${current_version:-missing}). Run ./scripts/mempalace-bootstrap.sh again."
}

ensure_index_ready() {
    ensure_bootstrap_ready

    if ! path_has_entries "$MEMPALACE_PALACE_PATH"; then
        die "MemPalace index is not built yet. Run ./scripts/mempalace-refresh.sh first."
    fi
}

load_corpus_manifest() {
    [[ -f "$MEMPALACE_CORPUS_MANIFEST" ]] || die "Missing corpus manifest: $MEMPALACE_CORPUS_MANIFEST"

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|'#'*) continue ;;
            *) printf '%s\n' "$line" ;;
        esac
    done <"$MEMPALACE_CORPUS_MANIFEST"
}

collect_curated_corpus_paths() {
    local tmp_file
    tmp_file="$(mktemp "${TMPDIR:-/tmp}/mempalace-corpus.XXXXXX")"

    local entry
    while IFS= read -r entry; do
        case "$entry" in
            '!'*)
                continue
                ;;
            MEMORY.md|SESSION_SUMMARY.md)
                [[ -f "$PROJECT_ROOT/$entry" ]] || die "Required project memory artifact missing: $entry"
                printf '%s\n' "$entry" >>"$tmp_file"
                ;;
            'docs/**/*.md')
                if [[ -d "$PROJECT_ROOT/docs" ]]; then
                    (cd "$PROJECT_ROOT" && find docs -type f -name '*.md' -print) >>"$tmp_file"
                fi
                ;;
            'knowledge/**/*.md')
                if [[ -d "$PROJECT_ROOT/knowledge" ]]; then
                    (cd "$PROJECT_ROOT" && find knowledge -type f -name '*.md' -print) >>"$tmp_file"
                fi
                ;;
            'specs/**/spec.md')
                if [[ -d "$PROJECT_ROOT/specs" ]]; then
                    (cd "$PROJECT_ROOT" && find specs -type f -name 'spec.md' -print) >>"$tmp_file"
                fi
                ;;
            'specs/**/plan.md')
                if [[ -d "$PROJECT_ROOT/specs" ]]; then
                    (cd "$PROJECT_ROOT" && find specs -type f -name 'plan.md' -print) >>"$tmp_file"
                fi
                ;;
            'specs/**/tasks.md')
                if [[ -d "$PROJECT_ROOT/specs" ]]; then
                    (cd "$PROJECT_ROOT" && find specs -type f -name 'tasks.md' -print) >>"$tmp_file"
                fi
                ;;
            *)
                die "Unsupported MemPalace corpus manifest entry: $entry"
                ;;
        esac
    done < <(load_corpus_manifest)

    local path excluded
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        excluded=false
        while IFS= read -r entry; do
            case "$entry" in
                "!$path")
                    excluded=true
                    break
                    ;;
            esac
        done < <(load_corpus_manifest)
        [[ "$excluded" == true ]] || printf '%s\n' "$path"
    done < <(sort -u "$tmp_file")

    rm -f "$tmp_file"
}

rebuild_curated_corpus_snapshot() {
    rm -rf "$MEMPALACE_CORPUS_DIR"
    mkdir -p "$MEMPALACE_CORPUS_DIR"

    local relative source target
    while IFS= read -r relative; do
        source="$PROJECT_ROOT/$relative"
        target="$MEMPALACE_CORPUS_DIR/$relative"
        mkdir -p "$(dirname "$target")"
        cp "$source" "$target"
    done < <(collect_curated_corpus_paths)
}

acquire_refresh_lock() {
    mkdir -p "$MEMPALACE_STATE_ROOT"
    mkdir "$MEMPALACE_LOCK_DIR" 2>/dev/null || die "Another MemPalace refresh is already running: $MEMPALACE_LOCK_DIR"
    trap 'rm -rf "$MEMPALACE_LOCK_DIR"' EXIT
}

swap_built_palace() {
    rm -rf "$MEMPALACE_PREVIOUS_PATH"
    if [[ -d "$MEMPALACE_PALACE_PATH" ]]; then
        mv "$MEMPALACE_PALACE_PATH" "$MEMPALACE_PREVIOUS_PATH"
    fi
    mv "$MEMPALACE_BUILD_PATH" "$MEMPALACE_PALACE_PATH"
    rm -rf "$MEMPALACE_PREVIOUS_PATH"
}
