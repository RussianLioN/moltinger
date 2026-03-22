#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MOLTIS_TEST_API_SCRIPT="${MOLTIS_TEST_API_SCRIPT:-$PROJECT_ROOT/scripts/test-moltis-api.sh}"
EXPECTED_PROVIDER="${EXPECTED_PROVIDER:-openai-codex}"
EXPECTED_MODEL="${EXPECTED_MODEL:-openai-codex::gpt-5.4}"
CHAT_WAIT_MS="${CHAT_WAIT_MS:-90000}"

declare -a REQUESTED_SURFACES=()

usage() {
    cat <<'EOF'
Usage: moltis-exercised-surface-matrix.sh [--base-url <url>] [--surface <name>]...

Run exercised-surface proofs for tracked Moltis capabilities. Supported surfaces:
- browser
- search
- repo-context

By default, all three surfaces are exercised in order.
EOF
}

require_command() {
    local command="$1"
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "moltis-exercised-surface-matrix.sh: required command not found: $command" >&2
        exit 2
    fi
}

normalize_surface() {
    case "${1:-}" in
        browser) printf 'browser\n' ;;
        search) printf 'search\n' ;;
        repo-context|repo_context|memory|memory-search) printf 'repo-context\n' ;;
        *)
            echo "moltis-exercised-surface-matrix.sh: unsupported surface: ${1:-}" >&2
            exit 2
            ;;
    esac
}

surface_prompt() {
    case "$1" in
        browser) printf 'Используй browser, открой https://docs.moltis.org/ и ответь только заголовком страницы.\n' ;;
        search) printf 'Используй search и найди официальный домен документации Moltis. Ответь только доменом.\n' ;;
        repo-context) printf 'Используй memory_search. В каком пути внутри runtime Moltis находится checkout репозитория? Ответь только одним путем.\n' ;;
    esac
}

surface_expected_reply() {
    case "$1" in
        browser) printf 'Introduction - Moltis Documentation\n' ;;
        search) printf 'docs.moltis.org\n' ;;
        repo-context) printf '/server\n' ;;
    esac
}

run_surface() {
    local surface="$1"
    local prompt expected_reply
    prompt="$(surface_prompt "$surface")"
    expected_reply="$(surface_expected_reply "$surface")"

    echo "Running exercised-surface proof: $surface"
    EXPECTED_PROVIDER="$EXPECTED_PROVIDER" \
    EXPECTED_MODEL="$EXPECTED_MODEL" \
    EXPECTED_REPLY_TEXT="$expected_reply" \
    CHAT_WAIT_MS="$CHAT_WAIT_MS" \
    MOLTIS_URL="$MOLTIS_URL" \
    bash "$MOLTIS_TEST_API_SCRIPT" "$prompt"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            MOLTIS_URL="${2:-}"
            shift 2
            ;;
        --surface)
            REQUESTED_SURFACES+=("$(normalize_surface "${2:-}")")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-exercised-surface-matrix.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

main() {
    require_command bash
    require_command jq
    require_command node

    if [[ ! -x "$MOLTIS_TEST_API_SCRIPT" ]]; then
        echo "moltis-exercised-surface-matrix.sh: API smoke script is missing or not executable: $MOLTIS_TEST_API_SCRIPT" >&2
        exit 2
    fi

    if [[ ${#REQUESTED_SURFACES[@]} -eq 0 ]]; then
        REQUESTED_SURFACES=(browser search repo-context)
    fi

    local surface
    for surface in "${REQUESTED_SURFACES[@]}"; do
        run_surface "$surface"
    done

    echo "Exercised-surface matrix completed successfully."
}

main
