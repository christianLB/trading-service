#!/bin/bash
# Production Database Migration Script
# Safely runs Alembic migrations in production with backup

set -e

# Configuration
CONTAINER_NAME="deploy-api-1"
BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
LOG_FILE="/volume1/docker/trading-service/logs/migration.log"
CONTEXT="nas"  # Docker context for NAS

# Ensure log directory exists
mkdir -p $(dirname $LOG_FILE)

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_message "========================================="
log_message "Starting production migration process..."

# Check if running on NAS or remotely
if [ "$1" == "--remote" ]; then
    DOCKER_CMD="docker --context $CONTEXT"
    log_message "Running migration remotely via Docker context: $CONTEXT"
else
    DOCKER_CMD="docker"
    log_message "Running migration locally"
fi

# Check if container is running
if ! $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_message "ERROR: Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Create pre-migration backup
echo -e "${YELLOW}Creating pre-migration backup...${NC}"
BACKUP_FILE="${BACKUP_DIR}/pre_migration_$(date +%Y%m%d_%H%M%S).sql.gz"
if $DOCKER_CMD exec deploy-db-1 pg_dump -U postgres trading | gzip > "$BACKUP_FILE"; then
    log_message "Pre-migration backup created: $BACKUP_FILE"
else
    echo -e "${RED}ERROR: Failed to create backup. Aborting migration.${NC}"
    log_message "ERROR: Backup failed, migration aborted"
    exit 1
fi

# Check current migration status
echo -e "${YELLOW}Checking current migration status...${NC}"
log_message "Checking current migration status..."
$DOCKER_CMD exec $CONTAINER_NAME alembic current

# Show pending migrations
echo -e "${YELLOW}Checking for pending migrations...${NC}"
$DOCKER_CMD exec $CONTAINER_NAME alembic history --verbose | head -10

# Prompt for confirmation
echo ""
echo -e "${YELLOW}⚠️  WARNING: You are about to run database migrations in PRODUCTION${NC}"
echo "Pre-migration backup has been created at: $BACKUP_FILE"
echo ""
read -p "Do you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${RED}Migration cancelled by user${NC}"
    log_message "Migration cancelled by user"
    exit 0
fi

# Run migrations
echo -e "${YELLOW}Running migrations...${NC}"
log_message "Executing alembic upgrade head..."

if $DOCKER_CMD exec $CONTAINER_NAME sh -c "
    export DATABASE_URL='postgresql+psycopg://postgres:zs6Fl+uC0XyqR7E7xFU2pats@db:5432/trading' && \
    alembic upgrade head
"; then
    echo -e "${GREEN}✓ Migrations completed successfully${NC}"
    log_message "Migrations completed successfully"
else
    echo -e "${RED}✗ Migration failed!${NC}"
    log_message "ERROR: Migration failed"
    
    echo -e "${YELLOW}Would you like to restore the pre-migration backup? (yes/no):${NC}"
    read -p "" -r
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        log_message "Restoring pre-migration backup..."
        gunzip -c "$BACKUP_FILE" | $DOCKER_CMD exec -i deploy-db-1 psql -U postgres -d trading
        echo -e "${GREEN}Backup restored${NC}"
        log_message "Backup restored successfully"
    fi
    exit 1
fi

# Verify migration status
echo -e "${YELLOW}Verifying migration status...${NC}"
$DOCKER_CMD exec $CONTAINER_NAME alembic current

# Test application health
echo -e "${YELLOW}Testing application health...${NC}"
if [ "$1" == "--remote" ]; then
    HEALTH_URL="http://192.168.1.11:8085/healthz"
else
    HEALTH_URL="http://localhost:8085/healthz"
fi

if curl -s $HEALTH_URL > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Application health check passed${NC}"
    log_message "Application health check passed"
else
    echo -e "${RED}✗ Application health check failed${NC}"
    log_message "WARNING: Application health check failed"
fi

log_message "Migration process completed"
log_message "========================================="

echo ""
echo -e "${GREEN}Migration completed successfully!${NC}"
echo "Backup saved at: $BACKUP_FILE"
echo ""

exit 0