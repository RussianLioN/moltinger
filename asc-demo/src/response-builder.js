import { normalizeText } from "./utils.js";

const STATUS_LABELS = {
  gate_pending: "Нужен доступ",
  awaiting_user_reply: "Сбор требований продолжается",
  awaiting_confirmation: "Brief ждёт подтверждения",
  confirmed: "Передача в фабрику",
  playground_ready: "Артефакты готовы",
};

const DEFAULT_AGENT_NAME = "Агент-архитектор Moltis";
const BRIEF_REVIEW_HIDDEN_SECTION_MARKERS = [
  "входные данные и примеры",
  "примеры входов и выходов",
  "входные примеры",
];

function shouldHideBriefReviewSection(title) {
  const normalized = normalizeText(title).toLowerCase();
  return BRIEF_REVIEW_HIDDEN_SECTION_MARKERS.some((marker) => normalized.includes(marker));
}

function nowIso() {
  return new Date().toISOString();
}

function safeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeUploadedFiles(uploadedFiles = []) {
  return safeArray(uploadedFiles).map((file, index) => {
    const uploadId = normalizeText(file.upload_id, `upload-${index + 1}`);
    const name = normalizeText(file.name, `file-${index + 1}`);
    const originalSize = Number(file.original_size_bytes || file.size_bytes || 0);
    const truncated = Boolean(file.truncated);
    const excerpt = normalizeText(file.excerpt).slice(0, 1200);
    return {
      upload_id: uploadId,
      name,
      content_type: normalizeText(file.content_type, "application/octet-stream"),
      size_bytes: Number(file.size_bytes || originalSize || 0),
      original_size_bytes: originalSize,
      truncated,
      ingest_status: excerpt ? "excerpt_ready" : "metadata_only",
      excerpt,
      uploaded_at: normalizeText(file.uploaded_at, nowIso()),
    };
  });
}

function selectionMode(payload) {
  return normalizeText(
    payload?.browser_project_pointer?.selection_mode
      || payload?.web_conversation_envelope?.selection_mode,
    "continue_active",
  );
}

function requestId(payload) {
  return normalizeText(payload?.web_conversation_envelope?.request_id);
}

function currentAction(payload, fallback = "submit_turn") {
  return normalizeText(payload?.web_conversation_envelope?.ui_action, fallback);
}

function statusSnapshot(
  session,
  {
    userVisibleStatus,
    userVisibleStatusLabel,
    nextRecommendedAction,
    nextRecommendedActionLabel,
    downloadReadiness = "pending",
    uploadedFileCount = 0,
  },
) {
  return {
    user_visible_status: userVisibleStatus,
    user_visible_status_label: userVisibleStatusLabel || STATUS_LABELS[userVisibleStatus] || userVisibleStatus,
    next_recommended_action: nextRecommendedAction,
    next_recommended_action_label: nextRecommendedActionLabel,
    brief_version: session.briefVersion > 0 ? `v${session.briefVersion}` : "",
    download_readiness: downloadReadiness,
    uploaded_file_count: uploadedFileCount,
  };
}

