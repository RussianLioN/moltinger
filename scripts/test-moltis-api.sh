#!/bin/bash
# test-moltis-api.sh - Тестирование Moltis через HTTP API
# Безопасность: пароль хранится только в .env на сервере

set -e

MOLTIS_URL="http://localhost:13131"
ENV_FILE="/opt/moltinger/.env"

# Читаем пароль из .env (без раскрытия в логах)
MOLTIS_PASSWORD=$(grep "^MOLTIS_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)

if [ -z "$MOLTIS_PASSWORD" ]; then
    echo "ERROR: MOLTIS_PASSWORD not found in $ENV_FILE"
    exit 1
fi

# Функция аутентификации - получает session cookie
authenticate() {
    local cookie_file="/tmp/moltis-cookie-$$"
    
    # Login через web form
    curl -s -c "$cookie_file" -b "$cookie_file" \
        -X POST "${MOLTIS_URL}/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "password=${MOLTIS_PASSWORD}" \
        -o /dev/null -w "%{http_code}"
    
    echo "$cookie_file"
}

# Отправить сообщение
send_message() {
    local message="$1"
    local cookie_file="$2"
    
    curl -s -b "$cookie_file" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d "{\"message\": \"${message}\"}"
}

# Получить ответ (polling)
get_response() {
    local cookie_file="$1"
    local timeout="${2:-30}"
    
    # Polling с таймаутом
    local start=$(date +%s)
    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        local response=$(curl -s -b "$cookie_file" "${MOLTIS_URL}/api/v1/chat")
        if [ -n "$response" ] && [ "$response" != "null" ]; then
            echo "$response"
            return 0
        fi
        sleep 1
    done
    echo "TIMEOUT"
}

# Main
main() {
    local command="${1:-/help}"
    
    echo "=== Testing Moltis API ==="
    echo "Command: $command"
    echo ""
    
    # Аутентификация
    echo "1. Authenticating..."
    local cookie_file="/tmp/moltis-session-$$"
    local auth_status=$(curl -s -c "$cookie_file" -b "$cookie_file" \
        -X POST "${MOLTIS_URL}/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "password=${MOLTIS_PASSWORD}" \
        -o /dev/null -w "%{http_code}")
    
    if [ "$auth_status" != "200" ] && [ "$auth_status" != "302" ]; then
        echo "ERROR: Authentication failed (HTTP $auth_status)"
        rm -f "$cookie_file"
        exit 1
    fi
    echo "   OK (HTTP $auth_status)"
    
    # Отправка сообщения
    echo ""
    echo "2. Sending message..."
    local result=$(curl -s -b "$cookie_file" \
        -X POST "${MOLTIS_URL}/api/v1/chat" \
        -H "Content-Type: application/json" \
        -d "{\"message\": \"${command}\"}")
    echo "   Response: $result"
    
    # Cleanup
    rm -f "$cookie_file"
    echo ""
    echo "=== Done ==="
}

# Run
main "$@"
