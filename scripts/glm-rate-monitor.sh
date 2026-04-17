#!/usr/bin/env bash
# ==============================================================================
# GLM Rate Limit Monitor
# ==============================================================================
# Мониторинг rate limits для официального BigModel Coding Plan API
# Использование:
#   ./scripts/glm-rate-monitor.sh           # Однократная проверка
#   ./scripts/glm-rate-monitor.sh --watch   # Постоянный мониторинг
#   ./scripts/glm-rate-monitor.sh --json    # JSON вывод для CI/CD
#
# Требования:
#   - GLM_API_KEY в переменных окружения или ~/.config/moltis/.env
# ==============================================================================

set -euo pipefail

# Конфигурация
API_BASE="https://open.bigmodel.cn/api/coding/paas/v4"
MODEL="glm-5.1"
CACHE_FILE="/tmp/glm-rate-limit-cache.json"
CACHE_TTL=30  # секунд

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==============================================================================
# Загрузка API ключа
# ==============================================================================
load_api_key() {
    # 1. Из переменной окружения
    if [[ -n "${GLM_API_KEY:-}" ]]; then
        return 0
    fi

    # 2. Из .env файла в текущем проекте
    local project_env=".env.local"
    if [[ -f "$project_env" ]]; then
        GLM_API_KEY=$(grep -E "^GLM_API_KEY=" "$project_env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [[ -n "$GLM_API_KEY" ]]; then
            return 0
        fi
    fi

    # 3. Из серверных secrets (при запуске на сервере)
    local server_env="/run/secrets/glm_api_key"
    if [[ -f "$server_env" ]]; then
        GLM_API_KEY=$(cat "$server_env")
        return 0
    fi

    # 4. Из глобального конфига Moltis
    local moltis_env="$HOME/.config/moltis/.env"
    if [[ -f "$moltis_env" ]]; then
        GLM_API_KEY=$(grep -E "^GLM_API_KEY=" "$moltis_env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [[ -n "$GLM_API_KEY" ]]; then
            return 0
        fi
    fi

    echo "ERROR: GLM_API_KEY не найден!"
    echo "Установите переменную окружения или создайте .env.local файл"
    exit 1
}

# ==============================================================================
# Проверка rate limits через API запрос
# ==============================================================================
check_rate_limit() {
    local response_headers
    local http_code
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Делаем минимальный запрос для получения заголовков
    response_headers=$(curl -s -w "\n%{http_code}" -I "$API_BASE/models" \
        -H "Authorization: Bearer $GLM_API_KEY" \
        -H "Content-Type: application/json" \
        2>/dev/null) || true

    http_code=$(echo "$response_headers" | tail -1)

    # Парсим заголовки rate limit (если есть)
    local x_ratelimit_limit=$(echo "$response_headers" | grep -i "^x-ratelimit-limit:" | awk '{print $2}' | tr -d '\r' || echo "unknown")
    local x_ratelimit_remaining=$(echo "$response_headers" | grep -i "^x-ratelimit-remaining:" | awk '{print $2}' | tr -d '\r' || echo "unknown")
    local x_ratelimit_reset=$(echo "$response_headers" | grep -i "^x-ratelimit-reset:" | awk '{print $2}' | tr -d '\r' || echo "unknown")

    # Альтернативные заголовки (некоторые API используют другие названия)
    local retry_after=$(echo "$response_headers" | grep -i "^retry-after:" | awk '{print $2}' | tr -d '\r' || echo "")

    # Если API не возвращает rate limit заголовки, делаем тестовый запрос
    if [[ "$x_ratelimit_limit" == "unknown" && "$http_code" != "429" ]]; then
        # Делаем минимальный chat completion запрос
        local test_response
        test_response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/chat/completions" \
            -H "Authorization: Bearer $GLM_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}" \
            2>/dev/null) || true

        http_code=$(echo "$test_response" | tail -1)
        local body=$(echo "$test_response" | head -n -1)

        # Проверяем на rate limit ошибку
        if [[ "$http_code" == "429" ]]; then
            local error_code=$(echo "$body" | jq -r '.error.code // "unknown"' 2>/dev/null || echo "unknown")
            local error_msg=$(echo "$body" | jq -r '.error.message // "Rate limited"' 2>/dev/null || echo "Rate limited")

            echo "status:limited"
            echo "http_code:$http_code"
            echo "error_code:$error_code"
            echo "error_message:$error_msg"
            echo "timestamp:$timestamp"
            return 0
        fi

        # Проверяем успешный ответ
        if [[ "$http_code" == "200" ]]; then
            echo "status:ok"
            echo "http_code:$http_code"
            echo "timestamp:$timestamp"
            return 0
        fi
    fi

    # Возвращаем результаты
    echo "status:checked"
    echo "http_code:$http_code"
    echo "ratelimit_limit:$x_ratelimit_limit"
    echo "ratelimit_remaining:$x_ratelimit_remaining"
    echo "ratelimit_reset:$x_ratelimit_reset"
    echo "retry_after:$retry_after"
    echo "timestamp:$timestamp"
}

# ==============================================================================
# Проверка статуса по debug логам Claude Code
# ==============================================================================
check_claude_debug_logs() {
    local debug_log="$HOME/.claude/debug/latest"

    if [[ ! -L "$debug_log" ]]; then
        echo "debug_log:not_found"
        return
    fi

    local recent_429=$(grep -c "429.*Rate limit" "$debug_log" 2>/dev/null || echo "0")
    local last_error=$(grep "Rate limit" "$debug_log" 2>/dev/null | tail -1)
    local last_error_time=""

    if [[ -n "$last_error" ]]; then
        last_error_time=$(echo "$last_error" | grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}" || echo "")
    fi

    echo "recent_429_count:$recent_429"
    echo "last_error_time:$last_error_time"
}

# ==============================================================================
# Форматирование вывода
# ==============================================================================
print_human() {
    local data="$1"
    local status=$(echo "$data" | grep "^status:" | cut -d: -f2-)

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  GLM Rate Limit Monitor${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    case "$status" in
        "ok")
            echo -e "  Status:    ${GREEN}● OK${NC} - API доступен"
            ;;
        "limited")
            local error_msg=$(echo "$data" | grep "^error_message:" | cut -d: -f2-)
            echo -e "  Status:    ${RED}● RATE LIMITED${NC}"
            echo -e "  Message:   $error_msg"
            ;;
        "checked")
            local remaining=$(echo "$data" | grep "^ratelimit_remaining:" | cut -d: -f2-)
            local limit=$(echo "$data" | grep "^ratelimit_limit:" | cut -d: -f2-)
            local reset=$(echo "$data" | grep "^ratelimit_reset:" | cut -d: -f2-)

            echo -e "  Status:    ${GREEN}● OK${NC}"
            if [[ "$remaining" != "unknown" ]]; then
                echo -e "  Remaining: ${YELLOW}$remaining${NC} / $limit"
                echo -e "  Reset:     $reset"
            else
                echo -e "  ${YELLOW}⚠ Rate limit headers не возвращаются API${NC}"
            fi
            ;;
        *)
            echo -e "  Status:    ${YELLOW}● UNKNOWN${NC}"
            ;;
    esac

    local timestamp=$(echo "$data" | grep "^timestamp:" | cut -d: -f2-)
    echo -e "  Timestamp: $timestamp"
    echo ""

    # Debug logs info
    local debug_info=$(check_claude_debug_logs)
    local recent_429=$(echo "$debug_info" | grep "^recent_429_count:" | cut -d: -f2-)
    local last_error=$(echo "$debug_info" | grep "^last_error_time:" | cut -d: -f2-)

    echo -e "${CYAN}  Recent Activity (Claude Code logs):${NC}"
    echo -e "  429 Errors: $recent_429"
    if [[ -n "$last_error" ]]; then
        echo -e "  Last Error: ${YELLOW}$last_error${NC}"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

