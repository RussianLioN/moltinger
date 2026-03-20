#!/bin/bash
# GitOps Metrics Collector
# Version: 1.0
# Purpose: Collect and report GitOps compliance metrics
# Usage: gitops-metrics.sh [--output json|markdown]

set -euo pipefail

# ========================================================================
# CONFIGURATION
# ========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DEPLOY_PATH="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="/var/log/gitops-metrics"
DEPLOY_PATH="${DEPLOY_PATH:-${MOLTIS_ACTIVE_ROOT:-$DEFAULT_DEPLOY_PATH}}"
METRICS_FILE="$METRICS_DIR/metrics.json"

# SLO Targets
SLO_COMPLIANCE_TARGET=95      # 95% of files should match git
SLO_DRIFT_DETECTION_SLA=360   # Detect drift within 6 hours
SLO_DEPLOY_SUCCESS_RATE=99    # 99% successful deployments

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================================================================
# FUNCTIONS
# ========================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Initialize metrics directory
init_metrics_dir() {
    mkdir -p "$METRICS_DIR"
}

# Count files tracked by GitOps
count_tracked_files() {
    local count=0

    # docker-compose.yml
    [[ -f "$DEPLOY_PATH/docker-compose.yml" ]] && ((count++))

    # config files
    for f in "$DEPLOY_PATH/config"/*; do
        [[ -f "$f" ]] && ((count++))
    done

    # scripts
    for f in "$DEPLOY_PATH/scripts"/*.sh; do
        [[ -f "$f" ]] && ((count++))
    done

    echo $count
}

# Calculate compliance percentage
calculate_compliance() {
    local total=0
    local compliant=0

    # Check docker-compose.yml
    if [[ -f "docker-compose.yml" ]] && [[ -f "$DEPLOY_PATH/docker-compose.yml" ]]; then
        ((total++))
        local local_hash server_hash
        local_hash=$(sha256sum docker-compose.yml | cut -d' ' -f1)
        server_hash=$(sha256sum "$DEPLOY_PATH/docker-compose.yml" 2>/dev/null | cut -d' ' -f1 || echo "")
        [[ "$local_hash" == "$server_hash" ]] && ((compliant++))
    fi

    # Check config files
    if [[ -d "config" ]] && [[ -d "$DEPLOY_PATH/config" ]]; then
        for f in config/*; do
            [[ -f "$f" ]] || continue
            ((total++))
            local basename local_hash server_hash
            basename=$(basename "$f")
            local_hash=$(sha256sum "$f" | cut -d' ' -f1)
            server_hash=$(sha256sum "$DEPLOY_PATH/config/$basename" 2>/dev/null | cut -d' ' -f1 || echo "")
            [[ "$local_hash" == "$server_hash" ]] && ((compliant++))
        done
    fi

    # Calculate percentage
    if [[ $total -eq 0 ]]; then
        echo 100
    else
        echo $(( (compliant * 100) / total ))
    fi
}

# Get last drift detection time
get_last_drift_check() {
    if [[ -f "$METRICS_DIR/last-drift-check" ]]; then
        cat "$METRICS_DIR/last-drift-check"
    else
        echo "never"
    fi
}

# Update last drift check timestamp
update_drift_check_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ > "$METRICS_DIR/last-drift-check"
}

# Get deployment success rate from logs
get_deployment_success_rate() {
    local log_file="/var/log/gitops-actions.log"

    if [[ ! -f "$log_file" ]]; then
        echo 100  # No data = assume OK
        return
    fi

    local total success
    total=$(grep -c "deploy" "$log_file" 2>/dev/null || echo 0)
    success=$(grep -c "deploy.*success" "$log_file" 2>/dev/null || echo 0)

    if [[ $total -eq 0 ]]; then
        echo 100
    else
        echo $(( (success * 100) / total ))
    fi
}

# Calculate SLO status
calculate_slo_status() {
    local metric="$1"
    local value="$2"
    local target="$3"

    if [[ $value -ge $target ]]; then
        echo "✅ MET"
    else
        echo "❌ BREACH"
    fi
}

# Generate JSON output
generate_json() {
    local compliance drift_check deploy_rate tracked_files
    compliance=$(calculate_compliance)
    drift_check=$(get_last_drift_check)
    deploy_rate=$(get_deployment_success_rate)
    tracked_files=$(count_tracked_files)

    cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "metrics": {
    "compliance_percentage": $compliance,
    "tracked_files": $tracked_files,
    "last_drift_check": "$drift_check",
    "deployment_success_rate": $deploy_rate
  },
  "slos": {
    "compliance_target": $SLO_COMPLIANCE_TARGET,
    "compliance_status": "$(calculate_slo_status compliance $compliance $SLO_COMPLIANCE_TARGET)",
    "drift_detection_sla_minutes": $SLO_DRIFT_DETECTION_SLA,
    "deploy_success_target": $SLO_DEPLOY_SUCCESS_RATE,
    "deploy_success_status": "$(calculate_slo_status deploy_rate $deploy_rate $SLO_DEPLOY_SUCCESS_RATE)"
  },
  "summary": {
    "overall_status": "$([[ $compliance -ge $SLO_COMPLIANCE_TARGET ]] && echo "healthy" || echo "degraded")"
  }
}
EOF
}

# Generate Markdown report
generate_markdown() {
    local compliance drift_check deploy_rate tracked_files
    compliance=$(calculate_compliance)
    drift_check=$(get_last_drift_check)
    deploy_rate=$(get_deployment_success_rate)
    tracked_files=$(count_tracked_files)

    cat <<EOF
# GitOps Metrics Report

**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Service Level Objectives (SLOs)

| SLO | Target | Current | Status |
|-----|--------|---------|--------|
| Compliance Rate | ${SLO_COMPLIANCE_TARGET}% | ${compliance}% | $(calculate_slo_status compliance $compliance $SLO_COMPLIANCE_TARGET) |
| Deployment Success | ${SLO_DEPLOY_SUCCESS_RATE}% | ${deploy_rate}% | $(calculate_slo_status deploy_rate $deploy_rate $SLO_DEPLOY_SUCCESS_RATE) |
| Drift Detection SLA | ${SLO_DRIFT_DETECTION_SLA}min | Last: $drift_check | $( [[ "$drift_check" != "never" ]] && echo "✅ ACTIVE" || echo "⚠️ NEVER RUN" ) |

## Metrics Summary

| Metric | Value |
|--------|-------|
| Tracked Files | $tracked_files |
| Compliance | ${compliance}% |
| Deploy Success Rate | ${deploy_rate}% |
| Last Drift Check | $drift_check |

## Status

**Overall:** $([[ $compliance -ge $SLO_COMPLIANCE_TARGET ]] && echo "🟢 Healthy" || echo "🟡 Degraded")

---
*Report generated by gitops-metrics.sh*
EOF
}

# Save metrics to file
save_metrics() {
    generate_json > "$METRICS_FILE"
    log_success "Metrics saved to $METRICS_FILE"
}

# ========================================================================
# MAIN
# ========================================================================

main() {
    local output="${1:-json}"

    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║       GitOps Metrics Collector v1.0       ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""

    init_metrics_dir
    update_drift_check_timestamp

    case "$output" in
        json)
            generate_json
            save_metrics
            ;;
        markdown|md)
            generate_markdown
            ;;
        both)
            generate_json
            save_metrics
            echo ""
            echo "---"
            echo ""
            generate_markdown
            ;;
        *)
            log_error "Unknown output format: $output"
            echo "Usage: $0 [--output json|markdown|both]"
            exit 1
            ;;
    esac
}

# Run from project root if checking local files
if [[ -f "docker-compose.yml" ]]; then
    :
elif [[ -f "../docker-compose.yml" ]]; then
    cd ..
fi

main "$@"
