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
const BRIEF_DIRECTIVE_MARKERS = [
  "исправь",
  "внеси",
  "добавь",
  "обнови",
  "уточни",
  "поправь",
  "правку",
  "без цитирования",
];
const EXPECTED_OUTPUT_HINT_MARKERS = [
  "one-page",
  "onepage",
  "pdf",
  "выход",
  "результат",
  "рекомендац",
  "ключев",
  "блок",
  "материал",
];

const SERVICE_PHRASE_PATTERNS = [
  /Требуется уточнение\.?/g,
  /Файлы в discovery не загружались\.?/g,
  /нет подтвержденных данных/g,
  /Brief собран в fallback-режиме\.?/g,
  /Требуется дополнительная проверка перед передачей в производство\.?/g,
];

function stripServicePhrases(text) {
  let result = text;
  SERVICE_PHRASE_PATTERNS.forEach((pattern) => {
    result = result.replace(pattern, "");
  });
  return result.replace(/\n{3,}/g, "\n\n").trim();
}

function fallbackBrief(session) {
  const lines = ["# Brief проекта", ""];
  BRIEF_SECTION_ORDER.forEach(([topicId, title]) => {
    lines.push(`## ${title}`);
    lines.push(normalizeText(session.topicAnswers?.[topicId], "Информация пока не собрана."));
    lines.push("");
  });
  lines.push("## Резюме");
  lines.push("Brief собран автоматически. Рекомендуется проверить перед подтверждением.");
  return lines.join("\n").trim();
}

function normalizeBrief(brief) {
  const text = normalizeText(brief);
  if (!text) {
    return "";
  }
  const cleaned = stripServicePhrases(text);
  if (!cleaned) {
    return "";
  }
  if (cleaned.startsWith("# ")) {
    return cleaned;
  }
  return ["# Brief проекта", "", cleaned].join("\n");
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
    return "Файлы не приложены.";
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
  if (targets.includes("expected_outputs") && targets.includes("input_examples")) {
    const outputContext = OUTPUT_CONTEXT_MARKERS.some((marker) => normalized.includes(marker));
    const explicitInputContext = [
      "входные данные",
      "прилож",
      "прикреп",
      "файл",
    ].some((marker) => normalized.includes(marker));
    if (outputContext && !explicitInputContext) {
      return targets.filter((topicId) => topicId !== "input_examples");
    }
  }

  return targets;
}

function isDirectiveLikeText(value) {
  const lower = normalizeText(value).toLowerCase();
  if (!lower) {
    return false;
  }
  return BRIEF_DIRECTIVE_MARKERS.some((marker) => lower.includes(marker));
}

