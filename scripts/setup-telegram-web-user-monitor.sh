#!/usr/bin/env bash
# setup-telegram-web-user-monitor.sh - Install dependencies for Telegram Web user monitor.

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/moltinger}"
INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-true}"

show_help() {
    cat <<'EOF'
Usage:
  setup-telegram-web-user-monitor.sh [--project-dir /opt/moltinger] [--install-systemd true|false]

Installs:
  - playwright npm package
  - chromium browser with required OS deps
  - systemd service+timer (enabled by default)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)
            PROJECT_DIR="${2:-}"
            shift 2
            ;;
        --install-systemd)
            INSTALL_SYSTEMD="${2:-true}"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

cd "$PROJECT_DIR"

npm install --omit=dev playwright
npx playwright install --with-deps chromium

if [[ "${INSTALL_SYSTEMD}" == "true" ]]; then
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "systemctl is not available, skipping systemd timer install"
    else
        install -m 0644 "${PROJECT_DIR}/systemd/moltis-telegram-web-user-monitor.service" /etc/systemd/system/
        install -m 0644 "${PROJECT_DIR}/systemd/moltis-telegram-web-user-monitor.timer" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable --now moltis-telegram-web-user-monitor.timer
        echo "systemd timer enabled: moltis-telegram-web-user-monitor.timer"
    fi
fi

echo "Playwright + Chromium installed in ${PROJECT_DIR}"
