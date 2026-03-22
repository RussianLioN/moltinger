#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-moltis-project-knowledge.sh"

run_component_sync_moltis_project_knowledge_tests() {
    start_timer

    local tmp_dir knowledge_root runtime_home output_file
    tmp_dir="$(mktemp -d /tmp/moltis-project-knowledge-sync.XXXXXX)"
    knowledge_root="$tmp_dir/knowledge"
    runtime_home="$tmp_dir/runtime-home"
    output_file="$runtime_home/memory/project-knowledge.md"

    mkdir -p "$knowledge_root/references" "$knowledge_root/troubleshooting" "$runtime_home"

    cat > "$knowledge_root/README.md" <<'EOF'
# Knowledge Root

Shared repository knowledge.
EOF

    cat > "$knowledge_root/AGENTS.md" <<'EOF'
# Ignore
This file should not be mirrored into runtime memory.
EOF

    cat > "$knowledge_root/references/runtime.md" <<'EOF'
---
title: "Runtime"
category: "reference"
tags: ["runtime"]
source: "original"
date: "2026-03-22"
confidence: "high"
---

# Runtime

Moltis must run from /server.
EOF

    cat > "$knowledge_root/troubleshooting/memory.md" <<'EOF'
---
title: "Memory"
category: "troubleshooting"
tags: ["memory"]
source: "original"
date: "2026-03-22"
confidence: "high"
---

# Memory

Use ~/.moltis/memory for durable searchable notes.
EOF

    test_start "component_sync_script_renders_tracked_knowledge_bundle"
    if ! bash "$SYNC_SCRIPT" \
        --knowledge-root "$knowledge_root" \
        --runtime-home "$runtime_home" >"$tmp_dir/output.log" 2>&1; then
        test_fail "Knowledge sync script failed on fixture inputs"
        rm -rf "$tmp_dir"
        return
    fi

    if [[ ! -f "$output_file" ]] || \
       ! grep -Fq 'Project Knowledge Bundle' "$output_file" || \
       ! grep -Fq '## Source: knowledge/README.md' "$output_file" || \
       ! grep -Fq '## Source: knowledge/references/runtime.md' "$output_file" || \
       ! grep -Fq '## Source: knowledge/troubleshooting/memory.md' "$output_file" || \
       grep -Fq 'This file should not be mirrored' "$output_file"; then
        test_fail "Knowledge bundle did not include the expected tracked markdown sources"
        rm -rf "$tmp_dir"
        return
    fi
    test_pass

    test_start "component_sync_script_overwrites_existing_bundle_atomically"
    cat > "$knowledge_root/references/runtime.md" <<'EOF'
---
title: "Runtime"
category: "reference"
tags: ["runtime"]
source: "original"
date: "2026-03-22"
confidence: "high"
---

# Runtime

Moltis must recreate the runtime process after config changes.
EOF

    if ! bash "$SYNC_SCRIPT" \
        --knowledge-root "$knowledge_root" \
        --runtime-home "$runtime_home" >"$tmp_dir/output-2.log" 2>&1; then
        test_fail "Knowledge sync script failed on overwrite run"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq 'recreate the runtime process after config changes' "$output_file"; then
        test_fail "Knowledge bundle was not refreshed on the second sync"
        rm -rf "$tmp_dir"
        return
    fi
    test_pass

    rm -rf "$tmp_dir"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_sync_moltis_project_knowledge_tests
fi
