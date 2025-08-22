#!/bin/bash
# Streamlined Deployment Script for Trading Service to NAS
# Builds locally and deploys to Synology NAS

set -e

# Configuration
NAS_HOST="${NAS_HOST:-192.168.1.11}"
NAS_USER="${NAS_USER:-k2600x}"
NAS_PATH="/volume1/docker/trading-service"
PROJECT_NAME="trading-service"
IMAGE_NAME="trading-service-api"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Spinner function for long operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to print colored messages
print_message() {
    local type=$1
    local message=$2
    case $type in
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
            echo -e "${BLUE}→${NC} $message"
            ;;
        "step")
            echo -e "\n${BLUE}▶${NC} $message"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    print_message "step" "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_message "error" "Docker is not installed"
        exit 1
    fi
    print_message "success" "Docker found"
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 ${NAS_USER}@${NAS_HOST} "echo 'SSH OK'" &> /dev/null; then
        print_message "error" "Cannot connect to ${NAS_HOST} via SSH"
        print_message "info" "Please ensure SSH key is configured: ssh-copy-id ${NAS_USER}@${NAS_HOST}"
        exit 1
    fi
    print_message "success" "SSH connectivity confirmed"
    
    # Check NAS Docker
    if ! ssh ${NAS_USER}@${NAS_HOST} "sudo /usr/local/bin/docker version" &> /dev/null; then
        print_message "error" "Docker not accessible on NAS"
        exit 1
    fi
    print_message "success" "Docker accessible on NAS"
}

# Build Docker image locally
build_image() {
    print_message "step" "Building Docker image locally..."
    
    # Check if .env.prod exists
    if [ ! -f ".env.prod" ]; then
        print_message "warning" ".env.prod not found, copying from sample"
        cp .env.sample .env.prod
        print_message "info" "Please update .env.prod with production values"
    fi
    
    # Build the image
    print_message "info" "Building ${IMAGE_NAME}:latest..."
    (
        DOCKER_TARGET=prod docker compose -f deploy/compose.yaml --env-file .env.prod --profile prod build api --no-cache > /tmp/docker_build.log 2>&1
    ) &
    BUILD_PID=$!
    spinner $BUILD_PID
    
    if wait $BUILD_PID; then
        print_message "success" "Docker image built successfully"
    else
        print_message "error" "Docker build failed. Check /tmp/docker_build.log"
        tail -20 /tmp/docker_build.log
        exit 1
    fi
}

# Transfer image to NAS
transfer_image() {
    print_message "step" "Transferring image to NAS..."
    
    # Tag the image
    docker tag deploy_api:latest ${IMAGE_NAME}:latest
    docker tag ${IMAGE_NAME}:latest ${IMAGE_NAME}:${TIMESTAMP}
    
    # Save image to tarball
    print_message "info" "Compressing image..."
    IMAGE_FILE="${IMAGE_NAME}-${TIMESTAMP}.tar.gz"
    (
        docker save ${IMAGE_NAME}:latest | gzip > /tmp/${IMAGE_FILE}
    ) &
    SAVE_PID=$!
    spinner $SAVE_PID
    wait $SAVE_PID
    
    IMAGE_SIZE=$(du -h /tmp/${IMAGE_FILE} | cut -f1)
    print_message "success" "Image compressed (${IMAGE_SIZE})"
    
    # Transfer to NAS
    print_message "info" "Transferring to NAS..."
    (
        scp /tmp/${IMAGE_FILE} ${NAS_USER}@${NAS_HOST}:${NAS_PATH}/ 2>&1 | grep -v "Permanently added"
    ) &
    TRANSFER_PID=$!
    spinner $TRANSFER_PID
    wait $TRANSFER_PID
    
    # Clean up local file
    rm /tmp/${IMAGE_FILE}
    print_message "success" "Image transferred to NAS"
}

# Load image on NAS
load_image_on_nas() {
    print_message "step" "Loading image on NAS..."
    
    IMAGE_FILE="${IMAGE_NAME}-${TIMESTAMP}.tar.gz"
    
    # Load the image
    print_message "info" "Loading Docker image..."
    ssh ${NAS_USER}@${NAS_HOST} "cd ${NAS_PATH} && sudo gunzip -c ${IMAGE_FILE} | sudo /usr/local/bin/docker load" > /dev/null 2>&1
    
    # Clean up remote file
    ssh ${NAS_USER}@${NAS_HOST} "rm ${NAS_PATH}/${IMAGE_FILE}"
    
    print_message "success" "Image loaded on NAS"
}

# Copy necessary files to NAS
sync_files() {
    print_message "step" "Syncing configuration files..."
    
    # Files to sync
    FILES_TO_SYNC=(
        ".env.prod"
        "docker-compose.yaml"
        "entrypoint.sh"
        "alembic.ini"
    )
    
    # Directories to sync
    DIRS_TO_SYNC=(
        "alembic"
        "apps"
        "pkg"
        "contracts"
    )
    
    # Copy files
    for file in "${FILES_TO_SYNC[@]}"; do
        if [ -f "$file" ]; then
            scp -q $file ${NAS_USER}@${NAS_HOST}:${NAS_PATH}/
            print_message "success" "Copied $file"
        fi
    done
    
    # Copy directories
    for dir in "${DIRS_TO_SYNC[@]}"; do
        if [ -d "$dir" ]; then
            scp -qr $dir ${NAS_USER}@${NAS_HOST}:${NAS_PATH}/
            print_message "success" "Copied $dir/"
        fi
    done
}

