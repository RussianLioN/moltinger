# Moltis Infrastructure Makefile
# Usage: make <target>

.PHONY: help deploy stop start restart status logs backup restore health-check
.PHONY: monitoring-up monitoring-down prometheus alertmanager grafana
.PHONY: secrets generate-key setup clean
.PHONY: backup-enable backup-disable backup-status version-check
.PHONY: test test-unit test-integration test-e2e test-security test-all
.PHONY: instructions-sync instructions-check skills-sync skills-check
.PHONY: codex-bootstrap codex-check codex-check-ci
.PHONY: codex-research codex-docs codex-runtime codex-assets codex-review codex-hotfix

CODEX_MODEL ?= gpt-5.4
CODEX_BASE_BRANCH ?= main

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
	@echo "  backup-enable   - Enable systemd backup timer"
	@echo "  backup-disable  - Disable systemd backup timer"
	@echo "  backup-status   - Show backup timer status"
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
	@echo ""
	@echo "Version:"
	@echo "  version-check   - Show current Docker image versions"
	@echo ""
	@echo "Testing:"
	@echo "  test            - Run unit tests (default)"
	@echo "  test-unit       - Run unit tests only"
	@echo "  test-integration - Run integration tests"
	@echo "  test-e2e        - Run end-to-end tests"
	@echo "  test-security   - Run security tests"
	@echo "  test-all        - Run all tests"
	@echo ""
	@echo "AI instructions & skills:"
	@echo "  instructions-sync  - Regenerate AGENTS.md from shared sources"
	@echo "  instructions-check - Verify AGENTS.md is in sync"
	@echo "  skills-sync        - Sync .claude skills into \$$CODEX_HOME/skills"
	@echo "  skills-check       - Verify Codex skills sync state"
	@echo ""
	@echo "Codex workflows:"
	@echo "  codex-bootstrap - Verify local Codex prerequisites and repo policy state"
	@echo "  codex-check     - Run repo-specific Codex governance checks"
	@echo "  codex-check-ci  - Run Codex governance checks in CI-safe mode"
	@echo "  codex-research  - Launch Codex in read-only research mode"
	@echo "  codex-docs      - Launch Codex for docs/knowledge work"
	@echo "  codex-runtime   - Launch Codex for runtime/config/workflow changes"
	@echo "  codex-assets    - Launch Codex for .ai/.claude asset work"
	@echo "  codex-review    - Run codex review against \$$CODEX_BASE_BRANCH"
	@echo "  codex-hotfix    - Launch Codex for bounded hotfix work"
	@echo ""
	@echo "  Override defaults with CODEX_MODEL=<model> CODEX_BASE_BRANCH=<branch>"

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

backup-enable: ## Enable systemd backup timer
	sudo cp systemd/moltis-backup.timer /etc/systemd/system/
	sudo cp systemd/moltis-backup.service /etc/systemd/system/
	sudo systemctl daemon-reload
	sudo systemctl enable --now moltis-backup.timer
	@echo "Backup timer enabled (daily at 02:00)"

backup-disable: ## Disable systemd backup timer
	sudo systemctl disable --now moltis-backup.timer
	@echo "Backup timer disabled"

backup-status: ## Show backup timer status
	systemctl list-timers moltis-backup.timer
	systemctl status moltis-backup.service

restore:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore FILE=/path/to/backup.tar.gz"; \
		exit 1; \
	fi
	@./scripts/backup-moltis-enhanced.sh restore $(FILE)

generate-key:
	@./scripts/backup-moltis-enhanced.sh generate-key

# ========================================================================
# VERSION MANAGEMENT
# ========================================================================

version-check: ## Show current Docker image versions
	@echo "Moltis version:"
	@grep -E 'image:.*moltis' docker-compose.yml docker-compose.prod.yml | head -2
	@echo "\nWatchtower version:"
	@grep -E 'image:.*watchtower' docker-compose.yml docker-compose.prod.yml | head -2

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

# ========================================================================
# TESTING
# ========================================================================

test: test-unit

test-unit:
	@echo "Running unit tests..."
	@./tests/run_unit.sh

test-integration:
	@echo "Running integration tests..."
	@./tests/run_integration.sh

test-e2e:
	@echo "Running end-to-end tests..."
	@./tests/run_e2e.sh

test-security:
	@echo "Running security tests..."
	@./tests/run_security.sh

test-all: test-unit test-integration test-e2e test-security
	@echo "All test suites completed"

# ========================================================================
# AI INSTRUCTIONS & SKILLS
# ========================================================================

instructions-sync:
	@./scripts/sync-agent-instructions.sh --write

instructions-check:
	@./scripts/sync-agent-instructions.sh --check

skills-sync:
	@./scripts/sync-claude-skills-to-codex.sh --install

skills-check:
	@./scripts/sync-claude-skills-to-codex.sh --check

# ========================================================================
# CODEX WORKFLOWS
# ========================================================================

codex-bootstrap:
	@command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found in PATH"; exit 1; }
	@./scripts/codex-check.sh
	@echo "Codex local setup looks ready"

codex-check:
	@./scripts/codex-check.sh

codex-check-ci:
	@./scripts/codex-check.sh --ci

codex-research:
	@CODEX_MODEL="$(CODEX_MODEL)" CODEX_BASE_BRANCH="$(CODEX_BASE_BRANCH)" ./scripts/codex-profile-launch.sh research

codex-docs:
	@CODEX_MODEL="$(CODEX_MODEL)" CODEX_BASE_BRANCH="$(CODEX_BASE_BRANCH)" ./scripts/codex-profile-launch.sh docs

codex-runtime:
	@CODEX_MODEL="$(CODEX_MODEL)" CODEX_BASE_BRANCH="$(CODEX_BASE_BRANCH)" ./scripts/codex-profile-launch.sh runtime

codex-assets:
	@CODEX_MODEL="$(CODEX_MODEL)" CODEX_BASE_BRANCH="$(CODEX_BASE_BRANCH)" ./scripts/codex-profile-launch.sh assets

codex-review:
	@CODEX_MODEL="$(CODEX_MODEL)" CODEX_BASE_BRANCH="$(CODEX_BASE_BRANCH)" ./scripts/codex-profile-launch.sh review

codex-hotfix:
	@CODEX_MODEL="$(CODEX_MODEL)" CODEX_BASE_BRANCH="$(CODEX_BASE_BRANCH)" ./scripts/codex-profile-launch.sh hotfix
