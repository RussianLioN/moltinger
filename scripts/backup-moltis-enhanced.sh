#!/bin/bash
# Moltis Enterprise Backup Script with Disaster Recovery
# Version: 3.0
# Features: Encryption, offsite backup, integrity verification, point-in-time recovery,
#           GitOps guards, JSON output, S3 retry logic, Prometheus metrics

set -euo pipefail

# ========================================================================
# EXIT CODES
# ========================================================================
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_BACKUP_FAILED=2
EXIT_S3_UPLOAD_FAILED=3

# ========================================================================
# GITOPS GUARDS (P1-3)
# ========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source GitOps guards library
if [[ -f "$SCRIPT_DIR/gitops-guards.sh" ]]; then
    source "$SCRIPT_DIR/gitops-guards.sh"
fi

# ========================================================================
# CONFIGURATION
# ========================================================================
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${BACKUP_CONFIG:-$PROJECT_ROOT/config/backup/backup.conf}"

# Default configuration (can be overridden by config file or environment)
BACKUP_DIR="${BACKUP_DIR:-/var/backups/moltis}"
CONFIG_DIR="${BACKUP_CONFIG_DIR:-$PROJECT_ROOT/config}"
DATA_DIR="${BACKUP_DATA_DIR:-$PROJECT_ROOT/data}"
LOG_DIR="${BACKUP_LOG_DIR:-/var/log/moltis}"
RUNTIME_ENV_FILE="${BACKUP_ENV_FILE:-$PROJECT_ROOT/.env}"
COMPOSE_FILE_MAIN="${BACKUP_COMPOSE_FILE_MAIN:-$PROJECT_ROOT/docker-compose.yml}"
COMPOSE_FILE_PROD="${BACKUP_COMPOSE_FILE_PROD:-$PROJECT_ROOT/docker-compose.prod.yml}"
BACKUP_RESTORE_RUNTIME_FILES="${BACKUP_RESTORE_RUNTIME_FILES:-true}"
CLAWDIY_BACKUP_ENABLED="${CLAWDIY_BACKUP_ENABLED:-true}"
CLAWDIY_CONFIG_DIR="${CLAWDIY_CONFIG_DIR:-$PROJECT_ROOT/config/clawdiy}"
CLAWDIY_RUNTIME_DIR="${CLAWDIY_RUNTIME_DIR:-$PROJECT_ROOT/data/clawdiy/runtime}"
CLAWDIY_STATE_DIR="${CLAWDIY_STATE_DIR:-$PROJECT_ROOT/data/clawdiy/state}"
CLAWDIY_AUDIT_DIR="${CLAWDIY_AUDIT_DIR:-$PROJECT_ROOT/data/clawdiy/audit}"
CLAWDIY_CONTAINER_NAME="${CLAWDIY_CONTAINER_NAME:-clawdiy}"
CLAWDIY_RESTORE_AUTOSTART="${CLAWDIY_RESTORE_AUTOSTART:-true}"
CLAWDIY_ALLOW_PARTIAL_RESTORE="${CLAWDIY_ALLOW_PARTIAL_RESTORE:-false}"
CLAWDIY_EVIDENCE_MANIFEST_NAME="${CLAWDIY_EVIDENCE_MANIFEST_NAME:-clawdiy-evidence-manifest.json}"
RETENTION_DAYS=30
RETENTION_WEEKS=12
RETENTION_MONTHS=12

# Encryption
ENCRYPTION_ENABLED=true
ENCRYPTION_KEY_FILE="/etc/moltis/backup.key"

# Remote backup (S3)
S3_ENABLED=false
S3_BUCKET=""
S3_PREFIX="moltis-backups"
AWS_REGION="us-east-1"
S3_MAX_RETRIES=3
S3_RETRY_DELAYS=(1 2 4)  # Exponential backoff: 1s, 2s, 4s

# Remote backup (SFTP)
SFTP_ENABLED=false
SFTP_HOST=""
SFTP_USER=""
SFTP_PATH="/backups/moltis"

# Notifications
NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

# JSON output mode
JSON_OUTPUT=false

# Prometheus metrics
PROMETHEUS_TEXTFILE_DIR="${PROMETHEUS_TEXTFILE_DIR:-/var/lib/node_exporter/textfile_dir}"
PROMETHEUS_METRICS_FILE="$PROMETHEUS_TEXTFILE_DIR/moltis_backup.prom"

# Backup status file
BACKUP_STATUS_FILE="${BACKUP_STATUS_FILE:-/var/lib/moltis/backup-status.json}"

# ========================================================================
# STATE TRACKING (for JSON output and metrics)
# ========================================================================
BACKUP_START_TIME=0
BACKUP_END_TIME=0
BACKUP_DURATION_MS=0
BACKUP_SIZE_BYTES=0
BACKUP_CHECKSUM=""
BACKUP_LOCAL_PATH=""
BACKUP_S3_LOCATION=""
BACKUP_ENCRYPTED=false
BACKUP_STATUS="pending"
BACKUP_ERRORS=()
BACKUP_ID=""
ENCRYPTED_OUTPUT_FILE=""

# ========================================================================
# INITIALIZATION
# ========================================================================

# Load configuration file if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Reconcile derived directories after config/env overrides are loaded.
CONFIG_DIR="${BACKUP_CONFIG_DIR:-${CONFIG_DIR:-$PROJECT_ROOT/config}}"
DATA_DIR="${BACKUP_DATA_DIR:-${DATA_DIR:-$PROJECT_ROOT/data}}"
LOG_DIR="${BACKUP_LOG_DIR:-${LOG_DIR:-/var/log/moltis}}"
RUNTIME_ENV_FILE="${BACKUP_ENV_FILE:-${RUNTIME_ENV_FILE:-$PROJECT_ROOT/.env}}"
COMPOSE_FILE_MAIN="${BACKUP_COMPOSE_FILE_MAIN:-${COMPOSE_FILE_MAIN:-$PROJECT_ROOT/docker-compose.yml}}"
COMPOSE_FILE_PROD="${BACKUP_COMPOSE_FILE_PROD:-${COMPOSE_FILE_PROD:-$PROJECT_ROOT/docker-compose.prod.yml}}"

