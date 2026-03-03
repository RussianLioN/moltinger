#!/bin/bash
# RCA Index Manager
# Manages docs/rca/INDEX.md - registry of all RCA reports
# Usage: rca-index.sh <command> [options]
#
# Commands:
#   update     - Update INDEX.md with all RCA reports
#   validate   - Validate INDEX.md consistency
#   next-id    - Get next available RCA ID (RCA-NNN)
#   stats      - Calculate and display statistics

set -e

# Configuration
RCA_DIR="docs/rca"
INDEX_FILE="${RCA_DIR}/INDEX.md"
DATE_FORMAT=$(date +%Y-%m-%d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print usage
usage() {
    echo "RCA Index Manager"
    echo ""
    echo "Usage: rca-index.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  update     Update INDEX.md with all RCA reports"
    echo "  validate   Validate INDEX.md consistency"
    echo "  next-id    Get next available RCA ID"
    echo "  stats      Calculate and display statistics"
    echo ""
    echo "Options:"
    echo "  --json     Output in JSON format"
    echo "  --quiet    Suppress non-essential output"
}

# Find all RCA reports
find_rca_reports() {
    # Find all .md files in RCA directory except INDEX.md and TEMPLATE.md
    find "${RCA_DIR}" -name "*.md" ! -name "INDEX.md" ! -name "TEMPLATE.md" -type f 2>/dev/null | sort -r
}

# Extract metadata from RCA report
extract_metadata() {
    local file="$1"
    local basename=$(basename "$file" .md)

    # Extract date from filename (YYYY-MM-DD-...)
    local date=$(echo "$basename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "N/A")

    # Extract category from file content
    local category="generic"
    if grep -qi "docker\|container\|image\|volume\|network" "$file" 2>/dev/null; then
        category="docker"
    elif grep -qi "workflow\|pipeline\|github actions\|ci\|cd" "$file" 2>/dev/null; then
        category="cicd"
    elif grep -qi "data loss\|deleted\|corrupted\|backup" "$file" 2>/dev/null; then
        category="data-loss"
    elif grep -qi "shell\|bash\|zsh\|script" "$file" 2>/dev/null; then
        category="shell"
    fi

    # Extract severity (P0-P4)
    local severity="P3"  # default
    if grep -qi "P0\|critical\|blocker" "$file" 2>/dev/null; then
        severity="P0"
    elif grep -qi "P1\|high\|urgent" "$file" 2>/dev/null; then
        severity="P1"
    elif grep -qi "P2\|medium" "$file" 2>/dev/null; then
        severity="P2"
    elif grep -qi "P4\|low\|backlog" "$file" 2>/dev/null; then
        severity="P4"
    fi

    # Extract status
    local status="resolved"
    if grep -qi "in.progress\|investigating" "$file" 2>/dev/null; then
        status="in_progress"
    elif grep -qi "draft\|wip" "$file" 2>/dev/null; then
        status="draft"
    fi

    # Extract root cause summary (first line after "## Корневая причина" or "## Root Cause")
    local root_cause=$(grep -A1 -i "корневая причина\|root cause" "$file" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' | cut -c1-50 || echo "N/A")
    if [[ -z "$root_cause" || "$root_cause" == "" ]]; then
        root_cause="N/A"
    fi

    # Check for fix commit
    local fix="N/A"
    if grep -qi "fix:\|commit:\|[a-f0-9]\{7,\}" "$file" 2>/dev/null; then
        fix=$(grep -oE '[a-f0-9]{7,}' "$file" 2>/dev/null | head -1 || echo "N/A")
    fi

    echo "${date}|${category}|${severity}|${status}|${root_cause}|${fix}|${basename}"
}

# Get next available RCA ID
get_next_id() {
    local json_mode="${1:-false}"

    # Find highest RCA ID in existing reports
    local max_id=0

    # Check existing RCA files
    for file in $(find_rca_reports); do
        local id=$(basename "$file" .md | grep -oE 'RCA-[0-9]{3}' | grep -oE '[0-9]+' || echo "0")
        if [[ "$id" -gt "$max_id" ]]; then
            max_id=$id
        fi
    done

    # Check INDEX.md for existing entries
    if [[ -f "$INDEX_FILE" ]]; then
        for id in $(grep -oE 'RCA-[0-9]{3}' "$INDEX_FILE" 2>/dev/null | grep -oE '[0-9]+' || echo "0"); do
            if [[ "$id" -gt "$max_id" ]]; then
                max_id=$id
            fi
        done
    fi

    local next_id=$((max_id + 1))
    local formatted_id=$(printf "RCA-%03d" $next_id)

    if [[ "$json_mode" == "true" ]]; then
        echo "{\"next_id\": \"${formatted_id}\", \"number\": ${next_id}}"
    else
        echo "${formatted_id}"
    fi
}

# Calculate statistics
calculate_stats() {
    local json_mode="${1:-false}"
    local total=0
    local docker_count=0
    local cicd_count=0
    local shell_count=0
    local data_loss_count=0
    local generic_count=0
    local p0_count=0
    local p1_count=0
    local p2_count=0
    local p3_count=0
    local p4_count=0

    for file in $(find_rca_reports); do
        local meta=$(extract_metadata "$file")
        local category=$(echo "$meta" | cut -d'|' -f2)
        local severity=$(echo "$meta" | cut -d'|' -f3)

        total=$((total + 1))

        case "$category" in
            docker) docker_count=$((docker_count + 1)) ;;
            cicd) cicd_count=$((cicd_count + 1)) ;;
            shell) shell_count=$((shell_count + 1)) ;;
            data-loss) data_loss_count=$((data_loss_count + 1)) ;;
            *) generic_count=$((generic_count + 1)) ;;
        esac

        case "$severity" in
            P0) p0_count=$((p0_count + 1)) ;;
            P1) p1_count=$((p1_count + 1)) ;;
            P2) p2_count=$((p2_count + 1)) ;;
            P3) p3_count=$((p3_count + 1)) ;;
            P4) p4_count=$((p4_count + 1)) ;;
        esac
    done

    # Calculate percentages
    local docker_pct=0 cicd_pct=0 shell_pct=0 data_loss_pct=0 generic_pct=0
    if [[ $total -gt 0 ]]; then
        docker_pct=$((docker_count * 100 / total))
        cicd_pct=$((cicd_count * 100 / total))
        shell_pct=$((shell_count * 100 / total))
        data_loss_pct=$((data_loss_count * 100 / total))
        generic_pct=$((generic_count * 100 / total))
    fi

    if [[ "$json_mode" == "true" ]]; then
        cat <<EOF
{
  "total": ${total},
  "by_category": {
    "docker": {"count": ${docker_count}, "percentage": ${docker_pct}},
    "cicd": {"count": ${cicd_count}, "percentage": ${cicd_pct}},
    "shell": {"count": ${shell_count}, "percentage": ${shell_pct}},
    "data-loss": {"count": ${data_loss_count}, "percentage": ${data_loss_pct}},
    "generic": {"count": ${generic_count}, "percentage": ${generic_pct}}
  },
  "by_severity": {
    "P0": ${p0_count},
    "P1": ${p1_count},
    "P2": ${p2_count},
    "P3": ${p3_count},
    "P4": ${p4_count}
  }
}
EOF
    else
        echo "Statistics:"
        echo "  Total RCA: ${total}"
        echo ""
        echo "  By Category:"
        echo "    docker:    ${docker_count} (${docker_pct}%)"
        echo "    cicd:      ${cicd_count} (${cicd_pct}%)"
        echo "    shell:     ${shell_count} (${shell_pct}%)"
        echo "    data-loss: ${data_loss_count} (${data_loss_pct}%)"
        echo "    generic:   ${generic_count} (${generic_pct}%)"
        echo ""
        echo "  By Severity:"
        echo "    P0: ${p0_count}"
        echo "    P1: ${p1_count}"
        echo "    P2: ${p2_count}"
        echo "    P3: ${p3_count}"
        echo "    P4: ${p4_count}"
    fi
}

