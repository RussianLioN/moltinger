(() => {
  const STORAGE_KEY = "agent-factory-web-demo-shell.v3";
  const ACCESS_TOKEN_KEY = "agent-factory-web-demo-access-token.v1";
  const DEFAULT_ACCESS_TOKEN = "demo-access-token";
  const MAX_LOCAL_UPLOAD_FILES = 4;
  const MAX_LOCAL_UPLOAD_BYTES = 512 * 1024;
  const IS_AUTOMATION = Boolean(window.navigator?.webdriver) || /playwright/i.test(window.navigator?.userAgent || "");
  const MIN_PENDING_VISUAL_MS = IS_AUTOMATION ? 80 : 420;
  const TURN_TIMEOUT_MS = IS_AUTOMATION ? 20_000 : 90_000;
  const DEFAULT_PROJECT_TITLE = "Новый проект";
  const SIDEBAR_WIDTH_DEFAULT = 264;
  const SIDEBAR_WIDTH_MIN = 220;
  const SIDEBAR_WIDTH_MAX = 560;
  const MOBILE_LAYOUT_QUERY = "(max-width: 920px)";
  const SUPPORTED_UPLOAD_EXTENSIONS = new Set([
    "txt",
    "md",
    "csv",
    "tsv",
    "json",
    "xml",
    "yaml",
    "yml",
    "log",
    "pdf",
    "doc",
    "docx",
    "odt",
    "xls",
    "xlsx",
    "ods",
    "ppt",
    "pptx",
    "odp",
    "rtf",
    "html",
    "htm",
    "png",
    "jpg",
    "jpeg",
    "webp",
    "gif",
  ]);
  const ACTION_LABELS = {
    start_project: "Новый проект",
    submit_turn: "Ответить",
    request_status: "Обновить проект",
    request_brief_review: "Открыть brief",
    request_brief_correction: "Внести правки",
    confirm_brief: "Подтвердить brief",
    reopen_brief: "Переоткрыть brief",
    download_artifact: "Открыть файлы",
    submit_access_token: "Открыть demo",
  };
  const ACTION_PRIORITY = [
    "submit_turn",
    "request_brief_correction",
    "confirm_brief",
    "reopen_brief",
    "request_brief_review",
    "request_status",
    "start_project",
  ];
  const STATUS_LABELS = {
    gate_pending: "Нужен доступ",
    discovery_in_progress: "В работе",
    awaiting_user_reply: "В работе",
    awaiting_confirmation: "Нужно внимание",
    confirmed: "Готово",
    playground_ready: "Готово",
    reopened: "Нужно внимание",
  };
  const MOCK_DISCOVERY_TOPICS = [
    {
      id: "problem",
      question: "Какую бизнес-проблему должен решить будущий агент?",
      why: "Нужно зафиксировать ценность автоматизации и целевой эффект.",
      signals: ["проблем", "боль", "долго", "ошиб", "срок", "узкое место"],
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
  const dom = {
    root: document.querySelector('[data-role="app-root"]'),
    appFrame: document.querySelector(".app-frame"),
    sidebarResizer: document.querySelector('[data-role="sidebar-resizer"]'),
    workspaceShell: document.querySelector('[data-role="workspace-shell"]'),
    gateNote: document.querySelector('[data-role="gate-note"]'),
    accessForm: document.querySelector('[data-role="access-form"]'),
    accessTokenInput: document.querySelector('[data-role="access-token-input"]'),
    accessSubmit: document.querySelector('[data-role="access-submit"]'),
    projectList: document.querySelector('[data-role="project-list"]'),
    newProject: document.querySelector('[data-role="new-project"]'),
    projectTitle: document.querySelector('[data-role="project-title"]'),
    projectSubtitle: document.querySelector('[data-role="project-subtitle"]'),
    projectMenu: document.querySelector('[data-role="project-menu"]'),
    homePanel: document.querySelector('[data-role="home-panel"]'),
    homeExamples: document.querySelector('[data-role="home-examples"]'),
    sidePanel: document.querySelector('[data-role="side-panel"]'),
    sidePanelToggle: document.querySelector('[data-role="side-panel-toggle"]'),
    sidePanelClose: document.querySelector('[data-role="side-panel-close"]'),
    sidePanelEyebrow: document.querySelector('[data-role="side-panel-eyebrow"]'),
    sidePanelTitle: document.querySelector('[data-role="side-panel-title"]'),
    sidePanelSummary: document.querySelector('[data-role="side-panel-summary"]'),
    panelCardList: document.querySelector('[data-role="panel-card-list"]'),
    artifactSection: document.querySelector('[data-role="artifact-section"]'),
    composerHelperExample: document.querySelector('[data-role="composer-helper-example"]'),
    connectionState: document.querySelector('[data-role="connection-state"]'),
    sessionBadge: document.querySelector('[data-role="session-badge"]'),
    refreshSession: document.querySelector('[data-role="refresh-session"]'),
    threadPanel: document.querySelector('[data-role="thread-panel"]'),
    chatLog: document.querySelector('[data-role="chat-log"]'),
    composerForm: document.querySelector('[data-role="composer-form"]'),
    composerLeadLabel: document.querySelector('[data-role="composer-lead-label"]'),
    composerMode: document.querySelector('[data-role="composer-mode"]'),
    composerThinking: document.querySelector('[data-role="composer-thinking"]'),
    composerInput: document.querySelector('[data-role="composer-input"]'),
    composerSubmit: document.querySelector('[data-role="composer-submit"]'),
    composerNotice: document.querySelector('[data-role="composer-notice"]'),
    attachmentInput: document.querySelector('[data-role="attachment-input"]'),
    attachmentList: document.querySelector('[data-role="attachment-list"]'),
    quickActions: document.querySelector('[data-role="quick-actions"]'),
    statusUserVisible: document.querySelector('[data-role="status-user-visible"]'),
    statusNextAction: document.querySelector('[data-role="status-next-action"]'),
    statusBriefVersion: document.querySelector('[data-role="status-brief-version"]'),
    statusUploadCount: document.querySelector('[data-role="status-upload-count"]'),
    statusDownloadReadiness: document.querySelector('[data-role="status-download-readiness"]'),
    statusProjectKey: document.querySelector('[data-role="status-project-key"]'),
    statusSessionId: document.querySelector('[data-role="status-session-id"]'),
    statusOperatorAttention: document.querySelector('[data-role="status-operator-attention"]'),
    artifactList: document.querySelector('[data-role="artifact-list"]'),
    artifactEmpty: document.querySelector('[data-role="artifact-empty"]'),
    messageTemplate: document.querySelector('[data-role="message-template"]'),
    artifactTemplate: document.querySelector('[data-role="artifact-template"]'),
    panelCardTemplate: document.querySelector('[data-role="panel-card-template"]'),
    projectActionsMenu: document.querySelector('[data-role="project-actions-menu"]'),
    projectActionsRename: document.querySelector('[data-role="project-actions-rename"]'),
    projectActionsDelete: document.querySelector('[data-role="project-actions-delete"]'),
  };

  const state = {
    accessToken: "",
    connectionMode: "booting",
    requestCounter: 0,
    sidebarWidth: SIDEBAR_WIDTH_DEFAULT,
    activeProjectId: "",
    projects: [],
    gateNote: "Токен запрашивается только один раз для этой браузерной сессии.",
    gateNoteTone: "neutral",
    awaitingResponse: false,
    activeAbortController: null,
    activeRequest: null,
    composerNotice: { text: "", tone: "info" },
    accessProbePending: false,
    projectActions: {
      open: false,
      projectId: "",
      x: 0,
      y: 0,
    },
  };

  function safeJsonParse(value, fallback) {
    try {
      return JSON.parse(value);
    } catch (_error) {
      return fallback;
    }
  }

  function normalizeText(value, fallback = "") {
    if (typeof value === "string") {
      const trimmed = value.trim();
      return trimmed || fallback;
    }
    if (typeof value === "number" || typeof value === "boolean") {
      return String(value);
    }
    return fallback;
  }

  function slugify(input, fallback = "value") {
    const normalized = normalizeText(input, fallback)
      .toLowerCase()
      .replace(/[^a-z0-9а-яё]+/gi, "-")
      .replace(/^-+|-+$/g, "");
    return normalized || fallback;
  }

  function nowIso() {
    return new Date().toISOString();
  }

  function defaultSessionId(projectId) {
    return `web-demo-session-${slugify(projectId, "project")}`;
  }

  function formatBytes(value) {
    const size = Number(value) || 0;
    if (size >= 1024 * 1024) {
      return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    }
    if (size >= 1024) {
      return `${Math.round(size / 1024)} KB`;
    }
    return `${size} B`;
  }

  function summarizeUploadMeta(upload) {
    const meta = [];
    if (upload?.original_size_bytes || upload?.size_bytes) {
      meta.push(formatBytes(upload.original_size_bytes || upload.size_bytes));
    }
    if (upload?.truncated) {
      meta.push("обрезан");
    }
    if (upload?.ingest_status === "metadata_only") {
      meta.push("без авто-извлечения");
    }
    return meta.join(" · ");
  }

  function uniqueUploads(items) {
    const seen = new Set();
    return (items || []).filter((item) => {
      const key = normalizeText(item?.upload_id) || `${normalizeText(item?.name)}:${item?.original_size_bytes || item?.size_bytes || 0}`;
      if (!key || seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  }

  function bufferToBase64(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    const chunkSize = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
    }
    return window.btoa(binary);
  }

  async function readLocalUpload(file) {
    const truncated = file.size > MAX_LOCAL_UPLOAD_BYTES;
    const source = truncated ? file.slice(0, MAX_LOCAL_UPLOAD_BYTES) : file;
    const buffer = await source.arrayBuffer();
    return {
      upload_id: `upload-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`,
      name: file.name,
      content_type: file.type || "application/octet-stream",
      size_bytes: buffer.byteLength,
      original_size_bytes: file.size,
      truncated,
      content_base64: bufferToBase64(buffer),
    };
  }

  function isSupportedUploadFile(file) {
    const name = normalizeText(file?.name);
    const ext = name.includes(".") ? name.split(".").pop().toLowerCase() : "";
    if (SUPPORTED_UPLOAD_EXTENSIONS.has(ext)) {
      return true;
    }
    const type = normalizeText(file?.type).toLowerCase();
    if (!type) {
      return false;
    }
    if (type.startsWith("text/") || type.startsWith("image/")) {
      return true;
    }
    return type === "application/pdf"
      || type.includes("word")
      || type.includes("excel")
      || type.includes("spreadsheet")
      || type.includes("presentation")
      || type.includes("officedocument")
      || type.includes("rtf");
  }

  function showComposerNotice(text, tone = "info") {
    state.composerNotice = {
      text: normalizeText(text),
      tone: normalizeText(tone, "info"),
    };
  }

  function clearComposerNotice() {
    state.composerNotice = { text: "", tone: "info" };
  }

  function hasFilePayload(dataTransfer) {
    if (!dataTransfer) {
      return false;
    }
    if (dataTransfer.files && dataTransfer.files.length > 0) {
      return true;
    }
    return Array.from(dataTransfer.types || []).includes("Files");
  }

  async function ingestSelectedFiles(project, selectedFiles) {
    if (!project || !selectedFiles.length) {
      return;
    }

    const unsupported = selectedFiles.filter((file) => !isSupportedUploadFile(file));
    const supported = selectedFiles.filter((file) => isSupportedUploadFile(file));
    const unsupportedNames = unsupported.slice(0, 3).map((file) => file.name || "без имени");
    const remainingSlots = Math.max(0, MAX_LOCAL_UPLOAD_FILES - project.pendingUploads.length);
    const acceptedFiles = supported.slice(0, remainingSlots);
    const skippedCount = Math.max(0, supported.length - acceptedFiles.length);
    const loadedUploads = [];
    const failedUploads = [];

    for (const file of acceptedFiles) {
      try {
        loadedUploads.push(await readLocalUpload(file));
      } catch (_error) {
        failedUploads.push(file.name || "без имени");
      }
    }

    if (loadedUploads.length) {
      project.pendingUploads = uniqueUploads([...project.pendingUploads, ...loadedUploads]).slice(0, MAX_LOCAL_UPLOAD_FILES);
      project.updatedAt = nowIso();
      renderAttachmentList(project);
      renderStatus(project);
      persist();
      focusComposerSoon();
    }

    const warnings = [];
    if (unsupported.length) {
      warnings.push(`Не добавлены неподдерживаемые файлы: ${unsupportedNames.join(", ")}${unsupported.length > unsupportedNames.length ? "..." : ""}`);
    }
    if (skippedCount) {
      warnings.push(`Превышен лимит: максимум ${MAX_LOCAL_UPLOAD_FILES} файла за один ответ.`);
    }
    if (failedUploads.length) {
      warnings.push(`Не удалось прочитать: ${failedUploads.slice(0, 3).join(", ")}${failedUploads.length > 3 ? "..." : ""}`);
    }
    if (warnings.length) {
      showComposerNotice(warnings.join(" "), unsupported.length ? "warning" : "info");
    } else if (loadedUploads.length) {
      clearComposerNotice();
    }
    renderComposer(project);
  }

  function shorten(value, limit = 96) {
    const text = normalizeText(value);
    if (!text) {
      return "";
    }
    return text.length > limit ? `${text.slice(0, limit - 1).trim()}…` : text;
  }

  function formatRelativeTime(isoValue) {
    const timestamp = Date.parse(isoValue || "");
    if (!timestamp) {
      return "только что";
    }
    const deltaMs = Date.now() - timestamp;
    const minutes = Math.round(deltaMs / 60000);
    if (minutes <= 1) {
      return "только что";
    }
    if (minutes < 60) {
      return `${minutes} мин назад`;
    }
    const hours = Math.round(minutes / 60);
    if (hours < 24) {
      return `${hours} ч назад`;
    }
    const days = Math.round(hours / 24);
    return `${days} д назад`;
  }

  function isMobileLayout() {
    return window.matchMedia(MOBILE_LAYOUT_QUERY).matches;
  }

  function sidebarMaxByViewport() {
    const viewport = Math.max(0, window.innerWidth || 0);
    const roomForWorkspace = Math.max(SIDEBAR_WIDTH_MIN, viewport - 560);
    return Math.max(SIDEBAR_WIDTH_MIN, Math.min(SIDEBAR_WIDTH_MAX, roomForWorkspace));
  }

  function clampSidebarWidth(value) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return SIDEBAR_WIDTH_DEFAULT;
    }
    const max = sidebarMaxByViewport();
    return Math.min(Math.max(Math.round(parsed), SIDEBAR_WIDTH_MIN), max);
  }

  function applySidebarWidth() {
    const nextWidth = clampSidebarWidth(state.sidebarWidth);
    state.sidebarWidth = nextWidth;
    if (dom.root) {
      dom.root.style.setProperty("--sidebar-width", `${nextWidth}px`);
    }
    if (dom.sidebarResizer) {
      dom.sidebarResizer.setAttribute("aria-valuemin", String(SIDEBAR_WIDTH_MIN));
      dom.sidebarResizer.setAttribute("aria-valuemax", String(sidebarMaxByViewport()));
      dom.sidebarResizer.setAttribute("aria-valuenow", String(nextWidth));
    }
  }

  function updateSidebarWidth(nextWidth, options = {}) {
    state.sidebarWidth = clampSidebarWidth(nextWidth);
    applySidebarWidth();
    if (options.persist) {
      persist();
    }
  }

  function selectionModeFor(action) {
    const map = {
      start_project: "new_project",
      submit_turn: "continue_active",
      request_status: "status_only",
      request_brief_review: "review_brief",
      request_brief_correction: "review_brief",
      confirm_brief: "review_brief",
      reopen_brief: "reopen_brief",
      download_artifact: "download_ready",
    };
    return map[action] || "continue_active";
  }

  function nextRequestId(project, action) {
    state.requestCounter += 1;
    return `browser-${slugify(project.id, "project")}-${slugify(action, "turn")}-${String(state.requestCounter).padStart(4, "0")}`;
  }

  function projectSnapshot(project) {
    return {
      id: project.id,
      title: project.title,
      titleEdited: Boolean(project.titleEdited),
      sidePanelOpen: Boolean(project.sidePanelOpen),
      lastPanelMode: normalizeText(project.lastPanelMode),
      sessionId: project.sessionId,
      timeline: Array.isArray(project.timeline) ? project.timeline : [],
      lastResponse: project.lastResponse && typeof project.lastResponse === "object" ? project.lastResponse : null,
      draftText: normalizeText(project.draftText),
      createdAt: normalizeText(project.createdAt, nowIso()),
      updatedAt: normalizeText(project.updatedAt, nowIso()),
      currentAction: normalizeText(project.currentAction, "start_project"),
      mockStage: normalizeText(project.mockStage, "gate_pending"),
      lastAutoFollowupSource: normalizeText(project.lastAutoFollowupSource),
      lastResumeFingerprint: normalizeText(project.lastResumeFingerprint),
    };
  }

  function sanitizeTimeline(items) {
    return (Array.isArray(items) ? items : []).map((entry) => {
      const message = entry && typeof entry === "object" ? { ...entry } : {};
      const title = normalizeText(message.title);
      if (/^следующий вопрос$/i.test(title)) {
        message.title = "";
      }
      return message;
    });
  }

  function normalizeProjectRecord(value) {
    const record = value && typeof value === "object" ? value : {};
    const id = normalizeText(record.id, `project-${Date.now()}-${Math.random().toString(16).slice(2, 7)}`);
    const updatedAt = normalizeText(record.updatedAt, nowIso());
    return {
      id,
      title: normalizeText(record.title, DEFAULT_PROJECT_TITLE),
      titleEdited: Boolean(record.titleEdited),
      sidePanelOpen: Boolean(record.sidePanelOpen),
      lastPanelMode: normalizeText(record.lastPanelMode),
      sessionId: normalizeText(record.sessionId, defaultSessionId(id)),
      timeline: sanitizeTimeline(record.timeline),
      lastResponse: record.lastResponse && typeof record.lastResponse === "object" ? record.lastResponse : null,
      draftText: normalizeText(record.draftText),
      createdAt: normalizeText(record.createdAt, updatedAt),
      updatedAt,
      currentAction: normalizeText(record.currentAction, "start_project"),
      mockStage: normalizeText(record.mockStage, "gate_pending"),
      lastAutoFollowupSource: normalizeText(record.lastAutoFollowupSource),
      lastResumeFingerprint: normalizeText(record.lastResumeFingerprint),
      pendingUploads: [],
    };
  }

  function createProject(seed = {}) {
    const id = normalizeText(seed.id, `project-${Date.now()}-${Math.random().toString(16).slice(2, 7)}`);
    return normalizeProjectRecord({
      id,
      title: normalizeText(seed.title, DEFAULT_PROJECT_TITLE),
      titleEdited: Boolean(seed.titleEdited),
      sessionId: normalizeText(seed.sessionId, defaultSessionId(id)),
      timeline: [],
      lastResponse: null,
      draftText: "",
      createdAt: nowIso(),
      updatedAt: nowIso(),
      currentAction: "start_project",
      mockStage: "gate_pending",
      sidePanelOpen: false,
      lastPanelMode: "",
      lastAutoFollowupSource: "",
      lastResumeFingerprint: "",
    });
  }

  function getActiveProject() {
    return state.projects.find((project) => project.id === state.activeProjectId) || state.projects[0] || null;
  }

  function persist() {
    const payload = {
      connectionMode: state.connectionMode,
      requestCounter: state.requestCounter,
      sidebarWidth: state.sidebarWidth,
      activeProjectId: state.activeProjectId,
      projects: state.projects.map((project) => projectSnapshot(project)),
    };
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    if (state.accessToken) {
      window.sessionStorage.setItem(ACCESS_TOKEN_KEY, state.accessToken);
    } else {
      window.sessionStorage.removeItem(ACCESS_TOKEN_KEY);
    }
  }

  function hydrate() {
    const saved = safeJsonParse(window.localStorage.getItem(STORAGE_KEY) || "null", null);
    state.accessToken = normalizeText(window.sessionStorage.getItem(ACCESS_TOKEN_KEY), "");
    if (saved && typeof saved === "object") {
      state.connectionMode = normalizeText(saved.connectionMode, "booting");
      state.requestCounter = Number.isFinite(saved.requestCounter) ? saved.requestCounter : 0;
      state.sidebarWidth = clampSidebarWidth(saved.sidebarWidth);
      state.projects = Array.isArray(saved.projects) && saved.projects.length
        ? saved.projects.map((project) => normalizeProjectRecord(project))
        : [];
      state.projects.forEach((project) => {
        if (project.titleEdited) {
          return;
        }
        const firstUserMessage = (project.timeline || []).find(
          (message) => message.role === "user" && Boolean(normalizeText(message.body)),
        );
        if (!firstUserMessage) {
          return;
        }
        if (looksLikeExcerpt(project.title, firstUserMessage.body) || isGenericProjectTitle(project.title)) {
          const repaired = prettifyTitle(firstUserMessage.body);
          if (repaired) {
            project.title = repaired;
          }
        }
      });
      state.activeProjectId = normalizeText(saved.activeProjectId);
    }
    if (!state.projects.length) {
      state.projects = [createProject()];
    }
    if (!state.activeProjectId || !state.projects.some((project) => project.id === state.activeProjectId)) {
      state.activeProjectId = state.projects[0].id;
    }
  }

  function saveComposerDraft() {
    const project = getActiveProject();
    if (!project || !dom.composerInput) {
      return;
    }
    project.draftText = dom.composerInput.value;
  }

  function setBusy(isBusy) {
    dom.root.dataset.mode = isBusy ? "busy" : "ready";
    dom.composerSubmit.disabled = isBusy && !state.awaitingResponse;
    dom.composerInput.disabled = false;
    dom.attachmentInput.disabled = state.awaitingResponse;
    dom.refreshSession.disabled = isBusy;
    dom.accessSubmit.disabled = isBusy;
    dom.accessTokenInput.disabled = isBusy && !state.accessToken;
    dom.projectMenu.disabled = isBusy;
    dom.newProject.disabled = isBusy;
  }

  function focusComposerSoon() {
    if (!state.accessToken || !dom.composerInput || dom.composerInput.disabled) {
      return;
    }
    window.setTimeout(() => {
      dom.composerInput.focus();
    }, 0);
  }

  function ensureWorkspaceAccess() {
    if (state.accessToken) {
      return true;
    }
    closeProjectActionsMenu();
    renderProjectActionsMenu();
    if (dom.accessTokenInput) {
      dom.accessTokenInput.focus();
    }
    return false;
  }

  function hasConversationActivity(project) {
    if (!project) {
      return false;
    }
    const response = project.lastResponse || {};
    const visibleStatus = normalizeText(response.status_snapshot?.user_visible_status || response.status);
    const transcriptSize = Array.isArray(project.timeline) ? project.timeline.length : 0;
    return Boolean(project.sessionId && response.web_demo_session?.status) || transcriptSize > 0 || ["awaiting_user_reply", "awaiting_confirmation", "confirmed", "playground_ready", "reopened"].includes(visibleStatus);
  }

  function currentResponse(project) {
    return project?.lastResponse || null;
  }

  function currentQuestion(project) {
    const response = currentResponse(project) || {};
    const explicit = normalizeText(response.ui_projection?.current_question || response.next_question);
    if (explicit) {
      return explicit;
    }
    const card = Array.isArray(response.reply_cards)
      ? response.reply_cards.find((item) => ["discovery_question", "confirmation_prompt"].includes(item.card_kind))
      : null;
    return normalizeText(card?.body_text);
  }

  function currentTopic(project) {
    const response = currentResponse(project) || {};
    return normalizeText(response.ui_projection?.current_topic || response.next_topic);
  }

  function currentStatus(project) {
    const response = currentResponse(project) || {};
    return normalizeText(response.status_snapshot?.user_visible_status || response.status || "gate_pending");
  }

  function statusLabel(project) {
    const response = currentResponse(project) || {};
    return normalizeText(response.status_snapshot?.user_visible_status_label || STATUS_LABELS[currentStatus(project)] || "Черновик");
  }

  function nextAction(project) {
    const response = currentResponse(project) || {};
    return normalizeText(
      response.ui_projection?.preferred_ui_action
      || response.status_snapshot?.next_recommended_action
      || response.next_action
      || project?.currentAction
      || "start_project",
      "start_project",
    );
  }

  function leadLabelFor(project) {
    if (!state.accessToken) {
      return "Демо-доступ";
    }
    if (state.awaitingResponse) {
      return "Агент отвечает";
    }
    return "Сообщение";
  }

  function modeTextFor(project) {
    if (!state.accessToken) {
      return "Открыть demo";
    }
    if (state.awaitingResponse) {
      return "Нажми ■ чтобы остановить";
    }
    if (!hasConversationActivity(project)) {
      return "Опиши задачу";
    }
    return "Ответ агенту-архитектору";
  }

  function placeholderFor(project) {
    if (!state.accessToken) {
      return "Введи access token";
    }
    const action = project?.currentAction || "start_project";
    const topic = currentTopic(project);
    const status = currentStatus(project);
    if (!hasConversationActivity(project)) {
      return "Коротко опиши процесс, который хочешь автоматизировать.";
    }
    if (action === "confirm_brief") {
      return "Подтверди brief кнопкой или коротко опиши, что нужно исправить.";
    }
    if (action === "request_brief_correction") {
      return "Опиши, что поправить в brief.";
    }
    if (action === "reopen_brief") {
      return "Опиши, что нужно доуточнить, чтобы переоткрыть brief.";
    }
    if (status === "playground_ready") {
      return "Если нужны правки, опиши их, и я переоткрою brief.";
    }
    if (topic === "problem") {
      return "Опиши ключевую бизнес-проблему и почему это важно сейчас.";
    }
    if (topic === "target_users") {
      return "Укажи, кто будет основным пользователем или выгодоприобретателем.";
    }
    if (topic === "current_workflow") {
      return "Опиши текущий процесс и где сейчас теряется время.";
    }
    if (topic === "desired_outcome") {
      return "Опиши, какой бизнес-результат нужен после автоматизации.";
    }
    if (topic === "user_story") {
      return "Опиши, кому и в какой рабочей ситуации агент помогает в первую очередь.";
    }
    if (topic === "input_examples") {
      return "Приведи 1-2 примера или прикрепи файл с примерами.";
    }
    if (topic === "expected_outputs") {
      return "Опиши ожидаемый результат на выходе.";
    }
    if (topic === "constraints") {
      return "Перечисли ограничения, запреты и исключения, которые обязательно учитывать.";
    }
    if (topic === "success_metrics") {
      return "Укажи метрики успеха: время, качество, SLA и другие критерии.";
    }
    return "Опиши, какой процесс нужно автоматизировать.";
  }

  function helperExampleFor(project) {
    if (!state.accessToken) {
      return "Введи access token, и после этого откроется рабочее пространство проекта.";
    }
    const action = project?.currentAction || "start_project";
    const question = currentQuestion(project);
    const topic = currentTopic(project);
    const status = currentStatus(project);

    if (!hasConversationActivity(project)) {
      return "Например: автоматизировать подготовку one-page summary по клиенту для кредитного комитета.";
    }
    if (action === "confirm_brief") {
      return "Например: подтверждаю brief. Или: добавь отдельные правила для срочных заявок.";
    }
    if (action === "request_brief_correction") {
      return "Например: добавь ограничения по роли пользователя и уточни метрики успеха.";
    }
    if (action === "reopen_brief") {
      return "Например: нужно доуточнить входные данные и сценарии исключений.";
    }
    if (status === "playground_ready") {
      return "Например: нужно доработать brief перед повторной генерацией материалов.";
    }
    if (topic === "target_users" || /пользовател/i.test(question)) {
      return "Например: пользователи — члены кредитного комитета и клиентская служба.";
    }
    if (topic === "current_workflow" || /как этот процесс/i.test(question)) {
      return "Например: сотрудник вручную собирает данные из трёх систем и сравнивает их в Excel.";
    }
    if (topic === "input_examples" || /пример|входн/i.test(question)) {
      return "Например: можно приложить файл с образцом заявки, отчёта или one-page summary.";
    }
    if (topic === "expected_outputs" || /результат|выход/i.test(question)) {
      return "Например: на выходе нужна аналитическая карточка, рекомендация и краткое заключение.";
    }
    if (topic === "problem" || /бизнес-проблем/i.test(question)) {
      return "Например: нужно сократить время согласования и повысить число рассмотренных кейсов.";
    }
    const projected = normalizeText(project?.lastResponse?.ui_projection?.composer_helper_example);
    if (projected) {
      return projected;
    }
    return "Отвечай простыми рабочими формулировками. Если есть примеры в файлах, прикрепи их прямо сюда.";
  }

  function submitLabelFor(project) {
    const action = project?.currentAction || "start_project";
    if (action === "confirm_brief") {
      return "Подтвердить";
    }
    if (action === "request_brief_review") {
      return "Открыть brief";
    }
    if (action === "request_status") {
      return "Обновить проект";
    }
    if (action === "reopen_brief") {
      return "Переоткрыть";
    }
    return "Отправить";
  }

  function projectPreview(project) {
    const question = currentQuestion(project);
    if (question) {
      return shorten(question, 84);
    }
    const lastUserMessage = [...(project?.timeline || [])].reverse().find((message) => message.role === "user");
    if (lastUserMessage?.body) {
      return shorten(lastUserMessage.body, 84);
    }
    return "Начни с описания задачи";
  }

  function projectSubtitle(project) {
    const status = currentStatus(project);
    if (!hasConversationActivity(project)) {
      return "Опиши задачу простыми словами. После первого содержательного ответа проект сам получит рабочее имя.";
    }
    if (status === "awaiting_confirmation") {
      return "Brief собран. Открой правую панель, чтобы проверить summary, внести правки или подтвердить версию.";
    }
    if (status === "playground_ready" || status === "confirmed") {
      return "Материалы готовы. Открой правую панель, чтобы скачать артефакты или вернуть проект на доработку.";
    }
    return "Продолжай диалог с агентом-архитектором и при необходимости прикладывай файлы с примерами.";
  }

  function responseActions(response) {
    const fromCards = Array.isArray(response?.reply_cards)
      ? response.reply_cards.flatMap((card) => (Array.isArray(card.action_hints) ? card.action_hints : []))
      : [];
    const unique = [...new Set(fromCards.map((action) => normalizeText(action)).filter(Boolean))];
    if (unique.length) {
      return unique;
    }
    if (!response?.access_gate?.granted) {
      return ["submit_access_token"];
    }
    return [
      normalizeText(response?.ui_projection?.preferred_ui_action),
      normalizeText(response?.status_snapshot?.next_recommended_action),
      normalizeText(response?.next_action),
      "request_status",
    ].filter(Boolean);
  }

  function availableActions(project) {
    const response = currentResponse(project);
    if (!response) {
      return hasConversationActivity(project) ? ["submit_turn", "request_status"] : ["start_project"];
    }
    return responseActions(response);
  }

  function statusTone(status) {
    if (["awaiting_confirmation", "reopened"].includes(status)) {
      return "attention";
    }
    if (["playground_ready", "confirmed"].includes(status)) {
      return "success";
    }
    return "neutral";
  }

  function renderConnection() {
    const labels = {
      booting: "Подготовка shell",
      live: "Подключен live adapter",
      mock: "Локальный mock fallback",
      error: "Adapter недоступен",
    };
    dom.connectionState.textContent = labels[state.connectionMode] || state.connectionMode;
  }

  function renderSessionBadge(project) {
    const sessionId = normalizeText(project?.lastResponse?.web_demo_session?.web_demo_session_id || project?.sessionId);
    dom.sessionBadge.textContent = sessionId ? `Сессия ${sessionId}` : "Сессия ещё не открыта";
  }

  function renderGateNote() {
    if (!dom.gateNote) {
      return;
    }
    dom.gateNote.textContent = state.gateNote;
    dom.gateNote.dataset.tone = normalizeText(state.gateNoteTone, "neutral");
  }

  function setGateNote(note, tone = "neutral") {
    state.gateNote = normalizeText(note, "Нужен access token для controlled demo surface.");
    state.gateNoteTone = normalizeText(tone, "neutral");
    renderGateNote();
  }

  function renderShellStage(project) {
    dom.root.dataset.access = state.accessToken ? "granted" : "gated";
    dom.root.dataset.stage = state.accessToken
      ? (hasConversationActivity(project) ? "active" : "empty")
      : "gated";
  }

  function closeProjectActionsMenu() {
    state.projectActions.open = false;
    state.projectActions.projectId = "";
  }

  function openProjectActionsMenu(projectId, triggerElement) {
    if (!ensureWorkspaceAccess()) {
      return;
    }
    const project = state.projects.find((item) => item.id === projectId);
    if (!project || !triggerElement) {
      return;
    }
    if (state.projectActions.open && state.projectActions.projectId === project.id) {
      closeProjectActionsMenu();
      renderProjectActionsMenu();
      return;
    }
    const rect = triggerElement.getBoundingClientRect();
    state.projectActions.open = true;
    state.projectActions.projectId = project.id;
    state.projectActions.x = Math.max(12, Math.round(rect.right - 180));
    state.projectActions.y = Math.max(12, Math.round(rect.bottom + 8));
    renderProjectActionsMenu();
  }

  function renderProjectActionsMenu() {
    const menu = dom.projectActionsMenu;
    if (!menu) {
      return;
    }
    const selectedProject = state.projects.find((item) => item.id === state.projectActions.projectId);
    if (!state.projectActions.open || !selectedProject) {
      menu.hidden = true;
      return;
    }
    menu.hidden = false;
    const menuRect = menu.getBoundingClientRect();
    const maxLeft = Math.max(12, window.innerWidth - menuRect.width - 12);
    const maxTop = Math.max(12, window.innerHeight - menuRect.height - 12);
    const left = Math.min(state.projectActions.x, maxLeft);
    const top = Math.min(state.projectActions.y, maxTop);
    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;
  }

  function createProjectCard(project) {
    const article = document.createElement("article");
    article.className = `project-card${project.id === state.activeProjectId ? " is-active" : ""}`;
    article.dataset.projectId = project.id;

    const main = document.createElement("button");
    main.type = "button";
    main.className = "project-card__main";

    const title = document.createElement("span");
    title.className = "project-card__title";
    title.textContent = project.title;
    main.append(title);
    main.addEventListener("click", () => {
      switchProject(project.id);
    });

    const menu = document.createElement("button");
    menu.type = "button";
    menu.className = "project-card__menu";
    menu.textContent = "⋯";
    menu.setAttribute("aria-label", `Действия для проекта ${project.title}`);
    menu.addEventListener("click", (event) => {
      event.stopPropagation();
      openProjectActionsMenu(project.id, menu);
    });

    article.append(main, menu);
    return article;
  }

  function renderProjectList() {
    dom.projectList.innerHTML = "";
    const ordered = [...state.projects].sort((left, right) => Date.parse(right.updatedAt || "") - Date.parse(left.updatedAt || ""));
    ordered.forEach((project) => {
      dom.projectList.appendChild(createProjectCard(project));
    });
  }

  function renderTopbar(project) {
    dom.projectTitle.textContent = project?.title || DEFAULT_PROJECT_TITLE;
    dom.projectSubtitle.textContent = projectSubtitle(project);
    renderSidePanelToggle(project);
  }

  function activeSessionUploads(project) {
    return Array.isArray(project?.lastResponse?.uploaded_files) ? project.lastResponse.uploaded_files : [];
  }

  function renderAttachmentList(project) {
    const pending = uniqueUploads(project?.pendingUploads || []);
    const items = pending.map((item) => ({ ...item, scope: "pending" }));
    dom.attachmentList.innerHTML = "";
    dom.attachmentList.hidden = items.length === 0;
    items.forEach((upload) => {
      const pill = document.createElement("div");
      pill.className = "attachment-pill";
      const label = document.createElement("span");
      label.className = "attachment-pill__label";
      label.textContent = upload.name || "Файл";
      const meta = document.createElement("span");
      meta.className = "attachment-pill__meta";
      meta.textContent = summarizeUploadMeta(upload) || "к отправке";
      pill.append(label, meta);
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "attachment-pill__remove";
      remove.textContent = "×";
      remove.setAttribute("aria-label", `Убрать файл ${upload.name || ""}`.trim());
      remove.addEventListener("click", () => {
        project.pendingUploads = project.pendingUploads.filter((item) => item.upload_id !== upload.upload_id);
        renderAttachmentList(project);
        renderStatus(project);
      });
      pill.appendChild(remove);
      dom.attachmentList.appendChild(pill);
    });
  }

  function splitAgentQuestionBody(value) {
    const text = normalizeText(value);
    if (!text) {
      return null;
    }
    const blocks = text
      .replace(/\r\n/g, "\n")
      .split(/\n{2,}/)
      .map((part) => normalizeText(part))
      .filter(Boolean);
    if (blocks.length < 2) {
      return null;
    }
    const question = blocks[blocks.length - 1];
    if (
      !/[?]$/.test(question)
      && !/^(кто|что|как|какой|какие|какому|по каким|приведи|опиши|перечисли)\b/i.test(question)
    ) {
      return null;
    }
    const acknowledgement = blocks.slice(0, -1).join(" ");
    if (!acknowledgement) {
      return null;
    }
    return { acknowledgement, question };
  }

  function createMessageNode(message) {
    const fragment = dom.messageTemplate.content.cloneNode(true);
    const article = fragment.querySelector(".message");
    const meta = fragment.querySelector(".message__meta");
    const author = fragment.querySelector(".message__author");
    const kind = fragment.querySelector(".message__kind");
    const title = fragment.querySelector(".message__title");
    const body = fragment.querySelector(".message__body");
    const attachments = fragment.querySelector(".message__attachments");
    const actions = fragment.querySelector(".message__actions");

    const roleClass = {
      agent: "message--agent",
      user: "message--user",
      system: "message--system",
      artifact: "message--artifact",
    }[message.role || "agent"];
    article.classList.add(roleClass);
    author.textContent = message.author || {
      agent: "Агент-архитектор Moltis",
      user: "Пользователь",
      system: "Система",
      artifact: "Фабрика",
    }[message.role || "agent"];
    kind.textContent = "";
    kind.hidden = true;
    const titleText = normalizeText(message.title);
    const hideRedundantTitle = /^следующий вопрос$/i.test(titleText);
    title.textContent = titleText;
    title.hidden = !titleText || hideRedundantTitle;
    meta.hidden = true;
    const bodyText = normalizeText(message.body);
    const splitBody = message.role === "agent" ? splitAgentQuestionBody(bodyText) : null;
    if (splitBody) {
      body.textContent = "";
      body.classList.add("message__body--split");
      const contextLine = document.createElement("span");
      contextLine.className = "message__context-line";
      contextLine.textContent = splitBody.acknowledgement;
      const questionLine = document.createElement("span");
      questionLine.className = "message__question-line";
      questionLine.textContent = splitBody.question;
      body.append(contextLine, questionLine);
    } else {
      body.classList.remove("message__body--split");
      body.textContent = bodyText;
    }
    attachments.innerHTML = "";
    (message.attachments || []).forEach((upload) => {
      const chip = document.createElement("span");
      chip.className = "attachment-pill";
      const label = document.createElement("span");
      label.className = "attachment-pill__label";
      label.textContent = upload.name || "Файл";
      const meta = document.createElement("span");
      meta.className = "attachment-pill__meta";
      meta.textContent = summarizeUploadMeta(upload) || "прикреплён";
      chip.append(label, meta);
      attachments.appendChild(chip);
    });
    attachments.hidden = (message.attachments || []).length === 0;

    actions.hidden = true;
    return fragment;
  }

  function timelineMessagesFromResponse(response) {
    const architectName = normalizeText(response?.ui_projection?.agent_display_name, "Агент-архитектор Moltis");
    return (response?.reply_cards || [])
      .filter((card) => ["discovery_question", "clarification_prompt", "confirmation_prompt"].includes(card.card_kind))
      .map((card) => ({
        role: "agent",
        author: architectName,
        kind: card.card_kind || "reply_card",
        title: "",
        body: card.body_text || "",
        actions: [],
      }));
  }

  function messageSignature(message) {
    if (!message || typeof message !== "object") {
      return "";
    }
    return [
      normalizeText(message.role),
      normalizeText(message.kind),
      normalizeText(message.title),
      normalizeText(message.body),
    ].join("|");
  }

  function isDuplicateAgentQuestion(project, message) {
    if (!project || !Array.isArray(project.timeline) || !message || typeof message !== "object") {
      return false;
    }
    if (normalizeText(message.role) !== "agent") {
      return false;
    }
    const body = normalizeText(message.body);
    if (!body) {
      return false;
    }
    let lastMatchingAgentIndex = -1;
    const lookbackLimit = Math.max(0, project.timeline.length - 24);
    for (let index = project.timeline.length - 1; index >= lookbackLimit; index -= 1) {
      const existing = project.timeline[index];
      if (!existing || typeof existing !== "object") {
        continue;
      }
      if (normalizeText(existing.role) !== "agent") {
        continue;
      }
      if (normalizeText(existing.body) === body) {
        lastMatchingAgentIndex = index;
        break;
      }
    }
    if (lastMatchingAgentIndex < 0) {
      return false;
    }
    for (let index = project.timeline.length - 1; index > lastMatchingAgentIndex; index -= 1) {
      const existing = project.timeline[index];
      if (!existing || typeof existing !== "object") {
        continue;
      }
      if (normalizeText(existing.role) === "user") {
        return false;
      }
    }
    return true;
  }

  function appendTimelineMessagesWithoutContiguousDuplicates(project, incomingMessages) {
    if (!project || !Array.isArray(project.timeline) || !Array.isArray(incomingMessages) || incomingMessages.length === 0) {
      return;
    }
    for (const message of incomingMessages) {
      const last = project.timeline[project.timeline.length - 1];
      if (messageSignature(last) && messageSignature(last) === messageSignature(message)) {
        continue;
      }
      if (isDuplicateAgentQuestion(project, message)) {
        continue;
      }
      project.timeline.push(message);
    }
  }

  function renderTimeline(project) {
    dom.chatLog.innerHTML = "";
    const items = project?.timeline?.length ? project.timeline : [];
    items.forEach((message) => {
      dom.chatLog.appendChild(createMessageNode(message));
    });
    dom.chatLog.scrollTop = dom.chatLog.scrollHeight;
  }

  function sidePanelMode(project) {
    const response = currentResponse(project) || {};
    const explicit = normalizeText(response.ui_projection?.side_panel_mode);
    if (explicit) {
      return explicit;
    }
    if (Array.isArray(response.download_artifacts) && response.download_artifacts.length) {
      return "downloads";
    }
    if (Array.isArray(response.reply_cards) && response.reply_cards.some((card) => card.card_kind === "brief_summary_section")) {
      return "brief_review";
    }
    return "hidden";
  }

  function hasPanelContent(project) {
    return sidePanelMode(project) !== "hidden";
  }

  function detailCards(project) {
    return (currentResponse(project)?.reply_cards || []).filter((card) => card.card_kind === "brief_summary_section");
  }

  function panelPromptCard(project) {
    const response = currentResponse(project) || {};
    const cards = Array.isArray(response.reply_cards) ? response.reply_cards : [];
    if (sidePanelMode(project) === "downloads") {
      return cards.find((card) => card.card_kind === "download_prompt") || null;
    }
    return cards.find((card) => card.card_kind === "confirmation_prompt") || null;
  }

  function renderHome(project) {
    dom.homePanel.hidden = !state.accessToken || hasConversationActivity(project);
    dom.threadPanel.hidden = !state.accessToken || !hasConversationActivity(project);
  }

  function renderSidePanelToggle(project) {
    const mode = sidePanelMode(project);
    dom.sidePanelToggle.hidden = mode === "hidden";
    if (mode === "brief_review") {
      dom.sidePanelToggle.textContent = "Проверить brief";
    } else if (mode === "downloads") {
      dom.sidePanelToggle.textContent = "Файлы проекта";
    } else {
      dom.sidePanelToggle.textContent = "Brief и файлы";
    }
  }

  function artifactPlaceholders() {
    return [
      {
        artifact_kind: "project_doc",
        download_name: "project-doc.md",
        download_status: "pending",
        description: "Проектная рамка и бизнес-контекст для защиты концепции.",
      },
      {
        artifact_kind: "agent_spec",
        download_name: "agent-spec.md",
        download_status: "pending",
        description: "Спецификация будущего агента, сценарии и интерфейсы.",
      },
      {
        artifact_kind: "presentation",
        download_name: "presentation.md",
        download_status: "pending",
        description: "Материал для защиты идеи и последующего feedback loop.",
      },
    ];
  }

  function createMockDownload(project, artifact) {
    const briefVersion = project?.lastResponse?.status_snapshot?.brief_version || "draft";
    const body = [
      `# ${artifact.download_name}`,
      "",
      "Mock download из browser shell.",
      `artifact_kind: ${artifact.artifact_kind}`,
      `brief_version: ${briefVersion}`,
      `project_key: ${project?.lastResponse?.browser_project_pointer?.project_key || "demo-project"}`,
      "",
      "Этот файл нужен только как placeholder до live delivery layer.",
    ].join("\n");
    return URL.createObjectURL(new Blob([body], { type: "text/markdown;charset=utf-8" }));
  }

  function renderArtifacts(project) {
    const responseArtifacts = Array.isArray(project?.lastResponse?.download_artifacts)
      ? project.lastResponse.download_artifacts
      : [];
    const artifacts = responseArtifacts.length ? responseArtifacts : artifactPlaceholders();
    dom.artifactList.innerHTML = "";
    dom.artifactEmpty.hidden = artifacts.length > 0;

    artifacts.forEach((artifact) => {
      const fragment = dom.artifactTemplate.content.cloneNode(true);
      const card = fragment.querySelector(".artifact-card");
      const kind = fragment.querySelector(".artifact-card__kind");
      const stateLabel = fragment.querySelector(".artifact-card__state");
      const title = fragment.querySelector(".artifact-card__title");
      const body = fragment.querySelector(".artifact-card__body");
      const button = fragment.querySelector(".artifact-card__button");
      const ready = ["ready", "available"].includes(normalizeText(artifact.download_status));

      card.dataset.artifactKind = artifact.artifact_kind || "artifact";
      kind.textContent = artifact.artifact_kind || "artifact";
      stateLabel.textContent = artifact.download_status || "pending";
      title.textContent = artifact.download_name || "Без имени";
      body.textContent = artifact.description
        || (ready ? "Артефакт готов к скачиванию из этой browser session." : "Появится после confirmed brief и downstream handoff.");
      button.disabled = !ready;
      button.textContent = ready ? "Скачать" : "Пока не готов";

      button.addEventListener("click", () => {
        if (!ready) {
          return;
        }
        const href = artifact.download_url || createMockDownload(project, artifact);
        const link = document.createElement("a");
        link.href = href;
        link.download = artifact.download_name || "artifact.txt";
        document.body.appendChild(link);
        link.click();
        link.remove();
      });

      dom.artifactList.appendChild(fragment);
    });
  }

  function createPanelCard(card) {
    const fragment = dom.panelCardTemplate.content.cloneNode(true);
    const kind = fragment.querySelector(".panel-card__kind");
    const title = fragment.querySelector(".panel-card__title");
    const body = fragment.querySelector(".panel-card__body");
    const actions = fragment.querySelector(".panel-card__actions");

    kind.textContent = "Раздел brief";
    title.textContent = card.title || "Раздел brief";
    body.textContent = card.body_text || "";
    actions.innerHTML = "";
    (card.action_hints || [])
      .filter((action) => ["request_brief_correction", "confirm_brief", "reopen_brief"].includes(action))
      .forEach((action) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "chip";
        button.dataset.uiAction = action;
        button.textContent = ACTION_LABELS[action] || action;
        button.addEventListener("click", () => handleActionShortcut(action));
        actions.appendChild(button);
      });
    actions.hidden = actions.children.length === 0;
    return fragment;
  }

  function renderSidePanel(project) {
    const mode = sidePanelMode(project);
    const open = Boolean(project?.sidePanelOpen) && mode !== "hidden";
    dom.workspaceShell.dataset.panelOpen = open ? "true" : "false";
    dom.sidePanel.hidden = !open;
    dom.sidePanel.dataset.mode = mode;
    if (!open) {
      return;
    }

    const promptCard = panelPromptCard(project);
    if (mode === "brief_review") {
      dom.sidePanelEyebrow.textContent = "Brief на проверке";
      dom.sidePanelTitle.textContent = "Проверь summary";
      dom.sidePanelSummary.textContent = promptCard?.body_text || "Проверь разделы brief, внеси правки или подтверди текущую версию.";
    } else if (mode === "downloads") {
      dom.sidePanelEyebrow.textContent = "Материалы проекта";
      dom.sidePanelTitle.textContent = "Артефакты готовы";
      dom.sidePanelSummary.textContent = promptCard?.body_text || "Скачай project doc, agent spec и presentation из этой сессии.";
    } else {
      dom.sidePanelEyebrow.textContent = "Детали проекта";
      dom.sidePanelTitle.textContent = "Brief и файлы";
      dom.sidePanelSummary.textContent = "Здесь появятся brief на review и пользовательские артефакты.";
    }

    dom.panelCardList.innerHTML = "";
    if (mode === "brief_review") {
      detailCards(project).forEach((card) => {
        dom.panelCardList.appendChild(createPanelCard(card));
      });
    }

    dom.artifactSection.hidden = mode !== "downloads";
    renderArtifacts(project);
  }

  function renderStatus(project) {
    const response = currentResponse(project) || {};
    const statusSnapshot = response.status_snapshot || {};
    const session = response.web_demo_session || {};
    const pointer = response.browser_project_pointer || {};
    const accessGate = response.access_gate || {};
    const resumeContext = response.resume_context || {};

    dom.statusUserVisible.textContent = statusSnapshot.user_visible_status_label || statusLabel(project) || "gate_pending";
    dom.statusNextAction.textContent =
      statusSnapshot.next_recommended_action_label
      || ACTION_LABELS[statusSnapshot.next_recommended_action]
      || ACTION_LABELS[project?.currentAction]
      || "request_demo_access";
    dom.statusBriefVersion.textContent = statusSnapshot.brief_version
      ? `${statusSnapshot.brief_version}${statusSnapshot.brief_status_label ? ` · ${statusSnapshot.brief_status_label}` : ""}`
      : "ещё нет";
    dom.statusUploadCount.textContent = String(uniqueUploads([...(project?.pendingUploads || []), ...activeSessionUploads(project)]).length);
    dom.statusDownloadReadiness.textContent = statusSnapshot.download_readiness || "pending";
    dom.statusProjectKey.textContent = pointer.project_key || "не выбран";
    dom.statusSessionId.textContent = session.web_demo_session_id || project?.sessionId || "не открыт";
    dom.statusOperatorAttention.textContent = accessGate.granted
      ? (resumeContext.summary_text || projectSubtitle(project))
      : (accessGate.reason || "Нужен access token для controlled demo surface.");
  }

  function renderQuickActions(project) {
    const actions = [...new Set(availableActions(project).filter(Boolean))];
    const selected = actions.length ? actions : ["start_project"];
    dom.quickActions.innerHTML = "";
    selected.forEach((action) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "chip";
      button.dataset.uiAction = action;
      button.textContent = ACTION_LABELS[action] || action;
      button.classList.toggle("is-active", action === (project?.currentAction || "start_project"));
      button.addEventListener("click", () => handleActionShortcut(action));
      dom.quickActions.appendChild(button);
    });
  }

  function renderComposer(project) {
    dom.composerLeadLabel.textContent = leadLabelFor(project);
    dom.composerMode.textContent = modeTextFor(project);
    if (dom.composerThinking) {
      dom.composerThinking.hidden = !state.awaitingResponse;
    }
    dom.composerForm.classList.toggle("is-pending", state.awaitingResponse);
    if (dom.composerHelperExample) {
      dom.composerHelperExample.textContent = helperExampleFor(project);
      dom.composerHelperExample.hidden = true;
    }
    dom.composerInput.placeholder = placeholderFor(project);
    dom.composerSubmit.textContent = state.awaitingResponse ? "■" : "↑";
    dom.composerSubmit.dataset.mode = state.awaitingResponse ? "stop" : "send";
    dom.composerSubmit.setAttribute("aria-label", state.awaitingResponse ? "Остановить ответ" : "Отправить сообщение");
    dom.composerNotice.textContent = normalizeText(state.composerNotice?.text);
    dom.composerNotice.hidden = !dom.composerNotice.textContent;
    dom.composerNotice.dataset.tone = normalizeText(state.composerNotice?.tone, "info");
    dom.composerInput.value = normalizeText(project?.draftText);
    resizeComposerInput();
  }

  function renderAll() {
    const project = getActiveProject();
    applySidebarWidth();
    renderGateNote();
    renderConnection();
    renderSessionBadge(project);
    renderShellStage(project);
    renderProjectList();
    renderTopbar(project);
    renderHome(project);
    renderStatus(project);
    renderTimeline(project);
    renderAttachmentList(project);
    renderComposer(project);
    renderSidePanel(project);
    renderProjectActionsMenu();
  }

  function resizeComposerInput() {
    if (!dom.composerInput) {
      return;
    }
    const minHeight = 44;
    const maxHeight = 220;
    dom.composerInput.style.height = "auto";
    const nextHeight = Math.min(Math.max(dom.composerInput.scrollHeight, minHeight), maxHeight);
    dom.composerInput.style.height = `${nextHeight}px`;
    dom.composerInput.style.overflowY = dom.composerInput.scrollHeight > maxHeight ? "auto" : "hidden";
  }

  function setProjectAction(project, action) {
    if (!project) {
      return;
    }
    project.currentAction = action;
    project.updatedAt = nowIso();
    persist();
    renderAll();
  }

  function looksLikeSlug(value) {
    const text = normalizeText(value);
    return Boolean(text && !/\s/.test(text) && /-/.test(text));
  }

  function looksLikeExcerpt(value, sourceText = "") {
    const title = normalizeText(value);
    if (!title) {
      return false;
    }
    if (/[.…]$/.test(title) || /\.\.\./.test(title)) {
      return true;
    }
    if (title.length > 58) {
      return true;
    }
    const source = normalizeText(sourceText).toLowerCase();
    if (!source) {
      return false;
    }
    const normalizedTitle = title.toLowerCase().replace(/[.…]+$/, "");
    return normalizedTitle.length >= 18 && source.startsWith(normalizedTitle);
  }

  function isGenericProjectTitle(value) {
    const normalized = normalizeText(value)
      .toLowerCase()
      .replace(/[.…]+$/g, "")
      .replace(/\s+/g, " ")
      .trim();
    if (!normalized) {
      return true;
    }
    if (
      normalized === "new project"
      || normalized === "новый проект"
      || normalized === "новый"
      || normalized === "project"
      || normalized === "проект"
      || normalized === "discovery project"
      || normalized === "factory project"
      || normalized === "demo project"
    ) {
      return true;
    }
    if (/^(discovery|demo|new)\s+project\s*\d*$/i.test(normalized)) {
      return true;
    }
    if (/^проект\s*\d*$/i.test(normalized)) {
      return true;
    }
    return false;
  }

  function titleCaseFromWords(words, maxWords = 5) {
    const selected = words.slice(0, maxWords);
    if (!selected.length) {
      return "";
    }
    const text = selected.join(" ").replace(/\s+/g, " ").trim();
    if (!text) {
      return "";
    }
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  function semanticTitleFromText(text) {
    const source = normalizeText(text).toLowerCase();
    if (!source) {
      return "";
    }
    if (/кредит/.test(source) && /(summary|one-page|саммери|one page)/.test(source)) {
      return "Кредитный one-page summary";
    }
    if (/кредит/.test(source) && /(заявк|согласован|комитет)/.test(source)) {
      return "Согласование кредитных заявок";
    }
    if (/(счет|счёт|инвойс|invoice)/.test(source) && /(согласован|маршрут|approval)/.test(source)) {
      return "Маршрутизация согласования счетов";
    }
    if (/(клиент|customer)/.test(source) && /(профил|карточк|summary|саммари)/.test(source)) {
      return "Карточка клиента";
    }
    return "";
  }

  function prettifyTitle(text) {
    const normalized = normalizeText(text)
      .replace(/\s+/g, " ")
      .replace(/…|\.\.\./g, " ")
      .replace(/^[\-\s]+|[\-\s]+$/g, "");
    if (!normalized) {
      return "";
    }
    const firstSentence = normalized.split(/[.!?\n]/)[0].trim();
    const cleaned = firstSentence
      .replace(/^нужен агент[,]?\s*/i, "")
      .replace(/^который\s+/i, "")
      .replace(/^надо\s+/i, "")
      .replace(/^нужно\s+/i, "")
      .replace(/^хочу автоматизировать\s*/i, "")
      .replace(/^нужно автоматизировать\s*/i, "")
      .replace(/^нужна автоматизация\s*/i, "")
      .replace(/^автоматизировать\s+/i, "")
      .replace(/^автоматизация\s+/i, "")
      .replace(/^ускорить\s+/i, "")
      .replace(/^сделать\s+/i, "")
      .replace(/^чтобы\s+/i, "");
    const semantic = semanticTitleFromText(cleaned || firstSentence);
    if (semantic) {
      return semantic;
    }
    const stopwords = new Set([
      "который",
      "которая",
      "которые",
      "чтобы",
      "если",
      "тогда",
      "нужно",
      "надо",
      "очень",
      "просто",
      "процесс",
      "проект",
      "система",
      "данные",
      "пользователь",
    ]);
    const words = (cleaned || firstSentence)
      .replace(/[,:;()"'`«»]+/g, " ")
      .split(/\s+/)
      .map((word) => word.trim())
      .filter((word) => word.length >= 3)
      .filter((word) => !stopwords.has(word.toLowerCase()));
    const candidate = titleCaseFromWords(words, 4);
    if (/^(новый проект|проект|автоматизация|задача)$/i.test(candidate)) {
      return "";
    }
    return candidate;
  }

  function maybeAutonameProject(project, userText, response) {
    if (!project || project.titleEdited) {
      return;
    }
    if (isLowSignalInput(userText)) {
      return;
    }
    const uiTitle = normalizeText(response?.ui_projection?.display_project_title || response?.ui_projection?.project_title);
    const rawUiCandidate = !looksLikeSlug(uiTitle) && !looksLikeExcerpt(uiTitle, userText) ? prettifyTitle(uiTitle) : "";
    const uiCandidate = !isGenericProjectTitle(rawUiCandidate) ? rawUiCandidate : "";
    const rawUserCandidate = prettifyTitle(userText);
    const userCandidate = !isGenericProjectTitle(rawUserCandidate) ? rawUserCandidate : "";
    const candidate = userCandidate || uiCandidate;
    if (!candidate) {
      return;
    }
    const canOverrideExisting = (
      project.title === DEFAULT_PROJECT_TITLE
      || project.title.startsWith(`${DEFAULT_PROJECT_TITLE} `)
      || looksLikeExcerpt(project.title, userText)
      || isGenericProjectTitle(project.title)
    );
    if (
      canOverrideExisting
    ) {
      project.title = candidate;
    }
  }

  function promptRenameProject(projectId) {
    if (!ensureWorkspaceAccess()) {
      return;
    }
    const project = state.projects.find((item) => item.id === projectId);
    if (!project) {
      return;
    }
    const nextTitle = window.prompt("Новое название проекта", project.title);
    const normalized = normalizeText(nextTitle);
    if (!normalized) {
      return;
    }
    project.title = normalized;
    project.titleEdited = true;
    project.updatedAt = nowIso();
    persist();
    renderAll();
  }

  function deleteProject(projectId) {
    if (!ensureWorkspaceAccess()) {
      return;
    }
    const target = state.projects.find((item) => item.id === projectId);
    if (!target) {
      return;
    }
    const remaining = state.projects.filter((item) => item.id !== projectId);
    const deletedActive = projectId === state.activeProjectId;
    if (deletedActive) {
      const fresh = createProject({ title: DEFAULT_PROJECT_TITLE });
      state.projects = [fresh, ...remaining];
      state.activeProjectId = fresh.id;
    } else {
      state.projects = remaining.length ? remaining : [createProject({ title: DEFAULT_PROJECT_TITLE })];
      if (!state.projects.some((item) => item.id === state.activeProjectId)) {
        state.activeProjectId = state.projects[0].id;
      }
    }
    closeProjectActionsMenu();
    persist();
    renderAll();
    focusComposerSoon();
  }

  function deleteProjectWithConfirm(projectId) {
    if (!ensureWorkspaceAccess()) {
      return;
    }
    const project = state.projects.find((item) => item.id === projectId);
    if (!project) {
      return;
    }
    const projectTitle = normalizeText(project.title, DEFAULT_PROJECT_TITLE);
    const approved = window.confirm(`Удалить проект "${projectTitle}"? Это действие нельзя отменить.`);
    if (!approved) {
      return;
    }
    deleteProject(projectId);
  }

  function createNewProject(options = {}) {
    if (!ensureWorkspaceAccess()) {
      return getActiveProject();
    }
    saveComposerDraft();
    closeProjectActionsMenu();
    const active = getActiveProject();
    const reusable = isEmptyDraftProject(active)
      ? active
      : state.projects.find((item) => item.id !== active?.id && isEmptyDraftProject(item));
    if (reusable && options.forceCreate !== true) {
      state.activeProjectId = reusable.id;
      reusable.updatedAt = nowIso();
      if (options.activate !== false) {
        renderAll();
      }
      persist();
      return reusable;
    }
    const project = createProject();
    state.projects.unshift(project);
    state.activeProjectId = project.id;
    if (options.activate !== false) {
      renderAll();
    }
    persist();
    return project;
  }

  function isEmptyDraftProject(project) {
    if (!project) {
      return false;
    }
    const hasUserMessages = (project.timeline || []).some(
      (message) => message.role === "user" && Boolean(normalizeText(message.body)),
    );
    const hasDraftText = Boolean(normalizeText(project.draftText));
    const hasUploads = uniqueUploads(project.pendingUploads || []).length > 0;
    return !hasUserMessages && !hasConversationActivity(project) && !hasDraftText && !hasUploads;
  }

  function switchProject(projectId) {
    if (!ensureWorkspaceAccess()) {
      return;
    }
    saveComposerDraft();
    closeProjectActionsMenu();
    if (!state.projects.some((project) => project.id === projectId)) {
      return;
    }
    state.activeProjectId = projectId;
    persist();
    renderAll();
    const active = getActiveProject();
    if (state.accessToken && active?.sessionId && active?.lastResponse) {
      void refreshActiveProject({ syncReason: "switch_project", suppressFailureBanner: true });
    }
    focusComposerSoon();
  }

  function buildAccessProbePayload(project, token) {
    const last = currentResponse(project) || {};
    return {
      working_language: "ru",
      project_key: last.browser_project_pointer?.project_key || "",
      requester_identity: {
        display_name: "Demo user",
        browser_session_label: "agent-factory-web-shell",
      },
      demo_access_grant: {
        grant_type: "shared_demo_token",
        grant_value: token,
        status: "active",
      },
      web_demo_session: {
        web_demo_session_id: last.web_demo_session?.web_demo_session_id || project.sessionId,
        session_cookie_id: last.web_demo_session?.session_cookie_id || "",
        status: last.web_demo_session?.status || "gate_pending",
      },
      browser_project_pointer: {
        pointer_id: last.browser_project_pointer?.pointer_id || "",
        project_key: last.browser_project_pointer?.project_key || "",
        linked_discovery_session_id: last.browser_project_pointer?.linked_discovery_session_id || "",
        linked_brief_id: last.browser_project_pointer?.linked_brief_id || "",
        linked_brief_version: last.browser_project_pointer?.linked_brief_version || "",
        selection_mode: "new_project",
        pointer_status: "active",
      },
      web_conversation_envelope: {
        request_id: nextRequestId(project, "request_demo_access"),
        ui_action: "request_demo_access",
        user_text: "",
        transport_mode: "browser_shell",
        linked_discovery_session_id: last.web_conversation_envelope?.linked_discovery_session_id || "",
        linked_brief_id: last.web_conversation_envelope?.linked_brief_id || "",
      },
      discovery_runtime_state: last.discovery_runtime_state || {},
    };
  }

  function responseRequiresAccessGate(response) {
    const accessGate = response?.access_gate || {};
    const granted = accessGate.granted;
    const status = normalizeText(response?.status_snapshot?.user_visible_status || response?.status).toLowerCase();
    const nextAction = normalizeText(response?.status_snapshot?.next_recommended_action || response?.next_action).toLowerCase();
    if (granted === false) {
      return true;
    }
    if (status === "gate_pending" || nextAction === "request_demo_access") {
      return true;
    }
    return granted !== true && Boolean(normalizeText(accessGate.reason));
  }

  function gateReasonFromResponse(response) {
    const explicit = normalizeText(response?.access_gate?.reason);
    if (explicit) {
      return explicit;
    }
    const hinted = normalizeText(response?.ui_projection?.current_question || response?.next_question);
    if (hinted && /(token|доступ|access)/i.test(hinted)) {
      return hinted;
    }
    return "Этот demo access token не подходит. Проверь токен или запроси актуальный доступ у оператора.";
  }

  async function unlockAccess(tokenOverride = "") {
    if (state.accessProbePending) {
      return;
    }
    const provided = normalizeText(tokenOverride || dom.accessTokenInput.value);
    if (!provided) {
      setGateNote("Укажи access token для входа в demo.", "error");
      dom.accessTokenInput.focus();
      return;
    }
    closeProjectActionsMenu();
    state.accessProbePending = true;
    setGateNote("Проверяю access token...", "info");
    setBusy(true);
    try {
      if (!state.projects.length) {
        state.projects = [createProject()];
      }
      if (!state.activeProjectId || !state.projects.some((project) => project.id === state.activeProjectId)) {
        state.activeProjectId = state.projects[0].id;
      }
      const project = getActiveProject();
      const payload = buildAccessProbePayload(project, provided);
      const response = await postTurn(payload);
      if (responseRequiresAccessGate(response)) {
        project.lastResponse = response;
        project.updatedAt = nowIso();
        state.connectionMode = "live";
        persist();
        relockAccess(gateReasonFromResponse(response));
        return;
      }
      state.accessToken = provided;
      setGateNote("Доступ открыт. Теперь можно начинать диалог и переключаться между проектами.", "success");
      applyResponse(project, response, "live", {
        appendReplyMessages: !hasConversationActivity(project),
        syncReason: "unlock_access",
      });
      persist();
      renderAll();
      focusComposerSoon();
    } catch (_error) {
      state.connectionMode = "error";
      relockAccess("Не удалось проверить access token. Повтори попытку через несколько секунд.");
    } finally {
      state.accessProbePending = false;
      setBusy(false);
      renderAll();
    }
  }

  function relockAccess(reason) {
    state.accessToken = "";
    state.accessProbePending = false;
    closeProjectActionsMenu();
    setGateNote(normalizeText(reason, "Нужен access token для controlled demo surface."), "error");
    persist();
    renderAll();
    window.setTimeout(() => {
      dom.accessTokenInput.focus();
    }, 0);
  }

  function serializeUploadsForTransport(uploads) {
    return uniqueUploads(uploads).map((upload) => ({
      upload_id: upload.upload_id,
      name: upload.name,
      content_type: upload.content_type,
      size_bytes: upload.size_bytes,
      original_size_bytes: upload.original_size_bytes,
      truncated: Boolean(upload.truncated),
      content_base64: upload.content_base64 || "",
    }));
  }

  function buildTurnPayload(project, action, userText, queuedUploads = []) {
    const last = currentResponse(project) || {};
    return {
      working_language: "ru",
      project_key: last.browser_project_pointer?.project_key || "",
      requester_identity: {
        display_name: "Demo user",
        browser_session_label: "agent-factory-web-shell",
      },
      demo_access_grant: state.accessToken
        ? {
            grant_type: "shared_demo_token",
            grant_value: state.accessToken,
            status: "active",
          }
        : {},
      web_demo_session: {
        web_demo_session_id: last.web_demo_session?.web_demo_session_id || project.sessionId,
        session_cookie_id: last.web_demo_session?.session_cookie_id || "",
        status: last.web_demo_session?.status || "gate_pending",
      },
      browser_project_pointer: {
        pointer_id: last.browser_project_pointer?.pointer_id || "",
        project_key: last.browser_project_pointer?.project_key || "",
        linked_discovery_session_id: last.browser_project_pointer?.linked_discovery_session_id || "",
        linked_brief_id: last.browser_project_pointer?.linked_brief_id || "",
        linked_brief_version: last.browser_project_pointer?.linked_brief_version || "",
        selection_mode: selectionModeFor(action),
        pointer_status: "active",
      },
      web_conversation_envelope: {
        request_id: nextRequestId(project, action),
        ui_action: action,
        user_text: normalizeText(userText),
        transport_mode: "browser_shell",
        linked_discovery_session_id: last.web_conversation_envelope?.linked_discovery_session_id || "",
        linked_brief_id: last.web_conversation_envelope?.linked_brief_id || "",
      },
      discovery_runtime_state: last.discovery_runtime_state || {},
      uploaded_files: queuedUploads.length ? serializeUploadsForTransport(queuedUploads) : undefined,
    };
  }

  function buildTurnSignal(signal) {
    const timeoutSignal = (typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function")
      ? AbortSignal.timeout(TURN_TIMEOUT_MS)
      : null;
    if (signal && timeoutSignal && typeof AbortSignal !== "undefined" && typeof AbortSignal.any === "function") {
      return { signal: AbortSignal.any([signal, timeoutSignal]), timeoutSignal };
    }
    if (signal && timeoutSignal && typeof AbortController !== "undefined") {
      const linkedController = new AbortController();
      const abortLinked = () => linkedController.abort();
      if (signal.aborted || timeoutSignal.aborted) {
        linkedController.abort();
      } else {
        signal.addEventListener("abort", abortLinked, { once: true });
        timeoutSignal.addEventListener("abort", abortLinked, { once: true });
      }
      return { signal: linkedController.signal, timeoutSignal };
    }
    return { signal: signal || timeoutSignal || undefined, timeoutSignal };
  }

  async function postTurn(payload, options = {}) {
    const requestSignal = buildTurnSignal(options.signal);
    let response;
    try {
      response = await fetch("/api/turn", {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify(payload),
        signal: requestSignal.signal,
      });
    } catch (error) {
      if (
        error?.name === "AbortError"
        && requestSignal.timeoutSignal?.aborted
        && !(options.signal?.aborted)
      ) {
        const timeoutError = new Error("Превышено время ожидания");
        timeoutError.name = "TimeoutError";
        throw timeoutError;
      }
      throw error;
    }
    if (!response.ok) {
      throw new Error(`adapter_http_${response.status}`);
    }
    return response.json();
  }

  async function fetchSession(sessionId) {
    const response = await fetch(`/api/session?session_id=${encodeURIComponent(sessionId)}`);
    if (!response.ok) {
      throw new Error(`session_http_${response.status}`);
    }
    return response.json();
  }

  function stopActiveResponse() {
    if (!state.awaitingResponse || !state.activeAbortController) {
      return;
    }
    state.activeAbortController.abort();
  }

  function isLowSignalInput(text) {
    const normalized = normalizeText(text).toLowerCase();
    if (!normalized) {
      return false;
    }
    if (normalized.length <= 2) {
      return true;
    }
    if (/^[0-9\s.,!?-]+$/.test(normalized)) {
      return true;
    }
    if (/^(ок|ага|угу|да|нет|норм|понял|поняла|хз|лол|test|123+|qwe+)$/i.test(normalized)) {
      return true;
    }
    const words = normalized.split(/\s+/).filter(Boolean);
    return words.length <= 2 && normalized.length < 18;
  }

  function buildMockCoverage(project, uploadedFiles = []) {
    const covered = new Set();
    if ((uploadedFiles || []).length > 0) {
      covered.add("input_examples");
    }
    const userTurns = (project.timeline || [])
      .filter((message) => message.role === "user")
      .map((message) => normalizeText(message.body).toLowerCase())
      .filter(Boolean);
    userTurns.forEach((turn) => {
      MOCK_DISCOVERY_TOPICS.forEach((topic) => {
        if (covered.has(topic.id)) {
          return;
        }
        if (topic.signals.some((signal) => turn.includes(signal))) {
          covered.add(topic.id);
        }
      });
    });
    return covered;
  }

  function mockNextDiscoveryStep(project, userText, uploadedFiles = []) {
    const coverage = buildMockCoverage(project, uploadedFiles);
    const missing = MOCK_DISCOVERY_TOPICS.filter((topic) => !coverage.has(topic.id));
    const next = missing[0] || MOCK_DISCOVERY_TOPICS[0];
    const lowSignal = isLowSignalInput(userText);
    const question = lowSignal
      ? `Похоже, ответ получился слишком общим. Перефразируй, пожалуйста. ${next.question}`
      : next.question;
    return {
      coveredCount: coverage.size,
      totalCount: MOCK_DISCOVERY_TOPICS.length,
      missing,
      nextTopic: next.id,
      nextQuestion: question,
      whyAskingNow: next.why,
      lowSignal,
    };
  }

  function mockReplyCards(mode, projectKey, discoveryStep) {
    if (mode === "awaiting_confirmation") {
      return [
        {
          card_kind: "status_update",
          title: "Статус проекта",
          body_text: "Discovery завершён. Brief ждёт подтверждения. Следующий шаг: проверить summary и либо подтвердить версию, либо запросить правки.",
          action_hints: ["request_status"],
        },
        {
          card_kind: "brief_summary_section",
          title: "Версия brief v2",
          body_text: "Сейчас на проверке версия v2. Проверь summary ниже, попроси правки обычным текстом или явно подтверди текущую редакцию.",
          action_hints: ["request_brief_correction", "confirm_brief"],
        },
        {
          card_kind: "confirmation_prompt",
          title: "Подтвердить brief v2",
          body_text: "Проверь summary и явно подтверди версию v2. Если нужны изменения, запроси правки обычным текстом или переоткрой brief.",
          action_hints: ["request_brief_correction", "confirm_brief", "reopen_brief"],
        },
      ];
    }
    if (mode === "downloads_ready") {
      return [
        {
          card_kind: "status_update",
          title: "Статус проекта",
          body_text: "Confirmed brief передан в фабрику. Concept pack готовится к выдаче пользователю.",
          action_hints: ["request_status"],
        },
        {
          card_kind: "download_prompt",
          title: "Артефакты готовы",
          body_text: `Проект ${projectKey} может отдать project doc, agent spec и presentation из той же сессии.`,
          action_hints: ["download_artifact"],
        },
      ];
    }
    const progress = `${discoveryStep.coveredCount}/${discoveryStep.totalCount}`;
    const cards = [
      {
        card_kind: "status_update",
        title: "Статус проекта",
        body_text: `Сбор требований продолжается. Закрыто тем: ${progress}. ${discoveryStep.whyAskingNow}`,
        action_hints: ["request_status"],
      },
      {
        card_kind: "discovery_question",
        title: "",
        body_text: discoveryStep.nextQuestion,
        action_hints: ["submit_turn"],
      },
    ];
    if (discoveryStep.lowSignal) {
      cards.push({
        card_kind: "clarification_prompt",
        title: "Нужно уточнение",
        body_text: "Сформулируй ответ чуть подробнее, чтобы я корректно зафиксировал требования в brief.",
        action_hints: ["submit_turn"],
      });
    }
    return cards;
  }

  function mockArtifacts(stage) {
    if (stage !== "downloads_ready") {
      return [];
    }
    return [
      { artifact_kind: "project_doc", download_name: "project-doc.md", download_status: "ready" },
      { artifact_kind: "agent_spec", download_name: "agent-spec.md", download_status: "ready" },
      { artifact_kind: "presentation", download_name: "presentation.md", download_status: "ready" },
    ];
  }

  function sanitizeMockUploads(uploads) {
    return uniqueUploads(uploads).map((upload) => ({
      upload_id: upload.upload_id,
      name: upload.name,
      content_type: upload.content_type,
      size_bytes: upload.size_bytes,
      original_size_bytes: upload.original_size_bytes,
      truncated: Boolean(upload.truncated),
      ingest_status: upload.content_base64 ? "excerpt_ready" : "metadata_only",
      excerpt: "",
      uploaded_at: nowIso(),
    }));
  }

  function mockAdapterTurn(project, payload) {
    const action = payload.web_conversation_envelope?.ui_action || "submit_turn";
    const userText = normalizeText(payload.web_conversation_envelope?.user_text);
    const uploadedFiles = sanitizeMockUploads(payload.uploaded_files || []);
    const accessGranted = Boolean(state.accessToken);
    const projectKey =
      project.lastResponse?.browser_project_pointer?.project_key ||
      `factory-${slugify(userText || project.title || "demo-project", "project")}`;

    if (!accessGranted) {
      project.mockStage = "gate_pending";
      return {
        status: "gate_pending",
        next_action: "request_demo_access",
        next_topic: "",
        next_question: "Укажи активный demo access token, чтобы открыть рабочую сессию фабрики.",
        access_gate: {
          granted: false,
          reason: "Укажи активный demo access token, чтобы открыть рабочую сессию фабрики.",
        },
        web_demo_session: {
          web_demo_session_id: project.sessionId,
          session_cookie_id: `cookie-${project.sessionId}`,
          status: "gate_pending",
          active_project_key: "",
        },
        browser_project_pointer: {
          pointer_id: `browser-pointer-${project.sessionId}`,
          project_key: "",
          selection_mode: selectionModeFor(action),
          pointer_status: "active",
        },
        status_snapshot: {
          user_visible_status: "gate_pending",
          next_recommended_action: "request_demo_access",
          uploaded_file_count: uploadedFiles.length,
          download_readiness: "pending",
        },
        reply_cards: [
          {
            card_kind: "status_update",
            title: "Нужен код доступа",
            body_text: "Shell ждёт access token, прежде чем открывать проект фабрики.",
            action_hints: ["submit_access_token"],
          },
        ],
        uploaded_files: uploadedFiles,
      };
    }

    const discoveryStep = mockNextDiscoveryStep(project, userText, uploadedFiles);
    let mode = normalizeText(project.mockStage, "discovery");
    if (action === "confirm_brief") {
      mode = "downloads_ready";
    } else if (action === "request_brief_correction" || action === "reopen_brief") {
      mode = "awaiting_confirmation";
    } else if (mode === "downloads_ready" && action === "request_status") {
      mode = "downloads_ready";
    } else if (discoveryStep.missing.length === 0 && !discoveryStep.lowSignal) {
      mode = "awaiting_confirmation";
    } else {
      mode = "discovery";
    }
    project.mockStage = mode;

    const brief = mode === "awaiting_confirmation" || mode === "downloads_ready"
      ? {
          brief_id: "brief-web-demo-001",
          version: mode === "downloads_ready" ? "v3" : "v2",
        }
      : {};
    const confirmationPrompt = "Я собрал черновой brief. Проверь summary, попроси правки или явно подтверди текущую версию.";
    const nextQuestion = mode === "awaiting_confirmation"
      ? confirmationPrompt
      : mode === "downloads_ready"
        ? "Brief подтверждён. Можно скачать concept pack и при необходимости переоткрыть brief."
        : discoveryStep.nextQuestion;
    const nextTopic = mode === "discovery" ? discoveryStep.nextTopic : "";

    return {
      status: mode === "downloads_ready" ? "confirmed" : mode === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
      next_action: mode === "downloads_ready" ? "start_concept_pack_handoff" : mode === "awaiting_confirmation" ? "await_for_confirmation" : "continue_discovery",
      next_topic: nextTopic,
      next_question: nextQuestion,
      access_gate: {
        granted: true,
        reason: "",
      },
      web_demo_session: {
        web_demo_session_id: project.sessionId,
        session_cookie_id: `cookie-${project.sessionId}`,
        status: mode === "downloads_ready" ? "download_ready" : mode === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
        active_project_key: projectKey,
      },
      browser_project_pointer: {
        pointer_id: `browser-pointer-${project.sessionId}`,
        project_key: projectKey,
        selection_mode: selectionModeFor(action),
        linked_discovery_session_id: "discovery-web-demo-001",
        linked_brief_id: brief.brief_id || "",
        linked_brief_version: brief.version || "",
        pointer_status: "active",
      },
      status_snapshot: {
        user_visible_status: mode === "downloads_ready" ? "playground_ready" : mode === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
        user_visible_status_label: mode === "downloads_ready" ? "Артефакты готовы" : mode === "awaiting_confirmation" ? "Brief ждёт подтверждения" : "Сбор требований продолжается",
        next_recommended_action: mode === "downloads_ready" ? "start_concept_pack_handoff" : mode === "awaiting_confirmation" ? "confirm_brief" : "submit_turn",
        next_recommended_action_label: mode === "downloads_ready" ? "Передать brief в фабрику" : mode === "awaiting_confirmation" ? "Проверить и подтвердить brief" : "Ответить на следующий вопрос",
        brief_version: brief.version || "",
        download_readiness: mode === "downloads_ready" ? "ready" : "pending",
        uploaded_file_count: uploadedFiles.length,
      },
      reply_cards: mockReplyCards(mode, projectKey, discoveryStep),
      download_artifacts: mockArtifacts(mode),
      uploaded_files: uploadedFiles,
      discovery_runtime_state: {
        status: mode === "downloads_ready" ? "confirmed" : mode === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
        next_question: nextQuestion,
        missing_coverage: discoveryStep.missing.map((topic) => topic.id),
      },
      ui_projection: {
        preferred_ui_action: mode === "downloads_ready" ? "request_status" : mode === "awaiting_confirmation" ? "confirm_brief" : "submit_turn",
        current_question: nextQuestion,
        current_topic: nextTopic,
        why_asking_now: mode === "discovery" ? discoveryStep.whyAskingNow : "",
        missing_coverage: discoveryStep.missing.map((topic) => topic.id),
        side_panel_mode: mode === "downloads_ready" ? "downloads" : mode === "awaiting_confirmation" ? "brief_review" : "hidden",
        composer_helper_example: helperExampleFor(project),
        project_stage_label: mode === "downloads_ready" ? "Артефакты готовы" : mode === "awaiting_confirmation" ? "Brief на проверке" : "Сбор требований",
        display_project_title: project.title,
        project_title: project.title,
        uploaded_file_count: uploadedFiles.length,
      },
    };
  }

  function applyResponse(project, response, connectionMode, options = {}) {
    const appendReplyMessages = options.appendReplyMessages !== false;
    const syncReason = normalizeText(options.syncReason);

    if (responseRequiresAccessGate(response)) {
      project.lastResponse = response;
      project.updatedAt = nowIso();
      persist();
      relockAccess(gateReasonFromResponse(response));
      return;
    }

    state.connectionMode = connectionMode;
    project.lastResponse = response;
    project.sessionId = normalizeText(response.web_demo_session?.web_demo_session_id, project.sessionId);
    project.updatedAt = nowIso();

    const replyMessages = appendReplyMessages ? timelineMessagesFromResponse(response) : [];
    if (replyMessages.length) {
      appendTimelineMessagesWithoutContiguousDuplicates(project, replyMessages);
    }

    const firstMeaningfulUserMessage = project.timeline.find(
      (message) => message.role === "user" && !isLowSignalInput(message.body),
    );
    maybeAutonameProject(project, firstMeaningfulUserMessage?.body || "", response);

    const preferredAction = normalizeText(response.ui_projection?.preferred_ui_action);
    project.currentAction = preferredAction || ACTION_PRIORITY.find((action) => availableActions(project).includes(action)) || "submit_turn";
    const panelMode = sidePanelMode(project);
    if (panelMode === "hidden") {
      project.sidePanelOpen = false;
    } else if (panelMode !== normalizeText(project.lastPanelMode)) {
      project.sidePanelOpen = true;
    }
    project.lastPanelMode = panelMode;
    project.lastResumeFingerprint = normalizeText(response.resume_context?.resume_fingerprint, project.lastResumeFingerprint);

    persist();
    renderAll();

    const sourceAction = normalizeText(response.web_conversation_envelope?.ui_action);
    const sourceRequestId = normalizeText(response.web_conversation_envelope?.request_id);
    if (
      connectionMode === "live"
      && sourceAction === "confirm_brief"
      && response.next_action === "start_concept_pack_handoff"
      && !Array.isArray(response.download_artifacts)
      && sourceRequestId
      && project.lastAutoFollowupSource !== sourceRequestId
    ) {
      project.lastAutoFollowupSource = sourceRequestId;
      persist();
      window.setTimeout(() => {
        dispatchTurn("request_status", "", { skipUserMessage: true });
      }, 120);
    }
  }

  async function dispatchTurn(action, userText, options = {}) {
    if (!ensureWorkspaceAccess()) {
      return;
    }
    const project = getActiveProject();
    if (!project) {
      return;
    }
    const queuedUploads = uniqueUploads(options.queuedUploads || []);
    const normalizedUserText = normalizeText(userText);
    const payload = buildTurnPayload(project, action, userText, queuedUploads);
    const requestId = normalizeText(payload?.web_conversation_envelope?.request_id);
    const abortController = new AbortController();
    let abortedByUser = false;
    let timedOut = false;
    const pendingStartedAt = Date.now();

    if (!options.skipUserMessage && (normalizedUserText || queuedUploads.length)) {
      project.timeline.push({
        role: "user",
        kind: action,
        title: "",
        body: normalizedUserText || "Добавил файлы к ответу.",
        request_id: requestId,
        attachments: queuedUploads.map((upload) => ({
          upload_id: upload.upload_id,
          name: upload.name,
          content_type: upload.content_type,
          size_bytes: upload.size_bytes,
          original_size_bytes: upload.original_size_bytes,
          truncated: Boolean(upload.truncated),
        })),
        actions: [],
      });
      project.updatedAt = nowIso();
      renderTimeline(project);
    }

    clearComposerNotice();
    state.awaitingResponse = true;
    state.activeAbortController = abortController;
    state.activeRequest = {
      projectId: project.id,
      requestId,
      userText: normalizedUserText,
      queuedUploads: queuedUploads.map((item) => ({ ...item })),
      action,
    };
    setBusy(true);
    renderComposer(project);
    try {
      const response = await postTurn(payload, { signal: abortController.signal });
      applyResponse(project, response, "live");
    } catch (error) {
      if (error?.name === "TimeoutError") {
        timedOut = true;
      } else if (error?.name === "AbortError") {
        abortedByUser = true;
      } else {
        applyResponse(project, mockAdapterTurn(project, payload), "mock");
      }
    } finally {
      if (!abortedByUser && !timedOut) {
        const elapsed = Date.now() - pendingStartedAt;
        const remaining = MIN_PENDING_VISUAL_MS - elapsed;
        if (remaining > 0) {
          await new Promise((resolve) => window.setTimeout(resolve, remaining));
        }
      }
      if (abortedByUser || timedOut) {
        const activeProject = state.projects.find((item) => item.id === project.id);
        if (activeProject) {
          const last = activeProject.timeline[activeProject.timeline.length - 1];
          if (last && normalizeText(last.request_id) === requestId) {
            activeProject.timeline.pop();
          }
          if (normalizedUserText) {
            activeProject.draftText = normalizedUserText;
          }
          if (queuedUploads.length) {
            activeProject.pendingUploads = uniqueUploads([...queuedUploads, ...activeProject.pendingUploads]);
          }
          activeProject.updatedAt = nowIso();
        }
        showComposerNotice(
          timedOut
            ? "Превышено время ожидания. Проверь соединение и отправь сообщение повторно."
            : "Ответ остановлен. Можно отредактировать сообщение и отправить снова.",
          timedOut ? "warning" : "info",
        );
      } else if (queuedUploads.length) {
        project.pendingUploads = project.pendingUploads.filter(
          (item) => !queuedUploads.some((queued) => queued.upload_id === item.upload_id),
        );
      }
      if (!abortedByUser && !timedOut) {
        project.draftText = "";
      }
      state.awaitingResponse = false;
      state.activeAbortController = null;
      state.activeRequest = null;
      renderAll();
      setBusy(false);
      focusComposerSoon();
    }
  }

  async function refreshActiveProject(options = {}) {
    if (!ensureWorkspaceAccess()) {
      return;
    }
    const project = getActiveProject();
    if (!project) {
      return;
    }
    const syncReason = normalizeText(options.syncReason, "manual_refresh");
    const suppressFailureBanner = Boolean(options.suppressFailureBanner);
    if (!project.sessionId) {
      return;
    }

    setBusy(true);
    try {
      const response = await fetchSession(project.sessionId);
      applyResponse(project, response, "live", { appendReplyMessages: false, syncReason });
    } catch (_error) {
      state.connectionMode = project.lastResponse ? state.connectionMode : "mock";
      renderConnection();
      if (!suppressFailureBanner) {
        renderAll();
      }
    } finally {
      setBusy(false);
    }
  }

  async function restoreSessionOnLoad() {
    const project = getActiveProject();
    if (!state.accessToken || !project?.sessionId) {
      return;
    }
    await refreshActiveProject({ syncReason: "auto_resume", suppressFailureBanner: true });
  }

  function handleActionShortcut(action) {
    closeProjectActionsMenu();
    const project = getActiveProject();
    if (!state.accessToken || action === "submit_access_token") {
      dom.accessTokenInput.focus();
      return;
    }

    if (action === "start_project") {
      if (!project || hasConversationActivity(project)) {
        createNewProject({ activate: true });
      }
      const active = getActiveProject();
      setProjectAction(active, "start_project");
      focusComposerSoon();
      return;
    }

    if (action === "download_artifact") {
      if (project) {
        project.sidePanelOpen = true;
        persist();
        renderAll();
      }
      return;
    }

    if (action === "request_brief_review") {
      if (project && hasPanelContent(project)) {
        project.sidePanelOpen = true;
        project.currentAction = action;
        persist();
        renderAll();
        return;
      }
      setProjectAction(project, action);
      dispatchTurn(action, "", { skipUserMessage: true });
      return;
    }

    if (["request_status", "confirm_brief"].includes(action)) {
      setProjectAction(project, action);
      dispatchTurn(action, "", { skipUserMessage: true });
      return;
    }

    setProjectAction(project, action);
    focusComposerSoon();
  }

  function bindEvents() {
    if (dom.sidebarResizer) {
      let resizeSession = null;

      const finishResize = (persistWidth) => {
        if (!resizeSession) {
          return;
        }
        resizeSession = null;
        dom.root.classList.remove("is-resizing");
        window.removeEventListener("pointermove", handleResizeMove);
        window.removeEventListener("pointerup", handleResizeEnd);
        window.removeEventListener("pointercancel", handleResizeEnd);
        if (persistWidth) {
          persist();
        }
      };

      const handleResizeMove = (event) => {
        if (!resizeSession) {
          return;
        }
        const delta = event.clientX - resizeSession.startX;
        updateSidebarWidth(resizeSession.startWidth + delta);
      };

      const handleResizeEnd = () => {
        finishResize(true);
      };

      dom.sidebarResizer.addEventListener("pointerdown", (event) => {
        if (event.button !== 0 || isMobileLayout()) {
          return;
        }
        event.preventDefault();
        resizeSession = {
          startX: event.clientX,
          startWidth: state.sidebarWidth,
        };
        dom.root.classList.add("is-resizing");
        window.addEventListener("pointermove", handleResizeMove);
        window.addEventListener("pointerup", handleResizeEnd);
        window.addEventListener("pointercancel", handleResizeEnd);
      });

      dom.sidebarResizer.addEventListener("keydown", (event) => {
        if (isMobileLayout()) {
          return;
        }
        if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") {
          return;
        }
        event.preventDefault();
        const delta = event.key === "ArrowRight" ? 24 : -24;
        updateSidebarWidth(state.sidebarWidth + delta, { persist: true });
      });

      window.addEventListener("resize", () => {
        const clamped = clampSidebarWidth(state.sidebarWidth);
        if (clamped !== state.sidebarWidth) {
          updateSidebarWidth(clamped, { persist: true });
          return;
        }
        applySidebarWidth();
      });
    }

    dom.newProject.addEventListener("click", () => {
      createNewProject({ activate: true });
      focusComposerSoon();
    });

    dom.projectMenu.addEventListener("click", (event) => {
      event.stopPropagation();
      const project = getActiveProject();
      if (project) {
        openProjectActionsMenu(project.id, dom.projectMenu);
      }
    });

    dom.projectActionsRename.addEventListener("click", () => {
      const projectId = normalizeText(state.projectActions.projectId);
      closeProjectActionsMenu();
      renderProjectActionsMenu();
      if (!projectId) {
        return;
      }
      promptRenameProject(projectId);
    });

    dom.projectActionsDelete.addEventListener("click", () => {
      const projectId = normalizeText(state.projectActions.projectId);
      closeProjectActionsMenu();
      renderProjectActionsMenu();
      if (!projectId) {
        return;
      }
      deleteProjectWithConfirm(projectId);
    });

    dom.sidePanelToggle.addEventListener("click", () => {
      const project = getActiveProject();
      if (!project || !hasPanelContent(project)) {
        return;
      }
      project.sidePanelOpen = !project.sidePanelOpen;
      persist();
      renderAll();
    });

    dom.sidePanelClose.addEventListener("click", () => {
      const project = getActiveProject();
      if (!project) {
        return;
      }
      project.sidePanelOpen = false;
      persist();
      renderAll();
    });

    dom.homeExamples.addEventListener("click", (event) => {
      const target = event.target.closest("[data-example-prompt]");
      if (!target) {
        return;
      }
      dom.composerInput.value = normalizeText(target.dataset.examplePrompt);
      const project = getActiveProject();
      if (project) {
        project.draftText = dom.composerInput.value;
        persist();
      }
      resizeComposerInput();
      focusComposerSoon();
    });

    dom.composerInput.addEventListener("input", () => {
      const project = getActiveProject();
      if (!project) {
        return;
      }
      project.draftText = dom.composerInput.value;
      if (state.composerNotice.text) {
        clearComposerNotice();
        renderComposer(project);
      }
      resizeComposerInput();
      persist();
    });

    dom.composerInput.addEventListener("keydown", (event) => {
      if (state.awaitingResponse || event.key !== "Enter" || event.shiftKey || event.isComposing) {
        return;
      }
      event.preventDefault();
      dom.composerForm.requestSubmit();
    });

    dom.composerForm.addEventListener("submit", (event) => {
      event.preventDefault();
      if (state.awaitingResponse) {
        const stopRequested = event.submitter === dom.composerSubmit || document.activeElement === dom.composerSubmit;
        if (stopRequested) {
          stopActiveResponse();
        }
        return;
      }
      const project = getActiveProject();
      if (!project || !state.accessToken) {
        dom.accessTokenInput.focus();
        return;
      }
      const text = normalizeText(dom.composerInput.value);
      const queuedUploads = uniqueUploads(project.pendingUploads);
      const allowWithoutText = ["request_status", "request_brief_review", "confirm_brief"].includes(project.currentAction);
      if (!text && !queuedUploads.length && !allowWithoutText) {
        dom.composerInput.focus();
        return;
      }
      clearComposerNotice();
      project.draftText = "";
      dispatchTurn(project.currentAction, text, { queuedUploads });
      dom.composerInput.value = "";
      resizeComposerInput();
      if (project.currentAction !== "submit_turn") {
        setProjectAction(project, "submit_turn");
      }
      focusComposerSoon();
    });

    dom.attachmentInput.addEventListener("change", async () => {
      const project = getActiveProject();
      const selectedFiles = Array.from(dom.attachmentInput.files || []);
      dom.attachmentInput.value = "";
      if (!project || !selectedFiles.length) {
        return;
      }
      await ingestSelectedFiles(project, selectedFiles);
    });

    let composerDragDepth = 0;
    const clearComposerDragState = () => {
      composerDragDepth = 0;
      dom.composerForm.classList.remove("is-dragover");
    };

    dom.composerForm.addEventListener("dragenter", (event) => {
      if (!state.accessToken || !hasFilePayload(event.dataTransfer)) {
        return;
      }
      event.preventDefault();
      composerDragDepth += 1;
      dom.composerForm.classList.add("is-dragover");
    });

    dom.composerForm.addEventListener("dragover", (event) => {
      if (!state.accessToken || !hasFilePayload(event.dataTransfer)) {
        return;
      }
      event.preventDefault();
      event.dataTransfer.dropEffect = "copy";
      dom.composerForm.classList.add("is-dragover");
    });

    dom.composerForm.addEventListener("dragleave", (event) => {
      if (!state.accessToken || !hasFilePayload(event.dataTransfer)) {
        return;
      }
      event.preventDefault();
      composerDragDepth = Math.max(0, composerDragDepth - 1);
      if (composerDragDepth === 0) {
        dom.composerForm.classList.remove("is-dragover");
      }
    });

    dom.composerForm.addEventListener("drop", async (event) => {
      if (!state.accessToken || !hasFilePayload(event.dataTransfer)) {
        return;
      }
      event.preventDefault();
      clearComposerDragState();
      const project = getActiveProject();
      const droppedFiles = Array.from(event.dataTransfer?.files || []);
      if (!project || !droppedFiles.length) {
        return;
      }
      await ingestSelectedFiles(project, droppedFiles);
    });

    document.addEventListener("dragover", (event) => {
      if (!hasFilePayload(event.dataTransfer)) {
        return;
      }
      event.preventDefault();
    });

    document.addEventListener("drop", (event) => {
      if (!hasFilePayload(event.dataTransfer)) {
        return;
      }
      if (dom.composerForm.contains(event.target)) {
        return;
      }
      event.preventDefault();
      clearComposerDragState();
    });

    if (dom.accessForm) {
      dom.accessForm.addEventListener("submit", (event) => {
        event.preventDefault();
        void unlockAccess();
      });
    }

    dom.refreshSession.addEventListener("click", () => {
      refreshActiveProject({ syncReason: "manual_refresh" });
    });

    document.addEventListener("click", (event) => {
      if (!state.projectActions.open) {
        return;
      }
      if (!dom.projectActionsMenu || !dom.projectMenu) {
        return;
      }
      if (dom.projectActionsMenu.contains(event.target) || dom.projectMenu.contains(event.target)) {
        return;
      }
      const clickedMenuTrigger = event.target instanceof Element ? event.target.closest(".project-card__menu") : null;
      if (clickedMenuTrigger) {
        return;
      }
      closeProjectActionsMenu();
      renderProjectActionsMenu();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && state.projectActions.open) {
        closeProjectActionsMenu();
        renderProjectActionsMenu();
        focusComposerSoon();
      }
    });
  }

  function init() {
    hydrate();
    bindEvents();
    const restoredToken = normalizeText(state.accessToken);
    state.accessToken = "";
    dom.accessTokenInput.value = restoredToken;
    renderAll();
    dom.root.dataset.mode = "ready";
    if (restoredToken) {
      setGateNote("Проверяю сохранённый access token...", "info");
      void unlockAccess(restoredToken);
      return;
    }
    void restoreSessionOnLoad();
  }

  init();
})();
