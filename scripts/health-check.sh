#!/bin/bash
# Comprehensive Health Check Script for Trading Service
# Checks all components and provides detailed status

set -e

# Configuration
NAS_HOST="${NAS_HOST:-192.168.1.11}"
NAS_USER="${NAS_USER:-k2600x}"
API_PORT="${API_PORT:-8085}"
API_URL="http://${NAS_HOST}:${API_PORT}"
API_TOKEN="${API_TOKEN:-4a92e7f8b1c3d5e6f7089a1b2c3d4e5f6789012345678901234567890abcdef0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored status
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "error")
            echo -e "${RED}✗${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        "info")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
    esac
}

# Function to check if running locally or remote
check_mode() {
    if [ "$1" == "--remote" ] || [ "$1" == "-r" ]; then
        REMOTE_MODE=true
        print_status "info" "Running remote health check on ${NAS_HOST}"
    else
        REMOTE_MODE=false
        print_status "info" "Running local health check"
    fi
}

# Function to execute Docker commands
docker_exec() {
    if [ "$REMOTE_MODE" = true ]; then
        ssh ${NAS_USER}@${NAS_HOST} "sudo /usr/local/bin/docker $*"
    else
        docker $*
    fi
}

# Function to execute SSH commands
ssh_exec() {
    if [ "$REMOTE_MODE" = true ]; then
        ssh ${NAS_USER}@${NAS_HOST} "$*"
    else
        eval "$*"
    fi
}

echo "========================================="
echo "   Trading Service Health Check"
echo "========================================="
echo ""

# Check mode (local or remote)
check_mode $1

# 1. Check container status
echo -e "\n${BLUE}1. Container Status${NC}"
echo "----------------------------------------"

# Check API container
API_STATUS=$(docker_exec ps --filter "name=trading-service-api" --format "{{.Status}}" 2>/dev/null || echo "Not found")
if [[ $API_STATUS == *"Up"* ]]; then
    print_status "success" "API Container: $API_STATUS"
else
    print_status "error" "API Container: $API_STATUS"
    HEALTH_ISSUES+=("API container not running")
fi

# Check Database container
DB_STATUS=$(docker_exec ps --filter "name=trading-service-db" --format "{{.Status}}" 2>/dev/null || echo "Not found")
if [[ $DB_STATUS == *"Up"* ]]; then
    print_status "success" "Database Container: $DB_STATUS"
else
    print_status "error" "Database Container: $DB_STATUS"
    HEALTH_ISSUES+=("Database container not running")
fi

# Check Redis container
REDIS_STATUS=$(docker_exec ps --filter "name=trading-service-redis" --format "{{.Status}}" 2>/dev/null || echo "Not found")
if [[ $REDIS_STATUS == *"Up"* ]]; then
    print_status "success" "Redis Container: $REDIS_STATUS"
else
    print_status "error" "Redis Container: $REDIS_STATUS"
    HEALTH_ISSUES+=("Redis container not running")
fi

# 2. Check API health endpoint
echo -e "\n${BLUE}2. API Health Endpoint${NC}"
echo "----------------------------------------"

HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" ${API_URL}/healthz 2>/dev/null || echo "000")
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" == "200" ]; then
    print_status "success" "Health endpoint responding (HTTP $HTTP_CODE)"
    if [ ! -z "$HEALTH_BODY" ]; then
        echo "  Response: $HEALTH_BODY"
    fi
else
    print_status "error" "Health endpoint not responding (HTTP $HTTP_CODE)"
    HEALTH_ISSUES+=("API health endpoint not responding")
fi

# 3. Check database connectivity
echo -e "\n${BLUE}3. Database Connectivity${NC}"
echo "----------------------------------------"

DB_CHECK=$(docker_exec exec trading-service-db-1 psql -U postgres -d trading -c "SELECT COUNT(*) FROM alembic_version;" 2>&1 || echo "Failed")
if [[ $DB_CHECK == *"COUNT"* ]] || [[ $DB_CHECK == *"1"* ]]; then
    print_status "success" "Database is accessible and migrations applied"
else
    print_status "error" "Database connectivity issue: $DB_CHECK"
    HEALTH_ISSUES+=("Database connectivity issue")
fi

# 4. Check Redis connectivity
echo -e "\n${BLUE}4. Redis Connectivity${NC}"
echo "----------------------------------------"

REDIS_CHECK=$(docker_exec exec trading-service-redis-1 redis-cli ping 2>&1 || echo "Failed")
if [[ $REDIS_CHECK == *"PONG"* ]]; then
    print_status "success" "Redis is responding"
