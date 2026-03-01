#!/usr/bin/env bash
# ==============================================================================
# Claude Code Rate Limit Watcher
# ==============================================================================
# Мониторинг rate limits в реальном времени через debug логи Claude Code
# Не требует API ключ - работает локально!
#
# Использование:
#   ./scripts/claude-rate-watch.sh           # Показать текущий статус
#   ./scripts/claude-rate-watch.sh --live    # Live мониторинг
#   ./scripts/claude-rate-watch.sh --stats   # Статистика за сессию
# ==============================================================================

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
NC='\033[0m'

DEBUG_LOG="$HOME/.claude/debug/latest"

# ==============================================================================
# Получение информации о запущенных процессах Claude
# ==============================================================================
get_claude_processes() {
    # Используем lsof для поиска процессов claude
    lsof 2>/dev/null | grep "2.1.50.*txt" | grep -v "grep" | awk '{print $2, $1}' | sort -u | while read pid name; do
        # Получаем cwd процесса
        local cwd=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}')
        echo "pid:$pid|name:$name|cwd:$cwd"
    done
}

# ==============================================================================
# Анализ debug логов
# ==============================================================================
analyze_debug_log() {
    if [[ ! -L "$DEBUG_LOG" && ! -f "$DEBUG_LOG" ]]; then
        echo "error:no_debug_log"
        return
    fi

    local log_file="$DEBUG_LOG"
    if [[ -L "$log_file" ]]; then
        log_file=$(readlink "$log_file")
    fi

    # Считаем статистику за последние 5 минут
    local now=$(date +%s)
    local five_min_ago=$((now - 300))

    local total_429=0
    local total_requests=0
    local last_429_time=""
    local last_429_request_id=""
    local current_status="unknown"

    # Анализируем лог (последние 1000 строк для скорости)
    local recent_logs=$(tail -1000 "$log_file" 2>/dev/null)

    # Считаем 429 ошибки
    total_429=$(echo "$recent_logs" | grep -c "429.*Rate limit" 2>/dev/null || echo "0")

    # Считаем API запросы
    total_requests=$(echo "$recent_logs" | grep -c "API:request\|API:auth" 2>/dev/null || echo "0")

    # Последняя ошибка 429
    local last_429=$(echo "$recent_logs" | grep "429.*Rate limit" | tail -1)
    if [[ -n "$last_429" ]]; then
        last_429_time=$(echo "$last_429" | grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}" || echo "")
        last_429_request_id=$(echo "$last_429" | grep -oE "request_id.*" | cut -d'"' -f4 || echo "")
    fi

    # Определяем текущий статус
    local recent_errors=$(echo "$recent_logs" | grep "429.*Rate limit" | tail -5 | wc -l | tr -d ' ')
    if [[ "$recent_errors" -gt 3 ]]; then
        current_status="rate_limited"
    elif [[ "$recent_errors" -gt 0 ]]; then
        current_status="warning"
    else
        current_status="ok"
    fi

    # Последняя активность
    local last_activity=$(echo "$recent_logs" | tail -1 | grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}" || echo "")

    echo "total_429:$total_429"
    echo "total_requests:$total_requests"
    echo "current_status:$current_status"
    echo "last_429_time:$last_429_time"
    echo "last_429_request_id:$last_429_request_id"
    echo "last_activity:$last_activity"
}

# ==============================================================================
# Форматирование времени
# ==============================================================================
format_time_ago() {
    local time_str="$1"
    if [[ -z "$time_str" ]]; then
        echo "N/A"
        return
    fi

    # Конвертируем в timestamp
    local log_time=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$time_str" +%s 2>/dev/null || echo "0")
    local now=$(date +%s)
    local diff=$((now - log_time))

    if [[ $diff -lt 60 ]]; then
        echo "${diff}s ago"
    elif [[ $diff -lt 3600 ]]; then
        echo "$((diff / 60))m ago"
    else
        echo "$((diff / 3600))h ago"
    fi
}

