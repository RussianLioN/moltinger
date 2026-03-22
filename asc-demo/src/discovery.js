import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chatCompletionJSON, isLLMConfigured } from "./llm.js";
import { normalizeText } from "./utils.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const DISCOVERY_TOPICS = [
  {
    id: "problem",
    question: "Какую бизнес-проблему должен решить будущий агент?",
    why: "Нужно зафиксировать ценность автоматизации и целевой эффект.",
    signals: ["проблем", "боль", "долго", "ошиб", "срок", "узкое место", "автомат", "сократ", "ускор", "уходит"],
  },
  {
    id: "target_users",
    question: "Кто основной пользователь или выгодоприобретатель результата?",
    why: "Нужно понимать, для кого проектируем сценарий и интерфейс.",
    signals: ["пользоват", "клиент", "комитет", "отдел", "команда", "роль", "менеджер", "выгодоприобрет"],
  },
  {
    id: "current_workflow",
    question: "Как процесс устроен сейчас и на каком шаге возникают потери?",
    why: "Нужно зафиксировать текущий процесс, чтобы измерять улучшение.",
    signals: ["сейчас", "вруч", "excel", "этап", "процесс", "согласован"],
  },
  {
    id: "input_examples",
    question: "Какие входные данные или кейсы агент получает на вход?",
    why: "Нужно понять формат входов для корректной обработки и тестов.",
    signals: ["вход", "данн", "файл", "заявк", "документ", "пример", "csv", "выгруз", "excel"],
  },
  {
    id: "expected_outputs",
    question: "Какой результат должен быть на выходе, в каком формате и с какими обязательными блоками?",
    why: "Нужно зафиксировать формат и структуру ожидаемого output будущего агента.",
    signals: ["выход", "результ", "отчет", "карточк", "summary", "рекомендац", "pdf", "презентац", "материал"],
  },
  {
    id: "branching_rules",
    question: "Какие ветвления, исключения, бизнес-правила и алгоритм обработки нужно учесть?",
    why: "Нужно собрать edge-cases и правила принятия решения/обработки данных.",
    signals: ["если", "иначе", "исключ", "ветвл", "правил", "эскалац"],
  },
  {
    id: "success_metrics",
    question: "Как измерим успех автоматизации: время, качество, SLA или другие метрики?",
    why: "Нужны измеримые критерии, чтобы подтвердить эффективность решения.",
    signals: ["метрик", "kpi", "sla", "успех", "точност", "время"],
  },
];

const MIN_TOPICS_FOR_COMPLETION = DISCOVERY_TOPICS.length;
const REQUIRED_TOPICS = DISCOVERY_TOPICS.map((topic) => topic.id);
const LOW_SIGNAL_MARKERS = new Set(["ok", "okay", "test", "ping", "да", "нет", "ага", "понял"]);
const NON_ANSWER_MARKERS = [
  "давай продолжим",
  "продолжим",
  "дальше",
  "не понял",
  "не поняла",
  "перефразируй",
  "я уже отвечал",
  "это уже было",
  "пример чего",
  "уже прикрепил",
  "уже приложил",
  "файл уже прикреп",
  "файл уже прилож",
  "во вложении",
];
const SYNTHETIC_DATA_NOTE = "Все данные во вложениях считаются синтетическими: не относятся к реальным лицам/контрагентам, любые совпадения случайны.";
const SYNTHETIC_AFFIRMATION_MARKERS = [
  "синтет",
  "обезлич",
  "аноним",
  "без реальных реквизит",
  "без реальных данных",
  "совпадения случайны",
];
const FILE_ACK_MARKERS = [
  "уже прикреп",
  "уже прилож",
  "файл прикреп",
  "файл прилож",
  "во вложени",
  "прикрепил файл",
  "добавил файл",
  "см. влож",
];
const ALREADY_ANSWERED_MARKERS = [
  "уже отвечал",
  "уже отвечала",
  "дублирую",
  "повторяю",
  "ответ выше",
  "это уже было",
];
const TOPIC_ACKS = {
  problem: "Проблему зафиксировал.",
  target_users: "Пользователей и выгодоприобретателей зафиксировал.",
  current_workflow: "Текущий процесс зафиксировал.",
  input_examples: "Входные данные зафиксировал.",
  expected_outputs: "Ожидаемый результат зафиксировал.",
  branching_rules: "Правила и исключения зафиксировал.",
  success_metrics: "Метрики успеха зафиксировал.",
};

