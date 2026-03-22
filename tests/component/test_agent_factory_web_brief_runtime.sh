#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

run_component_agent_factory_web_brief_runtime_tests() {
    start_timer
    require_commands_or_skip node jq || {
        test_start "component_agent_factory_web_brief_runtime_prereqs"
        test_skip "node and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_web_brief_runtime_syncs_topic_answers_from_revised_brief"
    if node --input-type=module >"$tmpdir/brief-sync.json" <<'NODE'
import { reviseBrief, syncSessionTopicAnswersFromBrief } from "./asc-demo/src/brief.js";

const session = {
  briefText: [
    "# Brief проекта",
    "",
    "## Бизнес-проблема",
    "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета.",
    "",
    "## Целевые пользователи и выгодоприобретатели",
    "Пользователь — клиентский менеджер. Выгодоприобретатели — члены кредитного комитета.",
    "",
    "## Текущий процесс и точки потерь",
    "Сейчас вручную собираю данные из выгрузки и формирую one-page в Word.",
    "",
    "## Входные данные и примеры",
    "Приложены файлы: demo-client-data.csv. Все данные синтетические.",
    "",
    "## Ожидаемые результаты",
    "Черновик результата.",
    "",
    "## Правила ветвления и исключения",
    "Пустые поля пропускаются.",
    "",
    "## Метрики успеха",
    "Скорость и качество.",
  ].join("\n"),
  topicAnswers: {
    problem: "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета.",
    target_users: "Пользователь — клиентский менеджер. Выгодоприобретатели — члены кредитного комитета.",
    current_workflow: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
    input_examples: "Приложены файлы: demo-client-data.csv. Все данные синтетические.",
    expected_outputs: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
    branching_rules: "Пустые поля пропускаются.",
    success_metrics: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
  },
  uploadedFiles: [{ name: "demo-client-data.csv", excerpt: "client_id,score,limit" }],
};

const revised = await reviseBrief(session, "Исправь: ожидаемый результат — это PDF one-page summary с рекомендацией по решению.");
syncSessionTopicAnswersFromBrief(session, revised);

console.log(JSON.stringify({
  revised,
  expected_outputs: session.topicAnswers.expected_outputs,
  current_workflow: session.topicAnswers.current_workflow,
  success_metrics: session.topicAnswers.success_metrics,
}, null, 2));
NODE
    then
        assert_contains "$(jq -r '.expected_outputs' "$tmpdir/brief-sync.json")" "PDF one-page summary" "Expected outputs should be synchronized from revised brief"
        assert_eq "Сейчас вручную собираю данные из выгрузки и формирую one-page в Word." "$(jq -r '.current_workflow' "$tmpdir/brief-sync.json")" "Untouched workflow section must stay synchronized from brief source of truth"
        assert_eq "Скорость и качество." "$(jq -r '.success_metrics' "$tmpdir/brief-sync.json")" "Untouched metrics section must stay synchronized from brief source of truth"
        test_pass
    else
        test_fail "Revised brief should become the source of truth for synchronized topic answers"
    fi

    test_start "component_agent_factory_web_brief_runtime_generates_one_page_from_confirmed_brief_not_stale_answers"
    if node --input-type=module >"$tmpdir/one-page-from-brief.json" <<'NODE'
import { generateArtifacts } from "./asc-demo/src/summary-generator.js";

const session = {
  sessionId: "web-demo-session-runtime",
  projectKey: "factory-credit-one-page",
  briefVersion: 2,
  briefText: [
    "# Brief проекта",
    "",
    "## Бизнес-проблема",
    "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета.",
    "",
    "## Целевые пользователи и выгодоприобретатели",
    "Пользователь — клиентский менеджер. Выгодоприобретатели — члены кредитного комитета.",
    "",
    "## Текущий процесс и точки потерь",
    "Сейчас вручную беру выгрузку, формирую one-page в Word и экспортирую в PDF.",
    "",
    "## Входные данные и примеры",
    "Приложены файлы: demo-client-data.csv. Все данные во вложениях синтетические и обезличенные.",
    "",
    "## Ожидаемые результаты",
    "PDF one-page summary с краткой рекомендацией по решению для кредитного комитета.",
    "",
    "## Правила ветвления и исключения",
    "Пустые поля пропускаются, персональные данные запрещены.",
    "",
    "## Метрики успеха",
    "Время подготовки one-page и количество ошибок в документе.",
  ].join("\n"),
  topicAnswers: {
    problem: "Автоматизировать подготовку подготовку материалов",
    target_users: "Пользователь — клиентский менеджер.",
    current_workflow: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
    input_examples: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
    expected_outputs: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
    branching_rules: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
    success_metrics: "УСТАРЕВШЕЕ ЗНАЧЕНИЕ",
  },
  uploadedFiles: [{ name: "demo-client-data.csv", excerpt: "client_id,score,limit\nSYN-100,701,250000" }],
};

const artifacts = await generateArtifacts(session);
const onePage = artifacts.find((item) => item.artifact_kind === "one_page_summary");

console.log(JSON.stringify({
  one_page_summary: onePage?.content || "",
}, null, 2));
NODE
    then
        assert_contains "$(jq -r '.one_page_summary' "$tmpdir/one-page-from-brief.json")" "PDF one-page summary с краткой рекомендацией" "One-page should reflect the corrected confirmed brief outputs"
        assert_contains "$(jq -r '.one_page_summary' "$tmpdir/one-page-from-brief.json")" "Сейчас вручную беру выгрузку, формирую one-page в Word и экспортирую в PDF." "One-page should reflect corrected current workflow from brief"
        assert_contains "$(jq -r '.one_page_summary' "$tmpdir/one-page-from-brief.json")" "Время подготовки one-page и количество ошибок в документе." "One-page should reflect corrected metrics from brief"
        assert_eq "false" "$(jq -r '.one_page_summary | contains("УСТАРЕВШЕЕ ЗНАЧЕНИЕ")' "$tmpdir/one-page-from-brief.json")" "One-page must not leak stale topicAnswers once confirmed brief exists"
        test_pass
    else
        test_fail "Artifact generation should prefer confirmed brief over stale discovery answers"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_brief_runtime_tests
fi
