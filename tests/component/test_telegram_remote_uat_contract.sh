#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WRAPPER_SCRIPT="$PROJECT_ROOT/scripts/telegram-e2e-on-demand.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"

setup_remote_uat_contract_fixture() {
    TEST_TMPDIR="$(mktemp -d)"
    cp "$WRAPPER_SCRIPT" "$TEST_TMPDIR/telegram-e2e-on-demand.sh"
    chmod +x "$TEST_TMPDIR/telegram-e2e-on-demand.sh"

    cat > "$TEST_TMPDIR/telegram-web-user-monitor.sh" <<'SH'
#!/usr/bin/env bash
base_payload="$(cat <<'JSON'
{
  "ok": false,
  "status": "fail",
  "stage": "send",
  "failure": {
    "code": "send_failure",
    "stage": "send",
    "summary": "Probe message was not observed in chat after send",
    "actionability": "engineering",
    "fallback_relevant": true
  },
  "attribution_evidence": {
    "attribution_confidence": "absent"
  },
  "diagnostic_context": {
    "token": "secret-token",
    "session": "secret-session",
    "state_path": "/opt/moltinger/data/.telegram-web-state.json",
    "stats": {
      "url": "https://web.telegram.org/k/",
      "hasSearch": true
    }
  },
  "recommended_action": "Inspect send diagnostics and rerun."
}
JSON
)"

if [[ "${TELEGRAM_WEB_DEBUG:-false}" == "true" ]]; then
  jq '. + {
    restricted_debug: {
      debug_flag: true,
      dom: {
        send_button_present: true,
        draft_matches_probe: true
      }
    }
  }' <<<"$base_payload"
else
  printf '%s\n' "$base_payload"
fi
SH
    chmod +x "$TEST_TMPDIR/telegram-web-user-monitor.sh"

    cat > "$TEST_TMPDIR/telegram-real-user-e2e.py" <<'PY'
#!/usr/bin/env python3
import json
print(json.dumps({
    "status": "precondition_failed",
    "observed_response": None,
    "error_code": "precondition",
    "error_message": "missing TELEGRAM_TEST_SESSION",
    "context": {"missing": ["TELEGRAM_TEST_SESSION"]},
    "transport": "telegram_mtproto_real_user"
}))
PY
    chmod +x "$TEST_TMPDIR/telegram-real-user-e2e.py"
}

cleanup_remote_uat_contract_fixture() {
    if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR:-}" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

run_component_telegram_remote_uat_contract_tests() {
    start_timer
    setup_remote_uat_contract_fixture
    trap cleanup_remote_uat_contract_fixture EXIT

    test_start "component_telegram_remote_uat_review_safe_artifact_redacts_sensitive_fields"
    if "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        --output "$TEST_TMPDIR/result.json" \
        --debug-output "$TEST_TMPDIR/debug.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper should fail closed when the stubbed Telegram Web helper reports send_failure"
    else
        if jq -e '.failure.code == "send_failure"' "$TEST_TMPDIR/result.json" >/dev/null 2>&1 \
            && ! grep -q 'secret-token' "$TEST_TMPDIR/result.json" \
            && ! grep -q 'secret-session' "$TEST_TMPDIR/result.json" \
            && ! grep -q '/opt/moltinger/data/.telegram-web-state.json' "$TEST_TMPDIR/result.json" \
            && jq -e '.diagnostic_context.state_file == ".telegram-web-state.json"' "$TEST_TMPDIR/result.json" >/dev/null 2>&1 \
            && jq -e '.debug_bundle.available == true' "$TEST_TMPDIR/result.json" >/dev/null 2>&1 \
            && grep -q 'secret-token' "$TEST_TMPDIR/debug.json" \
            && jq -e '.authoritative_raw.restricted_debug.debug_flag == true' "$TEST_TMPDIR/debug.json" >/dev/null 2>&1 \
            && ! grep -q 'debug_flag' "$TEST_TMPDIR/result.json"
        then
            test_pass
        else
            test_fail "Review-safe artifact must redact token/session/state-path and keep restricted debug only in the debug bundle"
        fi
    fi

    test_start "component_telegram_remote_uat_marks_mtproto_fallback_unavailable_when_prerequisites_missing"
    if "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --secondary-diagnostics mtproto \
        --message "/status" \
        --output "$TEST_TMPDIR/result-fallback.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper should still fail when the primary verdict is red even if fallback is evaluated"
    else
        if jq -e '.fallback_assessment.requested == true and .fallback_assessment.outcome == "unavailable"' "$TEST_TMPDIR/result-fallback.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must record unavailable MTProto fallback prerequisites explicitly"
        fi
    fi

    test_start "component_telegram_remote_uat_deploy_guard_keeps_scheduler_disabled"
    if grep -q "Disable Telegram Web auto-monitor scheduler" "$PROJECT_ROOT/.github/workflows/deploy.yml" \
        && grep -q "systemctl disable --now moltis-telegram-web-user-monitor.timer" "$PROJECT_ROOT/.github/workflows/deploy.yml" \
        && ! grep -q "systemctl enable --now moltis-telegram-web-user-monitor.timer" "$PROJECT_ROOT/.github/workflows/deploy.yml"
    then
        test_pass
    else
        test_fail "Deploy workflow must keep the Telegram Web scheduler disabled by default"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_remote_uat_contract_tests
fi
