#!/usr/bin/env bash
# setup-telegram-webhook-echo.sh - Deploy simple Telegram webhook endpoint behind Traefik.

set -euo pipefail

DOMAIN="${DOMAIN:-moltis.ainetic.tech}"
PATH_PREFIX="${PATH_PREFIX:-/telegram-webhook}"
CONTAINER_NAME="${CONTAINER_NAME:-telegram-webhook-echo}"
IMAGE="${IMAGE:-mendhak/http-https-echo:35}"
NETWORK="${NETWORK:-traefik-net}"

show_help() {
    cat <<'EOF'
Usage:
  setup-telegram-webhook-echo.sh [options]

Options:
  --domain DOMAIN          Public domain (default: moltis.ainetic.tech)
  --path PATH_PREFIX       Webhook path prefix (default: /telegram-webhook)
  --name CONTAINER_NAME    Container name (default: telegram-webhook-echo)
  --image IMAGE            Docker image (default: mendhak/http-https-echo:35)
  --network NETWORK        Docker network with Traefik (default: traefik-net)
  -h, --help               Show help

Example:
  ./scripts/setup-telegram-webhook-echo.sh --domain moltis.ainetic.tech --path /telegram-webhook
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) DOMAIN="${2:-}"; shift 2 ;;
        --path) PATH_PREFIX="${2:-}"; shift 2 ;;
        --name) CONTAINER_NAME="${2:-}"; shift 2 ;;
        --image) IMAGE="${2:-}"; shift 2 ;;
        --network) NETWORK="${2:-}"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$DOMAIN" || -z "$PATH_PREFIX" ]]; then
    echo "DOMAIN and PATH_PREFIX must not be empty" >&2
    exit 2
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --network "$NETWORK" \
    -l "traefik.enable=true" \
    -l "traefik.docker.network=${NETWORK}" \
    -l "traefik.http.routers.telegram-webhook.rule=Host(\`${DOMAIN}\`) && PathPrefix(\`${PATH_PREFIX}\`)" \
    -l "traefik.http.routers.telegram-webhook.entrypoints=websecure" \
    -l "traefik.http.routers.telegram-webhook.tls.certresolver=letsencrypt" \
    -l "traefik.http.routers.telegram-webhook.priority=100" \
    -l "traefik.http.services.telegram-webhook.loadbalancer.server.port=8080" \
    "$IMAGE" >/dev/null

echo "Webhook endpoint deployed:"
echo "  https://${DOMAIN}${PATH_PREFIX}"
echo "Container:"
echo "  ${CONTAINER_NAME}"
