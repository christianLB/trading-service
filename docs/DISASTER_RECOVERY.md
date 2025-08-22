# 🚨 Disaster Recovery Guide

## 📋 Overview

This guide provides comprehensive procedures for recovering the Trading Service from various failure scenarios. All procedures are designed for the production environment hosted on Synology NAS at `192.168.1.11`.

## 🎯 Recovery Objectives

- **Recovery Time Objective (RTO)**: < 30 minutes for critical failures
- **Recovery Point Objective (RPO)**: < 24 hours (daily backup schedule)
- **Data Integrity**: Zero data corruption tolerance
- **Service Availability**: 99.9% uptime target

## 🔥 Failure Scenarios & Recovery

### 1. Database Corruption

**Symptoms:**
- Application fails to start with database errors
- Queries return corrupted data
- PostgreSQL logs show corruption errors

**Recovery Steps:**

```bash
# 1. Stop all services immediately
make nas-stop

# 2. Verify the corruption
ssh username@192.168.1.11
docker exec deploy-db-1 pg_dump -U postgres trading > /tmp/test_dump.sql 2>&1
# Check for errors in the dump

# 3. Restore from latest backup
make nas-restore
# Or restore specific backup
ssh username@192.168.1.11 "/volume1/docker/trading-service/restore.sh backup_20250821_020000.sql.gz"

# 4. Verify restoration
make nas-health

# 5. Check for data gaps
docker --context nas exec deploy-db-1 psql -U postgres trading -c "
    SELECT MAX(created_at) as latest_order FROM orders;
    SELECT MAX(created_at) as latest_fill FROM fills;
"

# 6. Restart services
make nas-deploy
```

### 2. Complete Service Failure

**Symptoms:**
- All containers are down
- Health endpoint not responding
- Docker daemon issues

**Recovery Steps:**

```bash
# 1. SSH into NAS
ssh username@192.168.1.11

# 2. Check Docker daemon
sudo systemctl status docker
# If Docker is down:
sudo systemctl restart docker

# 3. Check disk space
df -h /volume1

# 4. Clean up if needed
docker system prune -af --volumes
# WARNING: This removes all unused containers and volumes!

# 5. Redeploy from local machine
make nas-deploy

# 6. Verify all services
make nas-status
make nas-health
```

### 3. Application Code Issues

**Symptoms:**
- API container crash loops
- Specific endpoints failing
- Migration failures

**Recovery Steps:**

```bash
# 1. Check logs for errors
make nas-logs

# 2. If migration issue:
# Rollback to previous migration
docker --context nas exec deploy-api-1 alembic downgrade -1

# 3. If code issue, rollback to previous version
# Stop current deployment
make nas-stop

# 4. Deploy previous version
git checkout <previous-tag>
make nas-deploy

# 5. If persistent issue, run in debug mode
ssh username@192.168.1.11
docker --context nas exec -it deploy-api-1 /bin/sh
# Debug inside container
```

### 4. Redis Cache Failure

**Symptoms:**
- Rate limiting not working
- Session management issues
- Performance degradation

**Recovery Steps:**

```bash
# 1. Check Redis status
docker --context nas logs deploy-redis-1 --tail 50

# 2. Restart Redis
docker --context nas restart deploy-redis-1

# 3. If data corruption, flush Redis
docker --context nas exec deploy-redis-1 redis-cli FLUSHALL

# 4. Restart application to repopulate cache
docker --context nas restart deploy-api-1

# 5. Verify functionality
make nas-health
```

### 5. Network/Connectivity Issues

**Symptoms:**
- Cannot reach API endpoint
- Database connection timeouts
- Inter-container communication failures

**Recovery Steps:**

```bash
# 1. Check NAS network
ssh username@192.168.1.11
ping -c 4 8.8.8.8
ip addr show

# 2. Check firewall rules
sudo iptables -L -n | grep 8085

# 3. Check Docker network
docker network ls
docker network inspect deploy_default

# 4. Recreate network if needed
docker --context nas compose -f deploy/compose.yaml -f deploy/compose.prod.yaml down
docker network prune -f
make nas-deploy

# 5. Test connectivity
curl http://192.168.1.11:8085/healthz
```

### 6. Disk Space Issues

**Symptoms:**
- Write operations failing
- Backup failures
- Container startup issues

**Recovery Steps:**

```bash
# 1. Check disk usage
ssh username@192.168.1.11
df -h /volume1
du -sh /volume1/docker/trading-service/*

# 2. Clean old backups
find /volume1/docker/trading-service/postgres_backups -name "*.sql.gz" -mtime +7 -delete

# 3. Clean Docker resources
docker system prune -af
docker volume prune -f

# 4. Archive old logs
tar -czf logs_archive_$(date +%Y%m%d).tar.gz /volume1/docker/trading-service/logs/*.log
rm /volume1/docker/trading-service/logs/*.log

# 5. If still insufficient, move backups
mv /volume1/docker/trading-service/postgres_backups/* /volume2/backups/
```

## 🔄 Full System Recovery

### From Complete NAS Failure

If the NAS hardware fails completely:

