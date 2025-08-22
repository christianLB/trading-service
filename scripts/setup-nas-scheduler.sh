#!/bin/bash
# Setup script for configuring automated backups on Synology NAS
# Run this script once to set up the Task Scheduler

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
REMOTE_SCRIPT_PATH="/volume1/docker/trading-service/nas-backup.sh"
LOCAL_SCRIPT_PATH="./scripts/nas-backup.sh"

# Function to print colored output
print_status() {
    case $1 in
        error) echo -e "${RED}✗ $2${NC}" ;;
        success) echo -e "${GREEN}✓ $2${NC}" ;;
        warning) echo -e "${YELLOW}⚠ $2${NC}" ;;
        info) echo -e "${BLUE}→ $2${NC}" ;;
    esac
}

echo ""
echo "========================================="
echo "  Trading Service NAS Backup Setup"
echo "========================================="
echo ""

# Step 1: Copy backup script to NAS
print_status info "Copying backup script to NAS..."
if scp "$LOCAL_SCRIPT_PATH" "${NAS_USER}@${NAS_HOST}:${REMOTE_SCRIPT_PATH}"; then
    print_status success "Backup script copied to NAS"
else
    print_status error "Failed to copy backup script"
    exit 1
fi

# Step 2: Set permissions
print_status info "Setting script permissions..."
if ssh "${NAS_USER}@${NAS_HOST}" "chmod +x ${REMOTE_SCRIPT_PATH}"; then
    print_status success "Script permissions set"
else
    print_status error "Failed to set permissions"
    exit 1
fi

# Step 3: Create Task Scheduler configuration
print_status info "Creating Task Scheduler configuration..."

# Create a task configuration file
cat > /tmp/trading-backup-task.txt << 'EOF'
Task Name: Trading Service Database Backup
Description: Automated daily backup of Trading Service database

Schedule:
- Type: Daily
- Time: 02:00 AM
- Run on the following days: Every day

Task Settings:
- User: root (required for Docker access)
- Enabled: Yes
- Send run details by email: Optional (configure email in DSM)
- Send run details only when the script terminates abnormally: Yes

User-defined script:
/volume1/docker/trading-service/nas-backup.sh

Environment Variables (optional):
- RETENTION_DAYS=30
- BACKUP_NOTIFY_EMAIL=your-email@example.com
EOF

# Copy configuration to NAS
scp /tmp/trading-backup-task.txt "${NAS_USER}@${NAS_HOST}:/tmp/" 2>/dev/null

print_status success "Task configuration created"

# Step 4: Test the backup script
print_status info "Testing backup script on NAS..."
echo ""
read -p "Do you want to run a test backup now? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status info "Running test backup..."
    if ssh "${NAS_USER}@${NAS_HOST}" "sudo ${REMOTE_SCRIPT_PATH}"; then
        print_status success "Test backup completed successfully"
    else
        print_status warning "Test backup failed - check logs at /volume1/docker/trading-service/logs/backup.log"
    fi
fi

# Step 5: Instructions for manual setup
echo ""
echo "========================================="
echo "  Manual Setup Instructions"
echo "========================================="
echo ""
echo "To complete the setup, follow these steps in DSM:"
echo ""
echo "1. Open DSM (Disk Station Manager) at http://${NAS_HOST}:5000"
echo ""
echo "2. Go to Control Panel → Task Scheduler"
echo ""
echo "3. Click 'Create' → 'Scheduled Task' → 'User-defined script'"
echo ""
echo "4. In the General tab:"
echo "   - Task: Trading Service Database Backup"
echo "   - User: root"
echo "   - Enabled: ✓"
echo ""
echo "5. In the Schedule tab:"
echo "   - Run on the following date: Daily"
echo "   - First run time: 02:00"
echo "   - Frequency: Every 1 day(s)"
echo "   - Last run time: (leave empty for indefinite)"
echo ""
echo "6. In the Task Settings tab:"
echo "   - Send run details by email: (optional)"
echo "   - User-defined script:"
echo "     ${REMOTE_SCRIPT_PATH}"
echo ""
echo "7. Click 'OK' to save the task"
echo ""
echo "8. Optional: Right-click the task and select 'Run' to test immediately"
echo ""
echo "========================================="
echo ""

# Step 6: Create monitoring script
print_status info "Creating backup monitoring script..."

cat > /tmp/check-backup.sh << 'EOF'
#!/bin/bash
# Check if backups are running successfully

BACKUP_DIR="/volume1/docker/trading-service/postgres_backups"
LOG_FILE="/volume1/docker/trading-service/logs/backup.log"
MAX_AGE_HOURS=26  # Alert if no backup in 26 hours

# Check latest backup
LATEST_BACKUP=$(ls -t $BACKUP_DIR/backup_*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: No backups found!"
    exit 1
fi

# Check age of latest backup
BACKUP_AGE_HOURS=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 3600 ))

if [ $BACKUP_AGE_HOURS -gt $MAX_AGE_HOURS ]; then
    echo "WARNING: Latest backup is ${BACKUP_AGE_HOURS} hours old (max: ${MAX_AGE_HOURS})"
    exit 1
fi

# Check for recent errors in log
RECENT_ERRORS=$(grep -c ERROR $LOG_FILE 2>/dev/null || echo 0)
if [ $RECENT_ERRORS -gt 0 ]; then
    echo "WARNING: Found $RECENT_ERRORS errors in backup log"
fi

echo "✓ Backups are running successfully"
echo "  Latest: $(basename $LATEST_BACKUP)"
echo "  Age: ${BACKUP_AGE_HOURS} hours"
echo "  Size: $(du -h $LATEST_BACKUP | cut -f1)"

# Show backup statistics
TOTAL_BACKUPS=$(ls -1 $BACKUP_DIR/backup_*.sql.gz 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh $BACKUP_DIR 2>/dev/null | cut -f1)
echo "  Total backups: $TOTAL_BACKUPS"
echo "  Total size: $TOTAL_SIZE"
EOF

# Copy monitoring script
scp /tmp/check-backup.sh "${NAS_USER}@${NAS_HOST}:/volume1/docker/trading-service/" 2>/dev/null
ssh "${NAS_USER}@${NAS_HOST}" "chmod +x /volume1/docker/trading-service/check-backup.sh"

print_status success "Monitoring script created"

# Step 7: Add to Makefile
print_status info "Backup commands available:"
echo ""
echo "  make nas-backup        # Run backup manually"
echo "  make nas-backup-check  # Check backup status"
echo "  make nas-backup-list   # List all backups"
echo ""

# Cleanup
rm -f /tmp/trading-backup-task.txt /tmp/check-backup.sh

print_status success "Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Follow the manual setup instructions above to create the scheduled task"
echo "2. Run 'make nas-backup-check' to verify backups are working"
echo "3. Consider setting up email notifications in DSM"
echo ""