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
    question: "Какой результат должен быть на выходе и в каком формате?",
    why: "Нужно зафиксировать ожидаемый output будущего агента.",
    signals: ["выход", "результ", "отчет", "карточк", "summary", "рекомендац", "pdf", "презентац", "материал"],
  },
  {
    id: "branching_rules",
    question: "Какие ветвления, исключения и бизнес-правила нужно учесть?",
    why: "Нужно собрать edge-cases и правила принятия решения.",
    signals: ["если", "иначе", "исключ", "ветвл", "правил", "эскалац"],
  },
  {
    id: "success_metrics",
    question: "Как измерим успех автоматизации: время, качество, SLA или другие метрики?",
    why: "Нужны измеримые критерии, чтобы подтвердить эффективность решения.",
    signals: ["метрик", "kpi", "sla", "успех", "точност", "время"],
  },
];

const MIN_TOPICS_FOR_COMPLETION = 5;
const REQUIRED_TOPICS = ["problem", "target_users", "expected_outputs"];
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

function syncTopicAnswers(session, userText, newCoverage, uploadedFiles = []) {
  const text = normalizeText(userText);
  const effectiveText = text || buildUploadedFilesAnswer(uploadedFiles);
  if (!effectiveText) {
    return;
  }
  newCoverage.forEach((topicId) => {
    if (!session.topicAnswers[topicId]) {
      session.topicAnswers[topicId] = effectiveText;
    }
  });
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

function finalizeDiscoveryStep(session, step, userText, uploadedFiles = []) {
  const normalizedText = normalizeText(userText);
  const lowerText = normalizedText.toLowerCase();
  const hasText = Boolean(normalizedText);
  const hasFiles = Array.isArray(uploadedFiles) && uploadedFiles.length > 0;
  const activeTopic = getTopicById(session.currentTopic);
  const alreadyAnsweredCurrentTopic = Boolean(
    activeTopic
    && session.topicAnswers?.[activeTopic.id]
    && hasAlreadyAnsweredMarker(lowerText),
  );
  const meaningfulTextForCurrentTopic = hasText && !isLikelyNonAnswerText(lowerText);
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

  if (!step.lowSignal && activeTopic && activeTopicCovered) {
    step.coveredTopics.add(activeTopic.id);
  }

  const fallback = defaultQuestion(step.coveredTopics);
  let nextTopic = getTopicById(step.nextTopic) ? step.nextTopic : fallback.nextTopic;

  if (step.lowSignal) {
    if (activeTopic) {
      nextTopic = activeTopic.id;
    }
  } else if (nextTopic && step.coveredTopics.has(nextTopic)) {
    nextTopic = fallback.nextTopic;
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
  const nextQuestion = step.lowSignal
    ? `Ответ пока слишком общий. Уточни, пожалуйста: ${fallbackQuestion}`
    : sanitizeNextQuestion(step.nextQuestion, fallbackQuestion);

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
  const reaskingInputExamples = finalized.nextTopic === "input_examples"
    && finalized.coveredTopics.has("input_examples");
  const anonymizedLoopQuestion = /обезлич|аноним|реквизит|контрагент|example-case/i.test(nextQuestion)
    && finalized.coveredTopics.has("input_examples");

  if (!repeatedTopic && !repeatedQuestion && !reaskingInputExamples && !anonymizedLoopQuestion) {
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
  const llmCovered = Array.isArray(data?.covered_topics) ? data.covered_topics : [];
  llmCovered.forEach((topicId) => {
    if (getTopicById(topicId)) {
      mergedCoverage.add(topicId);
    }
  });

  const defaultNext = defaultQuestion(mergedCoverage);
  const nextTopic = getTopicById(data?.next_topic) ? data.next_topic : defaultNext.nextTopic;
  const topic = getTopicById(nextTopic);
  const whyAskingNow = normalizeText(data?.why_asking_now, topic?.why || defaultNext.whyAskingNow);
  const nextQuestion = normalizeText(data?.next_question, topic?.question || defaultNext.nextQuestion);

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
  const inferred = heuristicCoverage(userText, uploadedFiles);
  inferred.forEach((topicId) => mergedCoverage.add(topicId));
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

  session.coveredTopics = finalized.coveredTopics;
  syncTopicAnswers(session, userText, finalized.coveredTopics, uploadedFiles);
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
