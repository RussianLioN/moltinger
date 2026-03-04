#!/bin/bash
# RCA Context Collector
# Automatically collects environment context for Root Cause Analysis
# Usage: context-collector.sh [error_type]

set -e

ERROR_TYPE="${1:-generic}"

echo "🔍 AUTO-CONTEXT COLLECTION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Base context (always collected)
echo "Timestamp: $(date -Iseconds)"
echo "PWD: $(pwd)"
echo "Shell: ${SHELL:-unknown}"
echo "User: ${USER:-unknown}"
echo "Hostname: $(hostname 2>/dev/null || echo 'N/A')"

# Git context (if available)
if git rev-parse --git-dir &>/dev/null; then
    echo ""
    echo "## Git Context"
    echo "Branch: $(git branch --show-current 2>/dev/null || echo 'N/A')"
    echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
    echo "Status: $(git status --short 2>/dev/null | head -5 | tr '\n' ' ' || echo 'clean')"
    echo "Remote: $(git remote get-url origin 2>/dev/null || echo 'N/A')"
else
    echo "Git: Not a git repository"
fi

# Docker context (if docker error or docker available)
if [[ "$ERROR_TYPE" == "docker" ]] || command -v docker &>/dev/null; then
    echo ""
    echo "## Docker Context"
    if docker info &>/dev/null; then
        echo "Docker Version: $(docker --version 2>/dev/null || echo 'N/A')"
        echo "Containers Running: $(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
        echo "Containers Total: $(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
        echo "Networks: $(docker network ls -q 2>/dev/null | wc -l | tr -d ' ')"
        echo "Images: $(docker images -q 2>/dev/null | wc -l | tr -d ' ')"
    else
        echo "Docker: Not available or not running"
    fi
fi

# CI/CD context (if cicd error or in CI environment)
if [[ "$ERROR_TYPE" == "cicd" ]] || [[ -n "${CI:-}" ]]; then
    echo ""
    echo "## CI/CD Context"
    echo "CI: ${CI:-false}"
    echo "GITHUB_WORKFLOW: ${GITHUB_WORKFLOW:-N/A}"
    echo "GITHUB_JOB: ${GITHUB_JOB:-N/A}"
    echo "GITHUB_RUN_ID: ${GITHUB_RUN_ID:-N/A}"
    echo "GITHUB_RUN_NUMBER: ${GITHUB_RUN_NUMBER:-N/A}"
    echo "GITHUB_REF: ${GITHUB_REF:-N/A}"
    echo "GITHUB_SHA: ${GITHUB_SHA:-N/A}"
    echo "RUNNER_OS: ${RUNNER_OS:-N/A}"
fi

# System context
echo ""
echo "## System Context"

# Disk usage
if command -v df &>/dev/null; then
    DISK_USAGE=$(df -h . 2>/dev/null | tail -1 | awk '{print $5}' || echo 'N/A')
    DISK_AVAIL=$(df -h . 2>/dev/null | tail -1 | awk '{print $4}' || echo 'N/A')
    echo "Disk Usage: ${DISK_USAGE} (${DISK_AVAIL} available)"
else
    echo "Disk Usage: N/A"
fi

# Memory usage
if command -v free &>/dev/null; then
    MEM_INFO=$(free -h 2>/dev/null | grep Mem || echo '')
    if [[ -n "$MEM_INFO" ]]; then
        MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
        MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
        echo "Memory: ${MEM_USED}/${MEM_TOTAL}"
    else
        echo "Memory: N/A"
    fi
elif [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    MEM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    MEM_USED=$(vm_stat 2>/dev/null | grep "Pages active" | awk '{print $3}' | tr -d '.' || echo 0)
    if [[ "$MEM_TOTAL" -gt 0 ]]; then
        MEM_TOTAL_GB=$((MEM_TOTAL / 1024 / 1024 / 1024))
        MEM_USED_GB=$((MEM_USED * 4096 / 1024 / 1024 / 1024))
        echo "Memory: ${MEM_USED_GB}G/${MEM_TOTAL_GB}G"
    else
        echo "Memory: N/A"
    fi
else
    echo "Memory: N/A"
fi

# CPU info
if command -v nproc &>/dev/null; then
    echo "CPU Cores: $(nproc 2>/dev/null || echo 'N/A')"
elif [[ "$(uname)" == "Darwin" ]]; then
    echo "CPU Cores: $(sysctl -n hw.ncpu 2>/dev/null || echo 'N/A')"
fi

# OS info
echo "OS: $(uname -s 2>/dev/null || echo 'N/A') $(uname -r 2>/dev/null || echo '')"

# Error type detection summary
echo ""
echo "## Error Analysis"
echo "Error Type: ${ERROR_TYPE}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