# Setup logging (with fallback if permission denied)
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    # Use TMPDIR if set, otherwise fallback to allowed temp directory
    LOG_DIR="${TMPDIR:-/private/tmp/claude-501}/moltis-backup-logs"
    mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/dev/null"
fi
if [[ "$LOG_DIR" != "/dev/null" ]]; then
    LOG_FILE="$LOG_DIR/backup-$(date +%Y%m%d).log"
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
else
    LOG_FILE="/dev/null"
fi
BACKUP_ID="$(date +%Y%m%d_%H%M%S)_$(hostname -s)"
BACKUP_TYPE="daily"

# Determine backup type based on day
case "$(date +%u)" in
    7) BACKUP_TYPE="weekly" ;;
esac
if [[ "$(date +%d)" == "01" ]]; then
    BACKUP_TYPE="monthly"
fi

string_is_true() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

container_exists() {
    local container_name="$1"
    docker inspect "$container_name" >/dev/null 2>&1
}

container_is_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"
}

clawdiy_inventory_present() {
    [[ -e "$CLAWDIY_CONFIG_DIR" || -e "$CLAWDIY_RUNTIME_DIR" || -e "$CLAWDIY_STATE_DIR" || -e "$CLAWDIY_AUDIT_DIR" ]]
}

count_files_under() {
    local root="$1"

    if [[ ! -d "$root" ]]; then
        echo "0"
        return
    fi

    find "$root" -type f | wc -l | tr -d ' '
}

latest_file_under() {
    local root="$1"

    if [[ ! -d "$root" ]]; then
        return 0
    fi

    find "$root" -type f | sort | tail -1
}

json_bool() {
    if string_is_true "$1"; then
        echo "true"
    else
        echo "false"
    fi
}

current_time_ms() {
    local timestamp
    timestamp=$(date +%s%3N 2>/dev/null || true)
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        echo "$timestamp"
    else
        echo "$(($(date +%s) * 1000))"
    fi
}

write_sha256_file() {
    local input_file="$1"
    local output_file="$2"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$input_file" > "$output_file"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$input_file" > "$output_file"
    else
        log_error "No SHA-256 checksum tool available"
        return 1
    fi
}

verify_sha256_file() {
    local input_file="$1"
    local checksum_file="$2"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "$checksum_file" --quiet 2>/dev/null
        return $?
    fi

    if command -v shasum >/dev/null 2>&1; then
        local expected actual
        expected=$(awk '{print $1}' "$checksum_file")
        actual=$(shasum -a 256 "$input_file" | awk '{print $1}')
        [[ -n "$expected" && "$expected" == "$actual" ]]
        return $?
    fi

    log_error "No SHA-256 checksum tool available"
    return 1
}

# ========================================================================
# LOGGING FUNCTIONS
# ========================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    else
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() {
    log "ERROR" "$@"
    BACKUP_ERRORS+=("$*")
}

# ========================================================================
# JSON OUTPUT FUNCTIONS
# ========================================================================

