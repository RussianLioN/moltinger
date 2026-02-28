#!/bin/bash
# Moltis Enterprise Backup Script with Disaster Recovery
# Version: 2.1
# Features: Encryption, offsite backup, integrity verification, point-in-time recovery, GitOps guards

set -euo pipefail

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
CONFIG_FILE="${BACKUP_CONFIG:-$PROJECT_ROOT/config/backup.conf}"

# Default configuration (can be overridden by config file)
BACKUP_DIR="/var/backups/moltis"
CONFIG_DIR="$PROJECT_ROOT/config"
DATA_DIR="$PROJECT_ROOT/data"
LOG_DIR="/var/log/moltis"
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

# Remote backup (SFTP)
SFTP_ENABLED=false
SFTP_HOST=""
SFTP_USER=""
SFTP_PATH="/backups/moltis"

# Notifications
NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

# ========================================================================
# INITIALIZATION
# ========================================================================

# Load configuration file if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Setup logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/backup-$(date +%Y%m%d).log"
BACKUP_ID="$(date +%Y%m%d_%H%M%S)"
BACKUP_TYPE="daily"

# Determine backup type based on day
case "$(date +%u)" in
    7) BACKUP_TYPE="weekly" ;;
esac
if [[ "$(date +%d)" == "01" ]]; then
    BACKUP_TYPE="monthly"
fi

# ========================================================================
# LOGGING FUNCTIONS
# ========================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

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
    mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly}
    mkdir -p "$BACKUP_DIR"/metadata
    mkdir -p "$BACKUP_DIR"/tmp
}

# Generate checksum
generate_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"
    sha256sum "$file" > "$checksum_file"
    echo "$checksum_file"
}

# Verify checksum
verify_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"

    if [[ ! -f "$checksum_file" ]]; then
        log_error "Checksum file not found: $checksum_file"
        return 1
    fi

    if sha256sum -c "$checksum_file" --quiet 2>/dev/null; then
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
    local output_file="${input_file}.enc"

    if [[ "$ENCRYPTION_ENABLED" != "true" ]]; then
        log_info "Encryption disabled, skipping"
        echo "$input_file"
        return 0
    fi

    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_error "Encryption key not found: $ENCRYPTION_KEY_FILE"
        echo "$input_file"
        return 0
    fi

    log_info "Encrypting: $input_file"

    openssl enc -aes-256-cbc \
        -salt -pbkdf2 \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$ENCRYPTION_KEY_FILE" \
        2>/dev/null

    # Verify encryption
    if [[ -f "$output_file" ]]; then
        rm -f "$input_file"
        log_info "Encryption complete: $output_file"
        echo "$output_file"
        return 0
    else
        log_error "Encryption failed"
        echo "$input_file"
        return 1
    fi
}

# Decrypt file (for restore)
decrypt_file() {
    local input_file="$1"
    local output_file="${input_file%.enc}"

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

    log_info "Creating $BACKUP_TYPE backup: $backup_name"
    mkdir -p "$tmp_dir"

    # Export container state (if running)
    if docker ps --format '{{.Names}}' | grep -q '^moltis$'; then
        log_info "Exporting container state..."
        docker inspect moltis > "$tmp_dir/container-inspect.json" 2>/dev/null || true
    fi

    # Create metadata
    cat > "$tmp_dir/backup-metadata.json" <<EOF
{
    "backup_id": "$BACKUP_ID",
    "backup_type": "$BACKUP_TYPE",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "version": "2.0",
    "config_dir": "$CONFIG_DIR",
    "data_dir": "$DATA_DIR",
    "docker_version": "$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')"
}
EOF

    # Create tarball
    log_info "Creating tarball..."
    tar -czf "$backup_path" \
        -C "$tmp_dir" "backup-metadata.json" \
        -C "$tmp_dir" "container-inspect.json" 2>/dev/null || true \
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" \
        -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" \
        2>/dev/null

    # Cleanup temp
    rm -rf "$tmp_dir"

    # Generate checksum
    generate_checksum "$backup_path"

    # Encrypt
    local encrypted_path
    encrypted_path=$(encrypt_file "$backup_path")

    # Get size
    local size
    size=$(du -h "$encrypted_path" | cut -f1)

    log_info "Backup created: $encrypted_path ($size)"

    echo "$encrypted_path"
}