# ==============================================================================
# Вывод статуса
# ==============================================================================
print_status() {
    local stats=$(analyze_debug_log)
    local processes=$(get_claude_processes)
    local process_count=$(echo "$processes" | grep -c "pid:" || echo "0")

    local status=$(echo "$stats" | grep "^current_status:" | cut -d: -f2-)
    local total_429=$(echo "$stats" | grep "^total_429:" | cut -d: -f2-)
    local last_429=$(echo "$stats" | grep "^last_429_time:" | cut -d: -f2-)
    local last_activity=$(echo "$stats" | grep "^last_activity:" | cut -d: -f2-)

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Claude Code Rate Limit Monitor                       ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo ""

    # Статус
    case "$status" in
        "ok")
            echo -e "  ${GREEN}● API Status: OK${NC}"
            ;;
        "warning")
            echo -e "  ${YELLOW}● API Status: WARNING (некоторые запросы отклонены)${NC}"
            ;;
        "rate_limited")
            echo -e "  ${RED}● API Status: RATE LIMITED${NC}"
            ;;
        *)
            echo -e "  ${DIM}● API Status: Unknown${NC}"
            ;;
    esac

    echo ""
    echo -e "  ${BLUE}Processes:${NC}    $process_count Claude instance(s) running"
    echo -e "  ${BLUE}429 Errors:${NC}   $total_429 in recent logs"

    if [[ -n "$last_429" ]]; then
        local time_ago=$(format_time_ago "$last_429")
        echo -e "  ${BLUE}Last 429:${NC}     ${YELLOW}$time_ago${NC}"
    fi

    if [[ -n "$last_activity" ]]; then
        local activity_ago=$(format_time_ago "$last_activity")
        echo -e "  ${BLUE}Last Activity:${NC} $activity_ago"
    fi

    echo ""

    # Список процессов
    if [[ "$process_count" -gt 0 ]]; then
        echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "  ${BLUE}Running Processes:${NC}"
        echo "$processes" | while read line; do
            local pid=$(echo "$line" | cut -d'|' -f1 | cut -d: -f2)
            local cwd=$(echo "$line" | cut -d'|' -f3 | cut -d: -f2-)
            echo -e "    ${DIM}PID $pid${NC} → $cwd"
        done
    fi

    echo ""
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

# ==============================================================================
# Live мониторинг
# ==============================================================================
live_mode() {
    local interval=${1:-5}

    echo "Starting live monitor (interval: ${interval}s, Ctrl+C to stop)..."

    # Очищаем экран и показываем начальное состояние
    tput clear 2>/dev/null || clear

    while true; do
        tput cup 0 0 2>/dev/null || true
        print_status
        echo ""
        echo -e "  ${DIM}Refresh: ${interval}s | Press Ctrl+C to stop${NC}"
        sleep "$interval"
    done
}

# ==============================================================================
# Статистика
# ==============================================================================
show_stats() {
    local stats=$(analyze_debug_log)

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Rate Limit Statistics${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    local total_429=$(echo "$stats" | grep "^total_429:" | cut -d: -f2-)
    local total_requests=$(echo "$stats" | grep "^total_requests:" | cut -d: -f2-)

    echo "  429 Errors:        $total_429"
    echo "  API Requests:      $total_requests"

    if [[ "$total_requests" -gt 0 ]]; then
        local rate=$(echo "scale=2; $total_429 * 100 / $total_requests" | bc 2>/dev/null || echo "0")
        echo "  Error Rate:        ${rate}%"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# ==============================================================================
# JSON output
# ==============================================================================
print_json() {
    local stats=$(analyze_debug_log)
    local processes=$(get_claude_processes)
    local process_count=$(echo "$processes" | grep -c "pid:" || echo "0")

    local status=$(echo "$stats" | grep "^current_status:" | cut -d: -f2-)
    local total_429=$(echo "$stats" | grep "^total_429:" | cut -d: -f2-)
    local last_429=$(echo "$stats" | grep "^last_429_time:" | cut -d: -f2-)
    local last_activity=$(echo "$stats" | grep "^last_activity:" | cut -d: -f2-)

    cat <<EOF
{
  "status": "$status",
  "processes": $process_count,
  "rate_limits": {
    "total_429_errors": $total_429,
    "last_429_time": "$last_429"
  },
  "last_activity": "$last_activity",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    local mode="status"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --live|-l)
                mode="live"
                shift
                if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
                    shift
                fi
                ;;
            --stats|-s)
                mode="stats"
                shift
                ;;
            --json|-j)
                mode="json"
                shift
                ;;
            --help|-h)
                echo "Claude Code Rate Limit Watcher"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --live, -l    Live monitoring (refresh every 5s)"
                echo "  --stats, -s   Show statistics"
                echo "  --json, -j    JSON output"
                echo "  --help, -h    Show this help"
                echo ""
                echo "Description:"
                echo "  Monitors Claude Code debug logs for rate limit errors."
                echo "  Works locally without API key."
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    case "$mode" in
        "live")
            live_mode
            ;;
        "stats")
            show_stats
            ;;
        "json")
            print_json
            ;;
        *)
            print_status
            ;;
    esac
}

main "$@"
