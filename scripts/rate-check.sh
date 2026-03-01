#!/usr/bin/env bash
# ==============================================================================
# Rate Limit Quick Check - для запуска из Claude Code
# ==============================================================================
# Usage:
#   ./scripts/rate-check.sh          # Быстрая проверка
#   ./scripts/rate-check.sh watch    # Постоянный мониторинг
#   ./scripts/rate-check.sh alarm    # С alarm при 429
# ==============================================================================

set -euo pipefail

DEBUG_DIR="$HOME/.claude/debug"
# Monitor ALL debug files, not just 'latest' symlink
# Important: parallel sessions write to different files!

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ==============================================================================
# Получить количество 429 ошибок за последние N секунд (из ВСЕХ сессий)
# ==============================================================================
get_429_count() {
    local seconds=${1:-60}
    # Use UTC for cutoff since debug logs are in UTC
    local cutoff=$(date -v-${seconds}S -u +%s 2>/dev/null || date -u -d "${seconds} seconds ago" +%s 2>/dev/null)

    if [[ ! -d "$DEBUG_DIR" ]]; then
        echo "0"
        return
    fi

    # Считаем 429 за период из ВСЕХ debug файлов
    local count=0
    # Check only files modified in last hour (performance optimization)
    local recent_files=$(find "$DEBUG_DIR" -name "*.txt" -mmin -60 2>/dev/null | tr '\n' ' ')

    if [[ -z "$recent_files" ]]; then
        echo "0"
        return
    fi

    while IFS= read -r line; do
        local timestamp=$(echo "$line" | grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}" || echo "")
        if [[ -n "$timestamp" ]]; then
            local line_ts
            # Parse as UTC (-u flag) since debug logs use UTC timestamps
            line_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" -u "$timestamp" +%s 2>/dev/null || echo "0")
            if [[ "$line_ts" -ge "$cutoff" ]]; then
                ((count++)) || true
            fi
        fi
    # Z.ai rate limit patterns: HTTP 429 OR code:"1302" (Z.ai specific)
    done < <(grep -hE '(429.*Rate limit|"code":"1302")' $recent_files 2>/dev/null | tail -50)

    echo "$count"
}

# ==============================================================================
# Последняя 429 ошибка (из ВСЕХ сессий)
# ==============================================================================
get_last_429() {
    if [[ ! -d "$DEBUG_DIR" ]]; then
        echo ""
        return
    fi

    # Check files modified in last hour
    local recent_files=$(find "$DEBUG_DIR" -name "*.txt" -mmin -60 2>/dev/null | tr '\n' ' ')

    if [[ -z "$recent_files" ]]; then
        echo ""
        return
    fi

    local last=$(grep -hE '(429.*Rate limit|"code":"1302")' $recent_files 2>/dev/null | tail -1)
    if [[ -n "$last" ]]; then
        # Извлекаем время
        local time=$(echo "$last" | grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")
        echo "$time"
    fi
}

# ==============================================================================
# Количество процессов Claude
# ==============================================================================
get_process_count() {
    lsof 2>/dev/null | grep -c "2.1.50.*txt" || echo "0"
}

# ==============================================================================
# Быстрая проверка
# ==============================================================================
quick_check() {
    local count_1m=$(get_429_count 60)
    local count_5m=$(get_429_count 300)
    local last_429=$(get_last_429)
    local processes=$(get_process_count)

    # Определяем статус
    local status_icon status_text
    if [[ "$count_1m" -gt 3 ]]; then
        status_icon="${RED}●${NC}"
        status_text="RATE LIMITED"
    elif [[ "$count_1m" -gt 0 ]]; then
        status_icon="${YELLOW}●${NC}"
        status_text="WARNING"
    else
        status_icon="${GREEN}●${NC}"
        status_text="OK"
    fi

    # Компактный вывод
    echo -e "${BOLD}Rate Limit Status:${NC} $status_icon $status_text"
    echo -e "  429 errors: ${count_1m} (1m) / ${count_5m} (5m)"
    echo -e "  Processes:  $processes"

    if [[ -n "$last_429" ]]; then
        echo -e "  Last 429:   ${DIM}$last_429${NC}"
    fi

    # Возвращаем код для CI/CD
    if [[ "$count_1m" -gt 3 ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# Watch режим
# ==============================================================================
watch_mode() {
    local interval=${1:-10}

    echo "Watching rate limits (interval: ${interval}s, Ctrl+C to stop)..."
    echo ""

    while true; do
        echo -e "${DIM}$(date '+%H:%M:%S')${NC}"
        quick_check
        echo ""
        sleep "$interval"
    done
}

# ==============================================================================
# Alarm режим - с уведомлением при 429
# ==============================================================================
alarm_mode() {
    local interval=${1:-5}
    local last_count=0

    echo "Rate limit alarm mode (checking every ${interval}s)..."
    echo "Will notify when 429 errors detected."
    echo ""

    while true; do
        local count=$(get_429_count 60)

        if [[ "$count" -gt 0 && "$count" -ne "$last_count" ]]; then
            # Новые 429 ошибки!
            echo -e "${RED}⚠️  RATE LIMIT DETECTED!${NC} $(date '+%H:%M:%S')"
            echo -e "   ${RED}$count errors in last minute${NC}"

            # Звуковое уведомление (macOS)
            if command -v say &> /dev/null; then
                say "rate limit" 2>/dev/null &
            fi

            # Визуальное уведомление (macOS)
            if command -v osascript &> /dev/null; then
                osascript -e "display notification \"Z.ai rate limit reached\" with title \"Claude Code\"" 2>/dev/null &
            fi
        fi

        last_count=$count
        sleep "$interval"
    done
}

# ==============================================================================
# JSON для парсинга
# ==============================================================================
json_output() {
    local count_1m=$(get_429_count 60)
    local count_5m=$(get_429_count 300)
    local processes=$(get_process_count)

    local status="ok"
    if [[ "$count_1m" -gt 3 ]]; then
        status="limited"
    elif [[ "$count_1m" -gt 0 ]]; then
        status="warning"
    fi

    cat <<EOF
{"status":"$status","errors_1m":$count_1m,"errors_5m":$count_5m,"processes":$processes,"timestamp":"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
EOF
}

# ==============================================================================
# Main
# ==============================================================================
case "${1:-}" in
    watch)
        watch_mode "${2:-10}"
        ;;
    alarm)
        alarm_mode "${2:-5}"
        ;;
    json)
        json_output
        ;;
    --help|-h)
        echo "Rate Limit Quick Check"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (none)  Quick status check"
        echo "  watch   Continuous monitoring"
        echo "  alarm   Notify on 429 errors"
        echo "  json    JSON output"
        ;;
    *)
        quick_check
        ;;
esac
