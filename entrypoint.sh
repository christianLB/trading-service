#!/bin/bash
set -e

# Configuration
MAX_WAIT_TIME=${DB_MAX_WAIT:-60}  # Maximum time to wait for database
DB_HOST=${DB_HOST:-db}
DB_USER=${DB_USER:-postgres}
DB_NAME=${DB_NAME:-trading}

# Colors for output (works in Docker logs)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handler
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Success message
success_msg() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Info message
info_msg() {
    echo -e "${YELLOW}→ $1${NC}"
}

# Extract password from DATABASE_URL
if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD=$(echo $DATABASE_URL | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
    if [ -z "$POSTGRES_PASSWORD" ]; then
        error_exit "Failed to extract database password from DATABASE_URL"
    fi
fi

# Wait for database with timeout
info_msg "Waiting for database connection..."
WAIT_TIME=0
until PGPASSWORD=$POSTGRES_PASSWORD psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c '\q' 2>/dev/null; do
    if [ $WAIT_TIME -ge $MAX_WAIT_TIME ]; then
        error_exit "Database connection timeout after ${MAX_WAIT_TIME} seconds"
    fi
    
    if [ $((WAIT_TIME % 10)) -eq 0 ]; then
        echo "  Still waiting for database... (${WAIT_TIME}s / ${MAX_WAIT_TIME}s)"
    fi
    
    sleep 1
    WAIT_TIME=$((WAIT_TIME + 1))
done

success_msg "Database connection established after ${WAIT_TIME} seconds"

# Check if database exists
info_msg "Checking database '$DB_NAME'..."
DB_EXISTS=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null)

if [ "$DB_EXISTS" != "1" ]; then
    info_msg "Creating database '$DB_NAME'..."
    PGPASSWORD=$POSTGRES_PASSWORD psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME" 2>/dev/null || \
        error_exit "Failed to create database"
    success_msg "Database created"
fi

# Run migrations
info_msg "Running database migrations..."

# Store original URL
ORIGINAL_DATABASE_URL=$DATABASE_URL

# Use sync URL for Alembic (replace asyncpg with psycopg)
export DATABASE_URL=$(echo $DATABASE_URL | sed 's/postgresql+asyncpg/postgresql+psycopg/')

# Check if alembic is available
if ! command -v alembic &> /dev/null; then
    error_exit "Alembic not found. Please ensure it's installed in the Docker image"
fi

# Run migrations and capture output
MIGRATION_OUTPUT=$(alembic upgrade head 2>&1) || {
    echo "$MIGRATION_OUTPUT"
    error_exit "Migration failed. Check the output above for details"
}

# Check if migrations were already up to date or newly applied
if echo "$MIGRATION_OUTPUT" | grep -q "Running upgrade"; then
    success_msg "Migrations applied successfully"
elif echo "$MIGRATION_OUTPUT" | grep -q "head"; then
    success_msg "Database already up to date"
else
    echo "$MIGRATION_OUTPUT"
    info_msg "Migration status unclear, continuing..."
fi

# Reset to async URL for the application
export DATABASE_URL=$ORIGINAL_DATABASE_URL

# Verify the application can import
info_msg "Verifying application modules..."
python -c "import pkg.api.main" 2>/dev/null || \
    error_exit "Failed to import application modules. Check your PYTHONPATH and module structure"

success_msg "Application modules verified"

# Start the application
info_msg "Starting application with command: $@"

# Use exec to replace the shell process with the application
exec "$@" || error_exit "Failed to start application"