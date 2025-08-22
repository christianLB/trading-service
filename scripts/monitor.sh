#!/bin/bash
# Continuous Monitoring Script for Trading Service
# Monitors health, performance, and logs in real-time

set -e

# Configuration
NAS_HOST="${NAS_HOST:-192.168.1.11}"
NAS_USER="${NAS_USER:-k2600x}"
API_URL="http://${NAS_HOST}:8085"
CHECK_INTERVAL=${CHECK_INTERVAL:-30}  # Seconds between checks
LOG_FILE="${LOG_FILE:-/tmp/trading-service-monitor.log}"
ALERT_EMAIL="${ALERT_EMAIL:-}"  # Set to receive email alerts
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"  # Set to receive Slack alerts

# State tracking
LAST_STATUS="unknown"
CONSECUTIVE_FAILURES=0
ALERT_THRESHOLD=3  # Alert after this many consecutive failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Trap for clean exit
trap cleanup EXIT

cleanup() {
    echo -e "\n${YELLOW}Monitoring stopped${NC}"
    exit 0
}

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case $level in
        "ERROR")
            echo -e "${RED}[$timestamp] $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}[$timestamp] $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[$timestamp] $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}[$timestamp] $message${NC}"
            ;;
        *)
            echo "[$timestamp] $message"
            ;;
    esac
}

