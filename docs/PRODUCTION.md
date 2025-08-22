# 📚 Production Deployment Guide

## 🏗️ Infrastructure Overview

The Trading Service is deployed on a self-hosted Synology NAS at `192.168.1.11` with:
- Full sudoer access for deployment and maintenance
- Docker and Docker Compose support
- Persistent volume storage on `/volume1/docker/trading-service/`
- Automated backup capabilities via Synology Task Scheduler

## 🚀 Initial Setup (One-Time)

### 1. Prerequisites

- SSH access to the NAS with sudo privileges
- SSH key authentication configured (recommended)
- Docker installed on the NAS
- Docker Compose v2 installed on the NAS

### 2. Configure SSH Key Authentication

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy SSH key to NAS
ssh-copy-id your_username@192.168.1.11
```

### 3. Run Initial Setup

```bash
# Run the one-time setup
make nas-setup

# This will:
# - Create Docker context for remote deployment
# - Create directory structure on NAS
# - Set proper permissions
# - Copy scripts to NAS
```

### 4. Configure Production Environment

Edit `.env.prod` and update:
- Generate secure `API_TOKEN` (use `openssl rand -hex 32`)
- Set production `WEBHOOK_URL` if using webhooks
- Adjust `MAX_POS_USD` and `MAX_DAILY_LOSS_USD` for production
- Configure real exchange credentials when ready

## 📦 Deployment Process

### First Deployment

```bash
# Deploy to production
make nas-deploy

# Check deployment status
make nas-status

# View logs
make nas-logs

# Verify health
make nas-health
```

### Updating Production

```bash
# 1. Create a backup first
make nas-backup

# 2. Deploy new version
make nas-deploy

# 3. Run migrations if needed
make nas-migrate

# 4. Verify deployment
make nas-health
```

## 🗂️ Directory Structure on NAS

```
/volume1/docker/trading-service/
├── postgres_data/      # PostgreSQL data files (persistent)
├── postgres_backups/   # Database backups (automated)
├── redis_data/         # Redis persistence files
├── logs/               # Application and backup logs
├── config/             # Configuration files
├── secrets/            # Sensitive configuration
├── backup.sh           # Automated backup script
├── restore.sh          # Database restore script
└── migrate-prod.sh     # Migration script
```

## 🔐 Security Configuration

### API Token

The production API uses Bearer token authentication. Generate a secure token:

```bash
# Generate 64-character secure token
openssl rand -hex 32
```

Update in `.env.prod`:
```env
API_TOKEN=your_generated_token_here
```

### Firewall Rules

Configure Synology firewall to:
- Allow port 8085 from internal network only (192.168.1.0/24)
- Block all other Docker ports from external access
- Allow SSH only from trusted IPs

### Database Security

- Strong password auto-generated during setup
- Database not exposed externally
- Connections only from internal Docker network

## 💾 Backup Strategy

### Automated Daily Backups

Set up via Synology Task Scheduler:

1. Open Control Panel → Task Scheduler
2. Create → Scheduled Task → User-defined script
3. Schedule: Daily at 2:00 AM
4. Script: `/volume1/docker/trading-service/backup.sh`

### Manual Backup

```bash
# Run backup manually
make nas-backup

# Or via SSH
ssh username@192.168.1.11 "/volume1/docker/trading-service/backup.sh"
```

### Backup Retention

- Local backups: 30 days (configurable in backup.sh)
- Backups stored in: `/volume1/docker/trading-service/postgres_backups/`
- Optional secondary location: `/volume1/backups/trading-service/`

## 🔄 Database Operations

### Running Migrations

```bash
# Run migrations on production
make nas-migrate

# This will:
# - Create pre-migration backup
# - Show pending migrations
# - Prompt for confirmation
# - Run migrations
# - Verify application health
```

### Restore from Backup

```bash
# Restore latest backup
make nas-restore

# Restore specific backup
make nas-restore
# Then enter: backup_20250821_140000.sql.gz
```

## 📊 Monitoring

### Health Checks

```bash
# Check application health
make nas-health

# Expected output:
{
  "status": "healthy",
  "timestamp": "2025-08-21T18:00:00.000000",
  "database": "healthy",
  "redis": "healthy"
}
```

### Viewing Logs

```bash
# Follow all logs
make nas-logs

# View specific container logs via SSH
ssh k2600x@192.168.1.11 "sudo /usr/local/bin/docker logs trading-service-api-1 --tail 100"
```

### Metrics Endpoint

Access Prometheus metrics at:
```
http://192.168.1.11:8085/metrics
```

Key metrics to monitor:
- `orders_total` - Total orders created
- `fills_total` - Total order fills
- `risk_blocks_total` - Risk validation failures
- `order_latency_seconds` - Order processing time

## 💾 Disk Management

### Monitoring Disk Usage

```bash
# Check current usage
ssh k2600x@192.168.1.11 "df -h /volume1"