const RESULT_FORMAT_MARKERS = [
  "pdf",
  "docx",
  "ppt",
  "pptx",
  "xlsx",
  "csv",
  "json",
  "xml",
  "markdown",
  "md",
  "one-page",
  "onepage",
  "презентац",
  "таблиц",
  "карточ",
  "документ",
  "отчёт",
  "отчет",
];

const OUTPUT_STRUCTURE_MARKERS = [
  "структур",
  "раздел",
  "блок",
  "порядок",
  "обязательн",
  "включать",
  "содержать",
  "шаблон",
];

const PROCESSING_RULE_MARKERS = [
  "правил",
  "алгорит",
  "ветвл",
  "если",
  "иначе",
  "огранич",
  "запрет",
  "исключ",
  "эскалац",
  "провер",
  "валидац",
];

const QUALITY_METRIC_MARKERS = [
  "метрик",
  "kpi",
  "sla",
  "время",
  "точност",
  "ошиб",
  "качеств",
  "%",
  "доля",
  "сократ",
];

const TOPIC_VALIDATION_MARKERS = {
  problem: ["проблем", "боль", "долго", "ошиб", "автомат", "сократ", "ускор", "потер"],
  target_users: ["пользоват", "клиент", "роль", "команда", "выгодоприобрет", "менеджер", "комитет"],
  current_workflow: ["процесс", "сейчас", "шаг", "этап", "вруч", "excel", "word", "pdf", "выгруз", "сверк"],
  input_examples: ["вход", "данн", "файл", "пример", "csv", "json", "xlsx", "выгруз", "документ"],
  expected_outputs: [...RESULT_FORMAT_MARKERS, ...OUTPUT_STRUCTURE_MARKERS],
  branching_rules: PROCESSING_RULE_MARKERS,
  success_metrics: QUALITY_METRIC_MARKERS,
};

const CONTRACT_FOLLOWUP_BY_GAP = {
  result_format: {
    topicId: "expected_outputs",
    question: "Уточни формат итогового результата: PDF, DOCX, Markdown, презентация или другой конкретный формат?",
    why: "Без чёткого формата невозможно корректно зафиксировать контракт результата.",
  },
  output_structure: {
    topicId: "expected_outputs",
    question: "Какие обязательные блоки должен содержать итоговый материал на выходе?",
    why: "Нужно зафиксировать структуру результата, чтобы генерация была предсказуемой.",
  },
  processing_rules: {
    topicId: "branching_rules",
    question: "По каким правилам или алгоритму агент обрабатывает входные данные и принимает решения?",
    why: "Нужно зафиксировать правила обработки до перехода к подтверждению brief.",
  },
  quality_criteria: {
    topicId: "success_metrics",
    question: "Какие измеримые критерии качества результата фиксируем для запуска?",
    why: "Подтверждение brief требует явных критериев качества и измеримости.",
  },
};

let cachedSystemPrompt = null;

function toWordList(text) {
  return normalizeText(text)
    .toLowerCase()
    .split(/\s+/)
    .map((word) => word.trim())
    .filter(Boolean);
}

function isLowSignal(userText, uploadedFiles = []) {
  if (Array.isArray(uploadedFiles) && uploadedFiles.length > 0) {
    return false;
  }
  const normalized = normalizeText(userText).toLowerCase();
  if (!normalized) {
    return true;
  }
  if (LOW_SIGNAL_MARKERS.has(normalized)) {
    return true;
  }
  const words = toWordList(normalized);
  return words.length <= 2 && normalized.length < 24;
}

function getTopicById(topicId) {
  return DISCOVERY_TOPICS.find((topic) => topic.id === topicId) || null;
}

