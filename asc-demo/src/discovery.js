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
    signals: ["проблем", "боль", "долго", "ошиб", "срок", "узкое место", "автомат"],
  },
  {
    id: "target_users",
    question: "Кто основной пользователь или выгодоприобретатель результата?",
    why: "Нужно понимать, для кого проектируем сценарий и интерфейс.",
    signals: ["пользоват", "клиент", "комитет", "отдел", "команда", "роль"],
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
    signals: ["вход", "данн", "файл", "заявк", "документ", "пример"],
  },
  {
    id: "expected_outputs",
    question: "Какой результат должен быть на выходе и в каком формате?",
    why: "Нужно зафиксировать ожидаемый output будущего агента.",
    signals: ["выход", "результ", "отчет", "карточк", "summary", "рекомендац"],
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

function syncTopicAnswers(session, userText, newCoverage) {
  const text = normalizeText(userText);
  if (!text) {
    return;
  }
  newCoverage.forEach((topicId) => {
    if (!session.topicAnswers[topicId]) {
      session.topicAnswers[topicId] = text;
    }
  });
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
  let step;
  if (lowSignal) {
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

  session.coveredTopics = step.coveredTopics;
  syncTopicAnswers(session, userText, step.coveredTopics);
  session.currentQuestion = step.nextQuestion;
  session.currentTopic = step.nextTopic;
  session.whyAskingNow = step.whyAskingNow;
  session.missingCoverage = step.missingCoverage;

  const complete = !step.lowSignal && completionReached(step.coveredTopics);
  const coveredCount = step.coveredTopics.size;

  return {
    complete,
    coveredCount,
    totalCount: DISCOVERY_TOPICS.length,
    nextTopic: step.nextTopic,
    nextQuestion: step.nextQuestion,
    whyAskingNow: step.whyAskingNow,
    missingCoverage: step.missingCoverage,
    lowSignal: step.lowSignal,
    helperExample: getTopicById(step.nextTopic)?.question || "",
  };
}
