#!/bin/bash
# Moltis Backup Script
# Daily backup with 7-day retention

set -e

# Configuration
BACKUP_DIR="/var/backups/moltis"
CONFIG_DIR="/opt/moltinger/config"
DATA_DIR="/opt/moltinger/data"
RETENTION_DAYS=7

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/moltis_$TIMESTAMP.tar.gz"

# Create backup
echo "[$(date)] Starting backup..."
tar -czf "$BACKUP_FILE" \
    -C "$(dirname $CONFIG_DIR)" "$(basename $CONFIG_DIR)" \
    -C "$(dirname $DATA_DIR)" "$(basename $DATA_DIR)" \
    2>/dev/null

# Check backup
if [ -f "$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "[$(date)] Backup created: $BACKUP_FILE ($SIZE)"
else
    echo "[$(date)] ERROR: Backup failed"
    exit 1
fi

# Rotate old backups
echo "[$(date)] Rotating backups older than $RETENTION_DAYS days..."
DELETED=$(find "$BACKUP_DIR" -name "moltis_*.tar.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
echo "[$(date)] Deleted $DELETED old backup(s)"

# List current backups
echo "[$(date)] Current backups:"
ls -lh "$BACKUP_DIR"/moltis_*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  None"

echo "[$(date)] Backup complete"
