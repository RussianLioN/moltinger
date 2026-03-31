#!/usr/bin/env bash
# Reclaim Docker/journal storage on the Moltinger host without touching live volumes.

set -euo pipefail

COMMAND="reclaim"
OUTPUT_JSON=false
DRY_RUN=false
IGNORE_DEPLOY_MUTEX=false
RUN_DOCKER_IMAGE_PRUNE=true
RUN_DOCKER_BUILDER_PRUNE=true
RUN_JOURNAL_VACUUM=true
RUN_PROBE_VOLUME_CLEANUP=true
RUN_PREDEPLOY_BACKUP_TRIM=true

DEPLOY_MUTEX_PATH="${DEPLOY_MUTEX_PATH:-/var/lock/moltinger/deploy.lock}"
MOLTIS_STORAGE_IMAGE_PRUNE_UNTIL="${MOLTIS_STORAGE_IMAGE_PRUNE_UNTIL:-168h}"
MOLTIS_STORAGE_BUILDER_PRUNE_UNTIL="${MOLTIS_STORAGE_BUILDER_PRUNE_UNTIL:-168h}"
MOLTIS_STORAGE_JOURNAL_VACUUM_SIZE="${MOLTIS_STORAGE_JOURNAL_VACUUM_SIZE:-1G}"
MOLTIS_STORAGE_BACKUP_DIR="${MOLTIS_STORAGE_BACKUP_DIR:-/var/backups/moltis}"
MOLTIS_STORAGE_KEEP_PREDEPLOY_BACKUPS="${MOLTIS_STORAGE_KEEP_PREDEPLOY_BACKUPS:-10}"

declare -a ACTIONS=()
declare -a WARNINGS=()
declare -a REMOVED_VOLUMES=()
declare -a REMOVED_BACKUP_STEMS=()

usage() {
    cat <<'EOF'
Usage:
  moltis-storage-maintenance.sh [options] [report|reclaim]

Options:
  --json                      Emit machine-readable JSON.
  --dry-run                   Print actions without mutating state.
  --ignore-deploy-mutex       Allow reclaim even while the deploy mutex is active.
  --skip-docker-image-prune   Skip docker image prune.
  --skip-docker-builder-prune Skip docker builder prune.
  --skip-journal-vacuum       Skip journald vacuum.
  --skip-probe-volume-cleanup Skip cleanup of known ephemeral probe volumes.
  --skip-predeploy-backup-trim
                              Skip trimming old pre_deploy backup sidecars.
  -h, --help                  Show this help.
EOF
}

log() {
    local level="$1"
    shift
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        printf '[moltis-storage-maintenance] [%s] %s\n' "$level" "$*"
    fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }

