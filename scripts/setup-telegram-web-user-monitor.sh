#!/usr/bin/env bash
# setup-telegram-web-user-monitor.sh - Install dependencies for Telegram Web user monitor.

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/moltinger}"

show_help() {
    cat <<'EOF'
Usage:
  setup-telegram-web-user-monitor.sh [--project-dir /opt/moltinger]

Installs:
  - playwright npm package
  - chromium browser with required OS deps
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)
            PROJECT_DIR="${2:-}"
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

echo "Playwright + Chromium installed in ${PROJECT_DIR}"
