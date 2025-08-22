#!/bin/bash
# Automated Database Backup Script for Trading Service on NAS
# This script is designed to run via Synology Task Scheduler

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

# Paths (NAS specific)
BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
CONTAINER_NAME="trading-service-db-1"
DB_NAME="trading"
DB_USER="postgres"
LOG_FILE="/volume1/docker/trading-service/logs/backup.log"
LOCK_FILE="/tmp/trading-backup.lock"

# Backup settings
RETENTION_DAYS=${RETENTION_DAYS:-30}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_${TIMESTAMP}.sql.gz"
MAX_BACKUP_SIZE=$((5 * 1024 * 1024 * 1024))  # 5GB max backup size

# Notification settings (optional)
NOTIFY_EMAIL="${BACKUP_NOTIFY_EMAIL:-}"
NOTIFY_ON_ERROR=true
NOTIFY_ON_SUCCESS=false

# ============================================================================
# FUNCTIONS
# ============================================================================

# Ensure log directory exists
mkdir -p $(dirname $LOG_FILE)

# Function to log messages
log_message() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a $LOG_FILE
}

# Function to send notification
send_notification() {
    local subject=$1
    local body=$2
    
    if [ -n "$NOTIFY_EMAIL" ]; then
        echo "$body" | mail -s "Trading Service Backup: $subject" "$NOTIFY_EMAIL" 2>/dev/null || true
    fi
    
    # Also log to Synology notification center if available
    if command -v synologset1 >/dev/null 2>&1; then
        synologset1 sys err 0x11800000 "Trading Service Backup: $subject"
    fi
}

# Function to cleanup on exit
cleanup() {
    rm -f $LOCK_FILE
}

# Function to check disk space
check_disk_space() {
    local available=$(df /volume1 | awk 'NR==2 {print $4}')
    local required=$((1024 * 1024))  # Require at least 1GB free
    
    if [ $available -lt $required ]; then
        log_message "ERROR" "Insufficient disk space. Available: ${available}KB, Required: ${required}KB"
        return 1
    fi
    return 0
}

# Function to verify backup
verify_backup() {
    local backup_path=$1
    
    # Check if file exists and is not empty
    if [ ! -f "$backup_path" ] || [ ! -s "$backup_path" ]; then
        return 1
    fi
    
    # Test gzip integrity
    if ! gunzip -t "$backup_path" 2>/dev/null; then
        return 1
    fi
    
    # Check file size is reasonable
    local size=$(stat -c%s "$backup_path")
    if [ $size -gt $MAX_BACKUP_SIZE ]; then
        log_message "WARNING" "Backup size ($size bytes) exceeds maximum ($MAX_BACKUP_SIZE bytes)"
    fi
    
    return 0
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

# Set trap for cleanup
trap cleanup EXIT

# Check if another backup is running
if [ -f "$LOCK_FILE" ]; then
    log_message "WARNING" "Another backup is already running (lock file exists)"
    exit 0
fi

# Create lock file
echo $$ > $LOCK_FILE

# Start backup process
log_message "INFO" "Starting automated database backup"

# Check disk space
if ! check_disk_space; then
    log_message "ERROR" "Pre-flight check failed: insufficient disk space"
    if [ "$NOTIFY_ON_ERROR" = true ]; then
        send_notification "Backup Failed" "Insufficient disk space on NAS"
    fi
    exit 1
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_message "ERROR" "Container ${CONTAINER_NAME} is not running"
    if [ "$NOTIFY_ON_ERROR" = true ]; then
        send_notification "Backup Failed" "Database container is not running"
    fi
    exit 1
fi

# Ensure backup directory exists
mkdir -p $BACKUP_DIR

# Get database password from container environment
DB_PASSWORD=$(docker exec $CONTAINER_NAME printenv POSTGRES_PASSWORD 2>/dev/null || echo "")
if [ -z "$DB_PASSWORD" ]; then
    log_message "WARNING" "Could not retrieve database password, attempting without password"
fi

# Perform database backup
log_message "INFO" "Creating backup: ${BACKUP_FILE}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"

# Execute backup with error handling
if docker exec $CONTAINER_NAME sh -c "PGPASSWORD='$DB_PASSWORD' pg_dump -U $DB_USER -d $DB_NAME --verbose --no-owner --no-acl" 2>>$LOG_FILE | gzip -9 > "${BACKUP_PATH}.tmp"; then
    # Move temp file to final location
    mv "${BACKUP_PATH}.tmp" "$BACKUP_PATH"
    
    # Get backup size
    BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
    log_message "INFO" "Backup created successfully. Size: ${BACKUP_SIZE}"
    
    # Verify backup integrity
    if verify_backup "$BACKUP_PATH"; then
        log_message "INFO" "Backup verification passed"
    else
        log_message "ERROR" "Backup verification failed"
        rm -f "$BACKUP_PATH"
        if [ "$NOTIFY_ON_ERROR" = true ]; then
            send_notification "Backup Failed" "Backup verification failed for ${BACKUP_FILE}"
        fi
        exit 1
    fi
else
    log_message "ERROR" "Backup creation failed"
    rm -f "${BACKUP_PATH}.tmp"
    if [ "$NOTIFY_ON_ERROR" = true ]; then
        send_notification "Backup Failed" "Failed to create backup ${BACKUP_FILE}"
    fi
    exit 1
fi

# Clean up old backups
log_message "INFO" "Cleaning up backups older than ${RETENTION_DAYS} days"
DELETED_COUNT=0
while IFS= read -r old_backup; do
    if [ -f "$old_backup" ]; then
        rm -f "$old_backup"
        log_message "INFO" "Deleted old backup: $(basename $old_backup)"
        ((DELETED_COUNT++))
    fi
done < <(find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +${RETENTION_DAYS} -type f 2>/dev/null)

if [ $DELETED_COUNT -gt 0 ]; then
    log_message "INFO" "Deleted $DELETED_COUNT old backup(s)"
fi

# Count remaining backups
BACKUP_COUNT=$(ls -1 $BACKUP_DIR/backup_*.sql.gz 2>/dev/null | wc -l)
log_message "INFO" "Total backups retained: ${BACKUP_COUNT}"

# Create latest symlink for easy access
ln -sf "$BACKUP_PATH" "${BACKUP_DIR}/latest.sql.gz"

# Optional: Sync to secondary location
SECONDARY_BACKUP="/volume1/backups/trading-service"
if [ -d "/volume1/backups" ]; then
    log_message "INFO" "Syncing to secondary backup location"
    mkdir -p $SECONDARY_BACKUP
    if rsync -av --delete $BACKUP_DIR/ $SECONDARY_BACKUP/ >> $LOG_FILE 2>&1; then
        log_message "INFO" "Secondary backup sync completed"
    else
        log_message "WARNING" "Secondary backup sync failed"
    fi
fi

# Report success
log_message "INFO" "Backup process completed successfully"

# Send success notification if configured
if [ "$NOTIFY_ON_SUCCESS" = true ] && [ -n "$NOTIFY_EMAIL" ]; then
    send_notification "Backup Successful" "Backup ${BACKUP_FILE} created successfully (${BACKUP_SIZE})"
fi

# Log summary statistics
log_message "INFO" "========================================="
log_message "INFO" "Backup Summary:"
log_message "INFO" "  File: ${BACKUP_FILE}"
log_message "INFO" "  Size: ${BACKUP_SIZE}"
log_message "INFO" "  Retained backups: ${BACKUP_COUNT}"
log_message "INFO" "  Deleted old backups: ${DELETED_COUNT}"
log_message "INFO" "========================================="

exit 0