# Detect patterns (3+ RCA in same category)
detect_patterns() {
    local json_mode="${1:-false}"
    local patterns=""

    for file in $(find_rca_reports); do
        local meta=$(extract_metadata "$file")
        local category=$(echo "$meta" | cut -d'|' -f2)
        echo "$category"
    done | sort | uniq -c | while read count category; do
        if [[ $count -ge 3 ]]; then
            if [[ "$json_mode" == "true" ]]; then
                echo "{\"category\": \"${category}\", \"count\": ${count}, \"warning\": true}"
            else
                echo "⚠️  Warning: ${count}+ RCA in category \"${category}\" - consider systemic fix"
            fi
        fi
    done
}

# Update INDEX.md
update_index() {
    local json_mode="${1:-false}"

    # Ensure INDEX.md exists
    if [[ ! -f "$INDEX_FILE" ]]; then
        mkdir -p "${RCA_DIR}"
        cat > "$INDEX_FILE" << 'HEADER'
# RCA Index

**Last Updated**: DATE_PLACEHOLDER
**Version**: 1.0.0

## Statistics

| Metric | Value |
|--------|-------|
| Total RCA | TOTAL_PLACEHOLDER |
| Avg Resolution Time | N/A |
| This Month | THIS_MONTH_PLACEHOLDER |

## By Category

| Category | Count | Percentage |
|----------|-------|------------|
| docker | DOCKER_PLACEHOLDER | DOCKER_PCT_PLACEHOLDER% |
| cicd | CICD_PLACEHOLDER | CICD_PCT_PLACEHOLDER% |
| shell | SHELL_PLACEHOLDER | SHELL_PCT_PLACEHOLDER% |
| data-loss | DATA_LOSS_PLACEHOLDER | DATA_LOSS_PCT_PLACEHOLDER% |
| generic | GENERIC_PLACEHOLDER | GENERIC_PCT_PLACEHOLDER% |

## By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| P0 | P0_PLACEHOLDER | Critical - blocks release |
| P1 | P1_PLACEHOLDER | High - production impact |
| P2 | P2_PLACEHOLDER | Medium - degraded service |
| P3 | P3_PLACEHOLDER | Low - minor issue |
| P4 | P4_PLACEHOLDER | Backlog |

## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
REGISTRY_PLACEHOLDER

## Patterns Detected

PATTERNS_PLACEHOLDER

---

*This index is automatically updated by the RCA skill.*
HEADER
    fi

    # Collect all RCA reports
    local total=0
    local docker_count=0 cicd_count=0 shell_count=0 data_loss_count=0 generic_count=0
    local p0_count=0 p1_count=0 p2_count=0 p3_count=0 p4_count=0
    local this_month=0
    local current_month=$(date +%Y-%m)
    local registry_entries=""
    local patterns=""

    for file in $(find_rca_reports); do
        local meta=$(extract_metadata "$file")
        local date=$(echo "$meta" | cut -d'|' -f1)
        local category=$(echo "$meta" | cut -d'|' -f2)
        local severity=$(echo "$meta" | cut -d'|' -f3)
        local status=$(echo "$meta" | cut -d'|' -f4)
        local root_cause=$(echo "$meta" | cut -d'|' -f5)
        local fix=$(echo "$meta" | cut -d'|' -f6)
        local basename=$(echo "$meta" | cut -d'|' -f7)

        # Get next ID
        local id=$(get_next_id)
        # For existing entries, use file basename as identifier
        id="RCA-$(printf '%03d' $((total + 1)))"

        total=$((total + 1))

        # Count by category
        case "$category" in
            docker) docker_count=$((docker_count + 1)) ;;
            cicd) cicd_count=$((cicd_count + 1)) ;;
            shell) shell_count=$((shell_count + 1)) ;;
            data-loss) data_loss_count=$((data_loss_count + 1)) ;;
            *) generic_count=$((generic_count + 1)) ;;
        esac

        # Count by severity
        case "$severity" in
            P0) p0_count=$((p0_count + 1)) ;;
            P1) p1_count=$((p1_count + 1)) ;;
            P2) p2_count=$((p2_count + 1)) ;;
            P3) p3_count=$((p3_count + 1)) ;;
            P4) p4_count=$((p4_count + 1)) ;;
        esac

        # Count this month
        if [[ "$date" == ${current_month}* ]]; then
            this_month=$((this_month + 1))
        fi

        # Build registry entry
        registry_entries="${registry_entries}| ${id} | ${date} | ${category} | ${severity} | ${status} | ${root_cause} | ${fix} |
