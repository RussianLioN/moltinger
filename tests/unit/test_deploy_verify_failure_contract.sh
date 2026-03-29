#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

prepare_deploy_library() {
    local tmp_dir="$1"
    local deploy_lib="$tmp_dir/deploy-lib.sh"

    sed '$d' "$PROJECT_ROOT/scripts/deploy.sh" >"$deploy_lib"
    printf '%s\n' "$deploy_lib"
}

test_verify_deployment_records_failure_without_aborting_shell() {
    test_start "verify_deployment should return a controlled failure after recording a reason"

    local tmp_dir deploy_lib scenario result_file trace_file
    tmp_dir="$(mktemp -d)"
    deploy_lib="$(prepare_deploy_library "$tmp_dir")"
    scenario="$tmp_dir/scenario.sh"
    result_file="$tmp_dir/result.txt"
    trace_file="$tmp_dir/trace.log"

    cat >"$scenario" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "$deploy_lib"

RESULT_FILE="$result_file"
TRACE_FILE="$trace_file"

log_info() { :; }
log_warn() { :; }
log_error() { :; }
log_success() { :; }

wait_for_healthy() {
    printf 'wait\n' >>"\$TRACE_FILE"
    return 1
}

curl() {
    printf 'curl\n' >>"\$TRACE_FILE"
    printf '200'
}

TARGET="clawdiy"
TARGET_CONTAINER="test-clawdiy"
TARGET_HEALTH_TIMEOUT=1
TARGET_HEALTH_URL="http://127.0.0.1/health"
TARGET_METRICS_URL=""
VERIFY_FAILURE_REASON=""

if verify_deployment; then
    status=0
else
    status=\$?
fi

cat >"\$RESULT_FILE" <<RESULT
status=\$status
reason=\$VERIFY_FAILURE_REASON
RESULT
EOF
    chmod +x "$scenario"

    if ! bash "$scenario"; then
        test_fail "verify_deployment shell aborted instead of returning a controlled failure"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fxq 'wait' "$trace_file" || ! grep -Fxq 'curl' "$trace_file"; then
        test_fail "verify_deployment must continue gathering evidence after the first recorded failure"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fqx 'status=1' "$result_file" || \
       ! grep -Fqx 'reason=Health wait timed out for target clawdiy' "$result_file"; then
        test_fail "verify_deployment must return 1 and preserve the first verification failure reason"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

test_moltis_skill_verification_failure_does_not_skip_later_contract_checks() {
    test_start "Moltis verify path should keep later contract checks even if skill discovery fails"

    local tmp_dir deploy_lib scenario result_file trace_file
    tmp_dir="$(mktemp -d)"
    deploy_lib="$(prepare_deploy_library "$tmp_dir")"
    scenario="$tmp_dir/scenario.sh"
    result_file="$tmp_dir/result.txt"
    trace_file="$tmp_dir/trace.log"

    mkdir -p "$tmp_dir/project/config" "$tmp_dir/runtime"
    printf 'model = "ok"\n' >"$tmp_dir/project/config/moltis.toml"
    cp "$tmp_dir/project/config/moltis.toml" "$tmp_dir/runtime/moltis.toml"

    cat >"$scenario" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "$deploy_lib"

RESULT_FILE="$result_file"
TRACE_FILE="$trace_file"
TEST_PROJECT_ROOT="$tmp_dir/project"
TEST_RUNTIME_DIR="$tmp_dir/runtime"

log_info() { :; }
log_warn() { :; }
log_error() { :; }
log_success() { :; }

wait_for_healthy() {
    printf 'wait\n' >>"\$TRACE_FILE"
    return 0
}

curl() {
    printf 'curl\n' >>"\$TRACE_FILE"
    printf '200'
}

container_mount_source() {
    case "\$2" in
        /server) printf '%s\n' "\$TEST_PROJECT_ROOT" ;;
        /home/moltis/.config/moltis) printf '%s\n' "\$TEST_RUNTIME_DIR" ;;
        *) return 1 ;;
    esac
}

container_mount_rw() {
    printf 'true\n'
}

canonicalize_existing_path() {
    printf '%s\n' "\$1"
}

read_env_file_value() {
    printf '%s\n' "\$TEST_RUNTIME_DIR"
}

normalize_runtime_config_path() {
    printf '%s\n' "\$1"
}

runtime_config_dir_allowed() {
    return 0
}

verify_moltis_repo_skills_discovery() {
    printf 'skills-check\n' >>"\$TRACE_FILE"
    record_verification_failure "Moltis runtime contract mismatch: simulated skill discovery failure"
    return 1
}

