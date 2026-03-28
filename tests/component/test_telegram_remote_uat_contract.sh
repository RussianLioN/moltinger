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
mode="${TELEGRAM_WEB_STUB_MODE:-send_failure}"

if [[ "$mode" == "status_semantic_mismatch" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "## Статус системы\nМодель: zai::glm-5",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "verification_gate_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "To use this bot, please enter the verification code.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "activity_log_emoji_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "📋 Activity log • 🗺️ mcp__tavily__tavily_map • 🧠 Searching memory...",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "pre_send_invalid_incoming_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Сначала проверю память и каталог навыков.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven",
    "last_pre_send_activity": {
      "observed_max_mid": 40,
      "messages": [
        {
          "mid": 40,
          "direction": "in",
          "text": "📋 Activity log • 💻 Running: `find /home/moltis/.moltis/skills -maxdepth 2 -type...`"
        }
      ]
    }
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "host_path_leak_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Для этого навыка использую /server/scripts/moltis-codex-update-run.sh --mode manual --stdout summary.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_false_negative_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "По-честному: подтверждённых новых версий Codex у меня сейчас нет. Что проверилось: путь к skill codex-update сейчас не существует физически; каталога /home/moltis/.moltis/skills в текущем файловом окружении тоже нет.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

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
import os

mode = os.environ.get("MTPROTO_STUB_MODE", "precondition")
if mode == "verification_gate":
    payload = {
        "status": "completed",
        "observed_response": "To use this bot, please enter the verification code.",
        "error_code": None,
        "error_message": None,
        "context": {"bot_username": "moltinger_bot"},
        "transport": "telegram_mtproto_real_user"
    }
else:
    payload = {
        "status": "precondition_failed",
        "observed_response": None,
        "error_code": "precondition",
        "error_message": "missing TELEGRAM_TEST_SESSION",
        "context": {"missing": ["TELEGRAM_TEST_SESSION"]},
        "transport": "telegram_mtproto_real_user"
    }
print(json.dumps(payload))
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

    test_start "component_telegram_remote_uat_fails_status_reply_without_canonical_model"
    if TELEGRAM_WEB_STUB_MODE=status_semantic_mismatch \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        --output "$TEST_TMPDIR/result-status-mismatch.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when /status reply omits the canonical model contract"
    else
        if jq -e '.failure.code == "semantic_status_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-status-mismatch.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.expected_model == "zai-telegram-safe::glm-5"' "$TEST_TMPDIR/result-status-mismatch.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface semantic /status mismatches as a failed authoritative verdict"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_verification_gate_reply_even_after_attributable_pass"
    if TELEGRAM_WEB_STUB_MODE=verification_gate_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        --output "$TEST_TMPDIR/result-verification-gate-primary.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the attributable /status reply is a verification gate"
    else
        if jq -e '.failure.code == "verification_gate_reply" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-verification-gate-primary.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must mark verification-gate replies as non-green authoritative outcomes"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_emoji_prefixed_activity_log_reply_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=activity_log_emoji_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Проверь память и каталог навыков" \
        --output "$TEST_TMPDIR/result-activity-log.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the helper falsely passes an emoji-prefixed internal activity reply"
    else
        if jq -e '.failure.code == "semantic_activity_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-activity-log.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface emoji-prefixed activity-log replies as failed authoritative outcomes"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_recent_invalid_pre_send_activity_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=pre_send_invalid_incoming_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Проверь память и каталог навыков" \
        --output "$TEST_TMPDIR/result-pre-send-activity.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when recent invalid incoming activity already contaminated the chat before send"
    else
        if jq -e '.failure.code == "semantic_pre_send_activity_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-pre-send-activity.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must fail on recent invalid pre-send activity leakage even when the helper payload is otherwise green"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_host_path_leak_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=host_path_leak_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Что умеет codex-update?" \
        --output "$TEST_TMPDIR/result-host-path-leak.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the reply exposes host filesystem or repo runtime paths"
    else
        if jq -e '.failure.code == "semantic_host_path_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-host-path-leak.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface host-path leakage as a failed authoritative outcome"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_false_negative_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_false_negative_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Что с новыми версиями codex?" \
        --output "$TEST_TMPDIR/result-codex-update-false-negative.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update is falsely treated as missing from a sandboxed Telegram surface"
    else
        if jq -e '.failure.code == "semantic_codex_update_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-false-negative.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface codex-update false negatives caused by sandbox-invisible host paths"
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

    test_start "component_telegram_remote_uat_marks_mtproto_verification_gate_as_noncomparable"
    if MTPROTO_STUB_MODE=verification_gate \
        TELEGRAM_TEST_API_ID=12345 \
        TELEGRAM_TEST_API_HASH=test-hash \
        TELEGRAM_TEST_SESSION=test-session \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --secondary-diagnostics mtproto \
        --message "/status" \
        --output "$TEST_TMPDIR/result-verification-gate.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper should still fail when the primary verdict is red even if MTProto only reaches a verification gate"
    else
        if jq -e '.fallback_assessment.requested == true and .fallback_assessment.outcome == "completed" and .fallback_assessment.observed_verification_gate == true and .fallback_assessment.comparable_to_authoritative == false' "$TEST_TMPDIR/result-verification-gate.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must mark MTProto verification-code responses as non-comparable secondary diagnostics"
        fi
    fi

    test_start "component_telegram_remote_uat_deploy_guard_keeps_scheduler_disabled"
    if grep -q "apply-moltis-host-automation.sh" "$PROJECT_ROOT/.github/workflows/deploy.yml" \
        && grep -Fq 'DISABLED_FALLBACK_SCHEDULER="moltis-telegram-web-user-monitor"' "$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh" \
        && grep -Fq 'systemctl disable --now "${DISABLED_FALLBACK_SCHEDULER}.timer"' "$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh" \
        && ! grep -Fq '${{ env.DEPLOY_ACTIVE_PATH }}/scripts/cron.d/moltis-telegram-web-user-monitor' "$PROJECT_ROOT/.github/workflows/deploy.yml" \
        && ! grep -q "systemctl enable --now .*telegram-web-user-monitor.timer" "$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh"
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
