#!/bin/bash
# Apply post-sync host automation from the tracked active deploy root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTIVE_ROOT=""
DRY_RUN=false
HOST_CRON_DIR="${MOLTIS_HOST_CRON_DIR:-/etc/cron.d}"
HOST_SYSTEMD_DIR="${MOLTIS_HOST_SYSTEMD_DIR:-/etc/systemd/system}"
CRON_SERVICE_NAME="${MOLTIS_CRON_SERVICE_NAME:-}"

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

if [[ "$DRY_RUN" != "true" ]]; then
    bash "$SCRIPT_DIR/prod-mutation-guard.sh" \
        --action "apply-moltis-host-automation" \
        --target-path "$ACTIVE_ROOT"
fi

CRON_DIR="$ACTIVE_ROOT/scripts/cron.d"
SYSTEMD_DIR="$ACTIVE_ROOT/systemd"
HEALTH_UNIT="moltis-health-monitor.service"
HEALTH_SRC="$SYSTEMD_DIR/$HEALTH_UNIT"
DISABLED_FALLBACK_SCHEDULER="moltis-telegram-web-user-monitor"
DISABLED_FALLBACK_SYSTEMD_UNITS=(
    "${DISABLED_FALLBACK_SCHEDULER}.service"
    "${DISABLED_FALLBACK_SCHEDULER}.timer"
)

log_dry_run() {
    printf '[dry-run] %s\n' "$*"
}

array_contains() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}

systemctl_available() {
    command -v systemctl >/dev/null 2>&1
}

cron_service_exists() {
    local candidate="${1:-}"
    local load_state=""

    [[ -n "$candidate" ]] || return 1

    load_state="$(systemctl show -p LoadState --value "${candidate}.service" 2>/dev/null || true)"
    [[ -n "$load_state" && "$load_state" != "not-found" ]]
}