"
    done

    # Calculate percentages
    local docker_pct=0 cicd_pct=0 shell_pct=0 data_loss_pct=0 generic_pct=0
    if [[ $total -gt 0 ]]; then
        docker_pct=$((docker_count * 100 / total))
        cicd_pct=$((cicd_count * 100 / total))
        shell_pct=$((shell_count * 100 / total))
        data_loss_pct=$((data_loss_count * 100 / total))
        generic_pct=$((generic_count * 100 / total))
    fi

    # Detect patterns
    if [[ $docker_count -ge 3 ]]; then
        patterns="⚠️ **Warning**: ${docker_count}+ RCA in category \"docker\" (${docker_pct}%) - consider systemic review

**Trend**: Docker configuration issues are recurring"
    elif [[ $cicd_count -ge 3 ]]; then
        patterns="⚠️ **Warning**: ${cicd_count}+ RCA in category \"cicd\" (${cicd_pct}%) - consider systemic review

**Trend**: CI/CD pipeline issues are recurring"
    elif [[ $shell_count -ge 3 ]]; then
        patterns="⚠️ **Warning**: ${shell_count}+ RCA in category \"shell\" (${shell_pct}%) - consider systemic review

**Trend**: Shell script issues are recurring"
    elif [[ $data_loss_count -ge 3 ]]; then
        patterns="⚠️ **Warning**: ${data_loss_count}+ RCA in category \"data-loss\" (${data_loss_pct}%) - consider systemic review

