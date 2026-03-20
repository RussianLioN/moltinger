#!/bin/bash
# Apply post-sync host automation from the tracked active deploy root.

set -euo pipefail

ACTIVE_ROOT=""
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: apply-moltis-host-automation.sh --active-root <path> [--dry-run]

Installs tracked cron jobs and the Moltis health monitor unit from the active
deploy root, while keeping the Telegram Web fallback scheduler disabled on host.
EOF
}

log() {
    echo "[apply-moltis-host-automation] $*"
}

run_or_print() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[dry-run] '
        printf '%q ' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --active-root)
            ACTIVE_ROOT="${2:-}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "apply-moltis-host-automation.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$ACTIVE_ROOT" ]]; then
    echo "apply-moltis-host-automation.sh: --active-root is required" >&2
    usage >&2
    exit 2
fi

if [[ ! -d "$ACTIVE_ROOT" ]]; then
    echo "apply-moltis-host-automation.sh: active root does not exist: $ACTIVE_ROOT" >&2
    exit 1
fi

CRON_DIR="$ACTIVE_ROOT/scripts/cron.d"
HEALTH_SRC="$ACTIVE_ROOT/systemd/moltis-health-monitor.service"
DISABLED_FALLBACK_SCHEDULER="moltis-telegram-web-user-monitor"

install_cron_jobs() {
    local cron_file cron_name
    local -a cron_files=()

    if [[ -d "$CRON_DIR" ]]; then
        shopt -s nullglob
        cron_files=("$CRON_DIR"/*)
        shopt -u nullglob
    fi

    if [[ ${#cron_files[@]} -eq 0 ]]; then
        log "No cron jobs to install from $CRON_DIR"
        return 0
    fi

    for cron_file in "${cron_files[@]}"; do
        [[ -f "$cron_file" ]] || continue
        cron_name="$(basename "$cron_file")"

        if [[ "$cron_name" == "$DISABLED_FALLBACK_SCHEDULER" ]]; then
            log "Skipping disabled fallback scheduler: $cron_name"
            continue
        fi

        log "Installing cron job: $cron_name"
        run_or_print cp "$cron_file" "/etc/cron.d/$cron_name"
        run_or_print chmod 644 "/etc/cron.d/$cron_name"
        run_or_print chown root:root "/etc/cron.d/$cron_name"
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] systemctl reload cron || systemctl restart cron || true"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl reload cron 2>/dev/null || systemctl restart cron 2>/dev/null || true
    fi
}

disable_telegram_web_scheduler() {
    log "Keeping Telegram Web fallback scheduler disabled on host"
    run_or_print rm -f "/etc/cron.d/$DISABLED_FALLBACK_SCHEDULER"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] systemctl disable --now ${DISABLED_FALLBACK_SCHEDULER}.timer 2>/dev/null || true"
        echo "[dry-run] systemctl stop ${DISABLED_FALLBACK_SCHEDULER}.service 2>/dev/null || true"
        echo "[dry-run] rm -f /etc/systemd/system/${DISABLED_FALLBACK_SCHEDULER}.service"
        echo "[dry-run] rm -f /etc/systemd/system/${DISABLED_FALLBACK_SCHEDULER}.timer"
        echo "[dry-run] systemctl reset-failed ${DISABLED_FALLBACK_SCHEDULER}.service ${DISABLED_FALLBACK_SCHEDULER}.timer 2>/dev/null || true"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "${DISABLED_FALLBACK_SCHEDULER}.timer" 2>/dev/null || true
        systemctl stop "${DISABLED_FALLBACK_SCHEDULER}.service" 2>/dev/null || true
        rm -f "/etc/systemd/system/${DISABLED_FALLBACK_SCHEDULER}.service"
        rm -f "/etc/systemd/system/${DISABLED_FALLBACK_SCHEDULER}.timer"
        systemctl reset-failed "${DISABLED_FALLBACK_SCHEDULER}.service" "${DISABLED_FALLBACK_SCHEDULER}.timer" 2>/dev/null || true
    fi
}

install_health_monitor() {
    if [[ ! -f "$HEALTH_SRC" ]]; then
        echo "apply-moltis-host-automation.sh: missing health monitor unit in $ACTIVE_ROOT/systemd" >&2
        exit 1
    fi

    log "Installing Moltis health monitor unit"
    run_or_print cp "$HEALTH_SRC" /etc/systemd/system/moltis-health-monitor.service
    run_or_print chmod 644 /etc/systemd/system/moltis-health-monitor.service

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] systemctl daemon-reload"
        echo "[dry-run] systemctl enable --now moltis-health-monitor.service"
        echo "[dry-run] systemctl is-active --quiet moltis-health-monitor.service"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl enable --now moltis-health-monitor.service
        systemctl is-active --quiet moltis-health-monitor.service
    fi
}

install_cron_jobs
disable_telegram_web_scheduler
install_health_monitor

log "Moltis host automation applied from $ACTIVE_ROOT"