# Clean Docker artifacts
ssh k2600x@192.168.1.11 "docker system prune -a"

# Review backup sizes
ssh k2600x@192.168.1.11 "du -sh /volume1/docker/trading-service/postgres_backups/*"
```

### Disk Usage Thresholds

- **<70%**: Normal operation
- **70-80%**: Monitor daily
- **80-85%**: ⚠️ Warning - cleanup required
- **85-90%**: 🔴 Critical - immediate action
- **>90%**: 🚨 Emergency - service degradation likely

### Cleanup Procedures

1. **Docker cleanup** (recovers ~1-5GB)
   ```bash
   ssh k2600x@192.168.1.11 "docker system prune -a --volumes"
   ```

2. **Reduce backup retention** (recovers variable)
   ```bash
   # Edit backup.sh RETENTION_DAYS from 30 to 14
   ssh k2600x@192.168.1.11 "sed -i 's/RETENTION_DAYS=30/RETENTION_DAYS=14/' /volume1/docker/trading-service/backup.sh"
   ```

3. **Archive old logs** (recovers ~100MB-1GB)
   ```bash
   ssh k2600x@192.168.1.11 "find /volume1/docker/trading-service/logs -name '*.log' -mtime +7 -exec gzip {} \;"
   ```

### Known Issues

- **2025-08-22**: Disk usage at 80% - see [issue report](./issues/2025-08-22-nas-disk-usage.md)

## 🛠️ Maintenance

### Restart Services

```bash
# Restart all services
make nas-restart

# Stop services
make nas-stop

# Start services
make nas-deploy
```

### Execute Commands in Container

```bash
# Interactive command execution
make nas-exec
# Enter: api
# Enter: /bin/sh

# Direct command
ssh k2600x@192.168.1.11 "sudo /usr/local/bin/docker exec trading-service-api-1 alembic current"
```

### Update Configuration

1. Edit `.env.prod` locally
2. Deploy changes: `make nas-deploy`
3. Services will restart with new configuration

## 🚨 Troubleshooting

### Service Won't Start

```bash
# Check logs
make nas-logs

# Check container status
make nas-status

# Verify disk space on NAS
ssh username@192.168.1.11 "df -h /volume1"
```

### Database Connection Issues

```bash
# Test database connection
ssh k2600x@192.168.1.11 "sudo /usr/local/bin/docker exec trading-service-db-1 psql -U postgres -c 'SELECT 1'"

# Check database logs
ssh k2600x@192.168.1.11 "sudo /usr/local/bin/docker logs trading-service-db-1 --tail 50"
```

### Port Conflicts

If port 8085 is in use:
1. Edit `.env.prod` and change `API_PORT`
2. Update firewall rules accordingly
3. Redeploy: `make nas-deploy`

### Recovery from Failed Deployment

```bash
# 1. Check what went wrong
make nas-logs

# 2. Restore previous version
make nas-restore

# 3. Fix issues and redeploy
make nas-deploy
```

## 📈 Performance Tuning

### Resource Limits

Configured in `deploy/compose.prod.yaml`:

```yaml
# API Service
limits:
  cpus: '2'
  memory: 1G

# Database
limits:
  cpus: '1'
  memory: 512M

# Redis
limits:
  cpus: '0.5'
  memory: 256M
```

Adjust based on NAS capabilities and load.

### Database Optimization

```bash
# Connect to production database
ssh -t k2600x@192.168.1.11 "sudo /usr/local/bin/docker exec -it trading-service-db-1 psql -U postgres trading"

# Check slow queries (after connecting to psql)
# SELECT query, calls, mean_exec_time
# FROM pg_stat_statements
# ORDER BY mean_exec_time DESC
# LIMIT 10;
```

## 📝 Operational Checklist

### Daily
- [ ] Check health endpoint
- [ ] Review error logs
- [ ] Monitor disk usage

### Weekly
- [ ] Review metrics and performance
- [ ] Check backup integrity
- [ ] Update documentation if needed

### Monthly
- [ ] Test restore procedure
- [ ] Review and rotate logs
- [ ] Security updates check
- [ ] Performance analysis

### Before Major Updates
- [ ] Create manual backup
- [ ] Review migration scripts
- [ ] Test in development first
- [ ] Schedule maintenance window
- [ ] Prepare rollback plan

## 🔗 Quick Reference

```bash
# Deployment
make nas-deploy         # Deploy to production
make nas-health         # Check health
make nas-logs           # View logs
make nas-status         # Container status

# Maintenance
make nas-backup         # Run backup
make nas-restore        # Restore database
make nas-migrate        # Run migrations
make nas-restart        # Restart services

# Debugging
make nas-exec           # Execute commands
make nas-stop           # Stop services
```

## 📞 Support

For issues or questions:
1. Check logs: `make nas-logs`
2. Review this documentation
3. Check [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md) for recovery procedures
4. Contact system administrator