#!/usr/bin/env bash
# Fail-closed guard for production-mutating entrypoints.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  prod-mutation-guard.sh \
    --action <name> \
    [--target-host <host>] \
    [--target-path <path>]
EOF
}

ACTION=""
TARGET_HOST=""
TARGET_PATH=""

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
            TARGET_PATH="${2:-}"
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
    local path="${TARGET_PATH:-}"

    if [[ -n "$host" && "$host" != "ainetic.tech" ]]; then
        return 1
    fi

    case "$path" in
        ""|/opt/moltinger|/opt/moltinger/*|/opt/moltinger-active|/opt/moltinger-active/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
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

REF_NAME="${MOLTINGER_PROD_GUARD_REF_NAME:-}"
REF_TYPE="${MOLTINGER_PROD_GUARD_REF_TYPE:-}"
REF_SHA="${MOLTINGER_PROD_GUARD_SHA:-}"

if [[ -z "$REF_NAME" || -z "$REF_TYPE" || -z "$REF_SHA" ]]; then
    deny "Missing approved git ref context."
fi

if [[ "$REF_TYPE" != "tag" && "$REF_NAME" != "main" ]]; then
    deny "Approved production mutations must come from main or a release tag. Current ref: $REF_NAME"
fi

exit 0
