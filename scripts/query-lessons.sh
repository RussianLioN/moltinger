#!/bin/bash
# Query Lessons from RCA Reports
# Usage: query-lessons.sh [--severity LEVEL] [--tag TAG] [--category CAT]
#
# Examples:
#   ./scripts/query-lessons.sh --severity critical
#   ./scripts/query-lessons.sh --tag docker
#   ./scripts/query-lessons.sh --category deployment
#   ./scripts/query-lessons.sh --all

set -euo pipefail

RCA_DIR="docs/rca"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
SEVERITY=""
TAG=""
CATEGORY=""
SHOW_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --all|-a)
            SHOW_ALL=true
            shift
            ;;
        --help|-h)
            echo "Query Lessons from RCA Reports"
            echo ""
            echo "Usage: query-lessons.sh [options]"
            echo ""
            echo "Options:"
            echo "  --severity LEVEL   Filter by severity (P0, P1, P2, P3, P4)"
            echo "  --tag TAG          Filter by tag (docker, gitops, security, etc.)"
            echo "  --category CAT     Filter by category (deployment, process, etc.)"
            echo "  --all, -a          Show all lessons"
            echo "  --help, -h         Show this help"
            echo ""
            echo "Examples:"
            echo "  ./scripts/query-lessons.sh --severity P1"
            echo "  ./scripts/query-lessons.sh --tag docker"
            echo "  ./scripts/query-lessons.sh --category deployment"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Find all RCA files
find_rca_files() {
    find "$RCA_DIR" -name "*.md" ! -name "INDEX.md" ! -name "TEMPLATE.md" -type f 2>/dev/null | sort -r
}

# Extract frontmatter field
extract_field() {
    local file="$1"
    local field="$2"
    grep "^$field:" "$file" 2>/dev/null | head -1 | sed "s/^$field: *//" | tr -d '"\r' || echo ""
}

# Extract lessons section
extract_lessons() {
    local file="$1"
    sed -n '/^## Уроки/,/^## /p' "$file" 2>/dev/null | head -20 || echo ""
}

# Check if file matches filters
matches_filters() {
    local file="$1"

    if [[ -n "$SEVERITY" ]]; then
        local sev=$(extract_field "$file" "severity" | tr '[:lower:]' '[:upper:]')
        if [[ "$sev" != "$SEVERITY" ]]; then
            return 1
        fi
    fi

    if [[ -n "$TAG" ]]; then
        local tags=$(extract_field "$file" "tags")
        if [[ ! "$tags" =~ $TAG ]]; then
            return 1
        fi
    fi

    if [[ -n "$CATEGORY" ]]; then
        local cat=$(extract_field "$file" "category")
        if [[ ! "$cat" =~ $CATEGORY ]]; then
            return 1
        fi
    fi

    return 0
}

# Display lesson
display_lesson() {
    local file="$1"
    local basename=$(basename "$file" .md)

    local title=$(extract_field "$file" "title")
    local date=$(extract_field "$file" "date")
    local severity=$(extract_field "$file" "severity")
    local category=$(extract_field "$file" "category")
    local tags=$(extract_field "$file" "tags")

    # Color for severity
    local sev_color="$NC"
    case "$severity" in
        P0|critical) sev_color="$RED" ;;
        P1|high) sev_color="$YELLOW" ;;
        P2|medium) sev_color="$BLUE" ;;
        P3|P4|low) sev_color="$GREEN" ;;
    esac

    echo -e "${sev_color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📁 File:${NC} $file"
    echo -e "${BLUE}📅 Date:${NC} ${date:-N/A}"
    echo -e "${BLUE}⚠️  Severity:${NC} ${sev_color}${severity:-N/A}${NC}"
    echo -e "${BLUE}📂 Category:${NC} ${category:-N/A}"
    echo -e "${BLUE}🏷️  Tags:${NC} ${tags:-N/A}"
    echo ""
    extract_lessons "$file" | grep -v "^## " | head -15
    echo ""
}

# Main logic
echo -e "${BLUE}🔍 Lessons Query Results${NC}"
echo ""

if [[ "$SHOW_ALL" == true ]]; then
    echo "Showing all lessons..."
    echo ""
fi

count=0
while IFS= read -r file; do
    if [[ "$SHOW_ALL" == true ]] || matches_filters "$file"; then
        # Check if file has lessons section
        if grep -q "^## Уроки" "$file" 2>/dev/null; then
            display_lesson "$file"
            count=$((count + 1))
        fi
    fi
done < <(find_rca_files)

if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}No lessons found matching criteria${NC}"
    echo ""
    echo "Try: ./scripts/query-lessons.sh --all"
else
    echo -e "${GREEN}✓ Found $count lesson(s)${NC}"
fi
