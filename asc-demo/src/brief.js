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
const SYNTHETIC_DATA_NOTE = "Все данные во вложениях считаются синтетическими: не относятся к реальным лицам/контрагентам, любые совпадения случайны.";
const BRIEF_SECTION_TITLES = Object.fromEntries(BRIEF_SECTION_ORDER);
const CORRECTION_TOPIC_HINTS = [
  {
    topicId: "problem",
    keywords: ["проблем", "боль", "ценност", "эффект", "зачем", "цель автоматизации"],
  },
  {
    topicId: "target_users",
    keywords: ["пользоват", "роль", "кто использ", "выгодоприобрет", "команда", "сотрудник"],
  },
  {
    topicId: "current_workflow",
    keywords: ["процесс", "workflow", "как сейчас", "as is", "текущ", "bpmn", "этап"],
  },
  {
    topicId: "input_examples",
    keywords: ["вход", "исходн", "данн", "файл", "влож", "пример", "csv", "excel", "документ"],
  },
  {
    topicId: "expected_outputs",
    keywords: ["выход", "результат", "output", "one-page", "pdf", "отчет", "документ на выходе", "summary"],
  },
  {
    topicId: "branching_rules",
    keywords: ["правил", "исключ", "ветвл", "если", "иначе", "эскалац", "огранич", "запрет"],
  },
  {
    topicId: "success_metrics",
    keywords: ["метрик", "kpi", "sla", "точност", "время", "сократ", "успех"],
  },
];
const OUTPUT_CONTEXT_MARKERS = [
  "на выход",
  "ожидаемый результат",
  "в one-page",
  "в onepage",
  "в pdf",
  "в документ",
  "в отч",
  "блок",
  "раздел",
  "подпункт",
  "рекомендац",
];
const SUCCESS_METRICS_SECTION_MARKERS = [
  "метрики успех",
  "kpi",
  "sla",
  "время подготовки",
  "время обработки",
  "уровень ошибок",
  "точность",
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

function collectUploadedFiles(session) {
  const deduped = new Map();
  const pushFile = (file) => {
    const name = normalizeText(file?.name);
    const excerpt = normalizeText(file?.excerpt).slice(0, 240);
    if (!name && !excerpt) {
      return;
    }
    const key = name || excerpt;
    if (!deduped.has(key)) {
      deduped.set(key, {
        name: name || "Файл без названия",
        excerpt,
      });
      return;
    }
    if (!deduped.get(key).excerpt && excerpt) {
      deduped.get(key).excerpt = excerpt;
    }
  };

  (session.uploadedFiles || []).forEach(pushFile);
  (session.conversationHistory || []).forEach((item) => {
    (item?.uploaded_files || []).forEach(pushFile);
  });

  return Array.from(deduped.values());
}

function buildUploadedFilesSummary(session) {
  const files = collectUploadedFiles(session);
  if (!files.length) {
    return "Файлы в discovery не загружались.";
  }
  return [
    SYNTHETIC_DATA_NOTE,
    ...files
    .map((file) => {
      const excerpt = normalizeText(file.excerpt);
      return excerpt
        ? `- ${file.name}: ${excerpt}`
        : `- ${file.name}`;
    }),
  ].join("\n");
}

function buildTopicSummary(session) {
  const answers = session.topicAnswers || {};
  const lines = ["Подтвержденный discovery context:"];
  BRIEF_SECTION_ORDER.forEach(([topicId, title]) => {
    lines.push(`- ${title}: ${normalizeText(answers[topicId], "нет подтвержденных данных")}`);
  });
  lines.push("", "Загруженные файлы:");
  lines.push(buildUploadedFilesSummary(session));
  return lines.join("\n");
}

function inferCorrectionTargets(correctionText) {
  const normalized = normalizeText(correctionText).toLowerCase();
  if (!normalized) {
    return [];
  }
  const targets = CORRECTION_TOPIC_HINTS
    .filter((hint) => hint.keywords.some((keyword) => normalized.includes(keyword)))
    .map((hint) => hint.topicId);

  if (targets.includes("expected_outputs") && targets.includes("success_metrics")) {
    const outputContext = OUTPUT_CONTEXT_MARKERS.some((marker) => normalized.includes(marker));
    const explicitMetricsSection = SUCCESS_METRICS_SECTION_MARKERS.some((marker) => normalized.includes(marker));
    if (outputContext && !explicitMetricsSection) {
      return targets.filter((topicId) => topicId !== "success_metrics");
    }
  }

  return targets;
}

function buildCorrectionGuidance(session, correctionText) {
  const targets = inferCorrectionTargets(correctionText);
  if (!targets.length) {
    return "Явная тематическая секция не распознана. Обнови только те части brief, которых касается смысл правки.";
  }
  return [
    "Приоритетные секции для правки:",
    ...targets.map((topicId) => {
      const title = BRIEF_SECTION_TITLES[topicId];
      const answer = normalizeText(session.topicAnswers?.[topicId], "нет подтвержденных данных");
      return `- ${title}: ${answer}`;
    }),
  ].join("\n");
}

function parseBriefSections(briefText) {
  const sections = new Map();
  let currentTitle = "";
  let buffer = [];

  normalizeBrief(briefText)
    .split("\n")
    .forEach((line) => {
      const headingMatch = line.match(/^##\s+(.+)$/);
      if (!headingMatch) {
        if (currentTitle) {
          buffer.push(line);
        }
        return;
      }
      if (currentTitle) {
        sections.set(currentTitle, buffer.join("\n").trim());
      }
      currentTitle = normalizeText(headingMatch[1]);
      buffer = [];
    });

  if (currentTitle) {
    sections.set(currentTitle, buffer.join("\n").trim());
  }

  return sections;
}

function buildFallbackRevision(session, correctionText) {
  const note = normalizeText(correctionText, "Пользователь запросил уточнение, но не добавил текст.");
  const baseBrief = normalizeBrief(session.briefText) || fallbackBrief(session);
  const sections = parseBriefSections(baseBrief);
  const targets = inferCorrectionTargets(correctionText);

  if (!targets.length) {
    const currentSummary = normalizeText(sections.get("Резюме"), "Brief обновлен в fallback-режиме.");
    if (!currentSummary.includes(note)) {
      sections.set("Резюме", `${currentSummary}\n\nУточнение пользователя: ${note}`.trim());
    }
  }

  targets.forEach((topicId) => {
    const title = BRIEF_SECTION_TITLES[topicId];
    const current = normalizeText(sections.get(title), "Требуется уточнение.");
    if (!current.includes(note)) {
      sections.set(title, `${current}\n\nДополнительное уточнение: ${note}`.trim());
    }
  });

  const lines = ["# Brief проекта", ""];
  BRIEF_SECTION_ORDER.forEach(([topicId, title]) => {
    lines.push(`## ${title}`);
    lines.push(normalizeText(sections.get(title), normalizeText(session.topicAnswers?.[topicId], "Требуется уточнение.")));
    lines.push("");
  });
  if (sections.has("Резюме")) {
    lines.push("## Резюме");
    lines.push(normalizeText(sections.get("Резюме"), "Brief обновлен в fallback-режиме."));
  }
  return lines.join("\n").trim();
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
        "Сначала опирайся на подтвержденные ответы по темам discovery и загруженные файлы. Историю диалога используй только как дополнительный контекст.",
        "Требуется структура с заголовком '# Brief проекта' и 7 секциями с заголовками второго уровня:",
        BRIEF_SECTION_ORDER.map(([, title]) => `- ${title}`).join("\n"),
        "Не придумывай факты. Если данных недостаточно, явно укажи это внутри соответствующей секции.",
        "Не добавляй JSON. Не добавляй пояснений вне markdown.",
      ].join("\n"),
    },
    {
      role: "user",
      content: [
        "Собери brief по результатам discovery.",
        "",
        buildTopicSummary(session),
        "",
        "История диалога:",
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
  const fallback = buildFallbackRevision(session, correctionText);

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
        "Сначала опирайся на подтвержденный discovery context и загруженные файлы, а не только на историю сообщений.",
        "Если корректировка семантически относится к конкретной теме brief, обнови соответствующую секцию в первую очередь и не разбрасывай факт по нерелевантным разделам.",
        "Если пользователь просит добавить подробности, используй только подтвержденные факты. Не придумывай новые данные.",
        "Верни только markdown.",
      ].join("\n"),
    },
    {
      role: "user",
      content: [
        "Подтвержденный discovery context:",
        buildTopicSummary(session),
        "",
        buildCorrectionGuidance(session, correctionText),
        "",
        "Текущий brief:",
        normalizeBrief(session.briefText) || fallbackBrief(session),
        "",
        "Недавняя история диалога:",
        buildConversationSummary(session),
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