# Output JSON result to stdout
output_json() {
    local status="$1"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build errors array
    local errors_json="[]"
    if [[ ${#BACKUP_ERRORS[@]} -gt 0 ]]; then
        errors_json="["
        local first=true
        for err in "${BACKUP_ERRORS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                errors_json+=","
            fi
            errors_json+="\"$(echo "$err" | sed 's/"/\\"/g')\""
        done
        errors_json+="]"
    fi

    # Build details object
    local s3_location="null"
    if [[ -n "$BACKUP_S3_LOCATION" ]]; then
        s3_location="\"$BACKUP_S3_LOCATION\""
    fi

    cat <<EOF
{
  "status": "$status",
  "timestamp": "$timestamp",
  "action": "backup",
  "details": {
    "backup_id": "$BACKUP_ID",
    "backup_type": "$BACKUP_TYPE",
    "local_path": "$BACKUP_LOCAL_PATH",
    "s3_location": $s3_location,
    "size_bytes": $BACKUP_SIZE_BYTES,
    "checksum": "$BACKUP_CHECKSUM",
    "duration_ms": $BACKUP_DURATION_MS,
    "encrypted": $BACKUP_ENCRYPTED
  },
  "errors": $errors_json
}
EOF
}

# Write backup status file
write_backup_status() {
    local status="$1"
    local timestamp
    local status_file="$BACKUP_STATUS_FILE"
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Ensure directory exists
    if ! mkdir -p "$(dirname "$status_file")" 2>/dev/null; then
        status_file="${TMPDIR:-/tmp}/moltis-backup-status.json"
        mkdir -p "$(dirname "$status_file")" 2>/dev/null || true
    fi

    # Build errors array
    local errors_json="[]"
    if [[ ${#BACKUP_ERRORS[@]} -gt 0 ]]; then
        errors_json="["
        local first=true
        for err in "${BACKUP_ERRORS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                errors_json+=","
            fi
            errors_json+="\"$(echo "$err" | sed 's/"/\\"/g')\""
        done
        errors_json+="]"
    fi

    local s3_location="null"
    if [[ -n "$BACKUP_S3_LOCATION" ]]; then
        s3_location="\"$BACKUP_S3_LOCATION\""
    fi

    cat > "$status_file" <<EOF
{
  "status": "$status",
  "last_backup_timestamp": "$timestamp",
  "backup_id": "$BACKUP_ID",
  "backup_type": "$BACKUP_TYPE",
  "local_path": "$BACKUP_LOCAL_PATH",
  "s3_location": $s3_location,
  "size_bytes": $BACKUP_SIZE_BYTES,
  "checksum": "$BACKUP_CHECKSUM",
  "duration_ms": $BACKUP_DURATION_MS,
  "encrypted": $BACKUP_ENCRYPTED,
  "retention": {
    "daily_days": $RETENTION_DAYS,
    "weekly_weeks": $RETENTION_WEEKS,
    "monthly_months": $RETENTION_MONTHS
  },
  "errors": $errors_json
}
EOF

    log_info "Backup status written to $status_file"
}

# ========================================================================
# PROMETHEUS METRICS FUNCTIONS
# ========================================================================

# Write Prometheus metrics to textfile
write_prometheus_metrics() {
    local status="$1"
    local duration_seconds
    local metrics_dir="$PROMETHEUS_TEXTFILE_DIR"
    local metrics_file="$PROMETHEUS_METRICS_FILE"
    duration_seconds=$(echo "scale=2; $BACKUP_DURATION_MS / 1000" | bc 2>/dev/null || echo "0")

    # Ensure directory exists
    if ! mkdir -p "$metrics_dir" 2>/dev/null; then
        metrics_dir="${TMPDIR:-/tmp}/moltis-prometheus-textfile"
        metrics_file="${metrics_dir}/$(basename "$PROMETHEUS_METRICS_FILE")"
        mkdir -p "$metrics_dir" 2>/dev/null || true
    fi

    # Convert status to metric value
    local status_success=0
    local status_failed=0
    if [[ "$status" == "success" ]]; then
        status_success=1
    else
        status_failed=1
    fi

    # Get current timestamp
    local current_timestamp
    current_timestamp=$(date +%s)

    # Write metrics in Prometheus textfile format
    # Using temporary file for atomic write
    local temp_file
    temp_file=$(mktemp "${metrics_dir}/.moltis_backup.XXXXXX") || {
        log_warn "Failed to create temp file for Prometheus metrics"
        return 1
    }

    cat > "$temp_file" <<EOF
# HELP moltis_backup_status Backup status (1=success/failed for respective label)
# TYPE moltis_backup_status gauge
moltis_backup_status{status="success"} $status_success
moltis_backup_status{status="failed"} $status_failed

# HELP moltis_backup_duration_seconds Duration of last backup in seconds
# TYPE moltis_backup_duration_seconds gauge
moltis_backup_duration_seconds $duration_seconds

# HELP moltis_backup_size_bytes Size of last backup in bytes
# TYPE moltis_backup_size_bytes gauge
moltis_backup_size_bytes $BACKUP_SIZE_BYTES

# HELP moltis_backup_last_success_timestamp Unix timestamp of last successful backup
# TYPE moltis_backup_last_success_timestamp gauge
moltis_backup_last_success_timestamp $( [[ "$status" == "success" ]] && echo "$current_timestamp" || echo "0" )

# HELP moltis_backup_encrypted Whether backup is encrypted (1=yes, 0=no)
# TYPE moltis_backup_encrypted gauge
moltis_backup_encrypted $( [[ "$BACKUP_ENCRYPTED" == "true" ]] && echo "1" || echo "0" )

# HELP moltis_backup_s3_uploaded Whether backup was uploaded to S3 (1=yes, 0=no)
# TYPE moltis_backup_s3_uploaded gauge
moltis_backup_s3_uploaded $( [[ -n "$BACKUP_S3_LOCATION" ]] && echo "1" || echo "0" )
EOF

    # Atomic move
    mv "$temp_file" "$metrics_file" || {
        log_warn "Failed to move Prometheus metrics file"
        rm -f "$temp_file"
        return 1
    }

    log_info "Prometheus metrics written to $metrics_file"
}

# ========================================================================
# NOTIFICATION FUNCTIONS
# ========================================================================

send_notification() {
    local subject="$1"
    local message="$2"
    local severity="${3:-info}"

    log_info "Notification: [$severity] $subject"

    # Email notification
    if [[ -n "$NOTIFY_EMAIL" ]] && command -v mail &> /dev/null; then
        {
            echo "Subject: [Moltis Backup] $subject"
            echo ""
            echo "$message"
            echo ""
            echo "---"
            echo "Backup ID: $BACKUP_ID"
            echo "Timestamp: $(date -Iseconds)"
            echo "Host: $(hostname)"
        } | mail -s "[Moltis Backup] $subject" "$NOTIFY_EMAIL" 2>/dev/null || true
    fi

    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        local color
        case "$severity" in
            error) color="danger" ;;
            warning) color="warning" ;;
            *) color="good" ;;
        esac
        curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"attachments\": [{
                    \"color\": \"$color\",
                    \"title\": \"Moltis Backup - $subject\",
                    \"text\": \"$message\",
                    \"footer\": \"Backup ID: $BACKUP_ID\",
                    \"ts\": $(date +%s)
                }]
            }" > /dev/null 2>&1 || true
    fi
}

# ========================================================================
# BACKUP FUNCTIONS
# ========================================================================

# Create backup directory structure
init_backup_dirs() {
    if ! mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly} "$BACKUP_DIR"/metadata "$BACKUP_DIR"/tmp 2>/dev/null; then
        log_warn "Cannot create backup directory $BACKUP_DIR, using fallback"
        BACKUP_DIR="${TMPDIR:-/private/tmp/claude-501}/moltis-backups"
        mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly} "$BACKUP_DIR"/metadata "$BACKUP_DIR"/tmp
    fi
}

# Generate checksum
generate_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"
    write_sha256_file "$file" "$checksum_file"

    # Extract just the hash for status tracking
    BACKUP_CHECKSUM=$(cut -d' ' -f1 "$checksum_file")
}

# Verify checksum
verify_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"

    if [[ ! -f "$checksum_file" ]]; then
        log_error "Checksum file not found: $checksum_file"
        return 1
    fi

    if verify_sha256_file "$file" "$checksum_file"; then
        log_info "Checksum verified: $file"
        return 0
    else
        log_error "Checksum verification failed: $file"
        return 1
    fi
}