# Create or update docker-compose on NAS
update_compose() {
    print_message "step" "Updating Docker Compose configuration..."
    
    # Create optimized compose file
    cat > /tmp/docker-compose.yaml << 'EOF'
version: '3.8'

services:
  db:
    image: postgres:16-alpine
    container_name: trading-service-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD:-zs6Fl+uC0XyqR7E7xFU2pats}
      POSTGRES_DB: trading
    volumes:
      - /volume1/docker/trading-service/postgres_data:/var/lib/postgresql/data
    networks:
      - trading-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: trading-service-redis
    volumes:
      - /volume1/docker/trading-service/redis_data:/data
    networks:
      - trading-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    image: trading-service-api:latest
    container_name: trading-service-api
    ports:
      - '${API_PORT:-8085}:8080'
    environment:
      DATABASE_URL: postgresql+asyncpg://postgres:${DB_PASSWORD:-zs6Fl+uC0XyqR7E7xFU2pats}@db:5432/trading
      REDIS_URL: redis://redis:6379
      API_TOKEN: ${API_TOKEN}
      WEBHOOK_URL: ${WEBHOOK_URL:-https://webhook.site/test}
      MAX_POS_USD: ${MAX_POS_USD:-50000}
      MAX_DAILY_LOSS_USD: ${MAX_DAILY_LOSS_USD:-5000}
      EXCHANGE_MODE: ${EXCHANGE_MODE:-sandbox}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - trading-net
    restart: unless-stopped
    entrypoint: ['/app/entrypoint.sh']
    command: ['uvicorn', 'apps.api.main:app', '--host', '0.0.0.0', '--port', '8080']
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  trading-net:
    driver: bridge
    name: trading-network
EOF
    
    # Copy to NAS
    scp -q /tmp/docker-compose.yaml ${NAS_USER}@${NAS_HOST}:${NAS_PATH}/
    rm /tmp/docker-compose.yaml
    print_message "success" "Docker Compose configuration updated"
}

# Deploy on NAS
deploy_on_nas() {
    print_message "step" "Deploying services on NAS..."
    
    # Stop existing services
    print_message "info" "Stopping existing services..."
    ssh ${NAS_USER}@${NAS_HOST} "cd ${NAS_PATH} && sudo /usr/local/bin/docker compose down" > /dev/null 2>&1 || true
    
    # Start services
    print_message "info" "Starting services..."
    ssh ${NAS_USER}@${NAS_HOST} "cd ${NAS_PATH} && sudo /usr/local/bin/docker compose up -d" > /dev/null 2>&1
    
    print_message "success" "Services started"
    
    # Wait for health checks
    print_message "info" "Waiting for services to be healthy..."
    sleep 10
    
    # Check container status
    CONTAINERS=$(ssh ${NAS_USER}@${NAS_HOST} "sudo /usr/local/bin/docker ps --format 'table {{.Names}}\t{{.Status}}' | grep trading-service")
    echo "$CONTAINERS" | while IFS= read -r line; do
        echo "  $line"
    done
}

# Run health check
run_health_check() {
    print_message "step" "Running health check..."
    
    # Use the health check script
    if [ -f "scripts/health-check.sh" ]; then
        ./scripts/health-check.sh --remote
    else
        # Basic health check
        HEALTH_URL="http://${NAS_HOST}:8085/healthz"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_URL 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" == "200" ]; then
            print_message "success" "Health endpoint responding"
        else
            print_message "warning" "Health endpoint returned: $HTTP_CODE"
        fi
    fi
}

# Main deployment flow
main() {
    echo "========================================="
    echo "   Trading Service Deployment to NAS"
    echo "========================================="
    echo "Target: ${NAS_USER}@${NAS_HOST}"
    echo "Path: ${NAS_PATH}"
    echo ""
    
    # Parse arguments
    SKIP_BUILD=false
    SKIP_HEALTH=false
    
    for arg in "$@"; do
        case $arg in
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-health)
                SKIP_HEALTH=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-build    Skip Docker image build"
                echo "  --skip-health   Skip health check after deployment"
                echo "  --help          Show this help message"
                exit 0
                ;;
        esac
    done
    
    # Start deployment
    START_TIME=$(date +%s)
    
    check_prerequisites
    
    if [ "$SKIP_BUILD" = false ]; then
        build_image
        transfer_image
        load_image_on_nas
    else
        print_message "info" "Skipping image build (--skip-build)"
    fi
    
    sync_files
    update_compose
    deploy_on_nas
    
    if [ "$SKIP_HEALTH" = false ]; then
        run_health_check
    else
        print_message "info" "Skipping health check (--skip-health)"
    fi
    
    # Calculate deployment time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    
    echo ""
    echo "========================================="
    print_message "success" "Deployment completed in ${MINUTES}m ${SECONDS}s"
    echo ""
    echo "Access the API at: http://${NAS_HOST}:8085"
    echo "View logs: ssh ${NAS_USER}@${NAS_HOST} 'sudo /usr/local/bin/docker logs -f trading-service-api'"
    echo "========================================="
}

# Run main function
main "$@"