#!/usr/bin/env bash
# Render the deployable Clawdiy OpenClaw runtime config from the tracked template
# plus the dedicated runtime env file. The rendered artifact lives under data/
# so GitOps deploys do not dirty the tracked worktree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="${TEMPLATE_FILE:-$PROJECT_ROOT/config/clawdiy/openclaw.json}"
OUTPUT_FILE="${OUTPUT_FILE:-$PROJECT_ROOT/data/clawdiy/runtime/openclaw.json}"
ENV_FILE="${ENV_FILE:-}"
OUTPUT_JSON=false
NO_COLOR=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        return
    fi

    case "$level" in
        INFO) echo -e "${BLUE}[INFO]${NC} $*" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $*" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $*" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
    esac
}

disable_colors() {
    if [[ "$NO_COLOR" == "true" || "$OUTPUT_JSON" == "true" || ! -t 1 ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        NC=''
    fi
}

read_env_file() {
    local file_path="$1"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" != *=* ]] && continue

        local key="${line%%=*}"
        local value="${line#*=}"
        key="$(printf '%s' "$key" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        export "$key=$value"
    done <"$file_path"
}

telegram_allow_from_json() {
    local raw="${CLAWDIY_TELEGRAM_ALLOWED_USERS:-}"

    if [[ -z "$raw" ]]; then
        printf '[]'
        return
    fi

    printf '%s' "$raw" | jq -R '
        split(",")
        | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        | map(select(length > 0))
        | map(if startswith("tg:") then . else "tg:" + . end)
    '
}

render_config() {
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        echo "Template file not found: $TEMPLATE_FILE" >&2
        return 1
    fi

    if ! jq empty "$TEMPLATE_FILE" >/dev/null 2>&1; then
        echo "Template file is not valid JSON: $TEMPLATE_FILE" >&2
        return 1
    fi

    mkdir -p "$(dirname "$OUTPUT_FILE")"

    local domain public_base_url internal_port allow_from_json tmp_file
    domain="${CLAWDIY_DOMAIN:-clawdiy.ainetic.tech}"
    public_base_url="${CLAWDIY_PUBLIC_BASE_URL:-https://${domain}}"
    internal_port="${CLAWDIY_INTERNAL_PORT:-18789}"
    allow_from_json="$(telegram_allow_from_json)"
    tmp_file="$(mktemp)"

    jq \
        --arg public_base_url "$public_base_url" \
        --argjson internal_port "$internal_port" \
        --argjson allow_from "$allow_from_json" \
        '
        .gateway.port = $internal_port
        | .gateway.controlUi.allowedOrigins = [$public_base_url]
        | .channels.telegram.allowFrom = $allow_from
        ' "$TEMPLATE_FILE" >"$tmp_file"

    mv "$tmp_file" "$OUTPUT_FILE"
    chmod 0644 "$OUTPUT_FILE"
}

output_result() {
    jq -n \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg template "$TEMPLATE_FILE" \
        --arg output "$OUTPUT_FILE" \
        --arg public_base_url "${CLAWDIY_PUBLIC_BASE_URL:-https://${CLAWDIY_DOMAIN:-clawdiy.ainetic.tech}}" \
        --argjson internal_port "${CLAWDIY_INTERNAL_PORT:-18789}" \
        --argjson allow_from "$(telegram_allow_from_json)" \
        '{
            status: "pass",
            timestamp: $timestamp,
            template: $template,
            output: $output,
            public_base_url: $public_base_url,
            internal_port: $internal_port,
            telegram_allow_from: $allow_from
        }'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --template)
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage: render-clawdiy-runtime-config.sh [--template path] [--output path] [--env-file path] [--json] [--no-color]
EOF
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    disable_colors

    if [[ -n "$ENV_FILE" ]]; then
        if [[ ! -f "$ENV_FILE" ]]; then
            echo "Env file not found: $ENV_FILE" >&2
            exit 1
        fi
        read_env_file "$ENV_FILE"
    fi

    if [[ -n "${CLAWDIY_GATEWAY_TOKEN:-}" && -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        export OPENCLAW_GATEWAY_TOKEN="$CLAWDIY_GATEWAY_TOKEN"
    fi

    # Legacy compatibility: first-rollout branches may still only provide
    # CLAWDIY_PASSWORD even though the hosted Control UI now uses token auth.
    if [[ -n "${CLAWDIY_PASSWORD:-}" && -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        export OPENCLAW_GATEWAY_TOKEN="$CLAWDIY_PASSWORD"
    fi

    if [[ -n "${CLAWDIY_TELEGRAM_BOT_TOKEN:-}" && -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        export TELEGRAM_BOT_TOKEN="$CLAWDIY_TELEGRAM_BOT_TOKEN"
    fi

    log INFO "Rendering Clawdiy OpenClaw runtime config"
    render_config

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_result
    else
        log SUCCESS "Rendered Clawdiy runtime config to $OUTPUT_FILE"
    fi
}

main "$@"
