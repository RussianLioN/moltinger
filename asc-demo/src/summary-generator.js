import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chatCompletion, isLLMConfigured } from "./llm.js";
import { normalizeText } from "./utils.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SECTION_CONFIG = [
  {
    artifactKey: "client_info",
    title: "ИНФОРМАЦИЯ ПО КЛИЕНТУ",
    promptFile: "client-info.md",
    dataSelector: (data) => data.client || {},
  },
  {
    artifactKey: "deal_info",
    title: "ИНФОРМАЦИЯ ПО СДЕЛКЕ",
    promptFile: "deal-info.md",
    dataSelector: (data) => data.deal || {},
  },
  {
    artifactKey: "pricing_info",
    title: "ЦЕНООБРАЗОВАНИЕ И ДОХОДНОСТЬ",
    promptFile: "pricing-info.md",
    dataSelector: (data) => ({ pricing: data.pricing || {}, potential: data.potential || {} }),
  },
  {
    artifactKey: "cooperation_info",
    title: "АНАЛИЗ СОТРУДНИЧЕСТВА И ВКЛАДА",
    promptFile: "cooperation-info.md",
    dataSelector: (data) => ({ cooperation: data.cooperation || {}, potential: data.potential || {} }),
  },
];

async function loadPrompt(promptFile) {
  const promptPath = path.join(__dirname, "prompts", promptFile);
  return fs.readFile(promptPath, "utf-8");
}

async function loadDemoData() {
  const demoPath = path.join(__dirname, "demo-data", "boku-do-manzh.json");
  const raw = await fs.readFile(demoPath, "utf-8");
  return JSON.parse(raw);
}

function fallbackSection(title, sectionData) {
  const entries = Object.entries(sectionData || {});
  const lines = [`## ${title}`, ""];
  if (!entries.length) {
    lines.push("Данные секции отсутствуют в демо-наборе.");
    return lines.join("\n");
  }
  lines.push(`Раздел собран в fallback-режиме. Количество полей: ${entries.length}.`);
  lines.push("");
  entries.slice(0, 10).forEach(([key, value]) => {
    lines.push(`- ${key}: ${normalizeText(value, "-")}`);
  });
  return lines.join("\n");
}

async function generateSection(config, demoData) {
  const sectionData = config.dataSelector(demoData);
  if (!isLLMConfigured()) {
    return fallbackSection(config.title, sectionData);
  }
  const prompt = await loadPrompt(config.promptFile);
  const messages = [
    { role: "system", content: prompt },
    {
      role: "user",
      content: [
        "Структурированные данные:",
        JSON.stringify(sectionData, null, 2),
      ].join("\n"),
    },
  ];
  try {
    const completion = await chatCompletion(messages, { temperature: 0.15, maxTokens: 2200 });
    const normalized = normalizeText(completion);
    if (!normalized) {
      return fallbackSection(config.title, sectionData);
    }
    return normalized.includes(config.title)
      ? normalized
      : [`## ${config.title}`, "", normalized].join("\n");
  } catch (error) {
    console.error("[asc-demo] summary.generateSection:", error?.message || error);
    return fallbackSection(config.title, sectionData);
  }
}

function buildProjectDoc(session) {
  const lines = [
    "# Project Doc",
    "",
    `Session ID: ${session.sessionId}`,
    `Project Key: ${session.projectKey || "factory-demo"}`,
    `Brief Version: v${session.briefVersion || 1}`,
    "",
    "## Scope",
    "Документ собран из confirmed brief и discovery-истории для последующей передачи в фабрику.",
    "",
    "## Brief Snapshot",
    normalizeText(session.briefText, "Brief пока отсутствует."),
  ];
  return lines.join("\n");
}

function buildAgentSpec(session) {
  const lines = [
    "# Agent Spec",
    "",
    "## Роль агента",
    "Агент-архитектор Moltis, ведущий бизнес-discovery и подготовку handoff-пакета.",
    "",
    "## Контракт входов",
    "- Пользовательские сообщения",
    "- Приложенные файлы",
    "- Корректировки brief",
    "",
    "## Контракт выходов",
    "- Confirmed brief",
    "- One-page summary",
    "- Project doc / Agent spec / Presentation",
    "",
    "## Текущая версия brief",
    normalizeText(session.briefText, "Brief пока отсутствует."),
  ];
  return lines.join("\n");
}

function buildPresentation(session) {
  const lines = [
    "# Presentation",
    "",
    "## Слайд 1 — Проблема",
    normalizeText(session.topicAnswers?.problem, "Требуется уточнение."),
    "",
    "## Слайд 2 — Пользователи и процесс",
    `Пользователь: ${normalizeText(session.topicAnswers?.target_users, "Требуется уточнение.")}`,
    `Текущий процесс: ${normalizeText(session.topicAnswers?.current_workflow, "Требуется уточнение.")}`,
    "",
    "## Слайд 3 — Решение и метрики",
    `Ожидаемый результат: ${normalizeText(session.topicAnswers?.expected_outputs, "Требуется уточнение.")}`,
    `Метрики: ${normalizeText(session.topicAnswers?.success_metrics, "Требуется уточнение.")}`,
    "",
    "## Слайд 4 — Статус",
    `Confirmed brief: v${session.briefVersion || 1}`,
    "Артефакты готовы к защите концепции.",
  ];
  return lines.join("\n");
}