function computeMissing(coveredTopics) {
  const covered = coveredTopics instanceof Set ? coveredTopics : new Set(coveredTopics || []);
  return DISCOVERY_TOPICS.filter((topic) => !covered.has(topic.id));
}

function heuristicCoverage(userText, uploadedFiles = []) {
  const covered = new Set();
  const text = normalizeText(userText).toLowerCase();
  DISCOVERY_TOPICS.forEach((topic) => {
    if (topic.signals.some((signal) => text.includes(signal))) {
      covered.add(topic.id);
    }
  });
  if ((uploadedFiles || []).length > 0) {
    covered.add("input_examples");
  }
  return covered;
}

function completionReached(coveredTopics) {
  const covered = coveredTopics instanceof Set ? coveredTopics : new Set(coveredTopics || []);
  if (covered.size < MIN_TOPICS_FOR_COMPLETION) {
    return false;
  }
  return REQUIRED_TOPICS.every((topicId) => covered.has(topicId));
}

function defaultQuestion(coveredTopics) {
  const missing = computeMissing(coveredTopics);
  const next = missing[0] || null;
  if (!next) {
    return {
      nextTopic: "",
      nextQuestion: "Discovery завершён. Переходим к формированию brief.",
      whyAskingNow: "",
      missingCoverage: [],
    };
  }
  return {
    nextTopic: next.id,
    nextQuestion: next.question,
    whyAskingNow: next.why,
    missingCoverage: missing.map((topic) => topic.id),
  };
}

function lowSignalQuestion(coveredTopics) {
  const fallback = defaultQuestion(coveredTopics);
  const lead = fallback.nextTopic === "problem"
    ? "Описание предмета автоматизации пока слишком общее."
    : "Ответ пока слишком общий.";
  return `${lead} ${fallback.nextQuestion}`;
}

function buildUploadedFilesAnswer(uploadedFiles = []) {
  const files = (uploadedFiles || [])
    .map((file) => normalizeText(file?.name))
    .filter(Boolean);
  if (!files.length) {
    return "";
  }
  return `Приложены файлы: ${files.join(", ")}. ${SYNTHETIC_DATA_NOTE}`;
}

function isNoisyInputExamplesAnswer(value) {
  const normalized = normalizeText(value).toLowerCase();
  if (!normalized) {
    return true;
  }
  if (normalized.length < 28) {
    return true;
  }
  if (hasFileAcknowledgement(normalized) || hasSyntheticAffirmation(normalized) || hasAlreadyAnsweredMarker(normalized)) {
    return true;
  }
  return /^(да|нет|ок|okay|понял|поняла|продолжим|давай продолжим)\b/.test(normalized);
}

function canonicalInputExamplesAnswer(session, userText, uploadedFiles = []) {
  const fromCurrentUploads = buildUploadedFilesAnswer(uploadedFiles);
  if (fromCurrentUploads) {
    return fromCurrentUploads;
  }

  const fromSessionUploads = buildUploadedFilesAnswer(session.uploadedFiles || []);
  if (fromSessionUploads) {
    return fromSessionUploads;
  }

  const normalizedText = normalizeText(userText);
  const lowerText = normalizedText.toLowerCase();
  if (!normalizedText || hasFileAcknowledgement(lowerText) || hasSyntheticAffirmation(lowerText)) {
    return `Входные данные подтверждены пользователем как обезличенные. ${SYNTHETIC_DATA_NOTE}`;
  }
  return normalizedText;
}

function syncTopicAnswers(session, userText, topicsToSync, uploadedFiles = []) {
  const text = normalizeText(userText);
  const effectiveText = text || buildUploadedFilesAnswer(uploadedFiles);
  const hasFiles = Array.isArray(uploadedFiles) && uploadedFiles.length > 0;
  const syncTopics = topicsToSync instanceof Set ? topicsToSync : new Set(topicsToSync || []);
  if (hasFiles) {
    syncTopics.add("input_examples");
  }
  if (!effectiveText) {
    return;
  }
  syncTopics.forEach((topicId) => {
    if (!topicId || !getTopicById(topicId)) {
      return;
    }
    if (topicId === "input_examples") {
      const existing = normalizeText(session.topicAnswers?.input_examples);
      const shouldReplaceExisting = !existing
        || isNoisyInputExamplesAnswer(existing)
        || (hasFiles && !/приложены файлы/i.test(existing));
      if (shouldReplaceExisting) {
        session.topicAnswers.input_examples = canonicalInputExamplesAnswer(session, userText, uploadedFiles);
      }
      return;
    }
    if (!session.topicAnswers[topicId]) {
      session.topicAnswers[topicId] = effectiveText;
    }
  });
}

