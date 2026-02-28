#!/bin/bash
# Moltis Deployment Script
# Version: 2.1
# Features: Blue-green deployment, health checks, rollback, notifications, GitOps guards

set -euo pipefail

# ========================================================================
# GITOPS GUARDS (P1-3)
# ========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source GitOps guards library
if [[ -f "$SCRIPT_DIR/gitops-guards.sh" ]]; then
    source "$SCRIPT_DIR/gitops-guards.sh"
fi

# ========================================================================
# CONFIGURATION
# ========================================================================
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.prod.yml"
ENV_FILE="$PROJECT_ROOT/.env"

# Deployment settings
HEALTH_CHECK_TIMEOUT=300
HEALTH_CHECK_INTERVAL=10
ROLLBACK_ENABLED=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ========================================================================
# UTILITY FUNCTIONS
# ========================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $message" ;;
    esac
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        exit 1
    fi

    # Check compose file
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    # Check secrets
    if [[ ! -f "$PROJECT_ROOT/secrets/moltis_password.txt" ]]; then
        log_warn "Secrets file not found, creating from .env"
        mkdir -p "$PROJECT_ROOT/secrets"
        if [[ -f "$ENV_FILE" ]]; then
            grep "MOLTIS_PASSWORD" "$ENV_FILE" | cut -d'=' -f2 > "$PROJECT_ROOT/secrets/moltis_password.txt"
        else
            log_error "No MOLTIS_PASSWORD found in .env"
            exit 1
        fi
    fi

    # Check network
    if ! docker network ls | grep -q "traefik_proxy"; then
        log_warn "traefik_proxy network not found, creating..."
        docker network create traefik_proxy
    fi

    log_success "Prerequisites check passed"
}

# Health check
wait_for_healthy() {
    local container="$1"
    local timeout="${2:-$HEALTH_CHECK_TIMEOUT}"
    local elapsed=0

    log_info "Waiting for $container to become healthy (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")

        case "$health" in
            healthy)
                log_success "$container is healthy"
                return 0
                ;;
            unhealthy)
                log_error "$container is unhealthy"
                docker logs "$container" --tail 50 2>&1
                return 1
                ;;
            starting)
                # Still starting, wait
                ;;
        esac

        sleep "$HEALTH_CHECK_INTERVAL"
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        echo -n "."
    done

    echo ""
    log_error "Timeout waiting for $container to become healthy"
    return 1
}

# Get current version
get_current_version() {
    docker inspect moltis --format='{{.Config.Image}}' 2>/dev/null || echo "none"
}

# Backup current state
backup_current_state() {
    local backup_name="pre-deploy-$(date +%Y%m%d_%H%M%S)"

    log_info "Creating pre-deployment backup: $backup_name"

    "$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh" backup

    # Save current image tag for rollback
    local current_image
    current_image=$(get_current_version)
    echo "$current_image" > "$PROJECT_ROOT/.last-deployed-image"

    log_success "Pre-deployment backup created"
}

# Pull latest images
pull_images() {
    log_info "Pulling latest images..."

    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" pull

    log_success "Images pulled successfully"
}

# Deploy containers
deploy_containers() {
    log_info "Deploying containers..."

    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

    log_success "Containers deployed"
}

