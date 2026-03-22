import { timingSafeEqual } from "node:crypto";
import {
  buildAwaitingConfirmationResponse,
  buildDiscoveryResponse,
  buildDownloadsReadyResponse,
  buildErrorFallbackResponse,
  buildGatePendingResponse,
  buildHandoffRunningResponse,
  normalizeBrowserUploads,
} from "./response-builder.js";
import { generateBrief, reviseBrief, syncSessionTopicAnswersFromBrief } from "./brief.js";
import { evaluateDiscoveryContract, getDiscoveryTopics, processDiscoveryTurn } from "./discovery.js";
import { generateArtifacts } from "./summary-generator.js";
import { getOrCreateSession, setSessionArtifacts, setSessionResponse, setSessionSummaryPromise, updateSession } from "./sessions.js";
import { normalizeText } from "./utils.js";

function withTimeout(promise, ms, fallback = null) {
  if (!promise || typeof promise.then !== "function") {
    return Promise.resolve(fallback);
  }
  return Promise.race([
    promise,
    new Promise((resolve) => {
      setTimeout(() => resolve(fallback), ms);
    }),
  ]);
}

function slugify(input) {
  const text = normalizeText(input, "demo-project")
    .toLowerCase()
    .replace(/[^a-z0-9а-яё]+/gi, "-")
    .replace(/^-+|-+$/g, "");
  return text || "demo-project";
}

function projectKeyFromPayload(payload, fallbackText = "") {
  const explicit = normalizeText(payload?.browser_project_pointer?.project_key);
  if (explicit) {
    return explicit;
  }
  const fromEnvelope = normalizeText(payload?.web_conversation_envelope?.project_key);
  if (fromEnvelope) {
    return fromEnvelope;
  }
  return `factory-${slugify(fallbackText || "demo-project")}`;
}

function sessionIdFromPayload(payload) {
  return normalizeText(
    payload?.web_demo_session?.web_demo_session_id
      || payload?.web_conversation_envelope?.session_id
      || payload?.web_conversation_envelope?.linked_discovery_session_id,
    "",
  );
}

function getAction(payload) {
  return normalizeText(payload?.web_conversation_envelope?.ui_action, "submit_turn");
}

function getRequestId(payload) {
  return normalizeText(
    payload?.web_conversation_envelope?.request_id
      || payload?.web_conversation_envelope?.web_conversation_envelope_id,
    "",
  );
}

function getUserText(payload) {
  return normalizeText(payload?.web_conversation_envelope?.user_text);
}

function getAccessToken(payload) {
  return normalizeText(
    payload?.demo_access_grant?.grant_value
      || payload?.access_token
      || payload?.web_conversation_envelope?.access_token,
  );
}

function validAccessToken(token) {
  const expected = normalizeText(process.env.DEMO_ACCESS_TOKEN, "demo-access-token");
  const candidate = normalizeText(token);
  if (!candidate || !expected || candidate.length !== expected.length) {
    return false;
  }
  return timingSafeEqual(Buffer.from(candidate), Buffer.from(expected));
}

function decodeBase64Excerpt(value) {
  try {
    const buffer = Buffer.from(value, "base64");
    const text = buffer.toString("utf-8");
    return normalizeText(text).slice(0, 1200);
  } catch (_error) {
    return "";
  }
}

function normalizeIncomingUploads(rawUploads = []) {
  return normalizeBrowserUploads(rawUploads).map((upload) => {
    const originalBase64 = normalizeText(rawUploads.find((item) => item.upload_id === upload.upload_id)?.content_base64);
    const excerpt = upload.excerpt || (originalBase64 ? decodeBase64Excerpt(originalBase64) : "");
    return {
      ...upload,
      excerpt,
      ingest_status: excerpt ? "excerpt_ready" : "metadata_only",
    };
  });
}

function uploadFingerprint(upload = {}) {
  const id = normalizeText(upload.upload_id);
  if (id) {
    return `id:${id}`;
  }
  const name = normalizeText(upload.name).toLowerCase();
  const size = Number(upload.original_size_bytes || upload.size_bytes || 0);
  if (name || size) {
    return `file:${name}:${size}`;
  }
  return "";
}