function hasTopicEvidence(topicId, lowerText, uploadedFiles = []) {
  const text = normalizeText(lowerText).toLowerCase();
  const hasFiles = Array.isArray(uploadedFiles) && uploadedFiles.length > 0;
  if (!topicId) {
    return false;
  }
  if (topicId === "input_examples") {
    return hasFiles || hasAnyMarker(text, TOPIC_VALIDATION_MARKERS.input_examples) || hasFileAcknowledgement(text);
  }
  if (!text) {
    return false;
  }
  const markers = TOPIC_VALIDATION_MARKERS[topicId] || [];
  if (hasAnyMarker(text, markers)) {
    return true;
  }
  if (topicId === "problem") {
    return text.length >= 42 && /(нужн|важн|автомат|проблем|ошиб|время|долго|срок)/i.test(text);
  }
  if (topicId === "current_workflow") {
    return text.length >= 42 && /(сейчас|процесс|шаг|этап|вруч|дела|формир|экспорт|соглас)/i.test(text);
  }
  if (topicId === "expected_outputs") {
    return text.length >= 36 && /(выход|результ|должен|получ|формат|pdf|docx|ppt|summary|one-page)/i.test(text);
  }
  if (topicId === "branching_rules") {
    return text.length >= 24 && /(если|иначе|правил|огранич|исключ|алгорит|эскала)/i.test(text);
  }
  if (topicId === "success_metrics") {
    return text.length >= 18 && /(метрик|kpi|sla|время|ошиб|качеств|доля|%|точност)/i.test(text);
  }
  if (topicId === "target_users") {
    return text.length >= 16 && /(пользоват|роль|клиент|комитет|менеджер|выгодоприобрет)/i.test(text);
  }
  return false;
}

function isLikelyNonAnswerText(lowerText) {
  if (!lowerText) {
    return false;
  }
  return NON_ANSWER_MARKERS.some((marker) => lowerText.includes(marker));
}

function hasSyntheticAffirmation(lowerText) {
  if (!lowerText) {
    return false;
  }
  return SYNTHETIC_AFFIRMATION_MARKERS.some((marker) => lowerText.includes(marker));
}

function hasFileAcknowledgement(lowerText) {
  if (!lowerText) {
    return false;
  }
  return FILE_ACK_MARKERS.some((marker) => lowerText.includes(marker));
}

function hasAlreadyAnsweredMarker(lowerText) {
  if (!lowerText) {
    return false;
  }
  return ALREADY_ANSWERED_MARKERS.some((marker) => lowerText.includes(marker));
}

function sanitizeNextQuestion(rawQuestion, fallbackQuestion) {
  const fallback = normalizeText(fallbackQuestion);
  const text = normalizeText(rawQuestion, fallback);
  if (!text) {
    return fallback;
  }

  const lines = text.split("\n").map((line) => normalizeText(line)).filter(Boolean);
  let candidate = lines.length ? lines[lines.length - 1] : text;
  const questionSentence = candidate
    .split(/(?<=[.?!])\s+/)
    .map((part) => normalizeText(part))
    .filter(Boolean)
    .reverse()
    .find((part) => part.includes("?"));
  if (questionSentence) {
    candidate = questionSentence;
  }

  return candidate.includes("?") ? candidate : fallback;
}

function hasAnyMarker(text, markers = []) {
  const lower = normalizeText(text).toLowerCase();
  if (!lower) {
    return false;
  }
  return markers.some((marker) => lower.includes(marker));
}