# Encrypt file
encrypt_file() {
    local input_file="$1"
    local output_file="${input_file}.aes"

    if [[ "$ENCRYPTION_ENABLED" != "true" ]]; then
        log_info "Encryption disabled, skipping"
        BACKUP_ENCRYPTED=false
        ENCRYPTED_OUTPUT_FILE="$input_file"
        return 0
    fi

    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_error "Encryption key not found: $ENCRYPTION_KEY_FILE"
        BACKUP_ENCRYPTED=false
        ENCRYPTED_OUTPUT_FILE="$input_file"
        return 0
    fi

    log_info "Encrypting: $input_file"

    if openssl enc -aes-256-cbc \
        -salt -pbkdf2 \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$ENCRYPTION_KEY_FILE" \
        2>/dev/null; then

        # Verify encryption produced output
        if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
            rm -f "$input_file"
            # Also update checksum for encrypted file
            write_sha256_file "$output_file" "${output_file}.sha256"
            BACKUP_CHECKSUM=$(cut -d' ' -f1 "${output_file}.sha256")
            BACKUP_ENCRYPTED=true
            ENCRYPTED_OUTPUT_FILE="$output_file"
            log_info "Encryption complete: $output_file"
            return 0
        fi
    fi

    log_error "Encryption failed"
    BACKUP_ENCRYPTED=false
    ENCRYPTED_OUTPUT_FILE="$input_file"
    return 1
}

# Decrypt file (for restore)
decrypt_file() {
    local input_file="$1"
    local output_file="${input_file%.aes}"

    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_error "Encryption key not found"
        return 1
    fi

    log_info "Decrypting: $input_file"

    openssl enc -aes-256-cbc \
        -d -pbkdf2 \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$ENCRYPTION_KEY_FILE" \
        2>/dev/null

    if [[ -f "$output_file" ]]; then
        echo "$output_file"
        return 0
    else
        log_error "Decryption failed"
        return 1
    fi
}

