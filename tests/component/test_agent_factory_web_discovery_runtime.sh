#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

run_component_agent_factory_web_discovery_runtime_tests() {
    start_timer
    require_commands_or_skip node jq || {
        test_start "component_agent_factory_web_discovery_runtime_prereqs"
        test_skip "node and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_web_discovery_runtime_does_not_smear_input_examples_from_workflow_turn"
    if node --input-type=module >"$tmpdir/no-smear.json" <<'NODE'
import { processDiscoveryTurn } from "./asc-demo/src/discovery.js";

const session = {
  coveredTopics: new Set(["problem", "target_users", "input_examples"]),
  topicAnswers: {
    problem: "Проблема зафиксирована",
    target_users: "Пользователи зафиксированы",
    current_workflow: "",
    input_examples: "",
    expected_outputs: "",
    branching_rules: "",
    success_metrics: "",
  },
  currentTopic: "current_workflow",
  currentQuestion: "Как процесс устроен сейчас?",
  whyAskingNow: "",
  missingCoverage: [],
  uploadedFiles: [],
};

await processDiscoveryTurn(
  session,
  "Сейчас беру выгрузку, вручную формирую one-page в Word и экспортирую в PDF.",
  [],
);

console.log(JSON.stringify({
  current_workflow: session.topicAnswers.current_workflow,
  input_examples: session.topicAnswers.input_examples,
}, null, 2));
NODE
    then
        assert_contains "$(jq -r '.current_workflow' "$tmpdir/no-smear.json")" "вручную формирую one-page" "Current workflow answer should be captured from workflow turn"
        assert_eq "" "$(jq -r '.input_examples' "$tmpdir/no-smear.json")" "Workflow turn must not auto-fill input_examples with process text"
        test_pass
    else
        test_fail "Runtime discovery should not smear workflow response into input_examples"
    fi

    test_start "component_agent_factory_web_discovery_runtime_keeps_file_based_input_examples_stable_after_followup"
    if node --input-type=module >"$tmpdir/file-stability.json" <<'NODE'
import { processDiscoveryTurn } from "./asc-demo/src/discovery.js";

const session = {
  coveredTopics: new Set(["problem", "target_users", "current_workflow"]),
  topicAnswers: {
    problem: "Проблема зафиксирована",
    target_users: "Пользователи зафиксированы",
    current_workflow: "Текущий процесс описан",
    input_examples: "",
    expected_outputs: "",
    branching_rules: "",
    success_metrics: "",
  },
  currentTopic: "input_examples",
  currentQuestion: "Какие входные данные получает агент?",
  whyAskingNow: "",
  missingCoverage: [],
  uploadedFiles: [],
};

const uploadedFiles = [{
  upload_id: "upload-1",
  name: "demo-client-data.csv",
  content_type: "text/csv",
  size_bytes: 44,
  original_size_bytes: 44,
  truncated: false,
  excerpt: "client_id,score,limit\\nSYN-100,701,250000\\n",
}];

await processDiscoveryTurn(session, "Прикрепил пример входных данных.", uploadedFiles);
const afterInputExamples = session.topicAnswers.input_examples;

session.currentTopic = "expected_outputs";
await processDiscoveryTurn(session, "На выходе нужен one-page PDF с рекомендацией.", []);

console.log(JSON.stringify({
  after_input_examples: afterInputExamples,
  final_input_examples: session.topicAnswers.input_examples,
  expected_outputs: session.topicAnswers.expected_outputs,
}, null, 2));
NODE
    then
        assert_contains "$(jq -r '.after_input_examples' "$tmpdir/file-stability.json")" "Приложены файлы: demo-client-data.csv." "Input examples should be captured from uploaded file context"
        assert_contains "$(jq -r '.after_input_examples' "$tmpdir/file-stability.json")" "синтетическими" "File-based input examples should keep synthetic-data disclaimer"
        assert_eq "$(jq -r '.after_input_examples' "$tmpdir/file-stability.json")" "$(jq -r '.final_input_examples' "$tmpdir/file-stability.json")" "Follow-up turn must not rewrite accepted file-based input examples"
        assert_contains "$(jq -r '.expected_outputs' "$tmpdir/file-stability.json")" "one-page PDF" "Expected outputs should be captured from dedicated expected_outputs turn"
        test_pass
    else
        test_fail "Runtime discovery should keep file-based input_examples stable after follow-up topics"
    fi

    test_start "component_agent_factory_web_discovery_runtime_reasks_when_answer_does_not_match_active_topic"
    if node --input-type=module >"$tmpdir/topic-mismatch.json" <<'NODE'
import { processDiscoveryTurn } from "./asc-demo/src/discovery.js";

const session = {
  coveredTopics: new Set(["problem", "target_users"]),
  topicAnswers: {
    problem: "Проблема зафиксирована",
    target_users: "Пользователи зафиксированы",
    current_workflow: "",
    input_examples: "",
    expected_outputs: "",
    branching_rules: "",
    success_metrics: "",
  },
  currentTopic: "current_workflow",
  currentQuestion: "Как процесс устроен сейчас и на каком шаге возникают потери?",
  whyAskingNow: "",
  missingCoverage: [],
  uploadedFiles: [],
};

const result = await processDiscoveryTurn(
  session,
  "Пользователь — клиентский менеджер. Выгодоприобретатели — члены кредитного комитета.",
  [],
);

console.log(JSON.stringify({
  covered_topics: Array.from(session.coveredTopics),
  current_workflow: session.topicAnswers.current_workflow,
  target_users: session.topicAnswers.target_users,
  next_topic: result.nextTopic,
  next_question: result.nextQuestion,
}, null, 2));
NODE
    then
        local covered_topics
        covered_topics="$(jq -r '.covered_topics | join(",")' "$tmpdir/topic-mismatch.json")"
        if [[ "$covered_topics" == *"current_workflow"* ]]; then
            test_fail "Current workflow must not be auto-covered by irrelevant answer"
        fi
        assert_eq "" "$(jq -r '.current_workflow' "$tmpdir/topic-mismatch.json")" "Mismatched answer must not populate current_workflow topic answer"
        assert_eq "current_workflow" "$(jq -r '.next_topic' "$tmpdir/topic-mismatch.json")" "Discovery should stay on the same topic when answer mismatches active topic"
        assert_contains "$(jq -r '.next_question' "$tmpdir/topic-mismatch.json")" "Ответ пока не закрыл текущий вопрос" "Mismatch should trigger clarification prompt"
        test_pass
    else
        test_fail "Runtime discovery should re-ask active topic on semantic mismatch"
    fi

    test_start "component_agent_factory_web_discovery_runtime_maps_answers_to_correct_topics"
    if node --input-type=module >"$tmpdir/topic-mapping.json" <<'NODE'
import { processDiscoveryTurn } from "./asc-demo/src/discovery.js";

const session = {
  coveredTopics: new Set(),
  topicAnswers: {
    problem: "",
    target_users: "",
    current_workflow: "",
    input_examples: "",
    expected_outputs: "",
    branching_rules: "",
    success_metrics: "",
  },
  currentTopic: "",
  currentQuestion: "",
  whyAskingNow: "",
  missingCoverage: [],
  uploadedFiles: [],
};

await processDiscoveryTurn(
  session,
  "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета.",
  [],
);

await processDiscoveryTurn(
  session,
  "Пользователь — клиентский менеджер; выгодоприобретатели — члены кредитного комитета.",
  [],
);

await processDiscoveryTurn(
  session,
  "Сейчас вручную формирую one-page из выгрузки в Word и экспортирую в PDF.",
  [],
);

await processDiscoveryTurn(
  session,
  "Прикладываю обезличенный синтетический пример входных данных.",
  [{
    upload_id: "upload-1",
    name: "demo-client-data.csv",
    content_type: "text/csv",
    size_bytes: 64,
    original_size_bytes: 64,
    truncated: false,
    excerpt: "client_id,score,limit\\nSYN-100,701,250000\\n",
  }],
);

await processDiscoveryTurn(
  session,
  "На выходе нужен PDF one-page summary с блоками факты, риски и рекомендация.",
  [],
);

await processDiscoveryTurn(
  session,
  "Если данных не хватает — эскалировать; иначе формировать итоговый документ.",
  [],
);

await processDiscoveryTurn(
  session,
  "Метрики: время подготовки one-page и количество ошибок в документе.",
  [],
);

console.log(JSON.stringify({
  answers: session.topicAnswers,
  covered_topics: Array.from(session.coveredTopics),
}, null, 2));
NODE
    then
        assert_contains "$(jq -r '.answers.problem' "$tmpdir/topic-mapping.json")" "Автоматизировать подготовку one-page summary" "Problem answer should stay in problem topic"
        assert_contains "$(jq -r '.answers.target_users' "$tmpdir/topic-mapping.json")" "Пользователь — клиентский менеджер" "Target users answer should stay in target_users topic"
        assert_contains "$(jq -r '.answers.current_workflow' "$tmpdir/topic-mapping.json")" "вручную формирую one-page" "Workflow answer should stay in current_workflow topic"
        assert_contains "$(jq -r '.answers.input_examples' "$tmpdir/topic-mapping.json")" "Приложены файлы: demo-client-data.csv." "Input examples should be captured from upload context"
        assert_contains "$(jq -r '.answers.expected_outputs' "$tmpdir/topic-mapping.json")" "PDF one-page summary" "Expected outputs should stay in expected_outputs topic"
        assert_contains "$(jq -r '.answers.branching_rules' "$tmpdir/topic-mapping.json")" "эскалировать" "Branching rules should stay in branching_rules topic"
        assert_contains "$(jq -r '.answers.success_metrics' "$tmpdir/topic-mapping.json")" "Метрики: время подготовки" "Metrics answer should stay in success_metrics topic"
        test_pass
    else
        test_fail "Runtime discovery should map topic answers without cross-topic pollution"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_web_discovery_runtime_tests
fi
