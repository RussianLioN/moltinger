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
import { generateBrief, reviseBrief } from "./brief.js";
import { getDiscoveryTopics, processDiscoveryTurn } from "./discovery.js";
import { generateArtifacts } from "./summary-generator.js";
import { getOrCreateSession, setSessionArtifacts, setSessionResponse, setSessionSummaryPromise, updateSession } from "./sessions.js";
import { normalizeText } from "./utils.js";

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

async function ensureBriefReady(session) {
  if (normalizeText(session.briefText)) {
    return session.briefText;
  }
  const briefText = await generateBrief(session);
  session.briefText = briefText;
  session.briefVersion = Math.max(1, Number(session.briefVersion || 0) + 1);
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

async function runSummaryGeneration(session) {
  if (session.summaryState === "running" && session.summaryPromise) {
    return session.summaryPromise;
  }

  const promise = (async () => {
    const artifacts = await generateArtifacts(session);
    setSessionArtifacts(session, artifacts);
    updateSession(session, {
      stage: "downloads_ready",
      summaryState: "ready",
      summaryPromise: null,
    });
    return artifacts;
  })().catch((error) => {
    console.error("[asc-demo] router.runSummaryGeneration:", error?.message || error);
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
  maybeAutonameProject(session, userText);
  pushUserMessage(session, userText, uploadedFiles);

  const discovery = await processDiscoveryTurn(session, userText, uploadedFiles);
  if (discovery.complete) {
    await ensureBriefReady(session);
    session.stage = "awaiting_confirmation";
    const response = buildAwaitingConfirmationResponse(session, payload, {
      theatreMessage: "Discovery завершён. Формирование brief...",
      uploadedFiles,
    });
    pushAssistantMessage(session, response.next_question);
    return response;
  }

  session.stage = "discovery";
  const response = buildDiscoveryResponse(session, payload, {
    nextQuestion: discovery.nextQuestion,
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
    await session.summaryPromise;
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
  const defaultTopic = getDiscoveryTopics()[0];
  const nextQuestion = normalizeText(session.currentQuestion, defaultTopic.question);
  const nextTopic = normalizeText(session.currentTopic, defaultTopic.id);
  return buildDiscoveryResponse(session, payload, {
    nextQuestion,
    nextTopic,
    whyAskingNow: normalizeText(session.whyAskingNow, defaultTopic.why),
    missingCoverage: session.missingCoverage || getDiscoveryTopics().map((topic) => topic.id),
    lowSignal: false,
    uploadedFiles: session.uploadedFiles || [],
    coveredCount: (session.coveredTopics || new Set()).size,
    totalCount: getDiscoveryTopics().length,
    helperExample: defaultTopic.question,
    questionSource: "adaptive_architect",
  });
}

export async function handleTurn(payload = {}) {
  const action = getAction(payload);
  const userText = getUserText(payload);
  const sessionId = sessionIdFromPayload(payload);
  const uploadedFiles = normalizeIncomingUploads(payload.uploaded_files || []);
  const token = getAccessToken(payload);

  const session = getOrCreateSession(sessionId, {
    projectKey: projectKeyFromPayload(payload, userText),
    displayProjectTitle: "Новый проект",
  });
  session.projectKey = session.projectKey || projectKeyFromPayload(payload, userText);
  session.uploadedFiles = uploadedFiles;

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
        setSessionResponse(session, denied);
        return denied;
      }
      session.accessGranted = true;
      session.stage = session.stage === "downloads_ready" ? "downloads_ready" : "discovery";
      const initial = await statusFlow(session, payload);
      setSessionResponse(session, initial);
      return initial;
    }

    let response;
    if (action === "confirm_brief") {
      await ensureBriefReady(session);
      session.stage = "confirmed";
      if (session.summaryState !== "running" && session.summaryState !== "ready") {
        session.summaryState = "running";
        void runSummaryGeneration(session);
      }
      response = buildHandoffRunningResponse(session, payload);
    } else if (action === "request_brief_correction") {
      const revised = await reviseBrief(session, userText);
      session.briefText = revised;
      session.briefVersion = Math.max(1, Number(session.briefVersion || 0) + 1);
      session.stage = "awaiting_confirmation";
      response = buildAwaitingConfirmationResponse(session, payload, {
        theatreMessage: "Правки применены. Проверь обновлённый brief и подтверди версию.",
        uploadedFiles,
      });
    } else if (action === "reopen_brief") {
      session.stage = "awaiting_confirmation";
      session.summaryPromise = null;
      session.summaryState = "idle";
      response = buildAwaitingConfirmationResponse(session, payload, {
        theatreMessage: "Brief переоткрыт для доработки. Внеси изменения и подтверди новую версию.",
        uploadedFiles,
      });
    } else if (action === "request_status" || action === "download_artifact" || action === "request_brief_review") {
      response = await statusFlow(session, payload);
    } else {
      response = await discoveryFlow(session, payload, userText, uploadedFiles);
    }

    setSessionResponse(session, response);
    updateSession(session, { stage: session.stage, uploadedFiles });
    return response;
  } catch (error) {
    console.error("[asc-demo] router.handleTurn:", error?.message || error);
    const fallback = buildErrorFallbackResponse(session, payload, normalizeText(error?.message));
    setSessionResponse(session, fallback);
    return fallback;
  }
}