json_array() {
    if [[ $# -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    printf '%s\n' "$@" | jq -R . | jq -s '.'
}

lock_meta_value() {
    local file="$1"
    local key="$2"

    [[ -r "$file" ]] || return 1
    awk -F= -v key="$key" '$1 == key { sub($1 FS, ""); print; exit }' "$file"
}

deploy_mutex_metadata_path() {
    local flock_meta="${DEPLOY_MUTEX_PATH}.meta"
    local mkdir_meta="${DEPLOY_MUTEX_PATH}.d/meta"

    if [[ -f "$flock_meta" ]]; then
        printf '%s\n' "$flock_meta"
        return 0
    fi

    if [[ -f "$mkdir_meta" ]]; then
        printf '%s\n' "$mkdir_meta"
        return 0
    fi

    return 1
}

deploy_mutex_active() {
    local metadata_path now_epoch expires_at

    metadata_path="$(deploy_mutex_metadata_path || true)"
    [[ -n "$metadata_path" ]] || return 1

    expires_at="$(lock_meta_value "$metadata_path" "expires_at" || true)"
    if [[ ! "$expires_at" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    now_epoch="$(date +%s)"
    (( now_epoch < expires_at ))
}

run_or_warn() {
    local description="$1"
    shift

    if [[ "$DRY_RUN" == "true" ]]; then
        ACTIONS+=("dry-run:${description}")
        log_info "[dry-run] $description"
        return 0
    fi

    if "$@"; then
        ACTIONS+=("$description")
        return 0
    fi

    WARNINGS+=("$description")
    log_warn "Step failed: $description"
    return 1
}

docker_usage_percent() {
    df -P /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
}

docker_available_kb() {
    df -P /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}'
}

journal_disk_usage() {
    if ! command -v journalctl >/dev/null 2>&1; then
        printf 'unsupported\n'
        return 0
    fi

    journalctl --disk-usage 2>/dev/null | sed 's/^Archived and active journals take up //; s/ in the file system\.$//'
}

print_report() {
    local docker_use docker_avail journal_use
    docker_use="$(docker_usage_percent || true)"
    docker_avail="$(docker_available_kb || true)"
    journal_use="$(journal_disk_usage || true)"

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        jq -n \
            --arg command "$COMMAND" \
            --arg docker_use_percent "${docker_use:-unknown}" \
            --arg docker_available_kb "${docker_avail:-unknown}" \
            --arg journal_usage "${journal_use:-unknown}" \
            --argjson actions "$(json_array "${ACTIONS[@]}")" \
            --argjson warnings "$(json_array "${WARNINGS[@]}")" \
            --argjson removed_volumes "$(json_array "${REMOVED_VOLUMES[@]}")" \
            --argjson removed_backup_stems "$(json_array "${REMOVED_BACKUP_STEMS[@]}")" \
            '{
                status: (if ($warnings | length) == 0 then "success" else "warning" end),
                command: $command,
                docker_use_percent: (if $docker_use_percent == "unknown" or $docker_use_percent == "" then null else ($docker_use_percent | tonumber) end),
                docker_available_kb: (if $docker_available_kb == "unknown" or $docker_available_kb == "" then null else ($docker_available_kb | tonumber) end),
                journal_usage: (if $journal_usage == "unknown" or $journal_usage == "" then null else $journal_usage end),
                actions: $actions,
                warnings: $warnings,
                removed_volumes: $removed_volumes,
                removed_backup_stems: $removed_backup_stems
            }'
        return 0
    fi

    log_info "Docker usage: ${docker_use:-unknown}%"
    log_info "Docker available: ${docker_avail:-unknown} KB"
    log_info "Journal usage: ${journal_use:-unknown}"
    if [[ ${#REMOVED_VOLUMES[@]} -gt 0 ]]; then
        log_info "Removed probe volumes: ${REMOVED_VOLUMES[*]}"
    fi
    if [[ ${#REMOVED_BACKUP_STEMS[@]} -gt 0 ]]; then
        log_info "Trimmed backup stems: ${REMOVED_BACKUP_STEMS[*]}"
    fi
}

cleanup_probe_volumes() {
    local volume
    local -a volumes=()

    mapfile -t volumes < <(docker volume ls --format '{{.Name}}' 2>/dev/null || true)

    for volume in "${volumes[@]}"; do
        case "$volume" in
            moltis-probe-*|openclaw-orchestrator-*|docker_openclaw_*|codefoundry-*)
                if [[ "$DRY_RUN" == "true" ]]; then
                    ACTIONS+=("dry-run:remove-volume:${volume}")
                    REMOVED_VOLUMES+=("$volume")
                    continue
                fi

                if docker volume rm "$volume" >/dev/null 2>&1; then
                    ACTIONS+=("remove-volume:${volume}")
                    REMOVED_VOLUMES+=("$volume")
                fi
                ;;
        esac
    done
}

trim_predeploy_backups() {
    local archive stem sidecar keep_count index
    local -a archives=()

    [[ "$MOLTIS_STORAGE_KEEP_PREDEPLOY_BACKUPS" =~ ^[0-9]+$ ]] || return 0
    keep_count="$MOLTIS_STORAGE_KEEP_PREDEPLOY_BACKUPS"
    [[ -d "$MOLTIS_STORAGE_BACKUP_DIR" ]] || return 0

    mapfile -t archives < <(
        find "$MOLTIS_STORAGE_BACKUP_DIR" -maxdepth 1 -type f -name 'pre_deploy_*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr \
            | awk '{$1=""; sub(/^ /, ""); print}'
    )

    index=0
    for archive in "${archives[@]}"; do
        index=$((index + 1))
        if (( index <= keep_count )); then
            continue
        fi

        stem="$archive"
        REMOVED_BACKUP_STEMS+=("$(basename "$stem")")
        for sidecar in "$stem" "$stem.compose" "$stem.compose-main" "$stem.runtime" "$stem.version"; do
            [[ -e "$sidecar" ]] || continue
            run_or_warn "remove-backup:${sidecar}" rm -f "$sidecar" || true
        done
    done
}

perform_reclaim() {
    if [[ "$IGNORE_DEPLOY_MUTEX" != "true" ]] && deploy_mutex_active; then
        ACTIONS+=("skip:deploy-mutex-active")
        log_warn "Skipping reclaim because the deploy mutex is active"
        return 0
    fi

    if [[ "$RUN_DOCKER_IMAGE_PRUNE" == "true" ]]; then
        run_or_warn "docker-image-prune" docker image prune -af --filter "until=${MOLTIS_STORAGE_IMAGE_PRUNE_UNTIL}" >/dev/null 2>&1 || true
    fi

    if [[ "$RUN_DOCKER_BUILDER_PRUNE" == "true" ]]; then
        run_or_warn "docker-builder-prune" docker builder prune -af --filter "until=${MOLTIS_STORAGE_BUILDER_PRUNE_UNTIL}" >/dev/null 2>&1 || true
    fi

    if [[ "$RUN_PROBE_VOLUME_CLEANUP" == "true" ]]; then
        cleanup_probe_volumes
    fi

    if [[ "$RUN_PREDEPLOY_BACKUP_TRIM" == "true" ]]; then
        trim_predeploy_backups
    fi

    if [[ "$RUN_JOURNAL_VACUUM" == "true" ]] && [[ -n "$MOLTIS_STORAGE_JOURNAL_VACUUM_SIZE" ]] && [[ "$MOLTIS_STORAGE_JOURNAL_VACUUM_SIZE" != "0" ]]; then
        if command -v journalctl >/dev/null 2>&1; then
            run_or_warn "journal-vacuum" journalctl --vacuum-size="$MOLTIS_STORAGE_JOURNAL_VACUUM_SIZE" >/dev/null 2>&1 || true
        else
            WARNINGS+=("journalctl unavailable")
        fi
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        report|reclaim)
            COMMAND="$1"
            shift
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --ignore-deploy-mutex)
            IGNORE_DEPLOY_MUTEX=true
            shift
            ;;
        --skip-docker-image-prune)
            RUN_DOCKER_IMAGE_PRUNE=false
            shift
            ;;
        --skip-docker-builder-prune)
            RUN_DOCKER_BUILDER_PRUNE=false
            shift
            ;;
        --skip-journal-vacuum)
            RUN_JOURNAL_VACUUM=false
            shift
            ;;
        --skip-probe-volume-cleanup)
            RUN_PROBE_VOLUME_CLEANUP=false
            shift
            ;;
        --skip-predeploy-backup-trim)
            RUN_PREDEPLOY_BACKUP_TRIM=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-storage-maintenance.sh: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

case "$COMMAND" in
    report)
        print_report
        ;;
    reclaim)
        perform_reclaim
        print_report
        ;;
esac