# Upload to S3
upload_to_s3() {
    local file="$1"
    local s3_key="$S3_PREFIX/$BACKUP_TYPE/$(basename "$file")"

    if [[ "$S3_ENABLED" != "true" ]]; then
        return 0
    fi

    log_info "Uploading to S3: s3://$S3_BUCKET/$s3_key"

    if command -v aws &> /dev/null; then
        aws s3 cp "$file" "s3://$S3_BUCKET/$s3_key" \
            --region "$AWS_REGION" \
            --storage-class STANDARD_IA \
            2>&1 | tee -a "$LOG_FILE"

        # Upload checksum
        if [[ -f "${file}.sha256" ]]; then
            aws s3 cp "${file}.sha256" "s3://$S3_BUCKET/${s3_key}.sha256" \
                --region "$AWS_REGION" \
                2>/dev/null || true
        fi
    else
        log_warn "AWS CLI not found, skipping S3 upload"
    fi
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
    if [[ "$backup_file" == *.enc ]]; then
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

    log_info "Starting restore from: $backup_file"
    log_warn "This will OVERWRITE existing data!"

    # Verify backup first
    if ! verify_backup "$backup_file"; then
        log_error "Backup verification failed, aborting restore"
        return 1
    fi

    # Decrypt if needed
    local restore_file="$backup_file"
    if [[ "$backup_file" == *.enc ]]; then
        restore_file=$(decrypt_file "$backup_file")
    fi

    # Create restore directory
    mkdir -p "$restore_dir"

    # Extract backup
    log_info "Extracting backup to: $restore_dir"
    tar -xzf "$restore_file" -C "$restore_dir"

    # Stop container
    log_info "Stopping Moltis container..."
    docker stop moltis 2>/dev/null || true

    # Restore data
    log_info "Restoring data..."
    rsync -av --delete "$restore_dir/data/" "$DATA_DIR/"
    rsync -av --delete "$restore_dir/config/" "$CONFIG_DIR/"

    # Start container
    log_info "Starting Moltis container..."
    cd "$PROJECT_ROOT"
    docker compose up -d

    log_info "Restore complete!"
    send_notification "Restore Complete" "Successfully restored from $backup_file" "info"
}

# ========================================================================
# MAIN EXECUTION
# ========================================================================

main() {
    local action="${1:-backup}"

    case "$action" in
        backup)
            log_info "=========================================="
            log_info "Starting Moltis backup - ID: $BACKUP_ID"
            log_info "Type: $BACKUP_TYPE"
            log_info "=========================================="

            init_backup_dirs

            local backup_file
            if backup_file=$(create_backup); then
                upload_to_s3 "$backup_file"
                upload_to_sftp "$backup_file"
                rotate_backups

                send_notification "Backup Complete" \
                    "Successfully created $BACKUP_TYPE backup\nSize: $(du -h "$backup_file" | cut -f1)" \
                    "info"

                log_info "Backup completed successfully"
            else
                send_notification "Backup Failed" "Backup creation failed" "error"
                log_error "Backup failed"
                exit 1
            fi
            ;;

        verify)
            local backup_file="${2:-}"
            if [[ -z "$backup_file" ]]; then
                log_error "Usage: $0 verify <backup-file>"
                exit 1
            fi
            verify_backup "$backup_file"
            ;;

        restore)
            local backup_file="${2:-}"
            local restore_dir="${3:-/tmp/moltis-restore}"
            if [[ -z "$backup_file" ]]; then
                log_error "Usage: $0 restore <backup-file> [restore-dir]"
                exit 1
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
            local key_file="${2:-$ENCRYPTION_KEY_FILE}"
            log_info "Generating encryption key: $key_file"
            mkdir -p "$(dirname "$key_file")"
            openssl rand -base64 32 > "$key_file"
            chmod 600 "$key_file"
            log_info "Key generated successfully"
            ;;

        *)
            echo "Usage: $0 {backup|verify|restore|list|rotate|generate-key}"
            echo ""
            echo "Commands:"
            echo "  backup        - Create a new backup"
            echo "  verify <file> - Verify backup integrity"
            echo "  restore <file> [dir] - Restore from backup"
            echo "  list          - List available backups"
            echo "  rotate        - Rotate old backups"
            echo "  generate-key  - Generate encryption key"
            exit 1
            ;;
    esac
}

main "$@"