docker() {
    if [[ "\$1" == "inspect" ]]; then
        printf '/server\n'
        return 0
    fi

    if [[ "\$1" == "exec" ]]; then
        printf 'docker-exec\n' >>"\$TRACE_FILE"
        return 0
    fi

    echo "unexpected docker invocation: \$*" >&2
    return 99
}

TARGET="moltis"
TARGET_CONTAINER="moltis"
TARGET_HEALTH_TIMEOUT=1
TARGET_HEALTH_URL="http://127.0.0.1:13131/health"
TARGET_METRICS_URL=""
PROJECT_ROOT="\$TEST_PROJECT_ROOT"
VERIFY_FAILURE_REASON=""

if verify_deployment; then
    status=0
else
    status=\$?
fi

docker_exec_count=\$(grep -c '^docker-exec$' "\$TRACE_FILE" || true)
cat >"\$RESULT_FILE" <<RESULT
status=\$status
reason=\$VERIFY_FAILURE_REASON
docker_exec_count=\$docker_exec_count
RESULT
EOF
    chmod +x "$scenario"

    if ! bash "$scenario"; then
        test_fail "Moltis verify path aborted instead of returning a controlled failure"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fqx 'status=1' "$result_file" || \
       ! grep -Fqx 'reason=Moltis runtime contract mismatch: simulated skill discovery failure' "$result_file"; then
        test_fail "Moltis verify path must surface the recorded skill-discovery failure without aborting the shell"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fqx 'docker_exec_count=3' "$result_file"; then
        test_fail "Moltis verify path must continue later docker contract checks after a skill-discovery failure"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

test_moltis_hook_verification_strips_cli_log_preamble_before_jq() {
    test_start "Moltis hook verify path should ignore CLI log preamble before parsing JSON"

    local tmp_dir deploy_lib scenario result_file trace_file
    tmp_dir="$(mktemp -d)"
    deploy_lib="$(prepare_deploy_library "$tmp_dir")"
    scenario="$tmp_dir/scenario.sh"
    result_file="$tmp_dir/result.txt"
    trace_file="$tmp_dir/trace.log"

    cat >"$scenario" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "$deploy_lib"

RESULT_FILE="$result_file"
TRACE_FILE="$trace_file"

log_info() { :; }
log_warn() { :; }
log_error() { :; }
log_success() { :; }

sync_moltis_repo_hooks_into_runtime() {
    printf 'sync-hooks\n' >>"\$TRACE_FILE"
    return 0
}

list_repo_hook_names() {
    printf 'telegram-safe-llm-guard\n'
}

docker() {
    if [[ "\$1" != "exec" ]]; then
        echo "unexpected docker invocation: \$*" >&2
        return 99
    fi

    if [[ "\$*" == *"test -f"* ]]; then
        printf 'hook-file-check\n' >>"\$TRACE_FILE"
        return 0
    fi

    if [[ "\$*" == *"moltis hooks list --json"* ]]; then
        printf 'hook-list\n' >>"\$TRACE_FILE"
        cat <<'JSON'
\u001b[2m2026-03-29T04:09:37.984155Z\u001b[0m \u001b[32m INFO\u001b[0m \u001b[2mmoltis\u001b[0m: moltis starting version="0.10.18"
[
  {
    "name": "telegram-safe-llm-guard",
    "source": "project",
    "eligible": true,
    "path": "/home/moltis/.moltis/.moltis/hooks/telegram-safe-llm-guard"
  }
]
JSON
        return 0
    fi

    echo "unexpected docker exec invocation: \$*" >&2
    return 98
}

TARGET_CONTAINER="moltis"
VERIFY_FAILURE_REASON=""

if verify_moltis_repo_hook_discovery; then
    status=0
else
    status=\$?
fi

cat >"\$RESULT_FILE" <<RESULT
status=\$status
reason=\${VERIFY_FAILURE_REASON:-}
trace=\$(tr '\n' ',' <"\$TRACE_FILE" | sed 's/,\$//')
RESULT
EOF
    chmod +x "$scenario"

    if ! bash "$scenario"; then
        test_fail "Hook verify path aborted instead of handling the CLI log preamble"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fqx 'status=0' "$result_file"; then
        test_fail "Hook verify path must accept hook registry JSON even when the CLI prefixes it with an INFO log line"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fqx 'reason=' "$result_file"; then
        test_fail "Hook verify path must leave VERIFY_FAILURE_REASON empty on successful JSON extraction"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fqx 'trace=sync-hooks,hook-file-check,hook-file-check,hook-list' "$result_file"; then
        test_fail "Hook verify path must sync repo hooks into the runtime path before performing tracked-source and runtime hook file checks"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

run_all_tests() {
    start_timer

    test_verify_deployment_records_failure_without_aborting_shell
    test_moltis_skill_verification_failure_does_not_skip_later_contract_checks
    test_moltis_hook_verification_strips_cli_log_preamble_before_jq

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
