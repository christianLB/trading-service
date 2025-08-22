#!/bin/bash
# Automated Database Backup Script for Trading Service
# This script should be run on the NAS via cron/Task Scheduler

set -e

# Configuration
BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
CONTAINER_NAME="deploy-db-1"
DB_NAME="trading"
DB_USER="postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_${TIMESTAMP}.sql.gz"
RETENTION_DAYS=30
LOG_FILE="/volume1/docker/trading-service/logs/backup.log"

# Ensure log directory exists
mkdir -p $(dirname $LOG_FILE)

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Start backup
log_message "Starting database backup..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_message "ERROR: Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Ensure backup directory exists
mkdir -p $BACKUP_DIR

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

# Optional: Sync to secondary location
SECONDARY_BACKUP="/volume1/backups/trading-service"
if [ -d "/volume1/backups" ]; then
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