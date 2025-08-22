# 💾 Backup Strategy

> **Purpose**: Document the comprehensive backup and recovery strategy for the Trading Service.

## Overview

The Trading Service implements a multi-layered backup strategy to ensure data durability and quick recovery:

1. **Automated Daily Backups** - Via Synology Task Scheduler
2. **Manual Backups** - On-demand via CLI/Makefile
3. **Secondary Sync** - Optional replication to secondary location
4. **Retention Policy** - 30-day rolling window
5. **Monitoring** - Health checks and alerts

## Backup Components

### What Gets Backed Up

| Component | Method | Frequency | Retention |
|-----------|--------|-----------|-----------|
| PostgreSQL Database | pg_dump + gzip | Daily @ 2 AM | 30 days |
| Application Logs | Log rotation | Daily | 7 days |
| Configuration | Git repository | On change | Forever |
| Docker Images | Registry/build | On deploy | Latest 3 |

### What Doesn't Need Backup

- Redis cache (ephemeral data)
- Temporary files
- Docker containers (recreated from images)

## Automated Backup Setup

### Prerequisites

1. SSH access to NAS with sudo privileges
2. Docker running on NAS
3. Trading Service deployed and running

### Installation Steps

```bash
# 1. Run the setup script
make nas-backup-setup

# 2. Follow the manual steps in DSM:
#    - Open Control Panel → Task Scheduler
#    - Create scheduled task for daily backup
#    - Set to run as root at 2:00 AM

# 3. Verify setup
make nas-backup-check
```

### Task Scheduler Configuration

**Schedule Settings:**
- **Frequency**: Daily
- **Time**: 02:00 AM (low activity period)
- **User**: root (required for Docker access)
- **Script**: `/volume1/docker/trading-service/nas-backup.sh`

**Email Notifications (optional):**
- Configure in DSM → Control Panel → Notification
- Set email for backup failures
- Test notification delivery

## Backup Script Features

### Reliability Features

1. **Lock File Management** - Prevents concurrent backups
2. **Disk Space Checks** - Ensures sufficient space before backup
3. **Container Health Verification** - Confirms database is running
4. **Backup Integrity Testing** - Validates gzip compression
5. **Atomic Operations** - Uses temp files to prevent corruption

### Error Handling

- Comprehensive logging to `/volume1/docker/trading-service/logs/backup.log`
- Email notifications on failure (if configured)
- Synology notification center integration
- Non-zero exit codes for monitoring

### Performance Optimization

- Compression level 9 (maximum)
- Streaming backup (no temp database files)
- Parallel operations where possible
- Rate limiting to prevent system overload

## Manual Backup Operations

### Create Backup

```bash
# Production (NAS)
make nas-backup

# Development (local)
make dev-backup
```

### List Backups

```bash
# Show all backups
make nas-backup-list

# Via CLI
./cli.py backup list
```

### Check Backup Status

```bash
# Check if backups are running successfully
make nas-backup-check

# Output includes:
# - Latest backup timestamp
# - Backup age in hours
# - File size
# - Total backup count
```

## Recovery Procedures

### Restore Latest Backup

```bash
# Stop application first
make nas-stop

# Restore database
make nas-restore

# Select backup file when prompted
# Restart application
make nas-deploy
```

### Restore Specific Backup

```bash
# SSH to NAS
ssh user@192.168.1.11

# List available backups
ls -lht /volume1/docker/trading-service/postgres_backups/

# Restore specific backup
docker exec -i trading-service-db-1 psql -U postgres trading < \
  <(gunzip -c /path/to/backup.sql.gz)
```

### Disaster Recovery

See [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md) for complete procedures.

## Monitoring & Alerts

### Health Checks

The monitoring script checks:
- Latest backup age (alert if >26 hours old)
- Backup file integrity
- Error count in logs
- Total backup size

### Monitoring Commands