function mergeIncomingUploads(session, incomingUploads = []) {
  const merged = new Map();
  const push = (upload) => {
    const fingerprint = uploadFingerprint(upload);
    if (!fingerprint) {
      return;
    }
    if (!merged.has(fingerprint)) {
      merged.set(fingerprint, { ...upload });
      return;
    }
    const existing = merged.get(fingerprint);
    const existingExcerpt = normalizeText(existing.excerpt);
    const nextExcerpt = normalizeText(upload.excerpt);
    if (!existingExcerpt && nextExcerpt) {
      existing.excerpt = nextExcerpt;
      existing.ingest_status = upload.ingest_status || existing.ingest_status;
    }
    existing.uploaded_at = normalizeText(upload.uploaded_at, existing.uploaded_at);
  };

  (session.uploadedFiles || []).forEach(push);
  incomingUploads.forEach(push);
  return Array.from(merged.values());
}

function shouldAutoname(session, userText) {
  const text = normalizeText(userText);
  if (!text) {
    return false;
  }
  if (normalizeText(session.displayProjectTitle) !== "Новый проект") {
    return false;
  }
  const lowSignal = ["test", "ping", "ok", "да", "нет"].includes(text.toLowerCase());
  return !lowSignal && text.length > 6;
}

function maybeAutonameProject(session, userText) {
  if (!shouldAutoname(session, userText)) {
    return;
  }
  const text = normalizeText(userText).replace(/\s+/g, " ");
  if (text.length <= 72) {
    session.displayProjectTitle = text;
    return;
  }
  const words = text.split(" ");
  const compact = [];
  for (const word of words) {
    const draft = compact.length ? `${compact.join(" ")} ${word}` : word;
    if (draft.length > 66) {
      break;
    }
    compact.push(word);
  }
  session.displayProjectTitle = compact.join(" ") || text.slice(0, 66);
}

function isNoisyInputExamplesValue(value) {
  const normalized = normalizeText(value).toLowerCase();
  if (!normalized) {
    return true;
  }
  if (normalized.length < 28) {
    return true;
  }
  return [
    "уже прикреп",
    "уже прилож",
    "это и есть",
    "обезличенн",
    "синтетич",
  ].some((marker) => normalized.includes(marker));
}

function isActionAllowedForStage(action, stage) {
  const currentStage = normalizeText(stage, "gate_pending");
  const allowed = {
    gate_pending: new Set(["request_demo_access", "submit_access_token", "request_status"]),
    discovery: new Set([
      "submit_turn",
      "request_status",
      "request_brief_review",
      "request_demo_access",
      "submit_access_token",
    ]),
    awaiting_confirmation: new Set([
      "submit_turn",
      "request_status",
      "request_brief_review",
      "request_brief_correction",
      "confirm_brief",
      "reopen_brief",
    ]),
    confirmed: new Set([
      "submit_turn",
      "request_status",
      "request_brief_review",
      "request_brief_correction",
      "reopen_brief",
      "preview_one_page",
      "download_artifact",
    ]),
    downloads_ready: new Set([
      "submit_turn",
      "request_status",
      "request_brief_review",
      "request_brief_correction",
      "reopen_brief",
      "preview_one_page",
      "download_artifact",
    ]),
  };
  const stageAllowed = allowed[currentStage] || allowed.discovery;
  return stageAllowed.has(normalizeText(action, "submit_turn"));
}

function rememberProcessedRequestId(session, requestId) {
  const normalized = normalizeText(requestId);
  if (!normalized) {
    return;
  }
  if (!Array.isArray(session.processedRequestIds)) {
    session.processedRequestIds = [];
  }
  if (session.processedRequestIds.includes(normalized)) {
    return;
  }
  session.processedRequestIds.push(normalized);
  if (session.processedRequestIds.length > 80) {
    session.processedRequestIds = session.processedRequestIds.slice(-80);
  }
}

function isDuplicateRequest(session, requestId) {
  const normalized = normalizeText(requestId);
  if (!normalized) {
    return false;
  }
  return Array.isArray(session.processedRequestIds) && session.processedRequestIds.includes(normalized);
}

