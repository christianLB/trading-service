#!/bin/bash
# Automated Database Backup Script for Trading Service
# This script should be run on the NAS via cron/Task Scheduler

set -e

# Detect environment (NAS or local)
if [ -d "/volume1" ]; then
    # NAS environment
    BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
    LOG_FILE="/volume1/docker/trading-service/logs/backup.log"
    SECONDARY_BACKUP="/volume1/backups/trading-service"
else
    # Local/development environment
    BACKUP_DIR="./backups/postgres"
    LOG_FILE="./logs/backup.log"
    SECONDARY_BACKUP=""
fi

# Configuration
CONTAINER_NAME="deploy-db-1"
DB_NAME="trading"
DB_USER="postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_${TIMESTAMP}.sql.gz"
RETENTION_DAYS=${RETENTION_DAYS:-30}

# Ensure directories exist (only if we have permissions)
if [ -w "." ] || [ ! -d "/volume1" ]; then
    # Local environment - create directories
    mkdir -p $(dirname $LOG_FILE) 2>/dev/null || true
    mkdir -p $BACKUP_DIR 2>/dev/null || true
fi

# Function to log messages
log_message() {
    MSG="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$MSG"
    if [ -w "$LOG_FILE" ] || [ -w "$(dirname $LOG_FILE)" ] 2>/dev/null; then
        echo "$MSG" >> $LOG_FILE
    fi
}

# Start backup
log_message "Starting database backup..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_message "ERROR: Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Ensure backup directory exists (only if we have permissions)
if [ -w "$(dirname $BACKUP_DIR)" ] 2>/dev/null || [ ! -d "/volume1" ]; then
    mkdir -p $BACKUP_DIR 2>/dev/null || true
fi

# Perform database backup
log_message "Backing up database to ${BACKUP_FILE}..."
if docker exec $CONTAINER_NAME pg_dump -U $DB_USER $DB_NAME | gzip > "${BACKUP_DIR}/${BACKUP_FILE}"; then
    # Get backup size
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    log_message "Backup completed successfully. Size: ${BACKUP_SIZE}"
    
    # Verify backup integrity
    if gunzip -t "${BACKUP_DIR}/${BACKUP_FILE}" 2>/dev/null; then
        log_message "Backup integrity verified."
    else
        log_message "ERROR: Backup integrity check failed!"
        exit 1
    fi
else
    log_message "ERROR: Backup failed!"
    exit 1
fi

# Clean up old backups
log_message "Cleaning up backups older than ${RETENTION_DAYS} days..."
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +${RETENTION_DAYS} -delete

# Count remaining backups
BACKUP_COUNT=$(ls -1 $BACKUP_DIR/backup_*.sql.gz 2>/dev/null | wc -l)
log_message "Retention cleanup complete. ${BACKUP_COUNT} backups remaining."

# Optional: Sync to secondary location (only on NAS)
if [ -n "$SECONDARY_BACKUP" ] && [ -d "$(dirname $SECONDARY_BACKUP)" ]; then
    log_message "Syncing to secondary backup location..."
    mkdir -p $SECONDARY_BACKUP
    rsync -av --delete $BACKUP_DIR/ $SECONDARY_BACKUP/
    log_message "Secondary backup sync completed."
fi

# Create latest symlink for easy access
ln -sf "${BACKUP_DIR}/${BACKUP_FILE}" "${BACKUP_DIR}/latest.sql.gz"

log_message "Backup process completed successfully."
log_message "----------------------------------------"

exit 0