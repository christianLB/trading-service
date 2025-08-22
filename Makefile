.PHONY: help dev-up dev-down logs health prod-build prod-up nas-setup nas-deploy test lint clean

DC_DEV = docker compose -f deploy/compose.yaml --env-file .env.dev --profile dev
DC_PROD = docker compose -f deploy/compose.yaml --env-file .env.prod --profile prod
DC_NAS = docker --context nas compose -f deploy/compose.yaml --env-file .env.prod --profile prod

help:
	@echo "Available targets:"
	@echo ""
	@echo "🔧 Development:"
	@echo "  dev-up       - Start development environment"
	@echo "  dev-down     - Stop development environment"
	@echo "  dev-backup   - Backup development database"
	@echo "  logs         - Follow development logs"
	@echo "  health       - Check service health"
	@echo ""
	@echo "🏭 Production (Local):"
	@echo "  prod-build   - Build production images"
	@echo "  prod-up      - Start production environment locally"
	@echo ""
	@echo "🚀 Production (NAS):"
	@echo "  nas-setup    - One-time NAS setup (creates context & directories)"
	@echo "  nas-deploy   - Deploy application to NAS"
	@echo "  nas-logs     - View production logs"
	@echo "  nas-health   - Check production health"
	@echo "  nas-status   - Show production container status"
	@echo "  nas-stop     - Stop production services"
	@echo "  nas-restart  - Restart production services"
	@echo "  nas-backup   - Run database backup"
	@echo "  nas-restore  - Restore database from backup"
	@echo "  nas-migrate  - Run database migrations"
	@echo "  nas-exec     - Execute command in production container"
	@echo "  nas-test     - Test production API endpoints"
	@echo ""
	@echo "🧪 Testing & Quality:"
	@echo "  test         - Run tests"
	@echo "  lint         - Run linters"
	@echo "  clean        - Clean up containers and volumes"

dev-up:
	@echo "Starting development environment..."
	@cp -n .env.sample .env.dev 2>/dev/null || true
	DOCKER_TARGET=dev $(DC_DEV) up -d --build
	@echo "Development environment started!"
	@echo "API available at http://localhost:8085"

dev-down:
	@echo "Stopping development environment..."
	$(DC_DEV) down -v

dev-backup:
	@echo "💾 Backing up development database..."
	@./scripts/backup-dev.sh

logs:
	$(DC_DEV) logs -f --tail=200

health:
	@curl -sS http://localhost:8085/healthz | jq . || echo "Service not responding"

prod-build:
	@echo "Building production images..."
	@cp -n .env.sample .env.prod 2>/dev/null || true
	DOCKER_TARGET=prod $(DC_PROD) build

prod-up:
	@echo "Starting production environment locally..."
	@cp -n .env.sample .env.prod 2>/dev/null || true
	DOCKER_TARGET=prod $(DC_PROD) up -d

nas-setup:
	@echo "Setting up NAS Docker context and directories..."
	@read -p "Enter NAS username (with sudo access): " nas_user && \
	docker context create nas --docker "host=ssh://$$nas_user@192.168.1.11" && \
	echo "Docker context created. Setting up directories..." && \
	ssh $$nas_user@192.168.1.11 "sudo mkdir -p /volume1/docker/trading-service/{postgres_data,postgres_backups,redis_data,logs,config,secrets}" && \
	ssh $$nas_user@192.168.1.11 "sudo chown -R $$nas_user:users /volume1/docker/trading-service" && \
	ssh $$nas_user@192.168.1.11 "sudo chmod -R 755 /volume1/docker/trading-service" && \
	echo "Copying scripts to NAS..." && \
	scp scripts/*.sh $$nas_user@192.168.1.11:/volume1/docker/trading-service/ && \
	echo "NAS setup completed successfully!"

nas-deploy:
	@echo "🚀 Deploying to Production NAS..."
	@echo "Using streamlined deployment script..."
	@./scripts/deploy.sh
	@echo "✅ Deployment completed!"
	@echo "Access the API at: http://192.168.1.11:8085"

nas-logs:
	@echo "📋 Viewing production logs..."
	@ssh k2600x@192.168.1.11 "sudo /usr/local/bin/docker logs -f --tail=100 trading-service-api"

nas-health:
	@echo "🏥 Checking production health..."
	@./scripts/health-check.sh --remote

nas-backup:
	@echo "💾 Running production backup..."
	@read -p "Enter NAS username: " nas_user && \
	ssh $$nas_user@192.168.1.11 "sudo /volume1/docker/trading-service/nas-backup.sh" && \
	echo "Backup completed!"

nas-backup-setup:
	@echo "🔧 Setting up automated backups on NAS..."
	@chmod +x scripts/setup-nas-scheduler.sh
	@./scripts/setup-nas-scheduler.sh

nas-backup-check:
	@echo "📊 Checking backup status..."
	@read -p "Enter NAS username: " nas_user && \
	ssh $$nas_user@192.168.1.11 "/volume1/docker/trading-service/check-backup.sh"

nas-backup-list:
	@echo "📋 Listing backups on NAS..."
	@read -p "Enter NAS username: " nas_user && \
	ssh $$nas_user@192.168.1.11 "ls -lht /volume1/docker/trading-service/postgres_backups/*.sql.gz | head -20"

nas-cleanup:
	@echo "🧹 Cleaning up NAS disk space..."
	@./scripts/cleanup-nas.sh

nas-restore:
	@echo "🔄 Restoring production database..."
	@echo "⚠️  WARNING: This will restore the production database!"
	@read -p "Enter backup file name (or press Enter for latest): " backup_file && \
	read -p "Enter NAS username: " nas_user && \
	ssh $$nas_user@192.168.1.11 "/volume1/docker/trading-service/restore.sh $$backup_file" && \
	echo "Restore completed!"

nas-migrate:
	@echo "🔧 Running production migrations..."
	@./scripts/migrate-prod.sh --remote

nas-stop:
	@echo "🛑 Stopping production services..."
	@ssh k2600x@192.168.1.11 "cd /volume1/docker/trading-service && sudo /usr/local/bin/docker compose stop"

nas-restart:
	@echo "🔄 Restarting production services..."
	@ssh k2600x@192.168.1.11 "cd /volume1/docker/trading-service && sudo /usr/local/bin/docker compose restart"

nas-status:
	@echo "📊 Production status..."
	@ssh k2600x@192.168.1.11 "sudo /usr/local/bin/docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAMES|trading-service'"

nas-exec:
	@echo "🖥️  Executing command in production container..."
	@read -p "Container name (api/db/redis): " container && \
	read -p "Command to execute: " cmd && \
	ssh -t k2600x@192.168.1.11 "sudo /usr/local/bin/docker exec -it trading-service-$$container $$cmd"

nas-test:
	@echo "🧪 Testing production API endpoints..."
	@./scripts/test-endpoints.sh

test:
	@echo "Running tests..."
	docker run --rm -v $$(pwd):/app -w /app python:3.11-slim sh -c "pip install poetry && poetry install && poetry run pytest"

lint:
	@echo "Running linters..."
	docker run --rm -v $$(pwd):/app -w /app python:3.11-slim sh -c "pip install poetry && poetry install && poetry run black . && poetry run ruff check ."

clean:
	@echo "Cleaning up..."
	$(DC_DEV) down -v
	$(DC_PROD) down -v
	docker system prune -f