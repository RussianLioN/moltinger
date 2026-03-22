#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MOLTIS_CONTAINER="${MOLTIS_CONTAINER:-moltis}"
MOLTIS_TEST_API_SCRIPT="${MOLTIS_TEST_API_SCRIPT:-$PROJECT_ROOT/scripts/test-moltis-api.sh}"
EXPECTED_AUTH_PROVIDER="${EXPECTED_AUTH_PROVIDER:-openai-codex}"
EXPECTED_PROVIDER="${EXPECTED_PROVIDER:-openai-codex}"
EXPECTED_MODEL="${EXPECTED_MODEL:-openai-codex::gpt-5.4}"
EXPECTED_REPLY_TEXT="${EXPECTED_REPLY_TEXT:-OK}"
SMOKE_PROMPT="${SMOKE_PROMPT:-Reply with exactly OK and nothing else.}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"
CHAT_WAIT_MS="${CHAT_WAIT_MS:-90000}"
RESTART_SURVIVAL=false

usage() {
    cat <<'EOF'
Usage: moltis-canonical-smoke.sh [--restart-survival] [--base-url <url>] [--container <name>]

Run canonical Moltis smoke proof against the current runtime and require:
- local health to return HTTP 200
- live auth status to keep the expected provider valid
- chat execution to complete on the expected provider/model

With --restart-survival, the script restarts the target container and repeats the
same proof after the container becomes healthy again.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restart-survival)
            RESTART_SURVIVAL=true
            shift
            ;;
        --base-url)
            MOLTIS_URL="${2:-}"
            shift 2
            ;;
        --container)
            MOLTIS_CONTAINER="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-canonical-smoke.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

require_command() {
    local command="$1"
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "moltis-canonical-smoke.sh: required command not found: $command" >&2
        exit 2
    fi
}

container_state() {
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "not_found"
}

health_status_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${MOLTIS_URL%/}/health" 2>/dev/null || echo "000"
}

wait_for_runtime_ready() {
    local phase="$1"
    local elapsed=0

    echo "Waiting for Moltis runtime during phase: $phase"
    while [[ $elapsed -lt $HEALTH_TIMEOUT ]]; do
        local state http_code
        state="$(container_state)"
        http_code="$(health_status_code)"

        if [[ "$http_code" == "200" && ( "$state" == "healthy" || "$state" == "running" ) ]]; then
            echo "Runtime ready for $phase (state=$state, http=$http_code)"
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "moltis-canonical-smoke.sh: runtime did not become ready for $phase within ${HEALTH_TIMEOUT}s" >&2
    echo "Last observed state=$(container_state) http=$(health_status_code)" >&2
    return 1
}

verify_auth_status() {
    local phase="$1"
    local auth_status

    echo "Checking provider auth status during phase: $phase"
    auth_status="$(docker exec "$MOLTIS_CONTAINER" moltis auth status 2>&1 || true)"
    printf '%s\n' "$auth_status"

    if printf '%s\n' "$auth_status" | grep -F "$EXPECTED_AUTH_PROVIDER" | grep -F '[valid' >/dev/null 2>&1; then
        echo "Provider auth proof OK for $phase: $EXPECTED_AUTH_PROVIDER"
        return 0
    fi

    echo "moltis-canonical-smoke.sh: expected valid auth provider not found during $phase: $EXPECTED_AUTH_PROVIDER" >&2
    return 1
}

run_chat_proof() {
    local phase="$1"

    echo "Running canonical chat proof during phase: $phase"
    EXPECTED_PROVIDER="$EXPECTED_PROVIDER" \
    EXPECTED_MODEL="$EXPECTED_MODEL" \
    EXPECTED_REPLY_TEXT="$EXPECTED_REPLY_TEXT" \
    CHAT_WAIT_MS="$CHAT_WAIT_MS" \
    MOLTIS_URL="$MOLTIS_URL" \
    bash "$MOLTIS_TEST_API_SCRIPT" "$SMOKE_PROMPT"
}

restart_container() {
    echo "Restarting container for restart-survival proof: $MOLTIS_CONTAINER"
    docker restart "$MOLTIS_CONTAINER" >/dev/null
}

main() {
    require_command bash
    require_command curl
    require_command docker
    require_command jq
    require_command node

    if [[ ! -x "$MOLTIS_TEST_API_SCRIPT" ]]; then
        echo "moltis-canonical-smoke.sh: API smoke script is missing or not executable: $MOLTIS_TEST_API_SCRIPT" >&2
        exit 2
    fi

    wait_for_runtime_ready "initial"
    verify_auth_status "initial"
    run_chat_proof "initial"

    if [[ "$RESTART_SURVIVAL" == "true" ]]; then
        restart_container
        wait_for_runtime_ready "post-restart"
        verify_auth_status "post-restart"
        run_chat_proof "post-restart"
    fi

    echo "Canonical Moltis smoke proof completed successfully."
}

main
