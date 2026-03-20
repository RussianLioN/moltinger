#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

REPAIR_SCRIPT="$PROJECT_ROOT/scripts/codex-session-path-repair.sh"

write_session_header() {
    local file="$1"
    local session_id="$2"
    local cwd="$3"

    cat > "$file" <<EOF
{"timestamp":"2026-03-20T00:00:00.000Z","type":"session_meta","payload":{"id":"$session_id","timestamp":"2026-03-20T00:00:00.000Z","cwd":"$cwd","originator":"codex_cli_rs","cli_version":"0.116.0","source":"cli","model_provider":"openai"}}
{"timestamp":"2026-03-20T00:00:01.000Z","type":"event_msg","payload":{"type":"task_started"}}
EOF
}

setup_codex_session_path_fixture() {
    local fixture_root="$1"
    local codex_home="$fixture_root/.codex"
    local old_main="$fixture_root/moltinger"
    local new_main="$fixture_root/moltinger/moltinger-main"
    local moved_root="$fixture_root/moltinger"
    local old_worktree="$fixture_root/moltinger-jb6-gpt54-primary"
    local new_worktree="$fixture_root/moltinger/moltinger-jb6-gpt54-primary"
    local archive_file session_file

    mkdir -p \
        "$codex_home/archived_sessions" \
        "$codex_home/sessions/2026/03/20" \
        "$new_main/.git" \
        "$new_worktree/.git"

    sqlite3 "$codex_home/state_5.sqlite" <<'SQL'
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    rollout_path TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    source TEXT NOT NULL,
    model_provider TEXT NOT NULL,
    cwd TEXT NOT NULL,
    title TEXT NOT NULL,
    sandbox_policy TEXT NOT NULL,
    approval_mode TEXT NOT NULL,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    has_user_event INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    archived_at INTEGER,
    git_sha TEXT,
    git_branch TEXT,
    git_origin_url TEXT,
    cli_version TEXT NOT NULL DEFAULT '',
    first_user_message TEXT NOT NULL DEFAULT '',
    agent_nickname TEXT,
    agent_role TEXT,
    memory_mode TEXT NOT NULL DEFAULT 'enabled',
    model TEXT,
    reasoning_effort TEXT
);
SQL

    archive_file="$codex_home/archived_sessions/archive-old-root.jsonl"
    session_file="$codex_home/sessions/2026/03/20/rollout-old-root-jb6.jsonl"

    write_session_header "$archive_file" "archive-old-root" "$old_main"
    write_session_header "$session_file" "live-old-worktree" "$old_worktree"

    sqlite3 "$codex_home/state_5.sqlite" <<SQL
INSERT INTO threads (
    id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
    sandbox_policy, approval_mode, archived, cli_version
) VALUES
(
    'archive-old-root',
    '$archive_file',
    1, 1, 'cli', 'openai', '$old_main', 'old main session',
    'workspace-write', 'on-request', 1, '0.116.0'
),
(
    'live-old-worktree',
    '$session_file',
    1, 1, 'cli', 'openai', '$old_worktree', 'old worktree session',
    'workspace-write', 'on-request', 0, '0.116.0'
);
SQL

    printf '%s\n' "$codex_home"
    printf '%s\n' "$old_main"
    printf '%s\n' "$new_main"
    printf '%s\n' "$moved_root"
    printf '%s\n' "$old_worktree"
    printf '%s\n' "$new_worktree"
    printf '%s\n' "$archive_file"
    printf '%s\n' "$session_file"
}

run_component_codex_session_path_repair_tests() {
    start_timer

    local fixture_root setup_output codex_home old_main new_main moved_root old_worktree new_worktree archive_file session_file
    fixture_root="$(secure_temp_dir codex-session-path-repair)"
    mapfile -t setup_output < <(setup_codex_session_path_fixture "$fixture_root")
    codex_home="${setup_output[0]}"
    old_main="${setup_output[1]}"
    new_main="${setup_output[2]}"
    moved_root="${setup_output[3]}"
    old_worktree="${setup_output[4]}"
    new_worktree="${setup_output[5]}"
    archive_file="${setup_output[6]}"
    session_file="${setup_output[7]}"

    test_start "component_codex_session_path_repair_updates_db_archived_and_live_rollouts"
    bash "$REPAIR_SCRIPT" \
        --apply \
        --codex-home "$codex_home" \
        --old-main "$old_main" \
        --new-main "$new_main" \
        --moved-root "$moved_root" >/dev/null

    assert_eq "$new_main" "$(sqlite3 -readonly "$codex_home/state_5.sqlite" "SELECT cwd FROM threads WHERE id='archive-old-root';")" \
        "Repair script should rewrite old main cwd in state DB"
    assert_eq "$new_worktree" "$(sqlite3 -readonly "$codex_home/state_5.sqlite" "SELECT cwd FROM threads WHERE id='live-old-worktree';")" \
        "Repair script should rewrite moved sibling worktree cwd in state DB"

    assert_eq "$new_main" "$(head -n 1 "$archive_file" | jq -r '.payload.cwd')" \
        "Repair script should rewrite archived session headers"
    assert_eq "$new_worktree" "$(head -n 1 "$session_file" | jq -r '.payload.cwd')" \
        "Repair script should rewrite live rollout session headers"
    test_pass

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_session_path_repair_tests
fi
