#!/usr/bin/env bash
# Fail-closed guard for production-mutating entrypoints.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  prod-mutation-guard.sh \
    --action <name> \
    [--target-host <host>] \
    [--target-path <path>] \
    [--expected-ref <ref>] \
    [--expected-sha <sha>]
EOF
}

ACTION=""
TARGET_HOST=""
EXPECTED_REF=""
EXPECTED_SHA=""
TARGET_PATHS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action)
            ACTION="${2:-}"
            shift 2
            ;;
        --target-host)
            TARGET_HOST="${2:-}"
            shift 2
            ;;
        --target-path)
            TARGET_PATHS+=("${2:-}")
            shift 2
            ;;
        --expected-ref)
            EXPECTED_REF="${2:-}"
            shift 2
            ;;
        --expected-sha)
            EXPECTED_SHA="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "prod-mutation-guard.sh: unknown argument: $1" >&2
            usage
            exit 64
            ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    echo "prod-mutation-guard.sh: --action is required" >&2
    usage
    exit 64
fi

is_production_target() {
    local host="${TARGET_HOST:-}"
    local path=""
    local candidate=""

    if [[ -n "$host" && "$host" != "ainetic.tech" ]]; then
        return 1
    fi

    if [[ ${#TARGET_PATHS[@]} -eq 0 ]]; then
        return 0
    fi

    for candidate in "${TARGET_PATHS[@]}"; do
        path="${candidate:-}"
        case "$path" in
            /opt/moltinger|/opt/moltinger/*|/opt/moltinger-active|/opt/moltinger-active/*)
                return 0
                ;;
        esac
    done

    return 1
}

if ! is_production_target; then
    exit 0
fi

deny() {
    local reason="$1"
    {
        echo "::error::Production mutation denied for action '$ACTION'."
        echo "::error::$reason"
        echo "::error::Do not replay production deploy steps manually from a feature branch."
        echo "::error::Use .github/workflows/feature-diagnostics.yml for read-only branch diagnostics."
        echo "::error::For production changes, promote to main and run the canonical deploy workflow."
    } >&2
    exit 78
}

if [[ "${MOLTINGER_PROD_GUARD_APPROVED:-}" != "true" ]]; then
    deny "Missing workflow approval context (MOLTINGER_PROD_GUARD_APPROVED=true)."
fi

if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
    deny "Production mutation is only allowed from GitHub Actions."
fi

if [[ -z "${GITHUB_RUN_ID:-}" ]]; then
    deny "Missing GITHUB_RUN_ID."
fi

GITHUB_TOKEN_VALUE="${MOLTINGER_PROD_GUARD_GITHUB_TOKEN:-}"
REPOSITORY_VALUE="${MOLTINGER_PROD_GUARD_REPOSITORY:-}"
WORKFLOW_VALUE="${MOLTINGER_PROD_GUARD_WORKFLOW:-}"
REF_NAME="${MOLTINGER_PROD_GUARD_REF_NAME:-}"
REF_TYPE="${MOLTINGER_PROD_GUARD_REF_TYPE:-}"
REF_SHA="${MOLTINGER_PROD_GUARD_SHA:-}"

if [[ -z "$GITHUB_TOKEN_VALUE" || -z "$REPOSITORY_VALUE" || -z "$WORKFLOW_VALUE" || -z "$REF_NAME" || -z "$REF_TYPE" || -z "$REF_SHA" ]]; then
    deny "Missing approved workflow identity or git ref context."
fi

if [[ "$REF_TYPE" != "tag" && "$REF_NAME" != "main" ]]; then
    deny "Approved production mutations must come from main or a release tag. Current ref: $REF_NAME"
fi

if [[ -n "$EXPECTED_REF" && "$EXPECTED_REF" != "$REF_NAME" ]]; then
    deny "Guard ref mismatch: expected $EXPECTED_REF, approved $REF_NAME."
fi

if [[ -n "$EXPECTED_SHA" && "$EXPECTED_SHA" != "$REF_SHA" ]]; then
    deny "Guard sha mismatch: expected $EXPECTED_SHA, approved $REF_SHA."
fi

api_get() {
    local url="$1"
    curl -fsSL \
        -H "Authorization: Bearer $GITHUB_TOKEN_VALUE" \
        -H "Accept: application/vnd.github+json" \
        "$url"
}

if ! command -v jq >/dev/null 2>&1; then
    deny "jq is required for production mutation guard verification."
fi

USER_JSON="$(api_get "https://api.github.com/user" 2>/dev/null || true)"
if [[ -z "$USER_JSON" ]]; then
    deny "Unable to verify GitHub token identity."
fi

USER_LOGIN="$(jq -r '.login // empty' <<<"$USER_JSON" 2>/dev/null || true)"
if [[ "$USER_LOGIN" != "github-actions[bot]" ]]; then
    deny "Guard token is not a GitHub Actions token."
fi

RUN_JSON="$(api_get "https://api.github.com/repos/$REPOSITORY_VALUE/actions/runs/${GITHUB_RUN_ID}" 2>/dev/null || true)"
if [[ -z "$RUN_JSON" ]]; then
    deny "Unable to verify GitHub Actions run ${GITHUB_RUN_ID}."
fi

RUN_NAME="$(jq -r '.name // empty' <<<"$RUN_JSON" 2>/dev/null || true)"
RUN_EVENT="$(jq -r '.event // empty' <<<"$RUN_JSON" 2>/dev/null || true)"
RUN_HEAD_SHA="$(jq -r '.head_sha // empty' <<<"$RUN_JSON" 2>/dev/null || true)"
RUN_HEAD_BRANCH="$(jq -r '.head_branch // empty' <<<"$RUN_JSON" 2>/dev/null || true)"

if [[ "$RUN_NAME" != "$WORKFLOW_VALUE" ]]; then
    deny "Guard workflow mismatch: expected '$WORKFLOW_VALUE', got '$RUN_NAME'."
fi

if [[ "$RUN_HEAD_SHA" != "$REF_SHA" ]]; then
    deny "Guard run sha mismatch: expected $REF_SHA, got $RUN_HEAD_SHA."
fi

if [[ "$REF_TYPE" != "tag" && "$RUN_HEAD_BRANCH" != "$REF_NAME" ]]; then
    deny "Guard run branch mismatch: expected $REF_NAME, got $RUN_HEAD_BRANCH."
fi

if [[ "$RUN_EVENT" != "push" && "$RUN_EVENT" != "workflow_dispatch" ]]; then
    deny "Unsupported guard run event: $RUN_EVENT."
fi

exit 0