# Create main backup
create_backup() {
    local backup_name="moltis_${BACKUP_TYPE}_${BACKUP_ID}"
    local backup_path="$BACKUP_DIR/$BACKUP_TYPE/${backup_name}.tar.gz"
    local tmp_dir="$BACKUP_DIR/tmp/${backup_name}"
    local clawdiy_included=false
    local env_included=false
    local compose_main_included=false
    local compose_prod_included=false
    local moltis_restore_ready=false

    log_info "Creating $BACKUP_TYPE backup: $backup_name"
    mkdir -p "$tmp_dir"

    # Export container state (if running)
    if container_is_running "moltis"; then
        log_info "Exporting container state..."
        docker inspect moltis > "$tmp_dir/container-inspect.json" 2>/dev/null || true
    fi

    if string_is_true "$CLAWDIY_BACKUP_ENABLED"; then
        if clawdiy_inventory_present; then
            clawdiy_included=true
            log_info "Recording Clawdiy inventory in backup metadata"

            cat > "$tmp_dir/$CLAWDIY_EVIDENCE_MANIFEST_NAME" <<EOF
{
  "schema_version": "v1",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "config_present": $(json_bool "$( [[ -d "$CLAWDIY_CONFIG_DIR" ]] && echo true || echo false )"),
  "runtime_present": $(json_bool "$( [[ -d "$CLAWDIY_RUNTIME_DIR" ]] && echo true || echo false )"),
  "state_present": $(json_bool "$( [[ -d "$CLAWDIY_STATE_DIR" ]] && echo true || echo false )"),
  "audit_present": $(json_bool "$( [[ -d "$CLAWDIY_AUDIT_DIR" ]] && echo true || echo false )"),
  "runtime_file_count": $(count_files_under "$CLAWDIY_RUNTIME_DIR"),
  "state_file_count": $(count_files_under "$CLAWDIY_STATE_DIR"),
  "audit_file_count": $(count_files_under "$CLAWDIY_AUDIT_DIR"),
  "latest_runtime_artifact": $(latest_file_under "$CLAWDIY_RUNTIME_DIR" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
  "latest_state_artifact": $(latest_file_under "$CLAWDIY_STATE_DIR" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
  "latest_audit_artifact": $(latest_file_under "$CLAWDIY_AUDIT_DIR" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end')
}
EOF
        else
            log_warn "Clawdiy backup inventory is enabled but no Clawdiy paths were found"
        fi

        if container_exists "$CLAWDIY_CONTAINER_NAME"; then
            log_info "Exporting Clawdiy container state..."
            docker inspect "$CLAWDIY_CONTAINER_NAME" > "$tmp_dir/clawdiy-container-inspect.json" 2>/dev/null || true
        fi
    fi

    if [[ -f "$RUNTIME_ENV_FILE" ]]; then
        env_included=true
    else
        log_warn "Runtime env file missing from backup scope: $RUNTIME_ENV_FILE"
    fi

    if [[ -f "$COMPOSE_FILE_MAIN" ]]; then
        compose_main_included=true
    else
        log_warn "Compose file missing from backup scope: $COMPOSE_FILE_MAIN"
    fi

    if [[ -f "$COMPOSE_FILE_PROD" ]]; then
        compose_prod_included=true
    else
        log_warn "Production compose file missing from backup scope: $COMPOSE_FILE_PROD"
    fi

    if [[ "$env_included" == "true" && "$compose_main_included" == "true" && "$compose_prod_included" == "true" ]]; then
        moltis_restore_ready=true
    fi

    # Create metadata
    cat > "$tmp_dir/backup-metadata.json" <<EOF
{
    "backup_id": "$BACKUP_ID",
    "backup_type": "$BACKUP_TYPE",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "version": "3.0",
    "config_dir": "$CONFIG_DIR",
    "data_dir": "$DATA_DIR",
    "clawdiy": {
        "enabled": $(json_bool "$CLAWDIY_BACKUP_ENABLED"),
        "included": $(json_bool "$clawdiy_included"),
        "config_dir": "$CLAWDIY_CONFIG_DIR",
        "runtime_dir": "$CLAWDIY_RUNTIME_DIR",
        "state_dir": "$CLAWDIY_STATE_DIR",
        "audit_dir": "$CLAWDIY_AUDIT_DIR",
        "container_name": "$CLAWDIY_CONTAINER_NAME"
    },
    "runtime_files": {
        "env_file": {
            "path": "$RUNTIME_ENV_FILE",
            "included": $(json_bool "$env_included")
        },
        "compose_file_main": {
            "path": "$COMPOSE_FILE_MAIN",
            "included": $(json_bool "$compose_main_included")
        },
        "compose_file_prod": {
            "path": "$COMPOSE_FILE_PROD",
            "included": $(json_bool "$compose_prod_included")
        }
    },
    "restore_readiness": {
        "moltis": {
            "ready": $(json_bool "$moltis_restore_ready"),
            "required": [
                "backup-metadata.json",
                "config/",
                "data/",
                ".env",
                "docker-compose.yml",
                "docker-compose.prod.yml"
            ],
            "clawdiy_runtime_dir": "$CLAWDIY_RUNTIME_DIR"
        }
    },
    "docker_version": "$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')"
}
EOF

    # Create tarball
    log_info "Creating tarball..."
    local -a tar_args
    tar_args=(
        -C "$tmp_dir" "backup-metadata.json"
    )

    if [[ -f "$tmp_dir/container-inspect.json" ]]; then
        tar_args+=(-C "$tmp_dir" "container-inspect.json")
    fi

    if [[ -f "$tmp_dir/clawdiy-container-inspect.json" ]]; then
        tar_args+=(-C "$tmp_dir" "clawdiy-container-inspect.json")
    fi

    if [[ -f "$tmp_dir/$CLAWDIY_EVIDENCE_MANIFEST_NAME" ]]; then
        tar_args+=(-C "$tmp_dir" "$CLAWDIY_EVIDENCE_MANIFEST_NAME")
    fi

    if [[ -f "$RUNTIME_ENV_FILE" ]]; then
        tar_args+=(-C "$(dirname "$RUNTIME_ENV_FILE")" "$(basename "$RUNTIME_ENV_FILE")")
    fi

    if [[ -f "$COMPOSE_FILE_MAIN" ]]; then
        tar_args+=(-C "$(dirname "$COMPOSE_FILE_MAIN")" "$(basename "$COMPOSE_FILE_MAIN")")
    fi

    if [[ -f "$COMPOSE_FILE_PROD" ]]; then
        tar_args+=(-C "$(dirname "$COMPOSE_FILE_PROD")" "$(basename "$COMPOSE_FILE_PROD")")
    fi

    tar_args+=(
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")"
        -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")"
    )

    if ! tar -czf "$backup_path" "${tar_args[@]}" 2>/dev/null; then
        log_error "Failed to create backup tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Cleanup temp
    rm -rf "$tmp_dir"

    # Generate checksum
    generate_checksum "$backup_path"

    # Encrypt
    local encrypted_path="$backup_path"
    if encrypt_file "$backup_path"; then
        encrypted_path="$ENCRYPTED_OUTPUT_FILE"
    else
        encrypted_path="${ENCRYPTED_OUTPUT_FILE:-$backup_path}"
    fi

    # Get size in bytes
    BACKUP_SIZE_BYTES=$(stat -f%z "$encrypted_path" 2>/dev/null || stat -c%s "$encrypted_path" 2>/dev/null || echo "0")
    BACKUP_LOCAL_PATH="$encrypted_path"

    local size_human
    size_human=$(du -h "$encrypted_path" | cut -f1)

    log_info "Backup created: $encrypted_path ($size_human)"
    return 0
}

# Upload to S3 with retry logic
upload_to_s3() {
    local file="$1"
    local s3_key="$S3_PREFIX/$BACKUP_TYPE/$(basename "$file")"

    if [[ "$S3_ENABLED" != "true" ]]; then
        return 0
    fi

    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI not found, skipping S3 upload"
        return 0
    fi

    log_info "Uploading to S3: s3://$S3_BUCKET/$s3_key"

    local attempt=0
    local max_attempts=$S3_MAX_RETRIES
    local success=false

    while [[ $attempt -lt $max_attempts ]]; do
        attempt=$((attempt + 1))

        # Calculate delay (exponential backoff)
        local delay_idx=$((attempt - 1))
        if [[ $delay_idx -ge ${#S3_RETRY_DELAYS[@]} ]]; then
            delay_idx=$(( ${#S3_RETRY_DELAYS[@]} - 1 ))
        fi
        local delay=${S3_RETRY_DELAYS[$delay_idx]}

        log_info "S3 upload attempt $attempt/$max_attempts..."

        if aws s3 cp "$file" "s3://$S3_BUCKET/$s3_key" \
            --region "$AWS_REGION" \
            --storage-class STANDARD_IA \
            2>&1 | tee -a "$LOG_FILE"; then

            # Upload checksum
            if [[ -f "${file}.sha256" ]]; then
                aws s3 cp "${file}.sha256" "s3://$S3_BUCKET/${s3_key}.sha256" \
                    --region "$AWS_REGION" \
                    2>/dev/null || true
            fi

            BACKUP_S3_LOCATION="s3://$S3_BUCKET/$s3_key"
            log_info "S3 upload successful: $BACKUP_S3_LOCATION"
            success=true
            break
        else
            log_warn "S3 upload attempt $attempt failed"

            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Retrying in ${delay}s (exponential backoff)..."
                sleep "$delay"
            fi
        fi
    done

    if [[ "$success" == "false" ]]; then
        log_error "S3 upload failed after $max_attempts attempts"
        return $EXIT_S3_UPLOAD_FAILED
    fi

    return 0
}

# Upload to SFTP
upload_to_sftp() {
    local file="$1"

    if [[ "$SFTP_ENABLED" != "true" ]]; then
        return 0
    fi

    log_info "Uploading to SFTP: $SFTP_HOST:$SFTP_PATH"

    sftp -o BatchMode=yes -o StrictHostKeyChecking=no \
        "${SFTP_USER}@${SFTP_HOST}:${SFTP_PATH}/${BACKUP_TYPE}/" <<< "put ${file}" \
        2>&1 | tee -a "$LOG_FILE" || log_warn "SFTP upload failed"
}

# Rotate old backups
rotate_backups() {
    log_info "Rotating old backups..."

    # Daily backups (keep last RETENTION_DAYS)
    find "$BACKUP_DIR/daily" -name "*.tar.gz*" -mtime +$RETENTION_DAYS -delete -print 2>/dev/null | \
        while read -r f; do log_info "Deleted old daily backup: $f"; done

    # Weekly backups (keep last RETENTION_WEEKS weeks)
    find "$BACKUP_DIR/weekly" -name "*.tar.gz*" -mtime +$((RETENTION_WEEKS * 7)) -delete -print 2>/dev/null | \
        while read -r f; do log_info "Deleted old weekly backup: $f"; done

    # Monthly backups (keep last RETENTION_MONTHS months)
    find "$BACKUP_DIR/monthly" -name "*.tar.gz*" -mtime +$((RETENTION_MONTHS * 30)) -delete -print 2>/dev/null | \
        while read -r f; do log_info "Deleted old monthly backup: $f"; done
}

# List available backups
list_backups() {
    echo "=== Available Backups ==="
    echo ""

    echo "Daily backups (last 7):"
    ls -lht "$BACKUP_DIR/daily"/*.tar.gz* 2>/dev/null | head -7 || echo "  None"
    echo ""

    echo "Weekly backups (last 4):"
    ls -lht "$BACKUP_DIR/weekly"/*.tar.gz* 2>/dev/null | head -4 || echo "  None"
    echo ""

    echo "Monthly backups (last 6):"
    ls -lht "$BACKUP_DIR/monthly"/*.tar.gz* 2>/dev/null | head -6 || echo "  None"
    echo ""

    echo "Total backup size:"
    du -sh "$BACKUP_DIR" 2>/dev/null || echo "  Unknown"
}

extract_backup_payload() {
    local backup_file="$1"
    local extract_dir="$2"
    local extract_file="$backup_file"

    if [[ "$backup_file" == *.aes ]]; then
        extract_file=$(decrypt_file "$backup_file")
    fi

    mkdir -p "$extract_dir"
    tar -xzf "$extract_file" -C "$extract_dir"
}

validate_restore_readiness() {
    local extracted_dir="$1"
    local metadata_file="$extracted_dir/backup-metadata.json"
    local expected_manifest="$extracted_dir/$CLAWDIY_EVIDENCE_MANIFEST_NAME"

    if [[ ! -f "$metadata_file" ]]; then
        log_error "Restore payload is missing backup-metadata.json"
        return 1
    fi

    if [[ ! -d "$extracted_dir/config" ]]; then
        log_error "Restore payload is missing config/"
        return 1
    fi

    if [[ ! -d "$extracted_dir/data" ]]; then
        log_error "Restore payload is missing data/"
        return 1
    fi

    if [[ ! -f "$extracted_dir/.env" ]]; then
        log_error "Restore payload is missing .env"
        return 1
    fi

    if [[ ! -f "$extracted_dir/docker-compose.yml" ]]; then
        log_error "Restore payload is missing docker-compose.yml"
        return 1
    fi

    if [[ ! -f "$extracted_dir/docker-compose.prod.yml" ]]; then
        log_error "Restore payload is missing docker-compose.prod.yml"
        return 1
    fi

    if ! jq -e '.restore_readiness.moltis.ready == true' "$metadata_file" >/dev/null 2>&1; then
        log_error "Backup metadata does not mark Moltis restore readiness as ready"
        return 1
    fi

    if [[ -f "$metadata_file" ]] && jq -e '.clawdiy.included == true' "$metadata_file" >/dev/null 2>&1; then
        if [[ ! -f "$expected_manifest" ]]; then
            log_error "Restore payload is missing $CLAWDIY_EVIDENCE_MANIFEST_NAME for Clawdiy"
            return 1
        fi

        if [[ ! -d "$extracted_dir/config/clawdiy" || ! -d "$extracted_dir/data/clawdiy/state" || ! -d "$extracted_dir/data/clawdiy/audit" ]]; then
            log_error "Restore payload is missing required Clawdiy config/state/audit directories"
            return 1
        fi
    fi

    log_info "Restore readiness verified for payload at $extracted_dir"
}

restore_check_backup() {
    local backup_file="$1"
    local restore_dir="${2:-}"
    local cleanup_dir=false

    if [[ -z "$restore_dir" ]]; then
        restore_dir=$(mktemp -d "${TMPDIR:-/tmp}/moltis-restore-check.XXXXXX")
        cleanup_dir=true
    fi

    if ! verify_backup "$backup_file"; then
        log_error "Backup verification failed, restore readiness check aborted"
        [[ "$cleanup_dir" == "true" ]] && rm -rf "$restore_dir"
        return 1
    fi

    if ! extract_backup_payload "$backup_file" "$restore_dir"; then
        log_error "Failed to extract backup payload for restore readiness check"
        [[ "$cleanup_dir" == "true" ]] && rm -rf "$restore_dir"
        return 1
    fi

    if ! validate_restore_readiness "$restore_dir"; then
        [[ "$cleanup_dir" == "true" ]] && rm -rf "$restore_dir"
        return 1
    fi

    if [[ "$cleanup_dir" == "true" ]]; then
        rm -rf "$restore_dir"
    fi

    log_info "Restore readiness check passed: $backup_file"
}

restore_runtime_file() {
    local source_file="$1"
    local target_file="$2"

    if [[ ! -f "$source_file" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$target_file")"
    cp "$source_file" "$target_file"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"

    log_info "Verifying backup: $backup_file"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    # Decrypt if needed
    local verify_file="$backup_file"
    if [[ "$backup_file" == *.aes ]]; then
        verify_file=$(decrypt_file "$backup_file")
    fi

    # Verify checksum
    if ! verify_checksum "$verify_file"; then
        log_error "Checksum verification failed"
        return 1
    fi

    # Verify tarball integrity
    if ! tar -tzf "$verify_file" > /dev/null 2>&1; then
        log_error "Tarball integrity check failed"
        return 1
    fi

    log_info "Backup integrity verified: $backup_file"
    return 0
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    local restore_dir="${2:-/tmp/moltis-restore}"
    local clawdiy_container_present=false
    local clawdiy_restore_expected=false
    local metadata_file=""

    log_info "Starting restore from: $backup_file"
    log_warn "This will OVERWRITE existing data!"

    if ! restore_check_backup "$backup_file" "$restore_dir"; then
        log_error "Restore readiness check failed, aborting restore"
        return 1
    fi

    metadata_file="$restore_dir/backup-metadata.json"

    if [[ -f "$metadata_file" ]] && jq -e '.clawdiy.included == true' "$metadata_file" >/dev/null 2>&1; then
        clawdiy_restore_expected=true
    fi

    if [[ "$clawdiy_restore_expected" != "true" ]] && clawdiy_inventory_present && ! string_is_true "$CLAWDIY_ALLOW_PARTIAL_RESTORE"; then
        log_error "Current runtime has Clawdiy inventory but the backup payload does not; set CLAWDIY_ALLOW_PARTIAL_RESTORE=true only for explicit partial restores"
        return 1
    fi

    # Stop container
    log_info "Stopping Moltis container..."
    docker stop moltis 2>/dev/null || true

    if container_exists "$CLAWDIY_CONTAINER_NAME"; then
        clawdiy_container_present=true
        log_info "Stopping Clawdiy container..."
        docker stop "$CLAWDIY_CONTAINER_NAME" 2>/dev/null || true
    fi

    # Restore data
    log_info "Restoring data..."
    rsync -av --delete "$restore_dir/data/" "$DATA_DIR/"
    rsync -av --delete "$restore_dir/config/" "$CONFIG_DIR/"

    if string_is_true "$BACKUP_RESTORE_RUNTIME_FILES"; then
        log_info "Restoring runtime env and compose files..."
        restore_runtime_file "$restore_dir/.env" "$RUNTIME_ENV_FILE"
        restore_runtime_file "$restore_dir/docker-compose.yml" "$COMPOSE_FILE_MAIN"
        restore_runtime_file "$restore_dir/docker-compose.prod.yml" "$COMPOSE_FILE_PROD"
    fi

    if string_is_true "$CLAWDIY_BACKUP_ENABLED" && [[ -e "$restore_dir/config/clawdiy" || -e "$restore_dir/data/clawdiy" ]]; then
        log_info "Clawdiy backup inventory detected in restore payload"
        mkdir -p "$CLAWDIY_STATE_DIR" "$CLAWDIY_AUDIT_DIR" 2>/dev/null || true
    fi

    # Start container
    log_info "Starting Moltis container..."
    cd "$PROJECT_ROOT"
    docker compose -f "$PROJECT_ROOT/docker-compose.prod.yml" up -d moltis

    if [[ "$clawdiy_container_present" == "true" ]] && string_is_true "$CLAWDIY_RESTORE_AUTOSTART"; then
        log_info "Starting Clawdiy container..."
        if [[ -f "$PROJECT_ROOT/docker-compose.clawdiy.yml" ]]; then
            local -a clawdiy_compose_args
            local clawdiy_env_file="${CLAWDIY_ENV_FILE:-$PROJECT_ROOT/.env.clawdiy}"
            clawdiy_compose_args=(-f "$PROJECT_ROOT/docker-compose.clawdiy.yml")
            if [[ -f "$clawdiy_env_file" ]]; then
                clawdiy_compose_args=(--env-file "$clawdiy_env_file" "${clawdiy_compose_args[@]}")
            fi
            docker compose "${clawdiy_compose_args[@]}" up -d "$CLAWDIY_CONTAINER_NAME" 2>/dev/null || \
                docker start "$CLAWDIY_CONTAINER_NAME" 2>/dev/null || \
                log_warn "Failed to start Clawdiy container automatically after restore"
        else
            docker start "$CLAWDIY_CONTAINER_NAME" 2>/dev/null || \
                log_warn "Failed to start Clawdiy container automatically after restore"
        fi
    fi

    if [[ "$clawdiy_restore_expected" == "true" ]]; then
        mkdir -p "$CLAWDIY_AUDIT_DIR" 2>/dev/null || true
        cat > "$CLAWDIY_AUDIT_DIR/restore-report-$(date -u +%Y%m%dT%H%M%SZ).json" <<EOF
{
  "schema_version": "v1",
  "restored_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_file": "$backup_file",
  "restore_dir": "$restore_dir",
  "clawdiy_config_dir": "$CLAWDIY_CONFIG_DIR",
  "clawdiy_state_dir": "$CLAWDIY_STATE_DIR",
  "clawdiy_audit_dir": "$CLAWDIY_AUDIT_DIR",
  "clawdiy_container_autostarted": $(json_bool "$CLAWDIY_RESTORE_AUTOSTART")
}
EOF
    fi

    log_info "Restore complete!"
    send_notification "Restore Complete" "Successfully restored from $backup_file" "info"
}

# ========================================================================
# MAIN EXECUTION
# ========================================================================

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS] {backup|verify|restore-check|restore|list|rotate|generate-key}

Commands:
  backup                Create a new backup
  verify <file>         Verify backup integrity
  restore-check <file>  Verify that a backup is restore-ready without mutating runtime
  restore <file> [dir]  Restore from backup
  list                  List available backups
  rotate                Rotate old backups
  generate-key          Generate encryption key

Options:
  --json                Output results in JSON format
  --help                Show this help message

Exit Codes:
  0  Success
  1  General error
  2  Backup creation failed
  3  S3 upload failed

Environment Variables:
  BACKUP_CONFIG         Path to backup configuration file
  PROMETHEUS_TEXTFILE_DIR  Directory for Prometheus metrics (default: /var/lib/node_exporter/textfile_dir)
  BACKUP_STATUS_FILE    Path to backup status JSON file (default: /var/lib/moltis/backup-status.json)

Examples:
  $0 backup                          # Create backup (human-readable output)
  $0 --json backup                   # Create backup (JSON output)
  $0 verify /path/to/backup          # Verify backup integrity
  $0 restore-check /path/to/backup   # Verify restore readiness
  $0 list                            # List all backups
EOF
}

main() {
    local action=""
    local action_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            backup|verify|restore-check|restore|list|rotate|generate-key)
                action="$1"
                shift
                # Collect remaining arguments for the action
                while [[ $# -gt 0 ]]; do
                    action_args+=("$1")
                    shift
                done
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit $EXIT_GENERAL_ERROR
                ;;
        esac
    done

    # Default action
    if [[ -z "$action" ]]; then
        action="backup"
    fi

    case "$action" in
        backup)
            # Record start time
            BACKUP_START_TIME=$(current_time_ms)

            if [[ "$JSON_OUTPUT" != "true" ]]; then
                log_info "=========================================="
                log_info "Starting Moltis backup - ID: $BACKUP_ID"
                log_info "Type: $BACKUP_TYPE"
                log_info "=========================================="
            fi

            init_backup_dirs

            local backup_result=0

            if create_backup; then
                local backup_file="$BACKUP_LOCAL_PATH"
                # Upload to S3 with retry logic
                local s3_result=0
                upload_to_s3 "$backup_file" || s3_result=$?

                if [[ $s3_result -eq $EXIT_S3_UPLOAD_FAILED ]]; then
                    backup_result=$EXIT_S3_UPLOAD_FAILED
                fi

                upload_to_sftp "$backup_file"
                rotate_backups

                # Record end time and calculate duration
                BACKUP_END_TIME=$(current_time_ms)
                BACKUP_DURATION_MS=$((BACKUP_END_TIME - BACKUP_START_TIME))

                # Determine final status
                local final_status="success"
                if [[ $backup_result -ne 0 ]]; then
                    final_status="partial"  # Backup created but S3 failed
                fi

                # Write metrics and status
                write_prometheus_metrics "$final_status"
                write_backup_status "$final_status"

                if [[ "$JSON_OUTPUT" == "true" ]]; then
                    output_json "$final_status"
                else
                    local size_human
                    size_human=$(numfmt --to=iec-i --suffix=B "$BACKUP_SIZE_BYTES" 2>/dev/null || \
                                 echo "$(( BACKUP_SIZE_BYTES / 1024 / 1024 ))MB")

                    send_notification "Backup Complete" \
                        "Successfully created $BACKUP_TYPE backup\nSize: $size_human" \
                        "info"

                    log_info "Backup completed successfully"
                    log_info "Duration: ${BACKUP_DURATION_MS}ms"
                fi

                # Return S3 failure code if applicable
                if [[ $s3_result -eq $EXIT_S3_UPLOAD_FAILED ]]; then
                    exit $EXIT_S3_UPLOAD_FAILED
                fi
            else
                # Record end time
                BACKUP_END_TIME=$(current_time_ms)
                BACKUP_DURATION_MS=$((BACKUP_END_TIME - BACKUP_START_TIME))

                # Write metrics and status
                write_prometheus_metrics "failed"
                write_backup_status "failed"

                if [[ "$JSON_OUTPUT" == "true" ]]; then
                    output_json "failed"
                else
                    send_notification "Backup Failed" "Backup creation failed" "error"
                    log_error "Backup failed"
                fi
                exit $EXIT_BACKUP_FAILED
            fi
            ;;

        verify)
            local backup_file="${action_args[0]:-}"
            if [[ -z "$backup_file" ]]; then
                log_error "Usage: $0 verify <backup-file>"
                exit $EXIT_GENERAL_ERROR
            fi
            verify_backup "$backup_file"
            ;;

        restore-check)
            local backup_file="${action_args[0]:-}"
            local restore_dir="${action_args[1]:-}"
            if [[ -z "$backup_file" ]]; then
                log_error "Usage: $0 restore-check <backup-file> [restore-dir]"
                exit $EXIT_GENERAL_ERROR
            fi
            restore_check_backup "$backup_file" "$restore_dir"
            ;;

        restore)
            local backup_file="${action_args[0]:-}"
            local restore_dir="${action_args[1]:-/tmp/moltis-restore}"
            if [[ -z "$backup_file" ]]; then
                log_error "Usage: $0 restore <backup-file> [restore-dir]"
                exit $EXIT_GENERAL_ERROR
            fi
            restore_backup "$backup_file" "$restore_dir"
            ;;

        list)
            init_backup_dirs
            list_backups
            ;;

        rotate)
            init_backup_dirs
            rotate_backups
            ;;

        generate-key)
            local key_file="${action_args[0]:-$ENCRYPTION_KEY_FILE}"
            log_info "Generating encryption key: $key_file"
            mkdir -p "$(dirname "$key_file")"
            openssl rand -base64 32 > "$key_file"
            chmod 600 "$key_file"
            log_info "Key generated successfully"
            ;;

        *)
            show_usage
            exit $EXIT_GENERAL_ERROR
            ;;
    esac
}

main "$@"
