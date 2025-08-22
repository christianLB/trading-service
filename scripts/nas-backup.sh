#!/bin/bash
# Automated Database Backup Script for Trading Service on NAS
# This script is designed to run via Synology Task Scheduler

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

# Paths (NAS specific)
BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
CONTAINER_NAME="trading-service-db"
DOCKER_CMD="/usr/local/bin/docker"
DB_NAME="trading"
DB_USER="postgres"
LOG_FILE="/volume1/docker/trading-service/logs/backup.log"
LOCK_FILE="/tmp/trading-backup.lock"

# Backup settings
MAX_BACKUPS=30  # Keep 30 days of backups
BACKUP_PREFIX="trading_db"
DATE_FORMAT="%Y%m%d_%H%M%S"

# Email notification (optional)
NOTIFY_ON_SUCCESS=false
NOTIFY_ON_ERROR=true
EMAIL_TO="admin@example.com"
EMAIL_SUBJECT_PREFIX="[Trading Service Backup]"

# ============================================================================
# FUNCTIONS
# ============================================================================

# Logging function
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Email notification function (uses Synology's built-in mail system)
send_notification() {
    local subject="$1"
    local body="$2"
    
    if command -v synodsmnotify &> /dev/null; then
        synodsmnotify @administrators "$EMAIL_SUBJECT_PREFIX $subject" "$body"
    else
        log_message "WARNING" "synodsmnotify not available, skipping email notification"
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log_message "INFO" "Cleaning up old backups (keeping last $MAX_BACKUPS)"
    
    # Count existing backups
    local backup_count=$(ls -1 ${BACKUP_DIR}/${BACKUP_PREFIX}_*.sql.gz 2>/dev/null | wc -l)
    
    if [ $backup_count -gt $MAX_BACKUPS ]; then
        local backups_to_delete=$((backup_count - MAX_BACKUPS))
        log_message "INFO" "Removing $backups_to_delete old backup(s)"
        
        # Remove oldest backups
        ls -1t ${BACKUP_DIR}/${BACKUP_PREFIX}_*.sql.gz | tail -n $backups_to_delete | while read backup; do
            rm "$backup"
            log_message "INFO" "Removed old backup: $(basename $backup)"
        done
    else
        log_message "INFO" "No cleanup needed ($backup_count backups found)"
    fi
}

# Check disk space
check_disk_space() {
    local required_space_mb=500  # Require at least 500MB free
    local available_space_kb=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    local available_space_mb=$((available_space_kb / 1024))
    
    if [ $available_space_mb -lt $required_space_mb ]; then
        log_message "ERROR" "Insufficient disk space: ${available_space_mb}MB available, ${required_space_mb}MB required"
        return 1
    fi
    
    log_message "INFO" "Disk space check passed: ${available_space_mb}MB available"
    return 0
}

# Calculate backup size
get_backup_size() {
    local file=$1
    if [ -f "$file" ]; then
        local size_bytes=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        local size_mb=$((size_bytes / 1024 / 1024))
        echo "${size_mb}MB"
    else
        echo "0MB"
    fi
}

# ============================================================================
# MAIN BACKUP PROCESS
# ============================================================================

log_message "INFO" "Starting automated database backup"

# Check for lock file (prevent concurrent backups)
if [ -f "$LOCK_FILE" ]; then
    log_message "ERROR" "Backup already in progress (lock file exists)"
    if [ "$NOTIFY_ON_ERROR" = true ]; then
        send_notification "Backup Failed" "Another backup is already running"
    fi
    exit 1
fi

# Create lock file
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Check disk space
if ! check_disk_space; then
    if [ "$NOTIFY_ON_ERROR" = true ]; then
        send_notification "Backup Failed" "Insufficient disk space"
    fi
    exit 1
fi

# Check if container is running
if ! $DOCKER_CMD ps --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    log_message "ERROR" "Container ${CONTAINER_NAME} is not running"
    if [ "$NOTIFY_ON_ERROR" = true ]; then
        send_notification "Backup Failed" "Database container is not running"
    fi
    exit 1
fi

# Ensure backup directory exists
mkdir -p $BACKUP_DIR

# Get database password from container environment
DB_PASSWORD=$($DOCKER_CMD exec $CONTAINER_NAME printenv POSTGRES_PASSWORD 2>/dev/null || echo "")
if [ -z "$DB_PASSWORD" ]; then
    log_message "WARNING" "Could not retrieve database password, attempting without password"
fi

# Generate backup filename
TIMESTAMP=$(date +"$DATE_FORMAT")
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_PREFIX}_${TIMESTAMP}.sql.gz"

# Perform backup
log_message "INFO" "Starting backup to: $(basename $BACKUP_PATH)"
if $DOCKER_CMD exec $CONTAINER_NAME sh -c "PGPASSWORD='$DB_PASSWORD' pg_dump -U $DB_USER -d $DB_NAME --verbose --no-owner --no-acl" 2>>$LOG_FILE | gzip -9 > "${BACKUP_PATH}.tmp"; then
    # Move temp file to final location
    mv "${BACKUP_PATH}.tmp" "$BACKUP_PATH"
    
    # Get backup size
    BACKUP_SIZE=$(get_backup_size "$BACKUP_PATH")
    
    log_message "SUCCESS" "Backup completed successfully: $(basename $BACKUP_PATH) (Size: $BACKUP_SIZE)"
    
    # Verify backup integrity
    if gunzip -t "$BACKUP_PATH" 2>/dev/null; then
        log_message "INFO" "Backup integrity verified"
    else
        log_message "ERROR" "Backup integrity check failed!"
        rm "$BACKUP_PATH"
        if [ "$NOTIFY_ON_ERROR" = true ]; then
            send_notification "Backup Failed" "Backup integrity check failed"
        fi
        exit 1
    fi
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Send success notification if enabled
    if [ "$NOTIFY_ON_SUCCESS" = true ]; then
        send_notification "Backup Successful" "Database backed up successfully (${BACKUP_SIZE})"
    fi
    
    # Log statistics
    TOTAL_BACKUPS=$(ls -1 ${BACKUP_DIR}/${BACKUP_PREFIX}_*.sql.gz 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh ${BACKUP_DIR}/${BACKUP_PREFIX}_*.sql.gz 2>/dev/null | tail -1 | cut -f1)
    log_message "INFO" "Backup statistics: $TOTAL_BACKUPS backups, Total size: $TOTAL_SIZE"
    
else
    log_message "ERROR" "Backup failed!"
    rm -f "${BACKUP_PATH}.tmp"
    
    if [ "$NOTIFY_ON_ERROR" = true ]; then
        send_notification "Backup Failed" "Database backup failed. Check logs for details."
    fi
    exit 1
fi

log_message "INFO" "Backup process completed"
exit 0