#!/bin/bash
# Database Backup Script for Trading Service - Development Version
# This script backs up the development database

set -e

# Configuration for development environment
BACKUP_DIR="./backups"
CONTAINER_NAME="deploy-db-1"
DB_NAME="trading"
DB_USER="postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_dev_${TIMESTAMP}.sql.gz"
RETENTION_DAYS=7  # Keep fewer backups in dev
LOG_FILE="./logs/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure directories exist
mkdir -p $BACKUP_DIR
mkdir -p $(dirname $LOG_FILE)

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to print colored output
print_status() {
    case $1 in
        error) echo -e "${RED}✗ $2${NC}" ;;
        success) echo -e "${GREEN}✓ $2${NC}" ;;
        info) echo -e "${YELLOW}→ $2${NC}" ;;
    esac
}

# Start backup
log_message "Starting development database backup..."
print_status info "Starting development database backup..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_message "ERROR: Container ${CONTAINER_NAME} is not running!"
    print_status error "Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Perform database backup
log_message "Backing up database to ${BACKUP_FILE}..."
print_status info "Creating backup: ${BACKUP_FILE}"

if docker exec $CONTAINER_NAME pg_dump -U $DB_USER $DB_NAME | gzip > "${BACKUP_DIR}/${BACKUP_FILE}"; then
    # Get backup size
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    log_message "Backup completed successfully. Size: ${BACKUP_SIZE}"
    print_status success "Backup completed (${BACKUP_SIZE})"
    
    # Verify backup integrity
    if gunzip -t "${BACKUP_DIR}/${BACKUP_FILE}" 2>/dev/null; then
        log_message "Backup integrity verified."
        print_status success "Backup integrity verified"
    else
        log_message "ERROR: Backup integrity check failed!"
        print_status error "Backup integrity check failed!"
        exit 1
    fi
else
    log_message "ERROR: Backup failed!"
    print_status error "Backup failed!"
    exit 1
fi

# Clean up old backups
log_message "Cleaning up backups older than ${RETENTION_DAYS} days..."
print_status info "Cleaning up old backups (>${RETENTION_DAYS} days)"
find $BACKUP_DIR -name "backup_dev_*.sql.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

# Count remaining backups
BACKUP_COUNT=$(ls -1 $BACKUP_DIR/backup_dev_*.sql.gz 2>/dev/null | wc -l || echo "0")
log_message "Retention cleanup complete. ${BACKUP_COUNT} backups remaining."
print_status success "${BACKUP_COUNT} backups retained"

# Create latest symlink for easy access
ln -sf "${BACKUP_DIR}/${BACKUP_FILE}" "${BACKUP_DIR}/latest_dev.sql.gz"

log_message "Development backup process completed successfully."
print_status success "Backup completed: ${BACKUP_DIR}/${BACKUP_FILE}"

echo ""
echo "To restore this backup, run:"
echo "  ./scripts/restore-dev.sh ${BACKUP_DIR}/${BACKUP_FILE}"
echo ""

exit 0