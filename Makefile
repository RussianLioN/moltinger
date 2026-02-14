# Moltis Infrastructure Makefile
# Usage: make <target>

.PHONY: help deploy stop start restart status logs backup restore health-check
.PHONY: monitoring-up monitoring-down prometheus alertmanager grafana
.PHONY: secrets generate-key setup clean

# Default target
help:
	@echo "Moltis Infrastructure Management"
	@echo ""
	@echo "Deployment:"
	@echo "  deploy          - Deploy Moltis stack"
	@echo "  stop            - Stop all services"
	@echo "  start           - Start all services"
	@echo "  restart         - Restart all services"
	@echo "  status          - Show service status"
	@echo "  logs            - Show logs (use LOGS_OPTS=-f for follow)"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  backup          - Create backup"
	@echo "  backup-list     - List available backups"
	@echo "  restore FILE    - Restore from backup file"
	@echo "  generate-key    - Generate encryption key"
	@echo ""
	@echo "Monitoring:"
	@echo "  monitoring-up   - Start monitoring stack"
	@echo "  monitoring-down - Stop monitoring stack"
	@echo "  prometheus      - Open Prometheus UI"
	@echo "  alertmanager    - Open AlertManager UI"
	@echo ""
	@echo "Setup:"
	@echo "  setup           - Initial setup (secrets, network)"
	@echo "  secrets         - Create secrets from .env"
	@echo "  generate-key    - Generate backup encryption key"
	@echo "  clean           - Clean up Docker resources"
	@echo ""
	@echo "Health:"
	@echo "  health-check    - Run health check"
	@echo "  health-monitor  - Start health monitor daemon"

# ========================================================================
# DEPLOYMENT
# ========================================================================

deploy:
	@./scripts/deploy.sh deploy

stop:
	@./scripts/deploy.sh stop

start:
	@./scripts/deploy.sh start

restart:
	@./scripts/deploy.sh restart

status:
	@./scripts/deploy.sh status

logs:
	docker compose -f docker-compose.prod.yml logs $(LOGS_OPTS)

# ========================================================================
# BACKUP & RECOVERY
# ========================================================================

backup:
	@./scripts/backup-moltis-enhanced.sh backup

backup-list:
	@./scripts/backup-moltis-enhanced.sh list

restore:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore FILE=/path/to/backup.tar.gz"; \
		exit 1; \
	fi
	@./scripts/backup-moltis-enhanced.sh restore $(FILE)

generate-key:
	@./scripts/backup-moltis-enhanced.sh generate-key

# ========================================================================
# MONITORING
# ========================================================================

monitoring-up:
	@echo "Starting monitoring stack..."
	docker compose -f docker-compose.prod.yml up -d prometheus alertmanager cadvisor

monitoring-down:
	@echo "Stopping monitoring stack..."
	docker compose -f docker-compose.prod.yml stop prometheus alertmanager cadvisor

prometheus:
	@echo "Opening Prometheus at http://localhost:9090"
	@open http://localhost:9090 2>/dev/null || xdg-open http://localhost:9090 2>/dev/null || echo "Open http://localhost:9090 in your browser"

alertmanager:
	@echo "Opening AlertManager at http://localhost:9093"
	@open http://localhost:9093 2>/dev/null || xdg-open http://localhost:9093 2>/dev/null || echo "Open http://localhost:9093 in your browser"

# ========================================================================
# SETUP
# ========================================================================

setup: secrets network
	@echo "Setup complete!"

secrets:
	@echo "Creating secrets..."
	@mkdir -p secrets
	@if [ -f .env ]; then \
		grep "MOLTIS_PASSWORD" .env | cut -d'=' -f2- > secrets/moltis_password.txt; \
		echo "Secrets created from .env"; \
	else \
		echo "ERROR: .env file not found"; \
		exit 1; \
	fi
	@chmod 600 secrets/*.txt

network:
	@echo "Creating Docker networks..."
	@docker network create traefik_proxy 2>/dev/null || echo "Network traefik_proxy already exists"
	@docker network create monitoring 2>/dev/null || echo "Network monitoring already exists"

clean:
	@echo "Cleaning up Docker resources..."
	docker system prune -af --volumes
	@echo "Cleanup complete"

# ========================================================================
# HEALTH
# ========================================================================

health-check:
	@echo "Checking Moltis health..."
	@curl -sf http://localhost:13131/health && echo "\nMoltis is healthy" || echo "\nMoltis is unhealthy"

health-monitor:
	@./scripts/health-monitor.sh

# ========================================================================
# DEVELOPMENT
# ========================================================================

dev:
	docker compose up -d

dev-down:
	docker compose down

dev-logs:
	docker compose logs -f