function normalizeCoveredTopics(rawCoveredTopics) {
  if (!Array.isArray(rawCoveredTopics)) {
    return [];
  }
  return rawCoveredTopics
    .map((topicId) => normalizeText(topicId))
    .filter((topicId, index, all) => Boolean(getTopicById(topicId)) && all.indexOf(topicId) === index);
}

function compactSummary(text, fallback = "не указан") {
  const normalized = normalizeText(text, fallback);
  if (normalized.length <= 140) {
    return normalized;
  }
  return `${normalized.slice(0, 137)}...`;
}

function detectResultFormat(answer) {
  const lower = normalizeText(answer).toLowerCase();
  if (!lower) {
    return "";
  }
  if (lower.includes("pdf")) {
    return "PDF";
  }
  if (lower.includes("docx") || lower.includes("word")) {
    return "DOCX/Word";
  }
  if (lower.includes("ppt") || lower.includes("презентац")) {
    return "PPT/Presentation";
  }
  if (lower.includes("markdown") || /\bmd\b/.test(lower)) {
    return "Markdown";
  }
  if (lower.includes("json")) {
    return "JSON";
  }
  if (lower.includes("csv")) {
    return "CSV";
  }
  if (lower.includes("таблиц") || lower.includes("xlsx")) {
    return "Table/XLSX";
  }
  if (lower.includes("one-page") || lower.includes("onepage")) {
    return "One-page document";
  }
  if (lower.includes("документ")) {
    return "Document";
  }
  return "";
}

export function evaluateDiscoveryContract(session) {
  const expectedOutputs = normalizeText(session?.topicAnswers?.expected_outputs);
  const branchingRules = normalizeText(session?.topicAnswers?.branching_rules);
  const successMetrics = normalizeText(session?.topicAnswers?.success_metrics);
  const resultFormat = detectResultFormat(expectedOutputs);
  const outputStructureReady = expectedOutputs.length >= 48 || hasAnyMarker(expectedOutputs, OUTPUT_STRUCTURE_MARKERS);
  const processingRulesReady = branchingRules.length >= 24 || hasAnyMarker(branchingRules, PROCESSING_RULE_MARKERS);
  const qualityCriteriaReady = successMetrics.length >= 18 || hasAnyMarker(successMetrics, QUALITY_METRIC_MARKERS);
  const resultFormatReady = Boolean(resultFormat) || hasAnyMarker(expectedOutputs, RESULT_FORMAT_MARKERS);

  const missing = [];
  if (!resultFormatReady) {
    missing.push("result_format");
  }
  if (!outputStructureReady) {
    missing.push("output_structure");
  }
  if (!processingRulesReady) {
    missing.push("processing_rules");
  }
  if (!qualityCriteriaReady) {
    missing.push("quality_criteria");
  }

  const followups = missing
    .map((gapId) => ({ gapId, ...(CONTRACT_FOLLOWUP_BY_GAP[gapId] || {}) }))
    .filter((item) => item.topicId && item.question);

  return {
    ready: followups.length === 0,
    missing,
    followups,
    summary: {
      result_format: resultFormat || compactSummary(expectedOutputs),
      output_structure: compactSummary(expectedOutputs),
      processing_rules: compactSummary(branchingRules),
      quality_criteria: compactSummary(successMetrics),
    },
  };
}