function withSafeMessage(response, message) {
  const normalizedMessage = normalizeText(message);
  if (!normalizedMessage || !response || typeof response !== "object") {
    return response;
  }
  const nextQuestion = normalizeText(response.next_question);
  if (!nextQuestion) {
    return {
      ...response,
      next_question: normalizedMessage,
    };
  }
  if (nextQuestion.startsWith(normalizedMessage)) {
    return response;
  }
  return {
    ...response,
    next_question: `${normalizedMessage}\n\n${nextQuestion}`,
  };
}

const BRIEF_CORRECTION_MARKERS = [
  "правк",
  "исправ",
  "уточни",
  "доработ",
  "переоткрой",
  "переоткры",
  "измени",
  "обнови brief",
  "нужно изменить",
];

const NON_CORRECTION_FOLLOWUP_MARKERS = [
  "продолж",
  "дальше",
  "ок",
  "okay",
  "понял",
  "поняла",
  "поясни",
  "объясни",
  "что дальше",
  "статус",
  "обнови",
  "refresh",
  "да",
  "нет",
];

const CONFIRM_BRIEF_MARKERS = [
  "подтверждаю",
  "подтвержд",
  "confirm",
  "всё верно",
  "все верно",
  "brief готов",
  "brief ок",
  "brief ok",
  "бриф готов",
  "принимаю brief",
  "принимаю бриф",
  "запускай",
  "в производство",
  "передавай в фабрику",
];

function isLikelyConfirmBriefText(text) {
  const normalized = normalizeText(text).toLowerCase();
  if (!normalized) {
    return false;
  }
  const negation = ["не подтверж", "не готов", "не верно", "не принима"].some(
    (marker) => normalized.includes(marker),
  );
  if (negation) {
    return false;
  }
  return CONFIRM_BRIEF_MARKERS.some((marker) => normalized.includes(marker));
}

const PRODUCTION_SIMULATION_MARKERS = [
  "имитац",
  "симуляц",
  "запусти цифров",
  "цифровой сущности",
  "production simulation",
  "стартовый результат",
];

function isLikelyBriefCorrectionText(text) {
  const normalized = normalizeText(text).toLowerCase();
  if (!normalized) {
    return false;
  }
  return BRIEF_CORRECTION_MARKERS.some((marker) => normalized.includes(marker));
}