# Rollback deployment
rollback() {
    log_warn "Initiating rollback..."

    local last_image
    if [[ -f "$PROJECT_ROOT/.last-deployed-image" ]]; then
        last_image=$(cat "$PROJECT_ROOT/.last-deployed-image")
        log_info "Rolling back to: $last_image"

        docker stop moltis 2>/dev/null || true
        docker rm moltis 2>/dev/null || true

        cd "$PROJECT_ROOT"
        # Update image in compose and restart
        sed -i.bak "s|image: ghcr.io/moltis-org/moltis:.*|image: $last_image|" "$COMPOSE_FILE"
        docker compose -f "$COMPOSE_FILE" up -d moltis
    else
        log_error "No previous image found for rollback"
        # Try to restore from backup
        local latest_backup
        latest_backup=$(ls -t /var/backups/moltis/daily/*.tar.gz* 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            log_info "Attempting restore from backup: $latest_backup"
            "$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh" restore "$latest_backup"
        fi
    fi

    log_success "Rollback complete"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."

    # Wait for health check
    if ! wait_for_healthy "moltis" "$HEALTH_CHECK_TIMEOUT"; then
        return 1
    fi

    # Test HTTP endpoint
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:13131/health 2>/dev/null || echo "000")

    if [[ "$http_code" != "200" ]]; then
        log_error "Health endpoint returned HTTP $http_code"
        return 1
    fi

    # Test metrics endpoint
    http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:13131/metrics 2>/dev/null || echo "000")

    if [[ "$http_code" != "200" ]]; then
        log_warn "Metrics endpoint returned HTTP $http_code (non-critical)"
    fi

    log_success "Deployment verification passed"
    return 0
}

# Send deployment notification
send_notification() {
    local status="$1"
    local message="$2"

    # Slack notification
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        local color
        case "$status" in
            success) color="good" ;;
            failure) color="danger" ;;
            *) color="warning" ;;
        esac

        curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"attachments\": [{
                    \"color\": \"$color\",
                    \"title\": \"Moltis Deployment - $status\",
                    \"text\": \"$message\",
                    \"footer\": \"Host: $(hostname)\",
                    \"ts\": $(date +%s)
                }]
            }" > /dev/null 2>&1 || true
    fi
}

# ========================================================================
# DEPLOYMENT COMMANDS
# ========================================================================

cmd_deploy() {
    local environment="${1:-production}"

    # GitOps Guard: Check and confirm before deployment
    if type gitops_guard_deploy &>/dev/null; then
        gitops_guard_deploy "deploy.sh"
    fi

    log_info "=========================================="
    log_info "Starting Moltis Deployment"
    log_info "Environment: $environment"
    log_info "=========================================="

    check_prerequisites
    backup_current_state
    pull_images
    deploy_containers

    if verify_deployment; then
        log_success "=========================================="
        log_success "Deployment completed successfully!"
        log_success "=========================================="
        send_notification "success" "Deployment completed successfully"
    else
        log_error "Deployment verification failed!"
        if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
            rollback
            send_notification "failure" "Deployment failed, rolled back"
        fi
        exit 1
    fi
}

cmd_rollback() {
    log_info "=========================================="
    log_info "Starting Rollback"
    log_info "=========================================="

    rollback

    if verify_deployment; then
        log_success "Rollback completed successfully!"
        send_notification "warning" "Deployment rolled back"
    else
        log_error "Rollback verification failed!"
        exit 1
    fi
}

cmd_status() {
    log_info "Deployment Status"
    echo ""

    echo "Container Status:"
    docker ps -a --filter "name=moltis" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""

    echo "Health Status:"
    docker inspect moltis --format='Health: {{.State.Health.Status}}' 2>/dev/null || echo "Not available"
    echo ""

    echo "Image:"
    echo "  Current: $(get_current_version)"
    if [[ -f "$PROJECT_ROOT/.last-deployed-image" ]]; then
        echo "  Previous: $(cat "$PROJECT_ROOT/.last-deployed-image")"
    fi
    echo ""

    echo "Recent Deploys:"
    ls -lt /var/backups/moltis/daily/*.tar.gz* 2>/dev/null | head -5 || echo "  No backups found"
}

cmd_stop() {
    log_info "Stopping Moltis..."
    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" down
    log_success "Moltis stopped"
}

cmd_start() {
    log_info "Starting Moltis..."
    check_prerequisites
    cd "$PROJECT_ROOT"
    docker compose -f "$COMPOSE_FILE" up -d
    wait_for_healthy "moltis"
    log_success "Moltis started"
}

cmd_restart() {
    cmd_stop
    sleep 5
    cmd_start
}

cmd_logs() {
    local follow="${1:-}"
    cd "$PROJECT_ROOT"

    if [[ "$follow" == "-f" ]]; then
        docker compose -f "$COMPOSE_FILE" logs -f --tail=100
    else
        docker compose -f "$COMPOSE_FILE" logs --tail=200
    fi
}

# ========================================================================
# MAIN
# ========================================================================

show_usage() {
    echo "Moltis Deployment Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy [env]   - Deploy to environment (default: production)"
    echo "  rollback       - Rollback to previous version"
    echo "  status         - Show deployment status"
    echo "  start          - Start services"
    echo "  stop           - Stop services"
    echo "  restart        - Restart services"
    echo "  logs [-f]      - Show logs (follow with -f)"
    echo ""
    echo "Environment Variables:"
    echo "  SLACK_WEBHOOK        - Slack webhook for notifications"
    echo "  HEALTH_CHECK_TIMEOUT - Health check timeout in seconds"
    echo "  ROLLBACK_ENABLED     - Enable automatic rollback (true/false)"
}

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        deploy)
            cmd_deploy "$@"
            ;;
        rollback)
            cmd_rollback
            ;;
        status)
            cmd_status
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        logs)
            cmd_logs "$@"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
