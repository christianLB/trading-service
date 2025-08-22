#!/bin/bash
# NAS Disk Cleanup Script for Trading Service
# This script helps clean up disk space on the NAS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAS_HOST="192.168.1.11"
NAS_USER="${NAS_USER:-k2600x}"
THRESHOLD_WARNING=80
THRESHOLD_CRITICAL=85

# Function to print colored output
print_status() {
    case $1 in
        error) echo -e "${RED}✗ $2${NC}" ;;
        success) echo -e "${GREEN}✓ $2${NC}" ;;
        warning) echo -e "${YELLOW}⚠ $2${NC}" ;;
        info) echo -e "${BLUE}→ $2${NC}" ;;
    esac
}

# Check if we're running locally or on NAS
if [ -d "/volume1" ]; then
    # Running on NAS
    IS_NAS=true
    print_status info "Running directly on NAS"
else
    # Running locally, need SSH
    IS_NAS=false
    print_status info "Running remotely, will connect to NAS at $NAS_HOST"
fi

# Function to execute command on NAS
nas_exec() {
    if [ "$IS_NAS" = true ]; then
        eval "$1"
    else
        ssh "$NAS_USER@$NAS_HOST" "$1"
    fi
}

# Check current disk usage
print_status info "Checking current disk usage..."
USAGE=$(nas_exec "df /volume1 | awk 'NR==2 {print int(\$5)}'")
print_status info "Current disk usage: ${USAGE}%"

if [ $USAGE -lt $THRESHOLD_WARNING ]; then
    print_status success "Disk usage is healthy (${USAGE}% < ${THRESHOLD_WARNING}%)"
    exit 0
elif [ $USAGE -ge $THRESHOLD_CRITICAL ]; then
    print_status error "CRITICAL: Disk usage at ${USAGE}%!"
else
    print_status warning "WARNING: Disk usage at ${USAGE}%"
fi

# Start cleanup
print_status info "Starting cleanup procedures..."
INITIAL_USAGE=$USAGE

# 1. Clean Docker system
print_status info "Cleaning Docker system..."
DOCKER_BEFORE=$(nas_exec "docker system df --format 'table {{.Type}}\t{{.Size}}' | tail -n +2 | awk '{sum+=\$2} END {print sum}'")
nas_exec "docker system prune -af --volumes 2>/dev/null || docker system prune -af"
DOCKER_AFTER=$(nas_exec "docker system df --format 'table {{.Type}}\t{{.Size}}' | tail -n +2 | awk '{sum+=\$2} END {print sum}'")
print_status success "Docker cleanup completed"

# 2. Clean old backups
print_status info "Cleaning old database backups..."
BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
if nas_exec "[ -d $BACKUP_DIR ]"; then
    # Count backups before
    BACKUPS_BEFORE=$(nas_exec "ls -1 $BACKUP_DIR/*.sql.gz 2>/dev/null | wc -l")
    
    # Keep only last 14 days
    nas_exec "find $BACKUP_DIR -name '*.sql.gz' -mtime +14 -delete 2>/dev/null || true"
    
    # Count backups after
    BACKUPS_AFTER=$(nas_exec "ls -1 $BACKUP_DIR/*.sql.gz 2>/dev/null | wc -l")
    DELETED=$((BACKUPS_BEFORE - BACKUPS_AFTER))
    
    if [ $DELETED -gt 0 ]; then
        print_status success "Deleted $DELETED old backups"
    else
        print_status info "No old backups to delete"
    fi
else
    print_status warning "Backup directory not found"
fi

# 3. Compress old logs
print_status info "Compressing old logs..."
LOG_DIR="/volume1/docker/trading-service/logs"
if nas_exec "[ -d $LOG_DIR ]"; then
    # Find and compress logs older than 7 days
    LOGS_TO_COMPRESS=$(nas_exec "find $LOG_DIR -name '*.log' -mtime +7 -not -name '*.gz' 2>/dev/null | wc -l")
    
    if [ $LOGS_TO_COMPRESS -gt 0 ]; then
        nas_exec "find $LOG_DIR -name '*.log' -mtime +7 -not -name '*.gz' -exec gzip {} \; 2>/dev/null"
        print_status success "Compressed $LOGS_TO_COMPRESS old log files"
    else
        print_status info "No logs to compress"
    fi
    
    # Delete compressed logs older than 30 days
    nas_exec "find $LOG_DIR -name '*.log.gz' -mtime +30 -delete 2>/dev/null || true"
else
    print_status warning "Log directory not found"
fi

# 4. Clean package manager cache (if applicable)
print_status info "Cleaning package caches..."
nas_exec "apt-get clean 2>/dev/null || true"
nas_exec "pip cache purge 2>/dev/null || true"
nas_exec "npm cache clean --force 2>/dev/null || true"

# 5. Clean temporary files
print_status info "Cleaning temporary files..."
nas_exec "find /tmp -type f -mtime +7 -delete 2>/dev/null || true"
nas_exec "find /var/tmp -type f -mtime +7 -delete 2>/dev/null || true"

# Check final disk usage
print_status info "Checking final disk usage..."
FINAL_USAGE=$(nas_exec "df /volume1 | awk 'NR==2 {print int(\$5)}'")
FREED=$((INITIAL_USAGE - FINAL_USAGE))

echo ""
print_status info "========== Cleanup Summary =========="
print_status info "Initial usage: ${INITIAL_USAGE}%"
print_status info "Final usage:   ${FINAL_USAGE}%"
if [ $FREED -gt 0 ]; then
    print_status success "Space freed:   ${FREED}%"
else
    print_status warning "No significant space freed"
fi

# Final status
if [ $FINAL_USAGE -lt $THRESHOLD_WARNING ]; then
    print_status success "Disk usage is now healthy!"
elif [ $FINAL_USAGE -ge $THRESHOLD_CRITICAL ]; then
    print_status error "Disk usage still critical! Consider:"
    echo "  - Moving backups to external storage"
    echo "  - Reducing retention periods further"
    echo "  - Expanding storage capacity"
else
    print_status warning "Disk usage still at warning level"
fi

echo ""
print_status info "Detailed usage:"
nas_exec "df -h /volume1"

exit 0