function finalizeDiscoveryStep(session, step, userText, uploadedFiles = []) {
  const normalizedText = normalizeText(userText);
  const lowerText = normalizedText.toLowerCase();
  const hasText = Boolean(normalizedText);
  const hasFiles = Array.isArray(uploadedFiles) && uploadedFiles.length > 0;
  const currentTopicId = normalizeText(session.currentTopic);
  const coveredCount = session.coveredTopics instanceof Set
    ? session.coveredTopics.size
    : new Set(session.coveredTopics || []).size;
  const noCoveredTopics = coveredCount === 0;
  const inferredInitialTopicId = !currentTopicId && noCoveredTopics ? "problem" : "";
  const activeTopic = getTopicById(currentTopicId || inferredInitialTopicId);
  const alreadyAnsweredCurrentTopic = Boolean(
    activeTopic
    && session.topicAnswers?.[activeTopic.id]
    && hasAlreadyAnsweredMarker(lowerText),
  );
  const activeTopicHasEvidence = activeTopic
    ? hasTopicEvidence(activeTopic.id, lowerText, uploadedFiles)
    : false;
  const meaningfulTextForCurrentTopic = hasText
    && !isLikelyNonAnswerText(lowerText)
    && (!activeTopic || activeTopicHasEvidence);
  const activeTopicCoveredByText = meaningfulTextForCurrentTopic
    || alreadyAnsweredCurrentTopic
    || Boolean(
      activeTopic
      && activeTopic.id === "input_examples"
      && hasText
      && (hasFileAcknowledgement(lowerText) || hasSyntheticAffirmation(lowerText)),
    );
  const activeTopicCoveredByFiles = Boolean(activeTopic && activeTopic.id === "input_examples" && hasFiles);
  const activeTopicCovered = activeTopicCoveredByText || activeTopicCoveredByFiles;

  if (hasFiles) {
    step.coveredTopics.add("input_examples");
  }

  const isLastUncoveredTopic = activeTopic
    && computeMissing(step.coveredTopics).length === 1
    && !step.coveredTopics.has(activeTopic.id);
  const forceLastTopicCoverage = !step.lowSignal && isLastUncoveredTopic && hasText;

  if (!step.lowSignal && activeTopic && (activeTopicCovered || forceLastTopicCoverage)) {
    step.coveredTopics.add(activeTopic.id);
  }

  const fallback = defaultQuestion(step.coveredTopics);
  let nextTopic = getTopicById(step.nextTopic) ? step.nextTopic : fallback.nextTopic;
  if (step.lowSignal && activeTopic) {
    nextTopic = activeTopic.id;
  }

  const shouldSkipInputExamplesReask = nextTopic === "input_examples"
    && step.coveredTopics.has("input_examples")
    && !hasFiles;
  if (shouldSkipInputExamplesReask) {
    const forced = forceNextUncoveredTopic("input_examples", step.coveredTopics);
    nextTopic = forced.nextTopic;
  }

  const nextTopicMeta = getTopicById(nextTopic);
  const whyAskingNow = nextTopicMeta?.why || fallback.whyAskingNow;
  const fallbackQuestion = nextTopicMeta?.question || fallback.nextQuestion;
  const adaptiveQuestion = sanitizeNextQuestion(step.nextQuestion, fallbackQuestion);
  const needsTopicClarification = Boolean(
    activeTopic
    && hasText
    && !step.lowSignal
    && !activeTopicCovered
    && !hasFiles,
  );
  const nextQuestion = needsTopicClarification
    ? `Ответ пока не закрыл текущий вопрос. Уточни, пожалуйста: ${activeTopic.question}`
    : step.lowSignal
    ? `Ответ пока слишком общий. Уточни, пожалуйста: ${fallbackQuestion}`
    : adaptiveQuestion;

  return {
    ...step,
    nextTopic,
    nextQuestion,
    whyAskingNow,
    missingCoverage: computeMissing(step.coveredTopics).map((item) => item.id),
    acknowledgedTopic: !step.lowSignal && activeTopic && activeTopicCovered ? activeTopic.id : "",
    acknowledgementText: !step.lowSignal && activeTopic && activeTopicCovered
      ? (TOPIC_ACKS[activeTopic.id] || "Ответ зафиксировал.")
      : "",
  };
}

function forceNextUncoveredTopic(currentTopicId, coveredTopics) {
  const covered = coveredTopics instanceof Set ? coveredTopics : new Set(coveredTopics || []);
  const currentIndex = DISCOVERY_TOPICS.findIndex((topic) => topic.id === currentTopicId);
  if (currentIndex === -1) {
    return defaultQuestion(covered);
  }

  for (let offset = 1; offset <= DISCOVERY_TOPICS.length; offset += 1) {
    const topic = DISCOVERY_TOPICS[(currentIndex + offset) % DISCOVERY_TOPICS.length];
    if (!covered.has(topic.id)) {
      return {
        nextTopic: topic.id,
        nextQuestion: topic.question,
        whyAskingNow: topic.why,
        missingCoverage: computeMissing(covered).map((item) => item.id),
      };
    }
  }

  return defaultQuestion(covered);
}

