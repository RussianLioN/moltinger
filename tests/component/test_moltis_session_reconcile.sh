#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

RECONCILE_SCRIPT="$PROJECT_ROOT/scripts/moltis-session-reconcile.sh"

write_fake_curl() {
    local output_path="$1"
    cat > "$output_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cookie_file=""
output_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|-b|-o|-X|-H|-d|-w|--max-time)
            if [[ $# -ge 2 ]]; then
                case "$1" in
                    -c) cookie_file="$2" ;;
                    -o) output_file="$2" ;;
                esac
                shift 2
                continue
            fi
            ;;
        -s)
            shift
            continue
            ;;
    esac
    shift
done

if [[ -n "$cookie_file" ]]; then
    cat > "$cookie_file" <<'COOKIE'
# Netscape HTTP Cookie File
localhost	FALSE	/	FALSE	0	moltis_session	fake-session
COOKIE
fi

if [[ -n "$output_file" ]]; then
    : > "$output_file"
fi

printf '200'
EOF
    chmod +x "$output_path"
}

write_fake_rpc_cli() {
    local output_path="$1"
    cat > "$output_path" <<'EOF'
import fs from "node:fs";

function argValue(name) {
  const idx = process.argv.indexOf(name);
  return idx >= 0 && idx + 1 < process.argv.length ? process.argv[idx + 1] : "";
}

const method = argValue("--method");
const params = JSON.parse(argValue("--params") || "{}");
const statePath = process.env.FAKE_RPC_STATE;
const logPath = process.env.FAKE_RPC_LOG;
const state = JSON.parse(fs.readFileSync(statePath, "utf8"));

function saveState(nextState) {
  fs.writeFileSync(statePath, JSON.stringify(nextState, null, 2));
}

function appendLog(entry) {
  fs.appendFileSync(logPath, `${entry}\n`);
}

function emit(payload) {
  process.stdout.write(`${JSON.stringify({ ok: true, result: { ok: true, payload }, events: [] }, null, 2)}\n`);
}

appendLog(`${method}:${JSON.stringify(params)}`);

switch (method) {
  case "sessions.list":
    emit(state.sessions);
    break;
  case "sessions.patch": {
    state.sessions = state.sessions.map((session) =>
      session.key === params.key ? { ...session, model: params.model } : session,
    );
    saveState(state);
    emit({ key: params.key, model: params.model });
    break;
  }
  case "sessions.reset":
    emit({ key: params.key, ok: true });
    break;
  default:
    process.stdout.write(`${JSON.stringify({ ok: false, result: { ok: false }, message: `unexpected method ${method}` }, null, 2)}\n`);
    process.exit(1);
}
EOF
}

seed_state_fixture() {
    local output_path="$1"
    cat > "$output_path" <<'EOF'
{
  "sessions": [
    {
      "key": "main",
      "label": null,
      "model": "zai::glm-5",
      "activeChannel": false,
      "updatedAt": 10,
      "channelBinding": null
    },
    {
      "key": "session:active-telegram",
      "label": "Telegram 2",
      "model": "openai-codex::gpt-5.3-codex-spark",
      "activeChannel": true,
      "updatedAt": 200,
      "channelBinding": "{\"channel_type\":\"telegram\",\"account_id\":\"moltis-bot\",\"chat_id\":\"262872984\"}"
    },
    {
      "key": "telegram:moltis-bot:262872984",
      "label": "Telegram 1",
      "model": "zai::glm-5",
      "activeChannel": false,
      "updatedAt": 100,
      "channelBinding": "{\"channel_type\":\"telegram\",\"account_id\":\"moltis-bot\",\"chat_id\":\"262872984\"}"
    }
  ]
}
EOF
}

run_component_moltis_session_reconcile_tests() {
    start_timer

    local tmp_dir fake_bin fake_curl fake_rpc env_file state_file log_file old_path
    tmp_dir="$(secure_temp_dir moltis-session-reconcile)"
    fake_bin="$tmp_dir/bin"
    mkdir -p "$fake_bin"
    fake_curl="$fake_bin/curl"
    fake_rpc="$tmp_dir/fake-ws-rpc-cli.mjs"
    env_file="$tmp_dir/moltis.env"
    state_file="$tmp_dir/rpc-state.json"
    log_file="$tmp_dir/rpc.log"

    write_fake_curl "$fake_curl"
    write_fake_rpc_cli "$fake_rpc"
    chmod +x "$fake_rpc"
    seed_state_fixture "$state_file"
    printf 'MOLTIS_PASSWORD=test-password\n' > "$env_file"
    : > "$log_file"

    old_path="$PATH"
    export PATH="$fake_bin:$PATH"
    export FAKE_RPC_STATE="$state_file"
    export FAKE_RPC_LOG="$log_file"

    test_start "component_moltis_session_reconcile_dry_run_prefers_unique_active_telegram_session"
    if ! MOLTIS_ENV_FILE="$env_file" MOLTIS_WS_RPC_CLI="$fake_rpc" \
        bash "$RECONCILE_SCRIPT" --telegram-chat-id 262872984 > "$tmp_dir/dry-run.json"; then
        test_fail "Session reconcile dry-run should succeed on the fake Telegram fixture"
        PATH="$old_path"
        return
    fi

    if [[ "$(jq -r '.status' "$tmp_dir/dry-run.json")" != "dry-run" ]] || \
       [[ "$(jq -r '.resolved_session.key' "$tmp_dir/dry-run.json")" != "session:active-telegram" ]] || \
       [[ "$(jq -r '.resolved_session.model' "$tmp_dir/dry-run.json")" != "openai-codex::gpt-5.3-codex-spark" ]] || \
       [[ "$(jq -r '.planned_actions.patch_model' "$tmp_dir/dry-run.json")" != "openai-codex::gpt-5.4" ]] || \
       [[ "$(jq -r '.planned_actions.reset_session' "$tmp_dir/dry-run.json")" != "true" ]]; then
        test_fail "Dry-run must resolve the unique active Telegram session and report the canonical patch/reset plan"
        PATH="$old_path"
        return
    fi
    test_pass

    test_start "component_moltis_session_reconcile_apply_patches_and_resets_target_session"
    if ! MOLTIS_ENV_FILE="$env_file" MOLTIS_WS_RPC_CLI="$fake_rpc" \
        bash "$RECONCILE_SCRIPT" --session-key main --apply > "$tmp_dir/apply.json"; then
        test_fail "Session reconcile apply should succeed on the fake main session"
        PATH="$old_path"
        return
    fi

    if [[ "$(jq -r '.status' "$tmp_dir/apply.json")" != "applied" ]] || \
       [[ "$(jq -r '.patch_result.model' "$tmp_dir/apply.json")" != "openai-codex::gpt-5.4" ]] || \
       [[ "$(jq -r '.reset_applied' "$tmp_dir/apply.json")" != "true" ]] || \
       [[ "$(jq -r '.verified_session.model' "$tmp_dir/apply.json")" != "openai-codex::gpt-5.4" ]] || \
       ! grep -Fq 'sessions.patch:{"key":"main","model":"openai-codex::gpt-5.4"}' "$log_file" || \
       ! grep -Fq 'sessions.reset:{"key":"main"}' "$log_file"; then
        test_fail "Apply mode must patch the target session to the canonical model, reset it, and verify the new model"
        PATH="$old_path"
        return
    fi
    test_pass

    PATH="$old_path"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_session_reconcile_tests
fi
