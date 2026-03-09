#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

LAUNCH_SCRIPT="$PROJECT_ROOT/scripts/codex-profile-launch.sh"

setup_component_codex_profile_launch() {
    require_commands_or_skip bash || return 2
    return 0
}

setup_fake_codex_runtime() {
    local bin_dir="$1"
    local state_dir="$2"

    cat > "$bin_dir/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_CODEX_STATE_DIR:?}"
printf '%s\n' "$@" > "$state_dir/codex-args.txt"
echo "fake codex invoked"
CODEX
    chmod +x "$bin_dir/codex"

    cat > "$state_dir/fake-delivery.sh" <<'DELIVERY'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_CODEX_STATE_DIR:?}"
args=("$@")
surface="unknown"
stdout_mode="summary"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface)
      surface="${2:-unknown}"
      shift 2
      ;;
    --stdout)
      stdout_mode="${2:-summary}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s\n' "${args[@]}" > "$state_dir/${surface}-args.txt"

if [[ "$surface" == "launcher" && "$stdout_mode" == "summary" ]]; then
  echo "[Codex Update Alert]"
  echo "Codex update banner"
fi
DELIVERY
    chmod +x "$state_dir/fake-delivery.sh"

    cat > "$state_dir/fake-sender.sh" <<'SENDER'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SENDER
    chmod +x "$state_dir/fake-sender.sh"
}

run_component_codex_profile_launch_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_profile_launch
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir bin_dir output

    test_start "component_codex_profile_launch_runs_banner_and_telegram_hook_when_enabled"
    work_dir="$(secure_temp_dir codex-profile-launch)"
    bin_dir="$work_dir/bin"
    mkdir -p "$bin_dir"
    setup_fake_codex_runtime "$bin_dir" "$work_dir"

    output="$(
        PATH="$bin_dir:$PATH" \
        FAKE_CODEX_STATE_DIR="$work_dir" \
        CODEX_UPDATE_DELIVERY_SCRIPT="$work_dir/fake-delivery.sh" \
        CODEX_UPDATE_LAUNCH_ALERT=1 \
        CODEX_UPDATE_LAUNCH_TELEGRAM=1 \
        CODEX_UPDATE_DELIVERY_TELEGRAM_CHAT_ID=262872984 \
        CODEX_UPDATE_LAUNCH_TELEGRAM_SEND_SCRIPT="$work_dir/fake-sender.sh" \
        bash "$LAUNCH_SCRIPT" docs "hello world"
    )"
    sleep 1

    assert_contains "$output" "[Codex Update Alert]" "Launcher should print the delivery banner before starting Codex"
    assert_contains "$(cat "$work_dir/codex-args.txt")" "-m" "Launcher should still exec Codex after running hooks"
    assert_contains "$(cat "$work_dir/launcher-args.txt")" "--surface" "Launcher hook should invoke the delivery script in launcher mode"
    assert_contains "$(cat "$work_dir/telegram-args.txt")" "--telegram-chat-id" "Telegram hook should invoke the delivery script in telegram mode"
    assert_contains "$(cat "$work_dir/telegram-args.txt")" "262872984" "Telegram hook should forward the configured chat id"
    assert_contains "$(cat "$work_dir/telegram-args.txt")" "$work_dir/fake-sender.sh" "Telegram hook should forward the configured sender path"
    test_pass

    test_start "component_codex_profile_launch_skips_telegram_hook_when_disabled"
    work_dir="$(secure_temp_dir codex-profile-launch-disabled)"
    bin_dir="$work_dir/bin"
    mkdir -p "$bin_dir"
    setup_fake_codex_runtime "$bin_dir" "$work_dir"

    PATH="$bin_dir:$PATH" \
    FAKE_CODEX_STATE_DIR="$work_dir" \
    CODEX_UPDATE_DELIVERY_SCRIPT="$work_dir/fake-delivery.sh" \
    CODEX_UPDATE_LAUNCH_ALERT=1 \
    CODEX_UPDATE_LAUNCH_TELEGRAM=0 \
    bash "$LAUNCH_SCRIPT" docs >/dev/null
    sleep 1

    if [[ -f "$work_dir/telegram-args.txt" ]]; then
        test_fail "Telegram hook should not run when CODEX_UPDATE_LAUNCH_TELEGRAM=0"
    else
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_profile_launch_tests
fi