**Trend**: Data protection issues are recurring"
    elif [[ $total -lt 3 ]]; then
        patterns="*No patterns detected yet - need at least 3 RCA entries*"
    else
        patterns="*No recurring patterns detected*"
    fi

    # If no entries, show placeholder
    if [[ $total -eq 0 ]]; then
        registry_entries="| *No entries yet* | | | | | | |
"
    fi

    # Update INDEX.md
    sed -i.bak \
        -e "s/DATE_PLACEHOLDER/${DATE_FORMAT}/g" \
        -e "s/TOTAL_PLACEHOLDER/${total}/g" \
        -e "s/THIS_MONTH_PLACEHOLDER/${this_month}/g" \
        -e "s/DOCKER_PLACEHOLDER/${docker_count}/g" \
        -e "s/DOCKER_PCT_PLACEHOLDER/${docker_pct}/g" \
        -e "s/CICD_PLACEHOLDER/${cicd_count}/g" \
        -e "s/CICD_PCT_PLACEHOLDER/${cicd_pct}/g" \
        -e "s/SHELL_PLACEHOLDER/${shell_count}/g" \
        -e "s/SHELL_PCT_PLACEHOLDER/${shell_pct}/g" \
        -e "s/DATA_LOSS_PLACEHOLDER/${data_loss_count}/g" \
        -e "s/DATA_LOSS_PCT_PLACEHOLDER/${data_loss_pct}/g" \
        -e "s/GENERIC_PLACEHOLDER/${generic_count}/g" \
        -e "s/GENERIC_PCT_PLACEHOLDER/${generic_pct}/g" \
        -e "s/P0_PLACEHOLDER/${p0_count}/g" \
        -e "s/P1_PLACEHOLDER/${p1_count}/g" \
        -e "s/P2_PLACEHOLDER/${p2_count}/g" \
        -e "s/P3_PLACEHOLDER/${p3_count}/g" \
        -e "s/P4_PLACEHOLDER/${p4_count}/g" \
        "$INDEX_FILE" 2>/dev/null || true

    # Replace registry section
    if [[ -f "$INDEX_FILE" ]]; then
        # Create temp file with updated content
        awk -v registry="${registry_entries}" -v patterns="${patterns}" '
        /^REGISTRY_PLACEHOLDER/ {
            print registry
            next
        }
        /^PATTERNS_PLACEHOLDER/ {
            print patterns
            next
        }
        { print }
        ' "$INDEX_FILE" > "${INDEX_FILE}.tmp"
        mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
        rm -f "${INDEX_FILE}.bak"
    fi

    if [[ "$json_mode" == "true" ]]; then
        echo "{\"status\": \"success\", \"total\": ${total}, \"file\": \"${INDEX_FILE}\"}"
    else
        echo -e "${GREEN}✓${NC} Updated ${INDEX_FILE}"
        echo "  Total RCA: ${total}"
        echo "  This month: ${this_month}"
    fi
}