function applyAntiLoopGuard(session, finalized) {
  const previousTopic = normalizeText(session.currentTopic);
  const previousQuestion = normalizeText(session.currentQuestion).toLowerCase();
  const nextQuestion = normalizeText(finalized.nextQuestion).toLowerCase();
  const repeatedTopic = previousTopic && finalized.nextTopic === previousTopic;
  const repeatedQuestion = previousQuestion && nextQuestion === previousQuestion;
  const previousTopicStillMissing = previousTopic && !finalized.coveredTopics.has(previousTopic);
  const reaskingCoveredTopic = finalized.nextTopic
    && finalized.coveredTopics.has(finalized.nextTopic);
  const anonymizedLoopQuestion = /обезлич|аноним|реквизит|контрагент|example-case/i.test(nextQuestion)
    && finalized.coveredTopics.has("input_examples");

  if (previousTopicStillMissing && (repeatedTopic || repeatedQuestion)) {
    return finalized;
  }

  if (!repeatedTopic && !repeatedQuestion && !reaskingCoveredTopic && !anonymizedLoopQuestion) {
    return finalized;
  }

  const forced = forceNextUncoveredTopic(previousTopic || finalized.nextTopic, finalized.coveredTopics);
  const forcedQuestion = normalizeText(forced.nextQuestion).toLowerCase();
  if (!forced.nextTopic || (forced.nextTopic === finalized.nextTopic && forcedQuestion === nextQuestion)) {
    return finalized;
  }

  return {
    ...finalized,
    nextTopic: forced.nextTopic,
    nextQuestion: forced.nextQuestion,
    whyAskingNow: forced.whyAskingNow,
    missingCoverage: forced.missingCoverage,
  };
}

async function getArchitectSystemPrompt() {
  if (cachedSystemPrompt) {
    return cachedSystemPrompt;
  }
  const promptPath = path.join(__dirname, "prompts", "architect-system.md");
  cachedSystemPrompt = await fs.readFile(promptPath, "utf-8");
  return cachedSystemPrompt;
}

function sanitizeLLMAnswer(data, coveredTopics) {
  const mergedCoverage = new Set(coveredTopics);
  normalizeCoveredTopics(data?.covered_topics).forEach((topicId) => {
    mergedCoverage.add(topicId);
  });

  const defaultNext = defaultQuestion(mergedCoverage);
  let nextTopic = getTopicById(data?.next_topic) ? data.next_topic : defaultNext.nextTopic;
  if (nextTopic && mergedCoverage.has(nextTopic)) {
    nextTopic = defaultNext.nextTopic;
  }
  const topic = getTopicById(nextTopic);
  const whyAskingNow = normalizeText(data?.why_asking_now, topic?.why || defaultNext.whyAskingNow);
  const nextQuestion = sanitizeNextQuestion(data?.next_question, topic?.question || defaultNext.nextQuestion);

  return {
    coveredTopics: mergedCoverage,
    nextTopic,
    nextQuestion,
    whyAskingNow,
    missingCoverage: computeMissing(mergedCoverage).map((item) => item.id),
    lowSignal: Boolean(data?.low_signal),
  };
}

async function llmDiscoveryStep(session, userText, uploadedFiles = []) {
  if (!isLLMConfigured()) {
    throw new Error("LLM_NOT_CONFIGURED");
  }
  const systemPrompt = await getArchitectSystemPrompt();
  const covered = Array.from(session.coveredTopics);
  const missing = computeMissing(session.coveredTopics).map((item) => item.id);
  const uploadContext = (uploadedFiles || [])
    .map((file) => `${file.name}: ${normalizeText(file.excerpt, "").slice(0, 300)}`)
    .join("\n");
  const uploadSafetyNote = uploadContext ? SYNTHETIC_DATA_NOTE : "Вложения не переданы.";

  const messages = [
    { role: "system", content: systemPrompt },
    {
      role: "user",
      content: [
        "Текущие covered_topics:",
        JSON.stringify(covered),
        "",
        "Текущие missing_topics:",
        JSON.stringify(missing),
        "",
        `Ответ пользователя: ${normalizeText(userText) || "(пусто)"}`,
        "",
        `Файлы (excerpt): ${uploadContext || "(нет файлов)"}`,
        "",
        `Комментарий по данным: ${uploadSafetyNote}`,
      ].join("\n"),
    },
  ];

  const data = await chatCompletionJSON(messages, { temperature: 0.1, maxTokens: 900 });
  return sanitizeLLMAnswer(data, session.coveredTopics);
}