```bash
# Check backup health
make nas-backup-check

# View backup logs
ssh user@nas "tail -f /volume1/docker/trading-service/logs/backup.log"

# Check disk usage
make nas-cleanup
```

### Alert Configuration

1. **Email Alerts** (via DSM):
   - Task failure notifications
   - Disk space warnings
   - Backup age alerts

2. **Synology Notifications**:
   - System tray alerts
   - Mobile app notifications (DS file)

3. **Custom Webhooks** (optional):
   - Integrate with monitoring systems
   - Send to Slack/Discord

## Retention Policy

### Default Settings

- **Daily Backups**: 30 days
- **Weekly Archives**: Not implemented (future)
- **Monthly Archives**: Not implemented (future)

### Disk Space Management

- Automatic cleanup of backups older than retention period
- Secondary sync to separate location (optional)
- Compression reduces size by ~80%

### Capacity Planning

Average backup sizes:
- Empty database: ~1 KB compressed
- 1,000 orders: ~50 KB compressed
- 100,000 orders: ~5 MB compressed
- 1M orders: ~50 MB compressed

With 30-day retention:
- Light usage: <100 MB total
- Medium usage: ~500 MB total
- Heavy usage: ~2 GB total

## Testing & Validation

### Regular Testing Schedule

- **Weekly**: Verify latest backup exists
- **Monthly**: Test restore procedure
- **Quarterly**: Full disaster recovery drill

### Test Commands

```bash
# Test backup creation
make nas-backup

# Verify backup integrity
ssh user@nas "gunzip -t /volume1/docker/trading-service/postgres_backups/latest.sql.gz"

# Test restore (on development)
make dev-backup
make dev-restore
```

## Troubleshooting

### Common Issues

#### Backup Fails with Permission Error

```bash
# Ensure script has execute permissions
ssh user@nas "chmod +x /volume1/docker/trading-service/nas-backup.sh"

# Ensure Task Scheduler runs as root
```

#### Disk Space Issues

```bash
# Clean up old backups
make nas-cleanup

# Reduce retention period
ssh user@nas "RETENTION_DAYS=14 /volume1/docker/trading-service/nas-backup.sh"
```

#### Container Not Found

```bash
# Check container name
docker ps --format "{{.Names}}"

# Update CONTAINER_NAME in backup script if needed
```

### Log Analysis

```bash
# View recent backup logs
ssh user@nas "tail -50 /volume1/docker/trading-service/logs/backup.log"

# Search for errors
ssh user@nas "grep ERROR /volume1/docker/trading-service/logs/backup.log"

# Check backup timestamps
ssh user@nas "grep 'Backup process completed' /volume1/docker/trading-service/logs/backup.log | tail -10"
```

## Best Practices

1. **Test Restores Regularly** - Don't wait for disaster
2. **Monitor Backup Age** - Set up alerts for missing backups
3. **Verify Integrity** - Check random backups periodically
4. **Document Changes** - Update this doc when modifying backup strategy
5. **Secure Backups** - Encrypt sensitive data (future enhancement)
6. **Offsite Copies** - Consider cloud sync for critical data

## Future Enhancements

- [ ] Encrypted backups with GPG
- [ ] Cloud sync to S3/B2
- [ ] Weekly and monthly archives
- [ ] Point-in-time recovery
- [ ] Incremental backups
- [ ] Multi-database support
- [ ] Backup metrics dashboard

## Quick Reference

```bash
# Setup
make nas-backup-setup         # Initial setup

# Operations
make nas-backup              # Manual backup
make nas-backup-check        # Check status
make nas-backup-list         # List backups
make nas-restore            # Restore database

# Monitoring
tail -f logs/backup.log     # Watch logs
make nas-cleanup            # Clean disk space
```

## Support

For backup issues:
1. Check backup logs
2. Verify container status
3. Review disk space
4. Test manual backup
5. Check Task Scheduler logs in DSM

---

*Last Updated: August 22, 2025*  
*Backup Version: 2.0*