function cleanExpectedOutputHint(value) {
  let text = normalizeText(value)
    .replace(/^["«]+/, "")
    .replace(/[»"]+$/, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!text) {
    return "";
  }
  text = text
    .replace(/^(исправь\s+brief|внеси\s+уточнение|добавь|обнови|уточни|поправь)\s*[:\-]\s*/i, "")
    .replace(/^в\s+разделе\s+[^:]+:\s*/i, "")
    .replace(
      /^(?:ожидаем(?:ый|ые)?\s+(?:выход|результат)\s*(?:долж(?:ен|на|ны)\s*быть)?|на\s+выходе(?:\s+нуж(?:ен|на|ны))?)\s*[:\-]\s*/i,
      "",
    )
    .replace(/\s+и\s+без\s+цитир[^.]+\.?$/i, "")
    .trim();
  return text;
}

function extractExpectedOutputHint(correctionText, session) {
  const source = normalizeText(correctionText);
  const fallback = normalizeText(session.topicAnswers?.expected_outputs);
  if (!source) {
    return cleanExpectedOutputHint(fallback);
  }
  const quotedAfterMarker = source.match(
    /(?:ожидаем(?:ый|ые)?\s+(?:выход|результат)[^:]{0,120}|на\s+выходе[^:]{0,120})[:\-]\s*[«"]([^»"]+)[»"]/i,
  );
  if (quotedAfterMarker?.[1]) {
    return cleanExpectedOutputHint(quotedAfterMarker[1]);
  }
  const quotedCandidates = Array.from(source.matchAll(/[«"]([^»"]{10,})[»"]/g))
    .map((match) => cleanExpectedOutputHint(match[1]))
    .filter(Boolean);
  const markerQuote = quotedCandidates.find((candidate) => {
    const lower = candidate.toLowerCase();
    return EXPECTED_OUTPUT_HINT_MARKERS.some((marker) => lower.includes(marker));
  });
  if (markerQuote) {
    return markerQuote;
  }
  const hasOutputContext = OUTPUT_CONTEXT_MARKERS.some((marker) => source.toLowerCase().includes(marker));
  if (hasOutputContext) {
    const afterColon = cleanExpectedOutputHint(source.split(":").slice(1).join(":"));
    if (afterColon) {
      return afterColon;
    }
  }
  return cleanExpectedOutputHint(fallback || source);
}

function protectUntargetedSections(session, revisedBrief, correctionTargets) {
  if (!correctionTargets.length) {
    return revisedBrief;
  }
  const originalBrief = normalizeBrief(session.briefText) || "";
  if (!originalBrief) {
    return revisedBrief;
  }
  const originalSections = parseBriefSections(originalBrief);
  const revisedSections = parseBriefSections(revisedBrief);
  const targetTitles = new Set(
    correctionTargets.map((topicId) => BRIEF_SECTION_TITLES[topicId]).filter(Boolean),
  );
  let protected_ = revisedBrief;
  for (const [title, originalContent] of originalSections) {
    if (targetTitles.has(title)) {
      continue;
    }
    const revisedContent = revisedSections.get(title);
    if (revisedContent !== undefined && revisedContent !== originalContent) {
      const escapedTitle = title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const sectionPattern = new RegExp(
        `(## ${escapedTitle}\\n)([\\s\\S]*?)(?=\\n## |$)`,
      );
      protected_ = protected_.replace(sectionPattern, `$1${originalContent}\n`);
    }
  }
  return protected_;
}

function sanitizeRevisedBrief(session, revisedBrief, correctionText) {
  let normalized = normalizeBrief(revisedBrief);
  if (!normalized) {
    return normalized;
  }
  const correction = normalizeText(correctionText);
  const targets = inferCorrectionTargets(correctionText);
  if (targets.length) {
    normalized = protectUntargetedSections(session, normalized, targets);
  }
  if (!targets.includes("expected_outputs")) {
    return normalized;
  }
  const expectedHint = extractExpectedOutputHint(correctionText, session);
  if (!expectedHint) {
    return normalized;
  }
  if (correction && correction.length >= 8 && normalized.includes(correction)) {
    normalized = normalized.split(correction).join(expectedHint);
  }
  normalized = normalized.replace(/[«"]([^»"]{10,})[»"]/g, (full, inner) => {
    if (!isDirectiveLikeText(inner)) {
      return full;
    }
    return `«${expectedHint}»`;
  });
  const lines = normalized.split("\n");
  let outputSection = false;
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const heading = line.match(/^##\s+(.+)$/);
    if (heading) {
      outputSection = /(ожидаем|выход|результат|примеры входов и выходов)/i.test(heading[1]);
      continue;
    }
    if (!outputSection) {
      continue;
    }
    const trimmed = normalizeText(line);
    if (!trimmed) {
      continue;
    }
    if (/^Ожидаемые выходы\s*:/i.test(trimmed)) {
      lines[index] = `Ожидаемые выходы: ${expectedHint}`;
      continue;
    }
    if (/^-/.test(trimmed) && isDirectiveLikeText(trimmed)) {
      lines[index] = `${line.match(/^\s*-\s*/)?.[0] || "- "}${expectedHint}`;
      continue;
    }
    if (isDirectiveLikeText(trimmed)) {
      lines[index] = expectedHint;
    }
  }
  return lines.join("\n");
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
  const expectedHint = extractExpectedOutputHint(correctionText, session);

  if (!targets.length) {
    const currentSummary = normalizeText(sections.get("Резюме"), "Brief обновлен в fallback-режиме.");
    if (!currentSummary.includes(note)) {
      sections.set("Резюме", `${currentSummary}\n\nУточнение пользователя: ${note}`.trim());
    }
  }

  targets.forEach((topicId) => {
    const title = BRIEF_SECTION_TITLES[topicId];
    if (topicId === "expected_outputs" && expectedHint) {
      sections.set(title, expectedHint);
      return;
    }
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
  const fallback = sanitizeRevisedBrief(session, buildFallbackRevision(session, correctionText), correctionText);

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
        "CRITICAL: Модифицируй ТОЛЬКО секции, перечисленные в correction guidance ниже. НЕ МЕНЯЙ остальные секции.",
        "Если пользователь просит добавить подробности, используй только подтвержденные факты. Не придумывай новые данные.",
        "Никогда не копируй управляющие формулировки пользователя в итоговый brief дословно (например: «исправь», «внеси», «добавь», «без цитирования»). Преобразуй их в нейтральный целевой факт.",
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
    const revised = normalizeBrief(completion) || fallback;
    return sanitizeRevisedBrief(session, revised, correctionText) || fallback;
  } catch (error) {
    console.error("[asc-demo] brief.reviseBrief:", error?.message || error);
    return fallback;
  }
}
