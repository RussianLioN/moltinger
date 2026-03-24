#!/usr/bin/env bash
# Unit tests for lessons indexing/query tolerance across English and Russian section headers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

BUILD_SCRIPT="$PROJECT_ROOT/scripts/build-lessons-index.sh"
QUERY_SCRIPT="$PROJECT_ROOT/scripts/query-lessons.sh"

create_rca_fixture() {
    local fixture_root="$1"

    mkdir -p "$fixture_root/docs/rca"

    cat >"$fixture_root/docs/rca/2026-03-24-english-lessons.md" <<'EOF'
---
title: "English lessons heading incident"
date: 2026-03-24
severity: P1
category: process
tags: [ollama, memory, lessons]
---

# RCA: English lessons heading incident

## Summary

Test fixture.

## Lessons

1. English lessons heading should still be indexed.
2. Query tooling should still display the lessons body.
EOF

    cat >"$fixture_root/docs/rca/2026-03-24-russian-lessons.md" <<'EOF'
---
title: "Russian lessons heading incident"
date: 2026-03-24
severity: P2
category: process
tags: [telegram, lessons]
---

# RCA: Russian lessons heading incident

## Summary

Test fixture.

## Уроки

1. Russian lessons heading should remain supported.
EOF
}

run_build_lessons_index() {
    local fixture_root="$1"
    (
        cd "$fixture_root"
        bash "$BUILD_SCRIPT"
    )
}

run_query_lessons() {
    local fixture_root="$1"
    shift
    (
        cd "$fixture_root"
        bash "$QUERY_SCRIPT" "$@"
    )
}

test_build_lessons_index_accepts_english_lessons_heading() {
    test_start "build_lessons_index_accepts_english_lessons_heading"

    local fixture_root output
    fixture_root="$(mktemp -d /tmp/lessons-index-unit.XXXXXX)"
    create_rca_fixture "$fixture_root"

    output="$(run_build_lessons_index "$fixture_root")"

    assert_contains "$output" "Total lessons: 2" "Lessons index should count both English and Russian lesson headings"
    assert_contains "$(cat "$fixture_root/docs/LESSONS-LEARNED.md")" "English lessons heading incident" "Generated lessons index should include English-heading RCA entries"

    rm -rf "$fixture_root"
    test_pass
}

test_query_lessons_accepts_english_lessons_heading() {
    test_start "query_lessons_accepts_english_lessons_heading"

    local fixture_root query_output
    fixture_root="$(mktemp -d /tmp/lessons-index-unit.XXXXXX)"
    create_rca_fixture "$fixture_root"
    run_build_lessons_index "$fixture_root" >/dev/null

    query_output="$(run_query_lessons "$fixture_root" --tag ollama)"

    assert_contains "$query_output" "2026-03-24-english-lessons.md" "Lessons query should find RCAs tagged for the English lessons-heading fixture"
    assert_contains "$query_output" "English lessons heading should still be indexed." "Lessons query should render lesson text from English-heading RCAs"

    rm -rf "$fixture_root"
    test_pass
}

run_lessons_indexing_unit_tests() {
    start_timer

    test_build_lessons_index_accepts_english_lessons_heading
    test_query_lessons_accepts_english_lessons_heading

    generate_report
}

run_lessons_indexing_unit_tests "$@"