print_json() {
    local data="$1"
    local timestamp=$(echo "$data" | grep "^timestamp:" | cut -d: -f2-)
    local status=$(echo "$data" | grep "^status:" | cut -d: -f2-)
    local http_code=$(echo "$data" | grep "^http_code:" | cut -d: -f2-)

    local debug_info=$(check_claude_debug_logs)
    local recent_429=$(echo "$debug_info" | grep "^recent_429_count:" | cut -d: -f2-)

    cat <<EOF
{
  "status": "$status",
  "http_code": ${http_code:-0},
  "timestamp": "$timestamp",
  "provider": "z.ai",
  "model": "$MODEL",
  "endpoint": "$API_BASE",
  "claude_logs": {
    "recent_429_count": $recent_429
  }
}
EOF
}

# ==============================================================================
# Watch mode
# ==============================================================================
watch_mode() {
    local interval=${1:-10}

    echo "Starting watch mode (interval: ${interval}s, Ctrl+C to stop)..."

    while true; do
        clear
        local data=$(check_rate_limit)
        print_human "$data"
        sleep "$interval"
    done
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    local mode="once"
    local output="human"
    local interval=10

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --watch|-w)
                mode="watch"
                shift
                if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
                    interval="$1"
                    shift
                fi
                ;;
            --json|-j)
                output="json"
                shift
                ;;
            --help|-h)
                echo "Z.AI Rate Limit Monitor"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --watch, -w [SEC]  Continuous monitoring (default interval: 10s)"
                echo "  --json, -j         JSON output for CI/CD"
                echo "  --help, -h         Show this help"
                echo ""
                echo "Environment:"
                echo "  GLM_API_KEY        API key (or use .env.local)"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    load_api_key

    case "$mode" in
        "watch")
            watch_mode "$interval"
            ;;
        *)
            local data=$(check_rate_limit)
            case "$output" in
                "json")
                    print_json "$data"
                    ;;
                *)
                    print_human "$data"
                    ;;
            esac
            ;;
    esac
}

main "$@"
