#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WEB_ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-web-adapter.py"
SESSION_NEW_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/web-demo/session-new.json"
UPLOAD_FIXTURE="$PROJECT_ROOT/asc-demo/demo-client-data.csv"

run_integration_local_agent_factory_web_full_cycle_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_web_full_cycle_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_web_full_cycle_runs_from_access_to_simulated_employee_launch"

    local upload_base64
    upload_base64="$(
        python3 -c 'import base64, pathlib; print(base64.b64encode(pathlib.Path("'"$UPLOAD_FIXTURE"'").read_bytes()).decode("ascii"))'
    )"

    local current="$tmpdir/step-00.json"
    local next="$tmpdir/step-01.json"
    local turn_index=0
    local uploaded_examples=0

    jq '
      .web_conversation_envelope = {
        "web_conversation_envelope_id": "web-envelope-full-cycle-000",
        "request_id": "web-request-full-cycle-000",
        "transport_mode": "synthetic_fixture",
        "ui_action": "request_demo_access",
        "user_text": ""
      }
      | .demo_access_grant.grant_type = "shared_demo_token"
      | .demo_access_grant.grant_value = "demo-access-token"
      | .demo_access_grant.status = "active"
      | .web_demo_session.status = "gate_pending"
      | del(.uploaded_files)
    ' "$SESSION_NEW_FIXTURE" >"$current"

    if ! python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$current" --state-root "$tmpdir/state" --output "$next" >/dev/null; then
        test_fail "Access-grant bootstrap should initialize the web session"
        generate_report
        return
    fi
    current="$next"

    local reached_confirmation="false"
    while [[ "$turn_index" -lt 18 ]]; do
        local status
        local next_action
        local current_topic
        status="$(jq -r '.status' "$current")"
        next_action="$(jq -r '.next_action' "$current")"
        current_topic="$(jq -r '.ui_projection.current_topic // .next_topic // ""' "$current")"

        if [[ "$status" == "awaiting_confirmation" ]]; then
            reached_confirmation="true"
            break
        fi

        local reply_text=""
        local include_upload=0
        if [[ "$status" == "awaiting_clarification" || "$next_action" == "resolve_clarification" ]]; then
            reply_text="Все данные в приложенном файле синтетические и обезличены, реальные реквизиты замаскированы. Продолжаем."
        else
            case "$current_topic" in
                problem)
                    reply_text="Нужно автоматизировать подготовку one-page summary по клиенту для кредитного комитета, чтобы сократить ручной труд и T2M."
                    ;;
                target_users)
                    reply_text="Основной пользователь — клиентский менеджер. Выгодоприобретатели — члены кредитного комитета и топ-менеджмент."
                    ;;
                current_workflow)
                    reply_text="Сейчас я выгружаю данные клиента в таблицу, вручную собираю one-page в Word и экспортирую в PDF. Потери в ручной сверке и форматировании."
                    ;;
                desired_outcome)
                    reply_text="На выходе нужен готовый one-page PDF с чёткой структурой и рекомендацией для принятия решения кредитным комитетом."
                    ;;
                user_story)
                    reply_text="Как клиентский менеджер, перед заседанием комитета я хочу быстро получить качественный one-page с рекомендацией, чтобы снизить риск ошибок."
                    ;;
                input_examples)
                    reply_text="Прикрепляю типовой CSV с показателями клиента. Агент должен анализировать его и формировать one-page."
                    if [[ "$uploaded_examples" -eq 0 ]]; then
                        include_upload=1
                        uploaded_examples=1
                    fi
                    ;;
                constraints)
                    reply_text="Запрещено использовать реальные реквизиты в output. Числа форматировать с пробелами, проценты всегда со знаком %."
                    ;;
                success_metrics)
                    reply_text="Метрики успеха: время подготовки one-page сокращено минимум на 50%, количество ошибок в материалах снижено минимум на 40%."
                    ;;
                *)
                    reply_text="Продолжаем по текущей теме, фиксируй как рабочее требование."
                    ;;
            esac
        fi

        turn_index=$((turn_index + 1))
        next="$tmpdir/step-$((turn_index + 1)).json"
        if [[ "$include_upload" -eq 1 ]]; then
            jq --arg text "$reply_text" --arg req "web-request-full-cycle-$(printf '%03d' "$turn_index")" --arg env "web-envelope-full-cycle-$(printf '%03d' "$turn_index")" --arg upload "$upload_base64" '
              .web_conversation_envelope = {
                "web_conversation_envelope_id": $env,
                "request_id": $req,
                "transport_mode": "synthetic_fixture",
                "ui_action": "submit_turn",
                "user_text": $text
              }
              | .browser_project_pointer.selection_mode = "continue_active"
              | .uploaded_files = [
                  {
                    "upload_id": "upload-full-cycle-001",
                    "name": "demo-client-data.csv",
                    "content_type": "text/csv",
                    "size_bytes": 8454,
                    "original_size_bytes": 8454,
                    "truncated": false,
                    "content_base64": $upload
                  }
                ]
              | del(.demo_access_grant)
            ' "$current" >"$tmpdir/request-$turn_index.json"
        else
            jq --arg text "$reply_text" --arg req "web-request-full-cycle-$(printf '%03d' "$turn_index")" --arg env "web-envelope-full-cycle-$(printf '%03d' "$turn_index")" '
              .web_conversation_envelope = {
                "web_conversation_envelope_id": $env,
                "request_id": $req,
                "transport_mode": "synthetic_fixture",
                "ui_action": "submit_turn",
                "user_text": $text
              }
              | .browser_project_pointer.selection_mode = "continue_active"
              | del(.uploaded_files)
              | del(.demo_access_grant)
            ' "$current" >"$tmpdir/request-$turn_index.json"
        fi

        if ! python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/request-$turn_index.json" --state-root "$tmpdir/state" --output "$next" >/dev/null; then
            test_fail "Turn $turn_index should be processed successfully in full-cycle flow"
            generate_report
            return
        fi
        current="$next"
    done

    if [[ "$reached_confirmation" != "true" ]]; then
        test_fail "Discovery loop should reach awaiting_confirmation within bounded number of turns"
        generate_report
        return
    fi

    local base_version
    local version_after_correction1
    local version_after_correction2

    base_version="$(jq -r '.discovery_runtime_state.requirement_brief.version // "0.0"' "$current")"

    jq '
      .web_conversation_envelope = {
        "web_conversation_envelope_id": "web-envelope-full-cycle-correction-001",
        "request_id": "web-request-full-cycle-correction-001",
        "transport_mode": "synthetic_fixture",
        "ui_action": "request_brief_correction",
        "user_text": "Корректировка #1: итоговый документ должен быть строго one-page PDF для КК, без альтернативных форматов."
      }
      | .brief_section_updates = {
          "expected_outputs": [
            "One-page PDF для кредитного комитета с рекомендацией по сделке"
          ]
        }
      | del(.demo_access_grant)
      | del(.uploaded_files)
    ' "$current" >"$tmpdir/correction-1-request.json"
    python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/correction-1-request.json" --state-root "$tmpdir/state" --output "$tmpdir/correction-1-out.json" >/dev/null
    version_after_correction1="$(jq -r '.discovery_runtime_state.requirement_brief.version // "0.0"' "$tmpdir/correction-1-out.json")"

    jq '
      .web_conversation_envelope = {
        "web_conversation_envelope_id": "web-envelope-full-cycle-correction-002",
        "request_id": "web-request-full-cycle-correction-002",
        "transport_mode": "synthetic_fixture",
        "ui_action": "request_brief_correction",
        "user_text": "Корректировка #2: добавить BPMN-схему процесса и отдельный блок рисков с форматированием для защиты."
      }
      | .brief_section_updates = {
          "expected_outputs": [
            "One-page PDF для кредитного комитета с рекомендацией по сделке",
            "Презентационный слайд с BPMN-схемой и блоком рисков"
          ],
          "constraints": [
            "В материалах для защиты обязательно должна быть BPMN-схема процесса",
            "Блок рисков должен быть представлен отдельным структурированным разделом"
          ]
        }
      | del(.demo_access_grant)
      | del(.uploaded_files)
    ' "$tmpdir/correction-1-out.json" >"$tmpdir/correction-2-request.json"
    python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/correction-2-request.json" --state-root "$tmpdir/state" --output "$tmpdir/correction-2-out.json" >/dev/null
    version_after_correction2="$(jq -r '.discovery_runtime_state.requirement_brief.version // "0.0"' "$tmpdir/correction-2-out.json")"

    jq '
      .web_conversation_envelope = {
        "web_conversation_envelope_id": "web-envelope-full-cycle-confirm-001",
        "request_id": "web-request-full-cycle-confirm-001",
        "transport_mode": "synthetic_fixture",
        "ui_action": "confirm_brief",
        "user_text": ""
      }
      | del(.demo_access_grant)
      | del(.uploaded_files)
    ' "$tmpdir/correction-2-out.json" >"$tmpdir/confirm-request.json"
    python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/confirm-request.json" --state-root "$tmpdir/state" --output "$tmpdir/confirmed-out.json" >/dev/null

    jq '
      .web_conversation_envelope = {
        "web_conversation_envelope_id": "web-envelope-full-cycle-status-001",
        "request_id": "web-request-full-cycle-status-001",
        "transport_mode": "synthetic_fixture",
        "ui_action": "request_status",
        "user_text": ""
      }
      | del(.demo_access_grant)
      | del(.uploaded_files)
    ' "$tmpdir/confirmed-out.json" >"$tmpdir/status-request.json"
    python3 "$WEB_ADAPTER_SCRIPT" handle-turn --source "$tmpdir/status-request.json" --state-root "$tmpdir/state" --output "$tmpdir/download-ready-out.json" >/dev/null

    assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/correction-1-out.json")" "First correction should keep flow in confirmation stage"
    assert_ne "$base_version" "$version_after_correction1" "First correction should bump brief version"
    assert_ne "$version_after_correction1" "$version_after_correction2" "Second correction should bump brief version again"
    assert_true "$(jq -r '.discovery_runtime_state.brief_feedback_history | length >= 2' "$tmpdir/correction-2-out.json")" "Brief feedback history should keep both correction iterations"
    assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/confirmed-out.json")" "Flow should enter confirmed state after explicit confirmation"
    assert_eq "download_ready" "$(jq -r '.status' "$tmpdir/download-ready-out.json")" "Status refresh should complete downstream generation"
    assert_eq "download_artifact" "$(jq -r '.next_action' "$tmpdir/download-ready-out.json")" "Download-ready response should expose artifact action"
    assert_eq "completed" "$(jq -r '.production_simulation.status' "$tmpdir/download-ready-out.json")" "Production simulation should complete in full-cycle run"
    assert_eq "live_user_data" "$(jq -r '.production_simulation.data_profile' "$tmpdir/download-ready-out.json")" "Production simulation should classify execution as live user data when uploads are present"
    assert_contains "$(jq -r '.production_simulation.data_profile_summary' "$tmpdir/download-ready-out.json")" "demo-client-data.csv" "Production simulation summary should reference the uploaded input file"
    assert_true "$(jq -r '.download_artifacts | length >= 4' "$tmpdir/download-ready-out.json")" "Full cycle should expose concept-pack artifacts and production simulation report"
    assert_true "$(jq -r '[.download_artifacts[] | select(.artifact_kind == "one_page_summary")] | length == 1' "$tmpdir/download-ready-out.json")" "Download list should contain one-page summary artifact"
    assert_true "$(jq -r '[.download_artifacts[] | select(.artifact_kind == "production_simulation")] | length == 1' "$tmpdir/download-ready-out.json")" "Download list should contain production simulation report artifact"
    assert_file_exists "$tmpdir/state/employees/digital-employees-registry.json" "Digital employee registry should be persisted"
    local download_session_id
    download_session_id="$(jq -r '.web_demo_session.web_demo_session_id' "$tmpdir/download-ready-out.json")"
    assert_file_exists "$tmpdir/state/downloads/$download_session_id/downloads/one-page-summary.md" "One-page summary should be persisted in web-demo downloads"
    local one_page_path
    one_page_path="$tmpdir/state/downloads/$download_session_id/downloads/one-page-summary.md"
    local one_page_content
    one_page_content="$(cat "$one_page_path")"
    assert_contains "$one_page_content" "Ключевые факты из приложенных данных" "One-page summary should expose a dedicated data-facts section"
    assert_contains "$one_page_content" "demo-client-data.csv: обработано" "One-page summary should include parsed upload evidence instead of brief-only retelling"
    assert_contains "$one_page_content" "Сумма = 300 000 000 руб." "One-page summary should include concrete extracted deal facts from CSV"
    if compgen -G "$tmpdir/state/employees/executions/*.json" >/dev/null; then
        :
    else
        test_fail "At least one execution record should be persisted for the simulated digital employee"
        generate_report
        return
    fi

    test_pass
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_web_full_cycle_tests
fi