else
    print_status "error" "Redis connectivity issue: $REDIS_CHECK"
    HEALTH_ISSUES+=("Redis connectivity issue")
fi

# 5. Check disk space
echo -e "\n${BLUE}5. Disk Space${NC}"
echo "----------------------------------------"

if [ "$REMOTE_MODE" = true ]; then
    DISK_USAGE=$(ssh ${NAS_USER}@${NAS_HOST} "df -h /volume1 | tail -1" 2>/dev/null)
else
    DISK_USAGE=$(df -h / | tail -1)
fi

DISK_PERCENT=$(echo $DISK_USAGE | awk '{print $5}' | sed 's/%//')
DISK_AVAIL=$(echo $DISK_USAGE | awk '{print $4}')

if [ "$DISK_PERCENT" -lt 80 ]; then
    print_status "success" "Disk usage: ${DISK_PERCENT}% (${DISK_AVAIL} available)"
elif [ "$DISK_PERCENT" -lt 90 ]; then
    print_status "warning" "Disk usage: ${DISK_PERCENT}% (${DISK_AVAIL} available)"
    HEALTH_ISSUES+=("Disk usage warning: ${DISK_PERCENT}%")
else
    print_status "error" "Disk usage critical: ${DISK_PERCENT}% (${DISK_AVAIL} available)"
    HEALTH_ISSUES+=("Disk usage critical: ${DISK_PERCENT}%")
fi

# 6. Check recent logs for errors
echo -e "\n${BLUE}6. Recent Error Logs${NC}"
echo "----------------------------------------"

ERROR_COUNT=$(docker_exec logs trading-service-api-1 --tail 100 2>&1 | grep -c "ERROR\|CRITICAL\|Exception" || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
    print_status "success" "No recent errors in API logs"
else
    print_status "warning" "Found $ERROR_COUNT error(s) in recent logs"
    echo "  Last errors:"
    docker_exec logs trading-service-api-1 --tail 100 2>&1 | grep "ERROR\|CRITICAL\|Exception" | tail -3 | sed 's/^/    /'
fi

# 7. Check API authentication
echo -e "\n${BLUE}7. API Authentication${NC}"
echo "----------------------------------------"

AUTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${API_TOKEN}" ${API_URL}/orders 2>/dev/null || echo "000")
if [ "$AUTH_CHECK" == "200" ]; then
    print_status "success" "API authentication working"
else
    print_status "error" "API authentication failed (HTTP $AUTH_CHECK)"
    HEALTH_ISSUES+=("API authentication not working")
fi

# 8. Check metrics endpoint
echo -e "\n${BLUE}8. Metrics Endpoint${NC}"
echo "----------------------------------------"

METRICS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" ${API_URL}/metrics 2>/dev/null || echo "000")
if [ "$METRICS_CHECK" == "200" ]; then
    print_status "success" "Metrics endpoint accessible"
else
    print_status "warning" "Metrics endpoint not responding (HTTP $METRICS_CHECK)"
fi

# 9. Database backup status
echo -e "\n${BLUE}9. Database Backup Status${NC}"
echo "----------------------------------------"

if [ "$REMOTE_MODE" = true ]; then
    LATEST_BACKUP=$(ssh ${NAS_USER}@${NAS_HOST} "ls -t /volume1/docker/trading-service/postgres_backups/backup_*.sql.gz 2>/dev/null | head -1")
    if [ ! -z "$LATEST_BACKUP" ]; then
        BACKUP_AGE=$(ssh ${NAS_USER}@${NAS_HOST} "stat -c %Y '$LATEST_BACKUP'" 2>/dev/null || echo "0")
        CURRENT_TIME=$(date +%s)
        AGE_HOURS=$(( ($CURRENT_TIME - $BACKUP_AGE) / 3600 ))
        
        if [ "$AGE_HOURS" -lt 25 ]; then
            print_status "success" "Latest backup: $(basename $LATEST_BACKUP) (${AGE_HOURS}h old)"
        else
            print_status "warning" "Latest backup is ${AGE_HOURS} hours old"
            HEALTH_ISSUES+=("Backup older than 24 hours")
        fi
    else
        print_status "error" "No backups found"
        HEALTH_ISSUES+=("No database backups found")
    fi
else
    print_status "info" "Backup check skipped (remote only)"
fi

# Summary
echo ""
echo "========================================="
echo "   Health Check Summary"
echo "========================================="

if [ ${#HEALTH_ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All systems operational${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}✗ Issues detected:${NC}"
    for issue in "${HEALTH_ISSUES[@]}"; do
        echo "  - $issue"
    done
    EXIT_CODE=1
fi

echo ""
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

exit $EXIT_CODE