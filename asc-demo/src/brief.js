import { chatCompletion, isLLMConfigured } from "./llm.js";
import { normalizeText } from "./utils.js";

const BRIEF_SECTION_ORDER = [
  ["problem", "Бизнес-проблема"],
  ["target_users", "Целевые пользователи и выгодоприобретатели"],
  ["current_workflow", "Текущий процесс и точки потерь"],
  ["input_examples", "Входные данные и примеры"],
  ["expected_outputs", "Ожидаемые результаты"],
  ["branching_rules", "Правила ветвления и исключения"],
  ["success_metrics", "Метрики успеха"],
];

function fallbackBrief(session) {
  const lines = ["# Brief проекта", ""];
  BRIEF_SECTION_ORDER.forEach(([topicId, title]) => {
    lines.push(`## ${title}`);
    lines.push(normalizeText(session.topicAnswers?.[topicId], "Требуется уточнение."));
    lines.push("");
  });
  lines.push("## Резюме");
  lines.push("Brief собран в fallback-режиме. Требуется дополнительная проверка перед передачей в производство.");
  return lines.join("\n").trim();
}

function normalizeBrief(brief) {
  const text = normalizeText(brief);
  if (!text) {
    return "";
  }
  if (text.startsWith("# ")) {
    return text;
  }
  return ["# Brief проекта", "", text].join("\n");
}

function buildConversationSummary(session) {
  const history = Array.isArray(session.conversationHistory) ? session.conversationHistory : [];
  if (!history.length) {
    return "История диалога пока пустая.";
  }
  return history
    .slice(-24)
    .map((item) => `${item.role}: ${normalizeText(item.content)}`)
    .join("\n");
}

export async function generateBrief(session) {
  if (!isLLMConfigured()) {
    return fallbackBrief(session);
  }
  const messages = [
    {
      role: "system",
      content: [
        "Ты агент-архитектор Moltis.",
        "Сформируй concise markdown brief на русском языке.",
        "Требуется структура с заголовком '# Brief проекта' и 7 секциями с заголовками второго уровня:",
        BRIEF_SECTION_ORDER.map(([, title]) => `- ${title}`).join("\n"),
        "Не добавляй JSON. Не добавляй пояснений вне markdown.",
      ].join("\n"),
    },
    {
      role: "user",
      content: [
        "Собери brief по истории discovery.",
        "",
        buildConversationSummary(session),
      ].join("\n"),
    },
  ];

  try {
    const completion = await chatCompletion(messages, { temperature: 0.15, maxTokens: 1800 });
    return normalizeBrief(completion) || fallbackBrief(session);
  } catch (error) {
    console.error("[asc-demo] brief.generateBrief:", error?.message || error);
    return fallbackBrief(session);
  }
}

export async function reviseBrief(session, correctionText) {
  const fallback = [
    normalizeBrief(session.briefText) || fallbackBrief(session),
    "",
    "## Корректировка",
    normalizeText(correctionText, "Пользователь запросил уточнение, но не добавил текст."),
  ].join("\n");

  if (!isLLMConfigured()) {
    return fallback;
  }

  const messages = [
    {
      role: "system",
      content: [
        "Ты агент-архитектор Moltis.",
        "Обнови markdown brief с учетом корректировки пользователя.",
        "Сохрани деловой стиль и структуру секций.",
        "Верни только markdown.",
      ].join("\n"),
    },
    {
      role: "user",
      content: [
        "Текущий brief:",
        normalizeBrief(session.briefText) || fallbackBrief(session),
        "",
        "Корректировка пользователя:",
        normalizeText(correctionText, "Уточнить формулировки."),
      ].join("\n"),
    },
  ];

  try {
    const completion = await chatCompletion(messages, { temperature: 0.1, maxTokens: 2000 });
    return normalizeBrief(completion) || fallback;
  } catch (error) {
    console.error("[asc-demo] brief.reviseBrief:", error?.message || error);
    return fallback;
  }
}
