#!/usr/bin/env bash
# Shared GLM (official BigModel) chat completion helper for GitHub Actions workflows.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  glm_chat_completion.sh \
    --prompt-file <path> \
    --output-file <path> \
    [--system-prompt <text>] \
    [--model <id>] \
    [--api-base <url>] \
    [--max-tokens <int>] \
    [--temperature <float>] \
    [--timeout-seconds <int>] \
    [--retry-count <int>]

Environment:
  GLM_API_KEY               Required API key for official BigModel Coding Plan
  GLM_MODEL                 Default: glm-5.1
  GLM_API_BASE              Default: https://open.bigmodel.cn/api/coding/paas/v4
  GLM_MAX_TOKENS            Default: 1800
  GLM_TEMPERATURE           Default: 0.2
  GLM_TIMEOUT_SECONDS       Default: 90
  GLM_RETRY_COUNT           Default: 1
  GLM_SYSTEM_PROMPT         Optional fallback system prompt
  GLM_RAW_RESPONSE_FILE     Optional file path to persist raw JSON response
USAGE
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd" >&2
        exit 4
    fi
}

PROMPT_FILE=""
OUTPUT_FILE=""
SYSTEM_PROMPT="${GLM_SYSTEM_PROMPT:-You are a precise software engineering assistant. Return valid Markdown only.}"
MODEL="${GLM_MODEL:-glm-5.1}"
API_BASE="${GLM_API_BASE:-https://open.bigmodel.cn/api/coding/paas/v4}"
MAX_TOKENS="${GLM_MAX_TOKENS:-1800}"
TEMPERATURE="${GLM_TEMPERATURE:-0.2}"
TIMEOUT_SECONDS="${GLM_TIMEOUT_SECONDS:-90}"
RETRY_COUNT="${GLM_RETRY_COUNT:-1}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt-file)
            PROMPT_FILE="$2"
            shift 2
            ;;
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --system-prompt)
            SYSTEM_PROMPT="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --api-base)
            API_BASE="$2"
            shift 2
            ;;
        --max-tokens)
            MAX_TOKENS="$2"
            shift 2
            ;;
        --temperature)
            TEMPERATURE="$2"
            shift 2
            ;;
        --timeout-seconds)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --retry-count)
            RETRY_COUNT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$PROMPT_FILE" || -z "$OUTPUT_FILE" ]]; then
    echo "ERROR: --prompt-file and --output-file are required." >&2
    usage
    exit 2
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
    exit 2
fi

if [[ -z "${GLM_API_KEY:-}" ]]; then
    echo "ERROR: GLM_API_KEY is required for official BigModel GLM requests." >&2
    exit 3
fi

require_command curl
require_command jq

payload_file="$(mktemp)"
response_file="$(mktemp)"
cleanup() {
    rm -f "$payload_file" "$response_file"
}
trap cleanup EXIT

jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --rawfile prompt "$PROMPT_FILE" \
    --arg max_tokens "$MAX_TOKENS" \
    --arg temperature "$TEMPERATURE" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $prompt}
      ],
      max_tokens: ($max_tokens | tonumber),
      temperature: ($temperature | tonumber)
    }' > "$payload_file"

api_url="${API_BASE%/}/chat/completions"
http_code="$(curl -sS \
    --retry "$RETRY_COUNT" \
    --retry-delay 1 \
    --max-time "$TIMEOUT_SECONDS" \
    -X POST "$api_url" \
    -H "Authorization: Bearer $GLM_API_KEY" \
    -H "Content-Type: application/json" \
    -o "$response_file" \
    -w "%{http_code}" \
    --data-binary "@$payload_file" || echo "000")"

if [[ "$http_code" != "200" ]]; then
    error_message="$(jq -r '.error.message // .message // "Unknown API error"' "$response_file" 2>/dev/null || true)"
    if [[ -n "${GLM_RAW_RESPONSE_FILE:-}" ]]; then
        cp "$response_file" "$GLM_RAW_RESPONSE_FILE" || true
    fi
    echo "ERROR: GLM request failed (HTTP ${http_code}): ${error_message}" >&2
    exit 5
fi

content="$(jq -r '
  if (.choices[0].message.content | type) == "string" then
    .choices[0].message.content
  elif (.choices[0].message.content | type) == "array" then
    [ .choices[0].message.content[] | .text // .content // empty ] | join("\n")
  else
    empty
  end
' "$response_file" 2>/dev/null || true)"

if [[ -z "$content" ]]; then
    if [[ -n "${GLM_RAW_RESPONSE_FILE:-}" ]]; then
        cp "$response_file" "$GLM_RAW_RESPONSE_FILE" || true
    fi
    echo "ERROR: GLM response did not contain choices[0].message.content" >&2
    exit 6
fi

printf '%s\n' "$content" > "$OUTPUT_FILE"

if [[ -n "${GLM_RAW_RESPONSE_FILE:-}" ]]; then
    cp "$response_file" "$GLM_RAW_RESPONSE_FILE" || true
fi