function hasUsableUploadData(session) {
  const uploads = session.uploadedFiles || [];
  return uploads.some((file) => normalizeText(file.excerpt).length > 20);
}

function buildSessionContext(session) {
  const lines = [];
  const brief = normalizeText(session.briefText);
  if (brief) {
    lines.push("## Confirmed Brief", "", brief);
  }
  const answers = session.topicAnswers || {};
  const answeredTopics = Object.entries(answers).filter(([, v]) => normalizeText(v));
  if (answeredTopics.length) {
    lines.push("", "## Discovery Answers");
    answeredTopics.forEach(([topic, answer]) => {
      lines.push(`### ${topic}`, normalizeText(answer), "");
    });
  }
  const uploads = (session.uploadedFiles || []).filter((f) => normalizeText(f.excerpt));
  if (uploads.length) {
    lines.push("", "## Uploaded Data Excerpts");
    uploads.forEach((file) => {
      lines.push(`### ${normalizeText(file.name, "file")}`, normalizeText(file.excerpt).slice(0, 800), "");
    });
  }
  return lines.join("\n");
}

async function generateOnePageFromSession(session) {
  const context = buildSessionContext(session);
  if (!isLLMConfigured()) {
    return fallbackOnePageFromSession(session);
  }
  const messages = [
    {
      role: "system",
      content: [
        "Ты агент-архитектор Moltis. Сформируй one-page summary на русском языке по результатам discovery.",
        "Структура документа:",
        "# One-page Summary",
        "## Бизнес-проблема и цель автоматизации",
        "## Целевые пользователи и текущий процесс",
        "## Входные данные и ожидаемые результаты",
        "## Ключевые правила, метрики и критерии успеха",
        "",
        "Используй ТОЛЬКО факты из предоставленного контекста. Не придумывай данных.",
        "Если в контексте есть загруженные файлы (CSV/Excel), используй ключевые поля и структуру данных для обогащения разделов.",
        "Деловой стиль, без JSON, без пояснений вне markdown.",
      ].join("\n"),
    },
    {
      role: "user",
      content: context,
    },
  ];
  try {
    const completion = await chatCompletion(messages, { temperature: 0.15, maxTokens: 2400 });
    const normalized = normalizeText(completion);
    return normalized || fallbackOnePageFromSession(session);
  } catch (error) {
    console.error("[asc-demo] summary.generateOnePageFromSession:", error?.message || error);
    return fallbackOnePageFromSession(session);
  }
}

function fallbackOnePageFromSession(session) {
  const answers = session.topicAnswers || {};
  const lines = [
    "# One-page Summary",
    "",
    "## Бизнес-проблема и цель автоматизации",
    normalizeText(answers.problem, "Данные отсутствуют."),
    "",
    "## Целевые пользователи и текущий процесс",
    `Пользователи: ${normalizeText(answers.target_users, "Не указаны.")}`,
    `Текущий процесс: ${normalizeText(answers.current_workflow, "Не описан.")}`,
    "",
    "## Входные данные и ожидаемые результаты",
    `Входы: ${normalizeText(answers.input_examples, "Не указаны.")}`,
    `Выходы: ${normalizeText(answers.expected_outputs, "Не указаны.")}`,
    "",
    "## Ключевые правила, метрики и критерии успеха",
    `Правила: ${normalizeText(answers.branching_rules, "Не указаны.")}`,
    `Метрики: ${normalizeText(answers.success_metrics, "Не указаны.")}`,
  ];
  const uploads = (session.uploadedFiles || []).filter((f) => normalizeText(f.excerpt));
  if (uploads.length) {
    lines.push("", "## Приложенные данные");
    uploads.forEach((file) => {
      lines.push(`- ${normalizeText(file.name, "файл")}: ${normalizeText(file.excerpt).slice(0, 300)}`);
    });
  }
  return lines.join("\n");
}

async function generateOnePageWithDemoData(session) {
  let demoData;
  try {
    demoData = await loadDemoData();
  } catch (_error) {
    return fallbackOnePageFromSession(session);
  }
  const sections = await Promise.all(
    SECTION_CONFIG.map((config) => generateSection(config, demoData)),
  );
  return ["# One-page Summary", "", ...sections].join("\n\n");
}

export async function generateArtifacts(session) {
  const useSessionData = normalizeText(session.briefText) || hasUsableUploadData(session);
  const onePageSummary = useSessionData
    ? await generateOnePageFromSession(session)
    : await generateOnePageWithDemoData(session);

  return [
    {
      artifact_kind: "one_page_summary",
      download_name: "one-page-summary.md",
      download_status: "ready",
      description: useSessionData
        ? "One-page summary на основе discovery и brief пользователя."
        : "One-page summary на основе демо-данных клиента «Боку до манж».",
      content: onePageSummary,
    },
    {
      artifact_kind: "project_doc",
      download_name: "project-doc.md",
      download_status: "ready",
      description: "Проектный документ из confirmed brief.",
      content: buildProjectDoc(session),
    },
    {
      artifact_kind: "agent_spec",
      download_name: "agent-spec.md",
      download_status: "ready",
      description: "Спецификация целевого агента по результатам discovery.",
      content: buildAgentSpec(session),
    },
    {
      artifact_kind: "presentation",
      download_name: "presentation.md",
      download_status: "ready",
      description: "Шаблон презентации для защиты концепции.",
      content: buildPresentation(session),
    },
  ];
}
