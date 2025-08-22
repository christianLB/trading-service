#!/bin/bash
# Database Restore Script for Trading Service
# Usage: ./restore.sh [backup_file]
# If no backup file specified, uses the latest backup

set -e

# Configuration
BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
CONTAINER_NAME="deploy-db-1"
DB_NAME="trading"
DB_USER="postgres"
LOG_FILE="/volume1/docker/trading-service/logs/restore.log"

# Ensure log directory exists
mkdir -p $(dirname $LOG_FILE)

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_message "ERROR: Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Determine backup file to restore
if [ -n "$1" ]; then
    BACKUP_FILE="$1"
else
    # Use latest backup
    BACKUP_FILE="${BACKUP_DIR}/latest.sql.gz"
    if [ ! -L "$BACKUP_FILE" ]; then
        # If no latest symlink, find the most recent backup
        BACKUP_FILE=$(ls -t ${BACKUP_DIR}/backup_*.sql.gz 2>/dev/null | head -1)
    fi
fi

# Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    log_message "ERROR: Backup file not found: $BACKUP_FILE"
    echo "Available backups:"
    ls -lh ${BACKUP_DIR}/backup_*.sql.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

log_message "Starting database restore from: $BACKUP_FILE"

# Verify backup integrity
log_message "Verifying backup integrity..."
if ! gunzip -t "$BACKUP_FILE"; then
    log_message "ERROR: Backup file is corrupted!"
    exit 1
fi

# Create a safety backup before restore
SAFETY_BACKUP="${BACKUP_DIR}/pre_restore_$(date +%Y%m%d_%H%M%S).sql.gz"
log_message "Creating safety backup before restore: $SAFETY_BACKUP"
docker exec $CONTAINER_NAME pg_dump -U $DB_USER $DB_NAME | gzip > "$SAFETY_BACKUP"

# Stop application containers to prevent connections
log_message "Stopping application containers..."
docker stop deploy-api-1 2>/dev/null || true

# Drop existing connections
log_message "Terminating existing database connections..."
docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres -c "
    SELECT pg_terminate_backend(pid) 
    FROM pg_stat_activity 
    WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();"

# Drop and recreate database
log_message "Dropping and recreating database..."
docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME};"
docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres -c "CREATE DATABASE ${DB_NAME};"

# Restore database
log_message "Restoring database..."
if gunzip -c "$BACKUP_FILE" | docker exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME; then
    log_message "Database restored successfully."
else
    log_message "ERROR: Restore failed! Attempting to restore safety backup..."
    gunzip -c "$SAFETY_BACKUP" | docker exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME
    log_message "Safety backup restored. Manual intervention may be required."
    exit 1
fi

# Restart application containers
log_message "Restarting application containers..."
docker start deploy-api-1 2>/dev/null || true

# Wait for application to be ready
log_message "Waiting for application to be ready..."
sleep 10

# Verify application health
if curl -s http://localhost:8085/healthz > /dev/null 2>&1; then
    log_message "Application health check passed."
else
    log_message "WARNING: Application health check failed. Please verify manually."
fi

log_message "Restore process completed successfully."
log_message "----------------------------------------"

echo ""
echo "IMPORTANT: Please verify the application and data integrity after restore."
echo "Safety backup created at: $SAFETY_BACKUP"

exit 0