function isLowConfidenceBriefCorrectionText(text) {
  const normalized = normalizeText(text).toLowerCase();
  if (!normalized || normalized.length < 12) {
    return true;
  }
  const compact = normalized
    .replace(/[^\p{L}\p{N}\s-]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
  const tokens = compact ? compact.split(" ") : [];
  return NON_CORRECTION_FOLLOWUP_MARKERS.some((marker) => {
    if (!marker) {
      return false;
    }
    if (marker.length <= 3) {
      return tokens.includes(marker);
    }
    if (marker.includes(" ")) {
      return compact.includes(marker);
    }
    return compact === marker || compact.startsWith(`${marker} `);
  });
}

function isProductionSimulationRequest(text) {
  const normalized = normalizeText(text).toLowerCase();
  if (!normalized) {
    return false;
  }
  return PRODUCTION_SIMULATION_MARKERS.some((marker) => normalized.includes(marker));
}

async function ensureBriefReady(session) {
  if (normalizeText(session.briefText)) {
    syncSessionTopicAnswersFromBrief(session, session.briefText);
    return session.briefText;
  }
  const briefText = await generateBrief(session);
  session.briefText = briefText;
  session.briefVersion = Math.max(1, Number(session.briefVersion || 0) + 1);
  syncSessionTopicAnswersFromBrief(session, briefText);
  return briefText;
}

function pushUserMessage(session, userText, uploadedFiles = []) {
  const text = normalizeText(userText);
  if (!text && !(uploadedFiles || []).length) {
    return;
  }
  session.conversationHistory.push({
    role: "user",
    content: text || "Пользователь приложил файлы без текста.",
    uploaded_files: uploadedFiles.map((item) => ({
      name: item.name,
      excerpt: normalizeText(item.excerpt).slice(0, 160),
    })),
    ts: new Date().toISOString(),
  });
}

function pushAssistantMessage(session, text) {
  const normalized = normalizeText(text);
  if (!normalized) {
    return;
  }
  session.conversationHistory.push({
    role: "assistant",
    content: normalized,
    ts: new Date().toISOString(),
  });
}

async function runSummaryGeneration(session, generationId) {
  if (
    session.summaryState === "running"
    && session.summaryPromise
    && Number(session.handoffGenerationId || 0) === Number(generationId || 0)
  ) {
    return session.summaryPromise;
  }

  const promise = (async () => {
    const artifacts = await generateArtifacts(session);
    const stillActual = Number(session.handoffGenerationId || 0) === Number(generationId || 0);
    if (!stillActual || normalizeText(session.stage) !== "confirmed") {
      return session.artifacts || artifacts;
    }
    setSessionArtifacts(session, artifacts);
    updateSession(session, {
      stage: "downloads_ready",
      summaryState: "ready",
      summaryPromise: null,
    });
    return artifacts;
  })().catch((error) => {
    console.error("[asc-demo] router.runSummaryGeneration:", error?.message || error);
    const stillActual = Number(session.handoffGenerationId || 0) === Number(generationId || 0);
    if (!stillActual || normalizeText(session.stage) !== "confirmed") {
      return session.artifacts || [];
    }
    const fallbackArtifacts = [
      {
        artifact_kind: "one_page_summary",
        download_name: "one-page-summary.md",
        download_status: "ready",
        description: "Fallback summary после ошибки генерации.",
        content: [
          "# One-page Summary",
          "",
          `Генерация завершилась с ошибкой: ${normalizeText(error?.message, "unknown_error")}`,
          "",
          "Использован резервный шаблон.",
        ].join("\n"),
      },
      {
        artifact_kind: "project_doc",
        download_name: "project-doc.md",
        download_status: "ready",
        description: "Fallback project doc.",
        content: session.briefText || "# Project Doc\n\nBrief недоступен.",
      },
      {
        artifact_kind: "agent_spec",
        download_name: "agent-spec.md",
        download_status: "ready",
        description: "Fallback agent spec.",
        content: "# Agent Spec\n\nFallback режим.",
      },
      {
        artifact_kind: "presentation",
        download_name: "presentation.md",
        download_status: "ready",
        description: "Fallback presentation.",
        content: "# Presentation\n\nFallback режим.",
      },
    ];
    setSessionArtifacts(session, fallbackArtifacts);
    updateSession(session, {
      stage: "downloads_ready",
      summaryState: "failed",
      summaryPromise: null,
    });
    return fallbackArtifacts;
  });

  session.summaryState = "running";
  setSessionSummaryPromise(session, promise);
  return promise;
}

async function discoveryFlow(session, payload, userText, uploadedFiles) {
  if (Array.isArray(session.uploadedFiles) && session.uploadedFiles.length > 0) {
    session.coveredTopics.add("input_examples");
    if (!session.topicAnswers || typeof session.topicAnswers !== "object") {
      session.topicAnswers = {};
    }
    const currentInputExamples = normalizeText(session.topicAnswers?.input_examples);
    const needsStructuredInputExamples = !currentInputExamples
      || isNoisyInputExamplesValue(currentInputExamples)
      || !/приложены файлы/i.test(currentInputExamples);
    if (needsStructuredInputExamples) {
      const names = session.uploadedFiles
        .map((file) => normalizeText(file?.name))
        .filter(Boolean)
        .join(", ");
      session.topicAnswers.input_examples = `Приложены файлы: ${names || "вложения пользователя"}. Данные считаются синтетическими и обезличенными.`;
    }
  }
  maybeAutonameProject(session, userText);
  pushUserMessage(session, userText, uploadedFiles);

  const discovery = await processDiscoveryTurn(session, userText, uploadedFiles);
  if (discovery.complete) {
    const contract = evaluateDiscoveryContract(session);
    if (!contract.ready) {
      const followup = contract.followups[0];
      const followupQuestion = followup?.question || "Уточни обязательные параметры результата перед подтверждением brief.";
      const followupTopic = normalizeText(followup?.topicId, "expected_outputs");
      const followupWhy = normalizeText(
        followup?.why,
        "Перед подтверждением brief нужно закрыть обязательные параметры результата и правил обработки.",
      );
      session.stage = "discovery";
      session.currentTopic = followupTopic;
      session.currentQuestion = followupQuestion;
      session.whyAskingNow = followupWhy;
      session.missingCoverage = [followupTopic];
      const response = buildDiscoveryResponse(session, payload, {
        nextQuestion: followupQuestion,
        nextTopic: followupTopic,
        whyAskingNow: followupWhy,
        missingCoverage: [followupTopic],
        lowSignal: false,
        theatreMessage: `Нужна ещё одна фиксация перед brief: ${followupWhy}`,
        uploadedFiles,
        coveredCount: discovery.coveredCount,
        totalCount: discovery.totalCount,
        helperExample: followupQuestion,
        questionSource: "mandatory_contract_guard",
      });
      pushAssistantMessage(session, response.next_question);
      return response;
    }

    await ensureBriefReady(session);
    session.stage = "awaiting_confirmation";
    session.currentTopic = "";
    session.currentQuestion = "";
    session.whyAskingNow = "";
    session.missingCoverage = [];
    const response = buildAwaitingConfirmationResponse(session, payload, {
      theatreMessage: [
        "Discovery завершён.",
        `Формат результата: ${contract.summary.result_format}.`,
        `Правила обработки: ${contract.summary.processing_rules}.`,
        `Критерии качества: ${contract.summary.quality_criteria}.`,
        "Сформировал brief для проверки.",
      ].join(" "),
      uploadedFiles,
    });
    pushAssistantMessage(session, response.next_question);
    return response;
  }

  session.stage = "discovery";
  const nextQuestionForUser = discovery.acknowledgementText
    ? `${discovery.acknowledgementText}\n\n${discovery.nextQuestion}`
    : discovery.nextQuestion;
  const response = buildDiscoveryResponse(session, payload, {
    nextQuestion: nextQuestionForUser,
    nextTopic: discovery.nextTopic,
    whyAskingNow: discovery.whyAskingNow,
    missingCoverage: discovery.missingCoverage,
    lowSignal: discovery.lowSignal,
    theatreMessage: `Закрыто тем: ${discovery.coveredCount}/${discovery.totalCount}. ${discovery.whyAskingNow}`,
    uploadedFiles,
    coveredCount: discovery.coveredCount,
    totalCount: discovery.totalCount,
    helperExample: discovery.helperExample,
    questionSource: discovery.lowSignal ? "low_signal_guard" : "adaptive_architect",
  });
  pushAssistantMessage(session, response.next_question);
  return response;
}

async function statusFlow(session, payload) {
  if (session.stage === "downloads_ready") {
    return buildDownloadsReadyResponse(session, payload);
  }
  if (session.stage === "confirmed" && session.summaryPromise) {
    await withTimeout(session.summaryPromise, 90_000, null);
    if (session.stage === "downloads_ready") {
      return buildDownloadsReadyResponse(session, payload);
    }
  }
  if (session.stage === "confirmed") {
    return buildHandoffRunningResponse(session, payload);
  }
  if (session.stage === "awaiting_confirmation") {
    return buildAwaitingConfirmationResponse(session, payload);
  }
  const topics = getDiscoveryTopics();
  const covered = session.coveredTopics instanceof Set ? session.coveredTopics : new Set(session.coveredTopics || []);
  const firstUncovered = topics.find((topic) => !covered.has(topic.id)) || topics[0];
  const currentTopicId = normalizeText(session.currentTopic);
  const currentTopicCovered = currentTopicId && covered.has(currentTopicId);
  const fallbackTopic = currentTopicCovered ? firstUncovered : (topics.find((topic) => topic.id === currentTopicId) || firstUncovered);
  const defaultTopic = fallbackTopic || topics[0];
  const nextQuestion = currentTopicCovered
    ? defaultTopic.question
    : normalizeText(session.currentQuestion, defaultTopic.question);
  const nextTopic = normalizeText(session.currentTopic, defaultTopic.id);
  session.currentQuestion = nextQuestion;
  session.currentTopic = currentTopicCovered ? defaultTopic.id : nextTopic;
  session.whyAskingNow = normalizeText(session.whyAskingNow, defaultTopic.why);
  if (!Array.isArray(session.missingCoverage) || !session.missingCoverage.length) {
    session.missingCoverage = topics.filter((topic) => !covered.has(topic.id)).map((topic) => topic.id);
  }
  return buildDiscoveryResponse(session, payload, {
    nextQuestion: session.currentQuestion,
    nextTopic: session.currentTopic,
    whyAskingNow: session.whyAskingNow,
    missingCoverage: session.missingCoverage,
    lowSignal: false,
    uploadedFiles: session.uploadedFiles || [],
    coveredCount: (session.coveredTopics || new Set()).size,
    totalCount: topics.length,
    helperExample: defaultTopic.question,
    questionSource: "adaptive_architect",
  });
}

export async function handleTurn(payload = {}) {
  const action = getAction(payload);
  const requestId = getRequestId(payload);
  const userText = getUserText(payload);
  const hasUserText = Boolean(normalizeText(userText));
  const sessionId = sessionIdFromPayload(payload);
  const incomingUploads = normalizeIncomingUploads(payload.uploaded_files || []);
  const token = getAccessToken(payload);

  const session = getOrCreateSession(sessionId, {
    projectKey: projectKeyFromPayload(payload, userText),
    displayProjectTitle: "Новый проект",
  });
  if (isDuplicateRequest(session, requestId) && session.lastResponse) {
    return session.lastResponse;
  }
  session.projectKey = session.projectKey || projectKeyFromPayload(payload, userText);
  session.uploadedFiles = mergeIncomingUploads(session, incomingUploads);

  try {
    if (!session.accessGranted || action === "request_demo_access") {
      if (!validAccessToken(token)) {
        session.stage = "gate_pending";
        const denied = buildGatePendingResponse(
          session,
          payload,
          token
            ? "Этот demo access token не подходит. Проверь токен или запроси актуальный доступ у оператора."
            : "Укажи active demo access token, чтобы открыть рабочее пространство фабрики.",
        );
        rememberProcessedRequestId(session, requestId);
        setSessionResponse(session, denied);
        return denied;
      }
      session.accessGranted = true;
      if (!normalizeText(session.stage) || session.stage === "gate_pending") {
        session.stage = "discovery";
      }
      const hasTurnPayload = hasUserText || incomingUploads.length > 0;
      const continueWithTurn = hasTurnPayload && !["submit_access_token", "request_demo_access"].includes(action);
      if (continueWithTurn) {
        updateSession(session, { stage: session.stage, uploadedFiles: session.uploadedFiles });
      } else {
        const initial = await statusFlow(session, payload);
        rememberProcessedRequestId(session, requestId);
        setSessionResponse(session, initial);
        return initial;
      }
    }

    if (!isActionAllowedForStage(action, session.stage)) {
      const guardMessage = [
        "Это действие сейчас недоступно для текущего этапа.",
        "Продолжаем с актуальным состоянием проекта.",
      ].join(" ");
      const safe = withSafeMessage(await statusFlow(session, payload), guardMessage);
      rememberProcessedRequestId(session, requestId);
      setSessionResponse(session, safe);
      updateSession(session, { stage: session.stage, uploadedFiles: session.uploadedFiles });
      return safe;
    }

    let response;
    const correctionIntent = hasUserText && isLikelyBriefCorrectionText(userText);
    const simulationIntent = hasUserText && isProductionSimulationRequest(userText);
    const downloadsMode = ["downloads_ready", "confirmed"].includes(normalizeText(session.stage));
    const reviewMode = normalizeText(session.stage) === "awaiting_confirmation";
    const explicitSectionUpdates = payload?.brief_section_updates
      && typeof payload.brief_section_updates === "object"
      && Object.keys(payload.brief_section_updates).length > 0;
    const explicitCorrectionTargets = new Set();
    const explicitTargetHint = normalizeText(payload?.brief_feedback_target);
    if (explicitTargetHint) {
      explicitCorrectionTargets.add(explicitTargetHint);
    }
    if (explicitSectionUpdates) {
      Object.keys(payload.brief_section_updates || {}).forEach((topicId) => {
        const normalizedTopic = normalizeText(topicId);
        if (normalizedTopic) {
          explicitCorrectionTargets.add(normalizedTopic);
        }
      });
    }
    const lowConfidenceCorrection = hasUserText && isLowConfidenceBriefCorrectionText(userText);
    const correctionAllowedByText = hasUserText && (!lowConfidenceCorrection || explicitSectionUpdates);

    const textConfirmBrief = hasUserText
      && reviewMode
      && isLikelyConfirmBriefText(userText)
      && !correctionIntent;
    const textCorrectionBrief = hasUserText
      && reviewMode
      && correctionIntent
      && correctionAllowedByText;

    if ((action === "confirm_brief" || textConfirmBrief) && reviewMode) {
      await ensureBriefReady(session);
      session.stage = "confirmed";
      const generationId = Number(session.handoffGenerationId || 0) + 1;
      session.handoffGenerationId = generationId;
      session.summaryState = "running";
      void runSummaryGeneration(session, generationId);
      response = buildHandoffRunningResponse(session, payload);
    } else if (action === "confirm_brief" && !reviewMode) {
      response = withSafeMessage(
        await statusFlow(session, payload),
        "Brief сейчас не находится на этапе подтверждения. Сначала открой актуальную версию и проверь её.",
      );
    } else if (downloadsMode && simulationIntent) {
      pushUserMessage(session, userText, incomingUploads);
      response = buildDownloadsReadyResponse(
        session,
        payload,
        "Имитация запуска цифрового сотрудника готова. Открой production simulation и проверь стартовый результат.",
        { primaryArtifactKind: "production_simulation" },
      );
      pushAssistantMessage(session, response.next_question);
    } else if (
      action === "request_brief_correction"
      || textCorrectionBrief
      || (downloadsMode && correctionIntent && correctionAllowedByText)
    ) {
      if (!correctionAllowedByText && !explicitSectionUpdates) {
        response = withSafeMessage(
          buildAwaitingConfirmationResponse(session, payload, {
            theatreMessage: "Нужна конкретная правка brief: укажи, какой раздел и что именно изменить.",
            uploadedFiles: session.uploadedFiles,
          }),
          "Не вижу конкретной правки. Опиши точное изменение по смыслу или укажи раздел.",
        );
      } else {
      pushUserMessage(session, userText, incomingUploads);
      const revised = await reviseBrief(session, userText, {
        explicitTargets: Array.from(explicitCorrectionTargets),
      });
      session.briefText = revised;
      session.briefVersion = Math.max(1, Number(session.briefVersion || 0) + 1);
      syncSessionTopicAnswersFromBrief(session, revised);
      session.stage = "awaiting_confirmation";
      session.handoffGenerationId = Number(session.handoffGenerationId || 0) + 1;
      session.summaryPromise = null;
      session.summaryState = "idle";
      session.artifacts = [];
      response = buildAwaitingConfirmationResponse(session, payload, {
        theatreMessage: "Правки применены. Проверь обновлённый brief и подтверди версию.",
        nextQuestion: "Правку применил. Проверь обновлённый brief: если всё верно — подтверди, иначе отправь следующую правку.",
        uploadedFiles: session.uploadedFiles,
      });
      pushAssistantMessage(session, response.next_question);
      }
    } else if (downloadsMode && hasUserText) {
      pushUserMessage(session, userText, incomingUploads);
      response = buildDownloadsReadyResponse(
        session,
        payload,
        "Материалы уже готовы. Если хочешь доработать brief, напиши конкретную правку, и я переоткрою его.",
      );
      pushAssistantMessage(session, response.next_question);
    } else if (action === "reopen_brief") {
      session.stage = "awaiting_confirmation";
      session.handoffGenerationId = Number(session.handoffGenerationId || 0) + 1;
      session.summaryPromise = null;
      session.summaryState = "idle";
      session.artifacts = [];
      response = buildAwaitingConfirmationResponse(session, payload, {
        theatreMessage: "Brief переоткрыт для доработки. Внеси изменения и подтверди новую версию.",
        uploadedFiles: session.uploadedFiles,
      });
    } else if (
      action === "request_status"
      || action === "download_artifact"
      || action === "request_brief_review"
      || action === "preview_one_page"
    ) {
      response = await statusFlow(session, payload);
    } else {
      response = await discoveryFlow(session, payload, userText, incomingUploads);
    }

    rememberProcessedRequestId(session, requestId);
    setSessionResponse(session, response);
    updateSession(session, { stage: session.stage, uploadedFiles: session.uploadedFiles });
    return response;
  } catch (error) {
    console.error("[asc-demo] router.handleTurn:", error?.message || error);
    const fallback = buildErrorFallbackResponse(session, payload, normalizeText(error?.message));
    rememberProcessedRequestId(session, requestId);
    setSessionResponse(session, fallback);
    return fallback;
  }
}