# Validate INDEX.md
validate_index() {
    local json_mode="${1:-false}"
    local errors=0
    local warnings=0
    local error_list=""

    if [[ ! -f "$INDEX_FILE" ]]; then
        if [[ "$json_mode" == "true" ]]; then
            echo "{\"status\": \"error\", \"errors\": 1, \"messages\": [\"INDEX.md not found\"]}"
        else
            echo -e "${RED}✗${NC} INDEX.md not found at ${INDEX_FILE}"
        fi
        return 1
    fi

    # Check total count matches registry
    local stated_total=$(grep "Total RCA" "$INDEX_FILE" | grep -oE '[0-9]+' | head -1 || echo "0")
    local actual_count=$(find_rca_reports | wc -l | tr -d ' ')

    if [[ "$stated_total" != "$actual_count" ]]; then
        errors=$((errors + 1))
        error_list="${error_list}\"Total count mismatch: stated ${stated_total}, actual ${actual_count}\", "
    fi

    # Check for duplicate IDs
    local duplicates=$(grep -oE 'RCA-[0-9]{3}' "$INDEX_FILE" 2>/dev/null | sort | uniq -d | wc -l | tr -d ' ')
    if [[ "$duplicates" -gt 0 ]]; then
        errors=$((errors + 1))
        error_list="${error_list}\"Duplicate RCA IDs found\", "
    fi

    # Check percentages sum to 100
    local pct_sum=$(grep -A5 "By Category" "$INDEX_FILE" | grep -oE '[0-9]+%' | tr -d '%' | awk '{s+=$1}END{print s}')
    if [[ "$pct_sum" != "100" && "$actual_count" -gt 0 ]]; then
        warnings=$((warnings + 1))
        error_list="${error_list}\"Percentages do not sum to 100% (got ${pct_sum}%)\", "
    fi

    if [[ "$json_mode" == "true" ]]; then
        if [[ $errors -eq 0 ]]; then
            echo "{\"status\": \"pass\", \"errors\": 0, \"warnings\": ${warnings}}"
        else
            echo "{\"status\": \"fail\", \"errors\": ${errors}, \"warnings\": ${warnings}, \"messages\": [${error_list%,*}]}"
        fi
    else
        if [[ $errors -eq 0 ]]; then
            echo -e "${GREEN}✓${NC} Validation passed"
            if [[ $warnings -gt 0 ]]; then
                echo -e "  ${YELLOW}Warnings:${NC} ${warnings}"
            fi
        else
            echo -e "${RED}✗${NC} Validation failed"
            echo "  Errors: ${errors}"
            echo "  Warnings: ${warnings}"
        fi
    fi

    return $errors
}

# Main command dispatcher
case "${1:-}" in
    update)
        update_index "${2:-}"
        ;;
    validate)
        validate_index "${2:-}"
        ;;
    next-id)
        get_next_id "${2:-}"
        ;;
    stats)
        calculate_stats "${2:-}"
        ;;
    patterns)
        detect_patterns "${2:-}"
        ;;
    --help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