resolve_cron_service_name() {
    local candidate=""

    if [[ -n "$CRON_SERVICE_NAME" ]]; then
        printf '%s' "$CRON_SERVICE_NAME"
        return 0
    fi

    for candidate in cron crond; do
        if cron_service_exists "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

ensure_cron_service_active() {
    local cron_service=""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "resolve cron service via MOLTIS_CRON_SERVICE_NAME or detected cron/crond unit"
        log_dry_run "systemctl reload \$CRON_SERVICE || systemctl restart \$CRON_SERVICE || true"
        log_dry_run "if ! systemctl is-active --quiet \$CRON_SERVICE; then systemctl enable --now \$CRON_SERVICE || systemctl start \$CRON_SERVICE; fi"
        log_dry_run "systemctl is-active --quiet \$CRON_SERVICE"
        return 0
    fi

    if ! systemctl_available; then
        log "systemctl not available; skipped cron service activation check"
        return 0
    fi

    cron_service="$(resolve_cron_service_name || true)"
    if [[ -z "$cron_service" ]]; then
        echo "apply-moltis-host-automation.sh: unable to resolve a cron service unit (expected cron or crond)" >&2
        return 1
    fi

    log "Ensuring cron service is active: ${cron_service}.service"
    if ! systemctl reload "$cron_service" 2>/dev/null; then
        systemctl restart "$cron_service" 2>/dev/null || true
    fi

    if ! systemctl is-active --quiet "$cron_service"; then
        log "Cron service is inactive after reload/restart; attempting enable/start: ${cron_service}.service"
        systemctl enable --now "$cron_service" 2>/dev/null || systemctl start "$cron_service" 2>/dev/null || true
    fi

    if ! systemctl is-active --quiet "$cron_service"; then
        echo "apply-moltis-host-automation.sh: cron service '${cron_service}.service' is not active after host automation" >&2
        return 1
    fi
}

install_cron_jobs() {
    local cron_file cron_name host_entry host_name
    local -a cron_files=()
    local -a desired_cron_names=()

    if [[ -d "$CRON_DIR" ]]; then
        shopt -s nullglob
        cron_files=("$CRON_DIR"/*)
        shopt -u nullglob
    fi

    if [[ ${#cron_files[@]} -eq 0 ]]; then
        log "No cron jobs to install from $CRON_DIR"
    fi

    for cron_file in "${cron_files[@]}"; do
        [[ -f "$cron_file" ]] || continue
        cron_name="$(basename "$cron_file")"

        if [[ "$cron_name" == "$DISABLED_FALLBACK_SCHEDULER" ]]; then
            log "Skipping disabled fallback scheduler: $cron_name"
            continue
        fi

        desired_cron_names+=("$cron_name")
        log "Installing cron job: $cron_name"
        run_or_print cp "$cron_file" "$HOST_CRON_DIR/$cron_name"
        run_or_print chmod 644 "$HOST_CRON_DIR/$cron_name"
        run_or_print chown root:root "$HOST_CRON_DIR/$cron_name"
    done

    shopt -s nullglob
    for host_entry in "$HOST_CRON_DIR"/moltis-*; do
        [[ -f "$host_entry" ]] || continue
        host_name="$(basename "$host_entry")"
        if ! array_contains "$host_name" "${desired_cron_names[@]}"; then
            log "Removing stale managed cron job: $host_name"
            run_or_print rm -f "$host_entry"
        fi
    done
    shopt -u nullglob

    if [[ ${#desired_cron_names[@]} -gt 0 ]]; then
        ensure_cron_service_active
    fi
}

sync_systemd_units() {
    local unit_file unit_name host_entry host_name
    local -a desired_systemd_units=()
    local -a systemd_files=()

    if [[ ! -d "$SYSTEMD_DIR" ]]; then
        echo "apply-moltis-host-automation.sh: missing systemd directory in $ACTIVE_ROOT" >&2
        exit 1
    fi

    if [[ ! -f "$HEALTH_SRC" ]]; then
        echo "apply-moltis-host-automation.sh: missing health monitor unit in $ACTIVE_ROOT/systemd" >&2
        exit 1
    fi

    shopt -s nullglob
    systemd_files=("$SYSTEMD_DIR"/moltis-*.service "$SYSTEMD_DIR"/moltis-*.timer)
    shopt -u nullglob

    for unit_file in "${systemd_files[@]}"; do
        [[ -f "$unit_file" ]] || continue
        unit_name="$(basename "$unit_file")"
        if array_contains "$unit_name" "${DISABLED_FALLBACK_SYSTEMD_UNITS[@]}"; then
            log "Keeping fallback scheduler systemd unit absent on host: $unit_name"
            continue
        fi

        desired_systemd_units+=("$unit_name")
        log "Installing systemd unit: $unit_name"
        run_or_print cp "$unit_file" "$HOST_SYSTEMD_DIR/$unit_name"
        run_or_print chmod 644 "$HOST_SYSTEMD_DIR/$unit_name"
        run_or_print chown root:root "$HOST_SYSTEMD_DIR/$unit_name"
    done

    shopt -s nullglob
    for host_entry in "$HOST_SYSTEMD_DIR"/moltis-*.service "$HOST_SYSTEMD_DIR"/moltis-*.timer; do
        [[ -f "$host_entry" ]] || continue
        host_name="$(basename "$host_entry")"
        if ! array_contains "$host_name" "${desired_systemd_units[@]}"; then
            log "Removing stale managed systemd unit: $host_name"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_dry_run "systemctl disable --now $host_name 2>/dev/null || true"
                log_dry_run "systemctl stop $host_name 2>/dev/null || true"
                log_dry_run "rm -f $host_entry"
                log_dry_run "systemctl reset-failed $host_name 2>/dev/null || true"
            else
                if systemctl_available; then
                    systemctl disable --now "$host_name" 2>/dev/null || true
                    systemctl stop "$host_name" 2>/dev/null || true
                fi
                rm -f "$host_entry"
                if systemctl_available; then
                    systemctl reset-failed "$host_name" 2>/dev/null || true
                fi
            fi
        fi
    done
    shopt -u nullglob

    log "Keeping Telegram Web fallback scheduler disabled on host"
    run_or_print rm -f "$HOST_CRON_DIR/$DISABLED_FALLBACK_SCHEDULER"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "systemctl disable --now ${DISABLED_FALLBACK_SCHEDULER}.timer 2>/dev/null || true"
        log_dry_run "systemctl stop ${DISABLED_FALLBACK_SCHEDULER}.service 2>/dev/null || true"
        log_dry_run "rm -f $HOST_SYSTEMD_DIR/${DISABLED_FALLBACK_SCHEDULER}.service"
        log_dry_run "rm -f $HOST_SYSTEMD_DIR/${DISABLED_FALLBACK_SCHEDULER}.timer"
        log_dry_run "systemctl daemon-reload"
        log_dry_run "systemctl reset-failed ${DISABLED_FALLBACK_SCHEDULER}.service ${DISABLED_FALLBACK_SCHEDULER}.timer 2>/dev/null || true"
        log_dry_run "systemctl enable --now $HEALTH_UNIT"
        log_dry_run "systemctl is-active --quiet $HEALTH_UNIT"
    elif systemctl_available; then
        systemctl disable --now "${DISABLED_FALLBACK_SCHEDULER}.timer" 2>/dev/null || true
        systemctl stop "${DISABLED_FALLBACK_SCHEDULER}.service" 2>/dev/null || true
        rm -f "$HOST_SYSTEMD_DIR/${DISABLED_FALLBACK_SCHEDULER}.service"
        rm -f "$HOST_SYSTEMD_DIR/${DISABLED_FALLBACK_SCHEDULER}.timer"
        systemctl daemon-reload
        systemctl reset-failed "${DISABLED_FALLBACK_SCHEDULER}.service" "${DISABLED_FALLBACK_SCHEDULER}.timer" 2>/dev/null || true
        systemctl enable --now "$HEALTH_UNIT"
        systemctl is-active --quiet "$HEALTH_UNIT"
    else
        log "systemctl not available; copied managed unit files but skipped service activation"
    fi
}

install_cron_jobs
sync_systemd_units

log "Moltis host automation applied from $ACTIVE_ROOT"