# Function to send alerts
send_alert() {
    local severity=$1
    local message=$2
    local details=$3
    
    # Log the alert
    log_message "ALERT" "[$severity] $message"
    
    # Send email alert if configured
    if [ ! -z "$ALERT_EMAIL" ]; then
        echo -e "Subject: Trading Service Alert - $severity\n\n$message\n\nDetails:\n$details" | \
            sendmail "$ALERT_EMAIL" 2>/dev/null || true
    fi
    
    # Send Slack alert if configured
    if [ ! -z "$SLACK_WEBHOOK" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\":warning: Trading Service Alert\",\"attachments\":[{\"color\":\"danger\",\"title\":\"$severity\",\"text\":\"$message\",\"fields\":[{\"title\":\"Details\",\"value\":\"$details\",\"short\":false}]}]}" \
            "$SLACK_WEBHOOK" 2>/dev/null || true
    fi
}

# Function to check API health
check_api_health() {
    local response=$(curl -s -w "\n%{http_code}" "${API_URL}/healthz" 2>/dev/null || echo "000")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" == "200" ]; then
        echo "healthy"
        return 0
    else
        echo "unhealthy (HTTP $http_code)"
        return 1
    fi
}

# Function to check container status
check_containers() {
    local api_status=$(ssh ${NAS_USER}@${NAS_HOST} "sudo /usr/local/bin/docker ps --filter 'name=trading-service-api' --format '{{.Status}}'" 2>/dev/null || echo "Not found")
    local db_status=$(ssh ${NAS_USER}@${NAS_HOST} "sudo /usr/local/bin/docker ps --filter 'name=trading-service-db' --format '{{.Status}}'" 2>/dev/null || echo "Not found")
    local redis_status=$(ssh ${NAS_USER}@${NAS_HOST} "sudo /usr/local/bin/docker ps --filter 'name=trading-service-redis' --format '{{.Status}}'" 2>/dev/null || echo "Not found")
    
    local all_healthy=true
    
    if [[ ! "$api_status" =~ "Up" ]]; then
        echo "API: $api_status"
        all_healthy=false
    fi
    
    if [[ ! "$db_status" =~ "Up" ]]; then
        echo "DB: $db_status"
        all_healthy=false
    fi
    
    if [[ ! "$redis_status" =~ "Up" ]]; then
        echo "Redis: $redis_status"
        all_healthy=false
    fi
    
    if [ "$all_healthy" = true ]; then
        echo "all healthy"
        return 0
    else
        return 1
    fi
}

# Function to check disk space
check_disk_space() {
    local disk_usage=$(ssh ${NAS_USER}@${NAS_HOST} "df -h /volume1 | tail -1" 2>/dev/null)
    local disk_percent=$(echo $disk_usage | awk '{print $5}' | sed 's/%//')
    
    if [ "$disk_percent" -gt 90 ]; then
        echo "critical: ${disk_percent}%"
        return 2
    elif [ "$disk_percent" -gt 80 ]; then
        echo "warning: ${disk_percent}%"
        return 1
    else
        echo "ok: ${disk_percent}%"
        return 0
    fi
}

# Function to check recent errors in logs
check_error_logs() {
    local error_count=$(ssh ${NAS_USER}@${NAS_HOST} "sudo /usr/local/bin/docker logs trading-service-api --tail 100 2>&1 | grep -c 'ERROR\|CRITICAL\|Exception'" 2>/dev/null || echo "0")
    
    if [ "$error_count" -gt 10 ]; then
        echo "high: $error_count errors"
        return 2
    elif [ "$error_count" -gt 0 ]; then
        echo "moderate: $error_count errors"
        return 1
    else
        echo "clean"
        return 0
    fi
}

# Function to measure API response time
check_response_time() {
    local response_time=$(curl -s -o /dev/null -w "%{time_total}" "${API_URL}/healthz" 2>/dev/null || echo "999")
    local response_ms=$(echo "$response_time * 1000" | bc 2>/dev/null || echo "999")
    
    if (( $(echo "$response_ms > 1000" | bc -l) )); then
        echo "slow: ${response_ms}ms"
        return 1
    else
        echo "fast: ${response_ms}ms"
        return 0
    fi
}

# Function to display dashboard
display_dashboard() {
    clear
    echo "========================================="
    echo "   Trading Service Monitor Dashboard"
    echo "========================================="
    echo "Target: ${NAS_HOST}"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Uptime: $UPTIME_COUNTER checks"
    echo ""
    echo "Status Overview:"
    echo "----------------"
    echo "API Health:      $API_HEALTH_STATUS"
    echo "Containers:      $CONTAINER_STATUS"
    echo "Disk Space:      $DISK_STATUS"
    echo "Error Logs:      $ERROR_STATUS"
    echo "Response Time:   $RESPONSE_TIME_STATUS"
    echo ""
    echo "Alert Status:"
    echo "----------------"
    echo "Consecutive Failures: $CONSECUTIVE_FAILURES"
    echo "Last Alert: $LAST_ALERT"
    echo ""
    echo "Recent Events:"
    echo "----------------"
    tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    echo ""
    echo "Press Ctrl+C to stop monitoring"
}

# Main monitoring loop
main() {
    log_message "INFO" "Starting continuous monitoring of Trading Service"
    
    UPTIME_COUNTER=0
    LAST_ALERT="None"
    
    while true; do
        UPTIME_COUNTER=$((UPTIME_COUNTER + 1))
        
        # Perform checks
        API_HEALTH_STATUS=$(check_api_health) || API_HEALTHY=false
        CONTAINER_STATUS=$(check_containers) || CONTAINERS_HEALTHY=false
        DISK_STATUS=$(check_disk_space) || DISK_OK=$?
        ERROR_STATUS=$(check_error_logs) || ERRORS_OK=$?
        RESPONSE_TIME_STATUS=$(check_response_time) || RESPONSE_OK=false
        
        # Determine overall status
        OVERALL_STATUS="healthy"
        ISSUES=""
        
        if [ "${API_HEALTHY:-true}" = false ]; then
            OVERALL_STATUS="unhealthy"
            ISSUES="${ISSUES}API not responding. "
        fi
        
        if [ "${CONTAINERS_HEALTHY:-true}" = false ]; then
            OVERALL_STATUS="unhealthy"
            ISSUES="${ISSUES}Container issues: $CONTAINER_STATUS. "
        fi
        
        if [ "${DISK_OK:-0}" -eq 2 ]; then
            OVERALL_STATUS="critical"
            ISSUES="${ISSUES}Disk space critical. "
        elif [ "${DISK_OK:-0}" -eq 1 ]; then
            if [ "$OVERALL_STATUS" != "critical" ]; then
                OVERALL_STATUS="warning"
            fi
            ISSUES="${ISSUES}Disk space warning. "
        fi
        
        if [ "${ERRORS_OK:-0}" -eq 2 ]; then
            if [ "$OVERALL_STATUS" == "healthy" ]; then
                OVERALL_STATUS="warning"
            fi
            ISSUES="${ISSUES}High error rate in logs. "
        fi
        
        # Handle status changes
        if [ "$OVERALL_STATUS" != "healthy" ]; then
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            
            if [ $CONSECUTIVE_FAILURES -ge $ALERT_THRESHOLD ]; then
                if [ "$LAST_STATUS" == "healthy" ] || [ $((CONSECUTIVE_FAILURES % 10)) -eq 0 ]; then
                    send_alert "$OVERALL_STATUS" "Service degraded for $CONSECUTIVE_FAILURES checks" "$ISSUES"
                    LAST_ALERT="$(date '+%H:%M:%S') - $OVERALL_STATUS"
                fi
            fi
            
            log_message "WARNING" "Health check failed: $ISSUES"
        else
            if [ "$LAST_STATUS" != "healthy" ] && [ "$LAST_STATUS" != "unknown" ]; then
                send_alert "RECOVERED" "Service recovered after $CONSECUTIVE_FAILURES failures" "All systems operational"
                log_message "SUCCESS" "Service recovered"
                LAST_ALERT="$(date '+%H:%M:%S') - Recovered"
            fi
            CONSECUTIVE_FAILURES=0
        fi
        
        LAST_STATUS="$OVERALL_STATUS"
        
        # Update dashboard
        if [ -t 1 ]; then  # Check if running interactively
            display_dashboard
        else
            # Non-interactive mode - just log
            log_message "INFO" "Status: $OVERALL_STATUS - $ISSUES"
        fi
        
        # Wait for next check
        sleep $CHECK_INTERVAL
    done
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        --log)
            LOG_FILE="$2"
            shift 2
            ;;
        --email)
            ALERT_EMAIL="$2"
            shift 2
            ;;
        --slack)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --interval SECONDS  Check interval (default: 30)"
            echo "  --log FILE         Log file path (default: /tmp/trading-service-monitor.log)"
            echo "  --email ADDRESS    Email address for alerts"
            echo "  --slack WEBHOOK    Slack webhook URL for alerts"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main monitoring loop
main