```bash
# 1. Provision new NAS or server
# Ensure Docker and Docker Compose are installed

# 2. Restore from offsite backup (if available)
# Copy backup files to new server

# 3. Clone repository on deployment machine
git clone <repository-url> trading-service
cd trading-service

# 4. Update .env.prod with new server IP
sed -i 's/192.168.1.11/NEW_IP/g' .env.prod

# 5. Run setup on new server
# Update Makefile with new IP
make nas-setup

# 6. Restore database
scp backup_latest.sql.gz username@NEW_IP:/volume1/docker/trading-service/postgres_backups/
ssh username@NEW_IP "/volume1/docker/trading-service/restore.sh"

# 7. Deploy application
make nas-deploy

# 8. Update DNS/routing to point to new server
```

### From Backup Files Only

```bash
# 1. Ensure you have:
# - Database backup file (.sql.gz)
# - Application source code
# - Environment configuration (.env.prod)

# 2. Setup fresh environment
make nas-setup

# 3. Deploy base services
make nas-deploy

# 4. Wait for services to start
sleep 30

# 5. Restore database
scp backup_file.sql.gz username@192.168.1.11:/volume1/docker/trading-service/postgres_backups/
make nas-restore

# 6. Verify restoration
make nas-health

# 7. Run smoke tests
./scripts/test-endpoints.sh
```

## 📊 Monitoring & Alerts

### Setting Up Alerts

Configure Synology notifications for:

1. **Disk Space Alert**
   - Control Panel → Notification → Advanced
   - Add rule: Disk usage > 90%

2. **Service Health Check**
   - Task Scheduler → Create → User-defined script
   - Schedule: Every 5 minutes
   ```bash
   #!/bin/bash
   if ! curl -s http://localhost:8085/healthz > /dev/null; then
       echo "Trading Service is DOWN" | mail -s "ALERT: Service Down" admin@example.com
   fi
   ```

3. **Backup Verification**
   - Add to backup.sh script
   ```bash
   if [ $? -ne 0 ]; then
       echo "Backup failed at $(date)" | mail -s "ALERT: Backup Failed" admin@example.com
   fi
   ```

## 🧪 Recovery Testing

### Monthly Drill Procedure

```bash
# 1. Create test backup
docker --context nas exec deploy-db-1 pg_dump -U postgres trading | gzip > test_recovery.sql.gz

# 2. Spin up test environment
docker compose -f deploy/compose.yaml -f deploy/compose.test.yaml up -d

# 3. Restore to test environment
gunzip -c test_recovery.sql.gz | docker exec -i test-db-1 psql -U postgres trading

# 4. Run validation tests
pytest tests/disaster_recovery/

# 5. Document results
echo "Recovery test $(date): PASSED/FAILED" >> recovery_tests.log

# 6. Clean up test environment
docker compose -f deploy/compose.yaml -f deploy/compose.test.yaml down -v
```

## 📝 Recovery Checklist

### Pre-Recovery
- [ ] Identify failure type
- [ ] Document incident start time
- [ ] Notify stakeholders
- [ ] Locate latest backup

### During Recovery
- [ ] Stop affected services
- [ ] Create safety backup (if possible)
- [ ] Execute recovery procedure
- [ ] Verify data integrity
- [ ] Test critical functionality

### Post-Recovery
- [ ] Document recovery steps taken
- [ ] Calculate data loss (if any)
- [ ] Run full test suite
- [ ] Monitor for 24 hours
- [ ] Update runbook if needed
- [ ] Schedule post-mortem

## 🔧 Troubleshooting Tools

### Database Integrity Check

```sql
-- Connect to production database
docker --context nas exec -it deploy-db-1 psql -U postgres trading

-- Check for corruption
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables 
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Verify foreign key constraints
SELECT conname, conrelid::regclass AS table_name
FROM pg_constraint
WHERE contype = 'f' AND NOT convalidated;

-- Check for orphaned orders
SELECT o.id FROM orders o
LEFT JOIN fills f ON o.id = f.order_id
WHERE o.status = 'FILLED' AND f.id IS NULL;
```

### Application Diagnostics

```bash
# Check memory usage
docker --context nas stats --no-stream

# View recent errors
docker --context nas logs deploy-api-1 2>&1 | grep ERROR | tail -20

# Check connection pool
docker --context nas exec deploy-api-1 python -c "
from pkg.infra.database import get_session
import asyncio
async def check():
    async with get_session() as session:
        result = await session.execute('SELECT COUNT(*) FROM orders')
        print(f'Orders count: {result.scalar()}')
asyncio.run(check())
"
```

## 🚨 Emergency Contacts

Configure these in your monitoring system:

1. **Primary On-Call**: Configure in alerting system
2. **Escalation**: Team lead after 15 minutes
3. **Synology Support**: For hardware issues
4. **Database Expert**: For corruption scenarios

## 📚 Related Documentation

- [PRODUCTION.md](./PRODUCTION.md) - Production deployment procedures
- [BOOTSTRAP.md](./BOOTSTRAP.md) - Initial setup guide
- [scripts/backup.sh](/scripts/backup.sh) - Backup script details
- [scripts/restore.sh](/scripts/restore.sh) - Restore script details

## 🔄 Continuous Improvement

After each incident:

1. Update this document with lessons learned
2. Automate manual recovery steps where possible
3. Review and adjust RTO/RPO objectives
4. Update monitoring thresholds
5. Schedule team training on new procedures

---

**Last Updated**: 2025-08-21
**Version**: 1.0.0
**Owner**: DevOps Team