function fallbackDiscoveryStep(session, userText, uploadedFiles = [], lowSignal) {
  const mergedCoverage = new Set(session.coveredTopics);
  if ((uploadedFiles || []).length > 0) {
    mergedCoverage.add("input_examples");
  }
  const fallback = defaultQuestion(mergedCoverage);
  return {
    coveredTopics: mergedCoverage,
    nextTopic: fallback.nextTopic,
    nextQuestion: lowSignal ? lowSignalQuestion(mergedCoverage) : fallback.nextQuestion,
    whyAskingNow: fallback.whyAskingNow,
    missingCoverage: fallback.missingCoverage,
    lowSignal,
  };
}

export function getDiscoveryTopics() {
  return DISCOVERY_TOPICS;
}

export async function processDiscoveryTurn(session, userText, uploadedFiles = []) {
  const lowSignal = isLowSignal(userText, uploadedFiles);
  const activeTopic = normalizeText(session.currentTopic);
  const previousCoverage = new Set(session.coveredTopics || []);
  const lowerText = normalizeText(userText).toLowerCase();
  const canTreatAsInputExamplesFollowup = lowSignal
    && activeTopic === "input_examples"
    && session.coveredTopics.has("input_examples")
    && (hasFileAcknowledgement(lowerText) || hasSyntheticAffirmation(lowerText));
  let step;
  if (canTreatAsInputExamplesFollowup) {
    step = fallbackDiscoveryStep(session, userText, uploadedFiles, false);
  } else if (lowSignal) {
    step = fallbackDiscoveryStep(session, userText, uploadedFiles, true);
  } else {
    try {
      step = await llmDiscoveryStep(session, userText, uploadedFiles);
      step.lowSignal = Boolean(step.lowSignal);
    } catch (error) {
      console.error("[asc-demo] discovery.llmDiscoveryStep:", error?.message || error);
      step = fallbackDiscoveryStep(session, userText, uploadedFiles, false);
    }
  }

  const finalized = applyAntiLoopGuard(
    session,
    finalizeDiscoveryStep(session, step, userText, uploadedFiles),
  );

  const newlyCoveredTopics = new Set(
    Array.from(finalized.coveredTopics).filter((topicId) => !previousCoverage.has(topicId)),
  );
  if (finalized.acknowledgedTopic) {
    newlyCoveredTopics.add(finalized.acknowledgedTopic);
  }
  if ((uploadedFiles || []).length > 0) {
    newlyCoveredTopics.add("input_examples");
  }

  session.coveredTopics = finalized.coveredTopics;
  syncTopicAnswers(session, userText, newlyCoveredTopics, uploadedFiles);
  session.currentQuestion = finalized.nextQuestion;
  session.currentTopic = finalized.nextTopic;
  session.whyAskingNow = finalized.whyAskingNow;
  session.missingCoverage = finalized.missingCoverage;

  const complete = !finalized.lowSignal && completionReached(finalized.coveredTopics);
  const coveredCount = finalized.coveredTopics.size;

  return {
    complete,
    coveredCount,
    totalCount: DISCOVERY_TOPICS.length,
    nextTopic: finalized.nextTopic,
    nextQuestion: finalized.nextQuestion,
    whyAskingNow: finalized.whyAskingNow,
    missingCoverage: finalized.missingCoverage,
    lowSignal: finalized.lowSignal,
    helperExample: getTopicById(finalized.nextTopic)?.question || "",
    acknowledgedTopic: finalized.acknowledgedTopic,
    acknowledgementText: finalized.acknowledgementText,
  };
}