function splitBriefToCards(briefText) {
  const normalized = normalizeText(briefText);
  if (!normalized) {
    return [];
  }
  const lines = normalized.split("\n");
  const cards = [];
  let currentTitle = "Общий обзор";
  let buffer = [];
  const flush = () => {
    const body = buffer.join("\n").trim();
    if (!body) {
      return;
    }
    if (shouldHideBriefReviewSection(currentTitle)) {
      return;
    }
    cards.push({
      card_kind: "brief_summary_section",
      title: currentTitle,
      body_text: body,
      action_hints: [],
    });
  };

  lines.forEach((line) => {
    const heading = line.match(/^##\s+(.+)$/);
    if (heading) {
      flush();
      currentTitle = heading[1].trim();
      buffer = [];
      return;
    }
    buffer.push(line);
  });
  flush();

  if (!cards.length) {
    return [
      {
        card_kind: "brief_summary_section",
        title: "Черновик brief",
        body_text: normalized,
        action_hints: [],
      },
    ];
  }
  return cards;
}

function responseBase(session, payload, overrides = {}) {
  const projectKey = normalizeText(
    overrides.projectKey || session.projectKey || payload?.browser_project_pointer?.project_key,
    "",
  );
  const uiAction = currentAction(payload);
  const hasExplicitNextQuestion = Object.prototype.hasOwnProperty.call(overrides, "nextQuestion");
  const hasExplicitNextTopic = Object.prototype.hasOwnProperty.call(overrides, "nextTopic");
  const nextQuestion = hasExplicitNextQuestion
    ? normalizeText(overrides.nextQuestion)
    : normalizeText(session.currentQuestion);
  const nextTopic = hasExplicitNextTopic
    ? normalizeText(overrides.nextTopic)
    : normalizeText(session.currentTopic);
  const uploadedFiles = normalizeUploadedFiles(overrides.uploadedFiles || session.uploadedFiles || []);

  return {
    status: overrides.status || "awaiting_user_reply",
    next_action: overrides.nextAction || "continue_discovery",
    next_topic: nextTopic,
    next_question: nextQuestion,
    access_gate: {
      granted: Boolean(overrides.accessGranted ?? session.accessGranted),
      reason: normalizeText(overrides.accessReason),
    },
    web_demo_session: {
      web_demo_session_id: session.sessionId,
      session_cookie_id: `cookie-${session.sessionId}`,
      status: overrides.webSessionStatus || overrides.status || "awaiting_user_reply",
      active_project_key: projectKey,
    },
    browser_project_pointer: {
      pointer_id: `browser-pointer-${session.sessionId}`,
      project_key: projectKey,
      selection_mode: selectionMode(payload),
      linked_discovery_session_id: session.sessionId,
      linked_brief_id: session.briefVersion > 0 ? `brief-${session.sessionId}` : "",
      linked_brief_version: session.briefVersion > 0 ? `v${session.briefVersion}` : "",
      pointer_status: "active",
    },
    status_snapshot: overrides.statusSnapshot || statusSnapshot(session, {
      userVisibleStatus: "awaiting_user_reply",
      nextRecommendedAction: "submit_turn",
      uploadedFileCount: uploadedFiles.length,
      downloadReadiness: "pending",
    }),
    reply_cards: safeArray(overrides.replyCards),
    download_artifacts: safeArray(overrides.downloadArtifacts),
    uploaded_files: uploadedFiles,
    discovery_runtime_state: {
      status: overrides.discoveryStatus || overrides.status || "awaiting_user_reply",
      next_question: nextQuestion,
      missing_coverage: safeArray(overrides.missingCoverage),
    },
    ui_projection: {
      preferred_ui_action: overrides.preferredAction || "submit_turn",
      current_question: nextQuestion,
      current_topic: nextTopic,
      why_asking_now: normalizeText(overrides.whyAskingNow, session.whyAskingNow),
      missing_coverage: safeArray(overrides.missingCoverage),
      side_panel_mode: overrides.sidePanelMode || "hidden",
      primary_artifact: normalizeText(overrides.primaryArtifact),
      primary_artifact_preview_url: normalizeText(overrides.primaryArtifactPreviewUrl),
      composer_helper_example: normalizeText(overrides.helperExample),
      project_stage_label: normalizeText(overrides.projectStageLabel),
      display_project_title: normalizeText(session.displayProjectTitle, "Новый проект"),
      project_title: normalizeText(session.displayProjectTitle, "Новый проект"),
      uploaded_file_count: uploadedFiles.length,
      agent_display_name: DEFAULT_AGENT_NAME,
      agent_role: "architect",
      question_source: normalizeText(overrides.questionSource, "adaptive_architect"),
    },
    web_conversation_envelope: {
      request_id: requestId(payload),
      ui_action: uiAction,
      user_text: normalizeText(payload?.web_conversation_envelope?.user_text),
      linked_discovery_session_id: session.sessionId,
      linked_brief_id: session.briefVersion > 0 ? `brief-${session.sessionId}` : "",
    },
  };
}

export function buildGatePendingResponse(session, payload, reason = "") {
  const nextQuestion = reason || "Укажи активный demo access token, чтобы открыть рабочую сессию фабрики.";
  return responseBase(session, payload, {
    status: "gate_pending",
    nextAction: "request_demo_access",
    nextTopic: "",
    nextQuestion,
    accessGranted: false,
    accessReason: nextQuestion,
    webSessionStatus: "gate_pending",
    preferredAction: "submit_access_token",
    projectStageLabel: "Ожидает доступ",
    sidePanelMode: "hidden",
    statusSnapshot: statusSnapshot(session, {
      userVisibleStatus: "gate_pending",
      userVisibleStatusLabel: "Нужен доступ",
      nextRecommendedAction: "request_demo_access",
      nextRecommendedActionLabel: "Открыть demo",
      uploadedFileCount: 0,
      downloadReadiness: "pending",
    }),
    replyCards: [
      {
        card_kind: "status_update",
        title: "Нужен код доступа",
        body_text: nextQuestion,
        action_hints: ["submit_access_token"],
      },
    ],
    missingCoverage: [],
    questionSource: "gate",
  });
}

export function buildDiscoveryResponse(
  session,
  payload,
  {
    nextQuestion,
    nextTopic,
    whyAskingNow,
    missingCoverage = [],
    lowSignal = false,
    theatreMessage = "",
    uploadedFiles = [],
    coveredCount = 0,
    totalCount = 7,
    helperExample = "",
    questionSource = "adaptive_architect",
  } = {},
) {
  const statusText = theatreMessage || `Сбор требований продолжается. Закрыто тем: ${coveredCount}/${totalCount}. ${whyAskingNow}`;
  const cards = [
    {
      card_kind: "status_update",
      title: "Статус проекта",
      body_text: statusText.trim(),
      action_hints: ["request_status"],
    },
    {
      card_kind: "discovery_question",
      title: "",
      body_text: nextQuestion,
      action_hints: ["submit_turn"],
    },
  ];
  if (lowSignal) {
    cards.push({
      card_kind: "clarification_prompt",
      title: "Нужно уточнение",
      body_text: "Сформулируй ответ чуть подробнее, чтобы корректно зафиксировать требования в brief.",
      action_hints: ["submit_turn"],
    });
  }
  return responseBase(session, payload, {
    status: "awaiting_user_reply",
    nextAction: "continue_discovery",
    nextTopic,
    nextQuestion,
    whyAskingNow,
    missingCoverage,
    uploadedFiles,
    preferredAction: "submit_turn",
    sidePanelMode: "hidden",
    helperExample,
    projectStageLabel: "Сбор требований",
    statusSnapshot: statusSnapshot(session, {
      userVisibleStatus: "awaiting_user_reply",
      userVisibleStatusLabel: "Сбор требований продолжается",
      nextRecommendedAction: "submit_turn",
      nextRecommendedActionLabel: "Ответить на следующий вопрос",
      uploadedFileCount: uploadedFiles.length,
      downloadReadiness: "pending",
    }),
    replyCards: cards,
    questionSource,
  });
}

export function buildAwaitingConfirmationResponse(
  session,
  payload,
  {
    theatreMessage = "",
    nextQuestion = "Проверь brief. Если всё верно — подтверди. Если нужны изменения — опиши правку.",
    uploadedFiles = [],
  } = {},
) {
  const cards = [
    {
      card_kind: "status_update",
      title: "Статус проекта",
      body_text: (theatreMessage || "Discovery завершён. Агент-архитектор формирует brief...").trim(),
      action_hints: ["request_status"],
    },
    ...splitBriefToCards(session.briefText),
    {
      card_kind: "confirmation_prompt",
      title: "Проверка brief",
      body_text: nextQuestion,
      action_hints: ["request_brief_correction", "confirm_brief", "reopen_brief"],
    },
  ];
  return responseBase(session, payload, {
    status: "awaiting_confirmation",
    nextAction: "await_for_confirmation",
    nextTopic: "",
    nextQuestion,
    uploadedFiles,
    preferredAction: "confirm_brief",
    sidePanelMode: "brief_review",
    projectStageLabel: "Brief на проверке",
    statusSnapshot: statusSnapshot(session, {
      userVisibleStatus: "awaiting_confirmation",
      userVisibleStatusLabel: "Brief ждёт подтверждения",
      nextRecommendedAction: "confirm_brief",
      nextRecommendedActionLabel: "Проверить и подтвердить brief",
      uploadedFileCount: uploadedFiles.length,
      downloadReadiness: "pending",
    }),
    replyCards: cards,
    missingCoverage: [],
    questionSource: "awaiting_confirmation",
  });
}

export function buildHandoffRunningResponse(session, payload, theatreMessage = "") {
  const nextQuestion = "Brief подтвержден. Фабрика готовит материалы. Напиши «обнови статус», если нужно проверить готовность.";
  return responseBase(session, payload, {
    status: "confirmed",
    nextAction: "start_concept_pack_handoff",
    nextTopic: "",
    nextQuestion,
    preferredAction: "request_status",
    sidePanelMode: "downloads",
    projectStageLabel: "Производство в процессе",
    statusSnapshot: statusSnapshot(session, {
      userVisibleStatus: "confirmed",
      userVisibleStatusLabel: "Передача в фабрику",
      nextRecommendedAction: "request_status",
      nextRecommendedActionLabel: "Проверить готовность артефактов",
      uploadedFileCount: safeArray(session.uploadedFiles).length,
      downloadReadiness: "pending",
    }),
    replyCards: [
      {
        card_kind: "status_update",
        title: "Готовлю материалы",
        body_text: (theatreMessage || "Фабрика собирает project doc, agent spec, presentation и демо цифрового сотрудника.").trim(),
        action_hints: ["request_status"],
      },
    ],
    downloadArtifacts: [],
    missingCoverage: [],
    questionSource: "handoff_running",
  });
}

export function buildDownloadsReadyResponse(session, payload, theatreMessage = "", options = {}) {
  const preferredKind = normalizeText(options.primaryArtifactKind, "one_page_summary");
  const artifacts = safeArray(session.artifacts)
    .map((item) => ({
      artifact_kind: item.artifact_kind,
      download_name: item.download_name,
      download_status: item.download_status || "ready",
      description: normalizeText(item.description),
      download_url: `/api/download/${encodeURIComponent(session.sessionId)}/${encodeURIComponent(item.artifact_kind)}`,
      preview_url: `/api/preview/${encodeURIComponent(session.sessionId)}/${encodeURIComponent(item.artifact_kind)}`,
      is_primary: item.artifact_kind === preferredKind,
    }))
    .sort((left, right) => Number(Boolean(right.is_primary)) - Number(Boolean(left.is_primary)));
  const primaryArtifact = artifacts.find((item) => item.is_primary) || artifacts[0] || null;
  const secondaryArtifacts = artifacts.filter((item) => item.artifact_kind !== primaryArtifact?.artifact_kind);
  const nextQuestion = primaryArtifact
    ? (preferredKind === "production_simulation"
      ? "Имитация запуска цифрового сотрудника готова. Открой artefact production simulation в preview и проверь стартовый результат."
      : "Материалы готовы. Открой one-page summary в preview или скачай артефакты.")
    : "Производство завершено. Артефакты готовы к скачиванию.";
  const secondarySummary = secondaryArtifacts.length
    ? ` Дополнительно доступны: ${secondaryArtifacts.map((item) => item.download_name).join(", ")}.`
    : "";
  return responseBase(session, payload, {
    status: "confirmed",
    nextAction: "download_artifact",
    nextTopic: "",
    nextQuestion,
    preferredAction: "preview_one_page",
    sidePanelMode: "downloads",
    primaryArtifact: primaryArtifact?.artifact_kind || preferredKind,
    primaryArtifactPreviewUrl: primaryArtifact?.preview_url || "",
    projectStageLabel: "Цифровой актив готов",
    statusSnapshot: statusSnapshot(session, {
      userVisibleStatus: "playground_ready",
      userVisibleStatusLabel: "Артефакты готовы",
      nextRecommendedAction: "download_artifact",
      nextRecommendedActionLabel: "Открыть результат",
      uploadedFileCount: safeArray(session.uploadedFiles).length,
      downloadReadiness: "ready",
    }),
    replyCards: [
      {
        card_kind: "status_update",
        title: "Статус проекта",
        body_text: (theatreMessage || "Производство завершено. Цифровой актив готов к просмотру и скачиванию.").trim(),
        action_hints: ["request_status"],
      },
      {
        card_kind: "factory_result",
        title: "Цифровой актив создан",
        body_text: primaryArtifact
          ? `Готово: ${primaryArtifact.download_name}.${secondarySummary}`
          : `Готово: материалы доступны в панели загрузок.${secondarySummary}`,
        action_hints: ["preview_one_page", "download_artifact", "request_status"],
      },
    ],
    downloadArtifacts: artifacts,
    missingCoverage: [],
    questionSource: "downloads_ready",
  });
}

export function buildErrorFallbackResponse(session, payload, errorMessage = "") {
  const reason = normalizeText(errorMessage, "Временная ошибка backend. Попробуй отправить сообщение ещё раз.");
  return responseBase(session, payload, {
    status: session.accessGranted ? "awaiting_user_reply" : "gate_pending",
    nextAction: session.accessGranted ? "continue_discovery" : "request_demo_access",
    nextTopic: session.currentTopic || "",
    nextQuestion: session.currentQuestion || reason,
    preferredAction: session.accessGranted ? "submit_turn" : "submit_access_token",
    sidePanelMode: "hidden",
    projectStageLabel: session.accessGranted ? "Сбор требований" : "Нужен доступ",
    statusSnapshot: statusSnapshot(session, {
      userVisibleStatus: session.accessGranted ? "awaiting_user_reply" : "gate_pending",
      nextRecommendedAction: session.accessGranted ? "submit_turn" : "request_demo_access",
      uploadedFileCount: safeArray(session.uploadedFiles).length,
      downloadReadiness: "pending",
    }),
    replyCards: [
      {
        card_kind: "status_update",
        title: "Статус проекта",
        body_text: reason,
        action_hints: [session.accessGranted ? "submit_turn" : "submit_access_token"],
      },
    ],
    missingCoverage: session.missingCoverage || [],
    questionSource: "error_fallback",
  });
}

export function normalizeBrowserUploads(uploadedFiles = []) {
  return normalizeUploadedFiles(uploadedFiles);
}
