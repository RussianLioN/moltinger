(() => {
  const STORAGE_KEY = "agent-factory-web-demo-shell.v3";
  const ACCESS_TOKEN_KEY = "agent-factory-web-demo-access-token.v1";
  const DEFAULT_ACCESS_TOKEN = "demo-access-token";
  const MAX_LOCAL_UPLOAD_FILES = 4;
  const MAX_LOCAL_UPLOAD_BYTES = 512 * 1024;
  const IS_AUTOMATION = Boolean(window.navigator?.webdriver) || /playwright/i.test(window.navigator?.userAgent || "");
  const MIN_PENDING_VISUAL_MS = IS_AUTOMATION ? 120 : 650;
  const TURN_TIMEOUT_MS = IS_AUTOMATION ? 20_000 : 90_000;
  const ARTIFACT_FETCH_TIMEOUT_MS = IS_AUTOMATION ? 10_000 : 40_000;
  const HANDOFF_POLL_MAX_ATTEMPTS = IS_AUTOMATION ? 4 : 8;
  const HANDOFF_POLL_INTERVAL_MS = IS_AUTOMATION ? 320 : 1400;
  const DEFAULT_PROJECT_TITLE = "Новый проект";
  const SIDEBAR_WIDTH_DEFAULT = 264;
  const SIDEBAR_WIDTH_MIN = 220;
  const SIDEBAR_WIDTH_MAX = 560;
  const PANEL_WIDTH_DEFAULT = 460;
  const PANEL_WIDTH_MIN = 320;
  const PANEL_WIDTH_MAX = 720;
  const SCROLL_BOTTOM_THRESHOLD = 80;
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
    request_status: "Обновить",
    request_brief_review: "Проверить brief",
    request_brief_correction: "Исправить",
    confirm_brief: "Подтвердить",
    reopen_brief: "Переоткрыть",
    preview_one_page: "Просмотр",
    test_asset: "Посмотреть результат",
    download_artifact: "Материалы",
    submit_access_token: "Войти",
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
    awaiting_clarification: "Нужно уточнение",
    awaiting_confirmation: "Нужно внимание",
    confirmed: "Готово",
    handoff_running: "Фабрика обрабатывает",
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
  const BUSINESS_IDEA_SIGNAL_MARKERS = [
    "автомат",
    "процесс",
    "заявк",
    "клиент",
    "кредит",
    "комитет",
    "one-page",
    "summary",
    "отчет",
    "документ",
    "согласован",
    "маршрут",
    "проверк",
    "анализ",
    "decision",
    "approval",
  ];
  const dom = {
    root: document.querySelector('[data-role="app-root"]'),
    appFrame: document.querySelector(".app-frame"),
    sidebarResizer: document.querySelector('[data-role="sidebar-resizer"]'),
    sidebarToggle: document.querySelector('[data-role="sidebar-toggle"]'),
    workspaceShell: document.querySelector('[data-role="workspace-shell"]'),
    workspaceTopbar: document.querySelector(".workspace-topbar"),
    panelResizer: document.querySelector('[data-role="panel-resizer"]'),
    gateNote: document.querySelector('[data-role="gate-note"]'),
    accessForm: document.querySelector('[data-role="access-form"]'),
    accessTokenInput: document.querySelector('[data-role="access-token-input"]'),
    accessSubmit: document.querySelector('[data-role="access-submit"]'),
    projectList: document.querySelector('[data-role="project-list"]'),
    newProject: document.querySelector('[data-role="new-project"]'),
    projectTitle: document.querySelector('[data-role="project-title"]'),
    projectSubtitle: document.querySelector('[data-role="project-subtitle"]'),
    projectMenu: document.querySelector('[data-role="project-menu"]'),
    agentStatus: document.querySelector('[data-role="agent-status"]'),
    homePanel: document.querySelector('[data-role="home-panel"]'),
    homeExamples: document.querySelector('[data-role="home-examples"]'),
    sidePanel: document.querySelector('[data-role="side-panel"]'),
    sidePanelToggle: document.querySelector('[data-role="side-panel-toggle"]'),
    sidePanelFullscreen: document.querySelector('[data-role="side-panel-fullscreen"]'),
    sidePanelClose: document.querySelector('[data-role="side-panel-close"]'),
    sidePanelEyebrow: document.querySelector('[data-role="side-panel-eyebrow"]'),
    sidePanelTitle: document.querySelector('[data-role="side-panel-title"]'),
    sidePanelSummary: document.querySelector('[data-role="side-panel-summary"]'),
    sidePanelBody: document.querySelector('[data-role="side-panel-body"]'),
    briefEditToggle: document.querySelector('[data-role="brief-edit-toggle"]'),
    briefEditSection: document.querySelector('[data-role="brief-edit"]'),
    briefEditInput: document.querySelector('[data-role="brief-edit-input"]'),
    briefEditApply: document.querySelector('[data-role="brief-edit-apply"]'),
    briefConfirm: document.querySelector('[data-role="brief-confirm"]'),
    panelCardList: document.querySelector('[data-role="panel-card-list"]'),
    primaryArtifactSection: document.querySelector('[data-role="primary-artifact-section"]'),
    primaryArtifactHeading: document.querySelector('[data-role="primary-artifact-heading"]'),
    primaryArtifactKind: document.querySelector('[data-role="primary-artifact-kind"]'),
    primaryArtifactState: document.querySelector('[data-role="primary-artifact-state"]'),
    primaryArtifactBody: document.querySelector('[data-role="primary-artifact-body"]'),
    primaryArtifactPreview: document.querySelector('[data-role="primary-artifact-preview"]'),
    primaryArtifactDownload: document.querySelector('[data-role="primary-artifact-download"]'),
    previewSection: document.querySelector('[data-role="preview-section"]'),
    previewHeading: document.querySelector('[data-role="preview-heading"]'),
    previewStatus: document.querySelector('[data-role="preview-status"]'),
    previewFrame: document.querySelector('[data-role="preview-frame"]'),
    previewDownload: document.querySelector('[data-role="preview-download"]'),
    artifactSection: document.querySelector('[data-role="artifact-section"]'),
    artifactSectionHeading: document.querySelector('[data-role="artifact-section-heading"]'),
    composerHelperExample: document.querySelector('[data-role="composer-helper-example"]'),
    connectionState: document.querySelector('[data-role="connection-state"]'),
    sessionBadge: document.querySelector('[data-role="session-badge"]'),
    refreshSession: document.querySelector('[data-role="refresh-session"]'),
    threadPanel: document.querySelector('[data-role="thread-panel"]'),
    chatLog: document.querySelector('[data-role="chat-log"]'),
    composerForm: document.querySelector('[data-role="composer-form"]'),
    composerLead: document.querySelector('[data-role="composer-lead"]'),
    composerLeadLabel: document.querySelector('[data-role="composer-lead-label"]'),
    composerMode: document.querySelector('[data-role="composer-mode"]'),
    composerThinking: document.querySelector('[data-role="composer-thinking"]'),
    composerInput: document.querySelector('[data-role="composer-input"]'),
    composerSubmit: document.querySelector('[data-role="composer-submit"]'),
    composerNotice: document.querySelector('[data-role="composer-notice"]'),
    attachmentTrigger: document.querySelector('[data-role="attachment-trigger"]'),
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
    sidebarVisible: true,
    sidebarWidth: SIDEBAR_WIDTH_DEFAULT,
    panelWidth: PANEL_WIDTH_DEFAULT,
    activeProjectId: "",
    projects: [],
    gateNote: "Токен запрашивается только один раз для этой браузерной сессии.",
    gateNoteTone: "neutral",
    awaitingResponse: false,
    forceScrollToBottom: false,
    activeAbortController: null,
    activeRequest: null,
    composerNotice: { text: "", tone: "info", projectId: "" },
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

  function showComposerNotice(text, tone = "info", projectId = "") {
    const activeProjectId = normalizeText(projectId) || normalizeText(getActiveProject()?.id);
    state.composerNotice = {
      text: normalizeText(text),
      tone: normalizeText(tone, "info"),
      projectId: activeProjectId,
    };
  }

  function clearComposerNotice() {
    state.composerNotice = { text: "", tone: "info", projectId: "" };
  }

  function composerNoticeForProject(project) {
    const text = normalizeText(state.composerNotice?.text);
    const noticeProjectId = normalizeText(state.composerNotice?.projectId);
    if (!text) {
      return { text: "", tone: "info" };
    }
    if (project && noticeProjectId && noticeProjectId !== project.id) {
      return { text: "", tone: "info" };
    }
    return {
      text,
      tone: normalizeText(state.composerNotice?.tone, "info"),
    };
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
      showComposerNotice(warnings.join(" "), unsupported.length ? "warning" : "info", project.id);
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

  function panelMaxByViewport() {
    const occupiedSidebar = state.sidebarVisible === false ? 0 : state.sidebarWidth;
    const shellWidth = Math.max(
      0,
      dom.workspaceShell?.clientWidth || 0,
      window.innerWidth - occupiedSidebar - 48,
    );
    const minCenterWidth = 300;
    const available = Math.max(PANEL_WIDTH_MIN, shellWidth - minCenterWidth - 20);
    return Math.max(PANEL_WIDTH_MIN, Math.min(Math.max(PANEL_WIDTH_MAX, 1040), available));
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
      dom.root.style.setProperty("--sidebar-width-effective", `${state.sidebarVisible === false ? 0 : nextWidth}px`);
    }
    if (dom.sidebarResizer) {
      dom.sidebarResizer.setAttribute("aria-valuemin", String(SIDEBAR_WIDTH_MIN));
      dom.sidebarResizer.setAttribute("aria-valuemax", String(sidebarMaxByViewport()));
      dom.sidebarResizer.setAttribute("aria-valuenow", String(nextWidth));
    }
  }

  function applySidebarVisibility() {
    const visible = state.sidebarVisible !== false;
    state.sidebarVisible = visible;
    if (dom.appFrame) {
      dom.appFrame.dataset.sidebarOpen = visible ? "true" : "false";
    }
    if (dom.root) {
      dom.root.style.setProperty("--sidebar-width-effective", `${visible ? state.sidebarWidth : 0}px`);
    }
    if (dom.sidebarResizer) {
      const mobileLayout = isMobileLayout();
      const interactive = visible && !mobileLayout;
      dom.sidebarResizer.hidden = mobileLayout;
      dom.sidebarResizer.setAttribute("aria-hidden", interactive ? "false" : "true");
      dom.sidebarResizer.tabIndex = interactive ? 0 : -1;
    }
    if (dom.sidebarToggle) {
      dom.sidebarToggle.hidden = false;
      dom.sidebarToggle.dataset.state = visible ? "active" : "inactive";
      dom.sidebarToggle.setAttribute("aria-pressed", visible ? "true" : "false");
      dom.sidebarToggle.setAttribute("aria-expanded", visible ? "true" : "false");
      dom.sidebarToggle.setAttribute("aria-label", visible ? "Свернуть левую панель" : "Развернуть левую панель");
      dom.sidebarToggle.title = visible ? "Свернуть левую панель" : "Развернуть левую панель";
    }
  }

  function updateSidebarWidth(nextWidth, options = {}) {
    state.sidebarWidth = clampSidebarWidth(nextWidth);
    applySidebarWidth();
    if (options.persist) {
      persist();
    }
  }

  function clampPanelWidth(value) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return PANEL_WIDTH_DEFAULT;
    }
    const max = panelMaxByViewport();
    return Math.min(Math.max(Math.round(parsed), PANEL_WIDTH_MIN), max);
  }

  function applyPanelWidth() {
    const nextWidth = clampPanelWidth(state.panelWidth);
    state.panelWidth = nextWidth;
    if (dom.root) {
      dom.root.style.setProperty("--panel-width", `${nextWidth}px`);
    }
    if (dom.panelResizer) {
      dom.panelResizer.setAttribute("aria-valuemin", String(PANEL_WIDTH_MIN));
      dom.panelResizer.setAttribute("aria-valuemax", String(panelMaxByViewport()));
      dom.panelResizer.setAttribute("aria-valuenow", String(nextWidth));
    }
  }

  function updatePanelWidth(nextWidth, options = {}) {
    state.panelWidth = clampPanelWidth(nextWidth);
    applyPanelWidth();
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
      preview_one_page: "preview_ready",
      test_asset: "preview_ready",
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
      sidePanelFullscreen: Boolean(project.sidePanelFullscreen),
      lastPanelMode: normalizeText(project.lastPanelMode),
      panelModeOverride: normalizeText(project.panelModeOverride),
      previewArtifactKind: normalizeText(project.previewArtifactKind),
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
      briefEditOpen: Boolean(project.briefEditOpen),
      briefDraft: normalizeText(project.briefDraft),
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
      sidePanelFullscreen: Boolean(record.sidePanelFullscreen),
      lastPanelMode: normalizeText(record.lastPanelMode),
      panelModeOverride: normalizeText(record.panelModeOverride),
      previewArtifactKind: normalizeText(record.previewArtifactKind),
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
      briefEditOpen: Boolean(record.briefEditOpen),
      briefDraft: normalizeText(record.briefDraft),
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
      sidePanelFullscreen: false,
      lastPanelMode: "",
      lastAutoFollowupSource: "",
      lastResumeFingerprint: "",
      briefEditOpen: false,
      briefDraft: "",
    });
  }

  function getActiveProject() {
    return state.projects.find((project) => project.id === state.activeProjectId) || state.projects[0] || null;
  }

  function persist() {
    const payload = {
      connectionMode: state.connectionMode,
      requestCounter: state.requestCounter,
      sidebarVisible: state.sidebarVisible,
      sidebarWidth: state.sidebarWidth,
      panelWidth: state.panelWidth,
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
      state.sidebarVisible = typeof saved.sidebarVisible === "boolean" ? saved.sidebarVisible : true;
      state.sidebarWidth = clampSidebarWidth(saved.sidebarWidth);
      state.panelWidth = clampPanelWidth(saved.panelWidth);
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
      dedupeProjectTitles();
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
    if (dom.attachmentTrigger) {
      dom.attachmentTrigger.disabled = state.awaitingResponse;
    }
    dom.refreshSession.disabled = isBusy;
    dom.accessSubmit.disabled = isBusy;
    dom.accessTokenInput.disabled = isBusy && !state.accessToken;
    dom.projectMenu.disabled = isBusy;
    dom.newProject.disabled = isBusy;
    if (dom.sidebarToggle) {
      dom.sidebarToggle.disabled = !state.accessToken;
    }
    renderAgentStatus();
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
    return Boolean(project.sessionId && response.web_demo_session?.status)
      || transcriptSize > 0
      || [
        "awaiting_user_reply",
        "awaiting_clarification",
        "awaiting_confirmation",
        "confirmed",
        "handoff_running",
        "playground_ready",
        "downloads_ready",
        "download_ready",
        "reopened",
      ].includes(visibleStatus);
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

  function isDownloadsReadyStatus(status) {
    return ["playground_ready", "downloads_ready", "download_ready"].includes(normalizeText(status));
  }

  function isPostBriefStatus(status) {
    const normalized = normalizeText(status);
    return isDownloadsReadyStatus(normalized) || normalized === "confirmed" || normalized === "handoff_running";
  }

  function isLikelyBriefConfirmationText(text) {
    const normalized = normalizeText(text).toLowerCase();
    if (!normalized) {
      return false;
    }
    const negationMarkers = ["не подтверж", "не готов подтверж", "not confirm", "don't confirm"];
    if (negationMarkers.some((marker) => normalized.includes(marker))) {
      return false;
    }
    const confirmationMarkers = [
      "подтверждаю",
      "подтверждено",
      "подтвердить",
      "confirm brief",
      "confirmed brief",
      "approve brief",
      "согласен",
      "согласна",
      "ок подтверждаю",
    ];
    return confirmationMarkers.some((marker) => normalized.includes(marker));
  }

  function isShortBriefConfirmationAck(text) {
    const normalized = normalizeText(text).toLowerCase();
    if (!normalized) {
      return false;
    }
    const negationMarkers = ["не подтверж", "не готов подтверж", "not confirm", "don't confirm"];
    if (negationMarkers.some((marker) => normalized.includes(marker))) {
      return false;
    }
    const compact = normalized
      .replace(/[.,!?;:()[\]{}"'`«»]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (!compact) {
      return false;
    }
    const shortAckMarkers = new Set(["да", "ок", "ok", "okay", "yes", "yep", "ага", "угу", "все ок", "всё ок"]);
    return shortAckMarkers.has(compact);
  }

  function hasBriefConfirmationIntent(text) {
    return isLikelyBriefConfirmationText(text) || isShortBriefConfirmationAck(text);
  }

  function isLikelyBriefCorrectionText(text) {
    const normalized = normalizeText(text).toLowerCase();
    if (!normalized) {
      return false;
    }
    const markers = [
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
    return markers.some((marker) => normalized.includes(marker));
  }

  function isLikelyStatusRefreshText(text) {
    const normalized = normalizeText(text).toLowerCase();
    if (!normalized) {
      return false;
    }
    if (hasBriefConfirmationIntent(normalized)) {
      return false;
    }
    if (isLikelyBriefCorrectionText(normalized)) {
      return false;
    }
    if (isLikelyProductionSimulationRequestText(normalized)) {
      return false;
    }
    if (normalized.length > 96) {
      return false;
    }
    const markers = ["обнов", "статус", "продолж", "что дальше", "refresh", "continue", "request status"];
    return markers.some((marker) => normalized.includes(marker));
  }

  function isLikelyProductionSimulationRequestText(text) {
    const normalized = normalizeText(text).toLowerCase();
    if (!normalized) {
      return false;
    }
    const markers = [
      "имитац",
      "симуляц",
      "запусти цифров",
      "цифровой сущности",
      "production simulation",
      "стартовый результат",
    ];
    return markers.some((marker) => normalized.includes(marker));
  }

  function resolveComposerAction(project, text) {
    const requestedAction = normalizeText(project?.currentAction, "submit_turn");
    const normalizedText = normalizeText(text);
    if (!normalizedText) {
      return requestedAction;
    }
    const status = currentStatus(project);
    const response = currentResponse(project) || {};
    const hasDownloadArtifacts = Array.isArray(response.download_artifacts) && response.download_artifacts.length > 0;
    const postBriefMode = hasDownloadArtifacts || isPostBriefStatus(status);
    const simulationRequest = isLikelyProductionSimulationRequestText(normalizedText);
    const confirmationRequest = hasBriefConfirmationIntent(normalizedText);
    const correctionRequest = isLikelyBriefCorrectionText(normalizedText);
    const explicitRefresh = isLikelyStatusRefreshText(normalizedText);
    const freeformFeedback = Boolean(normalizedText) && !simulationRequest && !confirmationRequest && !explicitRefresh;
    const reviewStage =
      ["awaiting_confirmation", "reopened"].includes(status)
      || (
        normalizeText(response?.ui_projection?.side_panel_mode) === "brief_review"
        && !postBriefMode
      );
    const knownComposerActions = new Set([
      "submit_turn",
      "request_status",
      "request_brief_review",
      "request_brief_correction",
      "confirm_brief",
      "reopen_brief",
    ]);
    if (reviewStage) {
      if (confirmationRequest) {
        return "confirm_brief";
      }
      if (explicitRefresh) {
        return "request_status";
      }
      if (correctionRequest || freeformFeedback) {
        return "request_brief_correction";
      }
    }

    if (
      confirmationRequest
      && ["confirm_brief", "request_brief_correction", "request_brief_review"].includes(requestedAction)
      && !postBriefMode
    ) {
      return "confirm_brief";
    }

    if (simulationRequest && postBriefMode) {
      return "request_status";
    }
    if (postBriefMode && !knownComposerActions.has(requestedAction)) {
      return correctionRequest || freeformFeedback ? "reopen_brief" : "request_status";
    }
    if (requestedAction === "confirm_brief") {
      if (confirmationRequest) {
        return "confirm_brief";
      }
      return correctionRequest || freeformFeedback ? "request_brief_correction" : "request_status";
    }
    if (requestedAction === "request_status") {
      if (["awaiting_confirmation", "reopened"].includes(status)) {
        if (confirmationRequest) {
          return "confirm_brief";
        }
        return correctionRequest || freeformFeedback ? "request_brief_correction" : "request_status";
      }
      if (isPostBriefStatus(status)) {
        return correctionRequest || freeformFeedback ? "reopen_brief" : "request_status";
      }
      return "submit_turn";
    }
    if (requestedAction === "request_brief_review") {
      if (["awaiting_confirmation", "reopened"].includes(status)) {
        return correctionRequest || freeformFeedback ? "request_brief_correction" : "request_status";
      }
      if (isPostBriefStatus(status)) {
        return correctionRequest || freeformFeedback ? "reopen_brief" : "request_status";
      }
      return "submit_turn";
    }
    if (requestedAction === "submit_turn" && isPostBriefStatus(status)) {
      return correctionRequest || freeformFeedback ? "reopen_brief" : "request_status";
    }
    return requestedAction;
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
      return "Войти";
    }
    if (state.awaitingResponse) {
      return "Агент-архитектор формирует следующий шаг";
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
      return "Опиши задачу автоматизации простыми словами.";
    }
    if (action === "confirm_brief") {
      return "Подтверди brief или напиши, что нужно исправить.";
    }
    if (action === "request_brief_correction") {
      return "Опиши, что поправить в brief.";
    }
    if (action === "reopen_brief") {
      return "Опиши, что нужно доуточнить, чтобы переоткрыть brief.";
    }
    if (status === "handoff_running") {
      return "Фабрика готовит материалы. Можно дождаться обновления статуса или отправить правку brief.";
    }
    if (isPostBriefStatus(status)) {
      return "Опиши правку brief или запроси имитацию запуска.";
    }
    if (topic === "input_examples") {
      return "Приведи 1–2 примера или прикрепи файл.";
    }
    return "Ответь на вопрос агента.";
  }

  function helperExampleFor(project) {
    return "";
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
    if (isPostBriefStatus(status)) {
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
    if (isPostBriefStatus(status)) {
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
    title.title = project.title;
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
    const title = project?.title || DEFAULT_PROJECT_TITLE;
    dom.projectTitle.textContent = title;
    dom.projectTitle.title = title;
    dom.projectSubtitle.textContent = projectSubtitle(project);
    renderSidePanelToggle(project);
    renderAgentStatus();
  }

  function renderAgentStatus() {
    if (!dom.agentStatus) {
      return;
    }
    dom.agentStatus.hidden = !state.awaitingResponse;
    dom.agentStatus.dataset.state = state.awaitingResponse ? "thinking" : "idle";
  }

  function isPanelOnlyAction(action) {
    return ["preview_one_page", "test_asset", "download_artifact"].includes(normalizeText(action));
  }

  function isKnownAction(action) {
    return Object.prototype.hasOwnProperty.call(ACTION_LABELS, normalizeText(action));
  }

  function isComposerAction(action) {
    const normalized = normalizeText(action);
    return Boolean(normalized) && isKnownAction(normalized) && !isPanelOnlyAction(normalized) && normalized !== "submit_access_token";
  }

  function normalizeArtifactKind(value) {
    return normalizeText(value)
      .toLowerCase()
      .replace(/[\s-]+/g, "_");
  }

  function artifactKindLabel(artifactKind) {
    const labels = {
      one_page_summary: "One-page summary",
      project_doc: "Project doc",
      agent_spec: "Agent spec",
      presentation: "Presentation",
    };
    return labels[normalizeArtifactKind(artifactKind)] || normalizeText(artifactKind, "artifact").replace(/_/g, " ");
  }

  function artifactDescription(artifact) {
    if (normalizeText(artifact?.description)) {
      return artifact.description;
    }
    const descriptions = {
      one_page_summary: "Главный one-page результат фабрики для быстрого просмотра и проверки.",
      project_doc: "Проектная рамка и бизнес-контекст для защиты концепции.",
      agent_spec: "Спецификация будущего агента, сценарии и интерфейсы.",
      presentation: "Материал для защиты идеи и последующего feedback loop.",
    };
    return descriptions[normalizeArtifactKind(artifact?.artifact_kind)] || "Артефакт проекта.";
  }

  function artifactIsReady(artifact) {
    return ["ready", "available"].includes(normalizeText(artifact?.download_status));
  }

  function artifactPlaceholders() {
    return [
      {
        artifact_kind: "one_page_summary",
        download_name: "one-page-summary.md",
        download_status: "pending",
        description: "Главный one-page результат фабрики для быстрого просмотра и проверки.",
      },
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

  function projectArtifacts(project) {
    const responseArtifacts = Array.isArray(project?.lastResponse?.download_artifacts)
      ? project.lastResponse.download_artifacts
      : [];
    if (responseArtifacts.length) {
      return responseArtifacts;
    }
    if (isDownloadsReadyStatus(currentStatus(project))) {
      return artifactPlaceholders();
    }
    return [];
  }

  function primaryArtifactKind(project, artifacts = projectArtifacts(project)) {
    const explicit = normalizeArtifactKind(project?.lastResponse?.ui_projection?.primary_artifact);
    const onePage = artifacts.find((artifact) => normalizeArtifactKind(artifact.artifact_kind) === "one_page_summary");
    // One-page всегда главный артефакт, кроме явного переключения на production simulation.
    if (onePage && explicit !== "production_simulation") {
      return "one_page_summary";
    }
    if (explicit && artifacts.some((artifact) => normalizeArtifactKind(artifact.artifact_kind) === explicit)) {
      return explicit;
    }
    if (onePage) {
      return "one_page_summary";
    }
    return normalizeArtifactKind(artifacts[0]?.artifact_kind);
  }

  function primaryArtifact(project, artifacts = projectArtifacts(project)) {
    const kind = primaryArtifactKind(project, artifacts);
    return artifacts.find((artifact) => normalizeArtifactKind(artifact.artifact_kind) === kind) || artifacts[0] || null;
  }

  function secondaryArtifacts(project, artifacts = projectArtifacts(project)) {
    const primary = primaryArtifact(project, artifacts);
    const primaryKind = normalizeArtifactKind(primary?.artifact_kind);
    return artifacts.filter((artifact) => normalizeArtifactKind(artifact.artifact_kind) !== primaryKind);
  }

  function selectedPreviewArtifact(project, artifacts = projectArtifacts(project)) {
    const requestedKind = normalizeArtifactKind(project?.previewArtifactKind);
    if (requestedKind) {
      const selected = artifacts.find((artifact) => normalizeArtifactKind(artifact.artifact_kind) === requestedKind);
      if (selected) {
        return selected;
      }
    }
    return primaryArtifact(project, artifacts);
  }

  function artifactDownloadUrl(project, artifact) {
    if (!artifact) {
      return "";
    }
    if (normalizeText(artifact.download_url)) {
      return artifact.download_url;
    }
    const sessionId = normalizeText(project?.lastResponse?.web_demo_session?.web_demo_session_id || project?.sessionId);
    const artifactKind = normalizeText(artifact.artifact_kind);
    if (sessionId && artifactKind && state.connectionMode === "live") {
      return `/api/download/${encodeURIComponent(sessionId)}/${encodeURIComponent(artifactKind)}`;
    }
    return "";
  }

  function artifactPreviewUrl(project, artifact) {
    const sessionId = normalizeText(project?.lastResponse?.web_demo_session?.web_demo_session_id || project?.sessionId);
    const artifactKind = normalizeText(artifact?.artifact_kind);
    if (!sessionId || !artifactKind) {
      return "";
    }
    return `/api/preview/${encodeURIComponent(sessionId)}/${encodeURIComponent(artifactKind)}`;
  }

  async function triggerArtifactDownload(project, artifact) {
    if (!artifact || !artifactIsReady(artifact)) {
      return;
    }
    let objectUrl = "";
    try {
      const href = artifactDownloadUrl(project, artifact);
      if (!href) {
        throw new Error("download_unavailable");
      }
      const response = await fetchWithTimeout(
        href,
        {
          headers: { Accept: "*/*" },
          cache: "no-store",
        },
        ARTIFACT_FETCH_TIMEOUT_MS,
      );
      if (!response.ok) {
        throw new Error(`download_http_${response.status}`);
      }
      const blob = await response.blob();
      objectUrl = URL.createObjectURL(blob);

      const link = document.createElement("a");
      link.href = objectUrl;
      link.download = artifact.download_name || "artifact.txt";
      document.body.appendChild(link);
      link.click();
      link.remove();
      showComposerNotice("Файл подготовлен к скачиванию.", "info", project?.id);
    } catch (error) {
      showComposerNotice(
        `Не удалось скачать артефакт: ${normalizeText(error?.message, "unknown_error")}.`,
        "error",
        project?.id,
      );
    } finally {
      if (objectUrl) {
        window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
      }
      renderComposer(getActiveProject());
    }
  }

  function openPanelMode(project, mode, artifactKind = "") {
    if (!project) {
      return;
    }
    if (mode !== "hidden" && state.panelWidth < 420) {
      updatePanelWidth(PANEL_WIDTH_DEFAULT, { persist: true });
    }
    project.sidePanelOpen = mode !== "hidden";
    project.sidePanelFullscreen = mode === "hidden" ? false : Boolean(project.sidePanelFullscreen);
    project.panelModeOverride = mode === "preview" || mode === "downloads" ? mode : "";
    project.previewArtifactKind = mode === "preview"
      ? normalizeArtifactKind(artifactKind || primaryArtifact(project)?.artifact_kind)
      : "";
    persist();
    renderAll();
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
    const normalizedAck = acknowledgement.replace(/\s+/g, " ").trim();
    const looksTruncatedSummary = /[:]\s*.+[.…]+$/.test(normalizedAck) || /…/.test(normalizedAck);
    const cleanedAck = looksTruncatedSummary
      ? "Ответ зафиксировал."
      : normalizedAck;
    return { acknowledgement: cleanedAck, question };
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

    actions.innerHTML = "";
    if (bodyText && message.role === "agent") {
      const copy = document.createElement("button");
      copy.type = "button";
      copy.className = "message__action";
      copy.textContent = "⧉";
      copy.title = "Копировать";
      copy.setAttribute("aria-label", "Скопировать сообщение");
      copy.addEventListener("click", async () => {
        try {
          await window.navigator.clipboard.writeText(bodyText);
          showComposerNotice("Сообщение скопировано.", "info", getActiveProject()?.id);
        } catch (_error) {
          showComposerNotice("Не удалось скопировать сообщение.", "warning", getActiveProject()?.id);
        }
        renderComposer(getActiveProject());
      });
      actions.appendChild(copy);
    }
    actions.hidden = actions.childElementCount === 0;
    return fragment;
  }

  function timelineMessagesFromResponse(response) {
    const architectName = normalizeText(response?.ui_projection?.agent_display_name, "Агент-архитектор Moltis");
    const messages = (response?.reply_cards || [])
      .filter((card) => ["discovery_question", "clarification_prompt", "confirmation_prompt"].includes(card.card_kind))
      .map((card) => ({
        role: "agent",
        author: architectName,
        kind: card.card_kind || "reply_card",
        title: "",
        body: card.body_text || "",
        actions: [],
      }));
    if (messages.length) {
      return messages;
    }
    const fallbackBody = normalizeText(response?.ui_projection?.current_question || response?.next_question);
    if (!fallbackBody) {
      return [];
    }
    return [{
      role: "agent",
      author: architectName,
      kind: "status_update",
      title: "",
      body: fallbackBody,
      actions: [],
    }];
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

  function isChatNearBottom() {
    if (!dom.chatLog) {
      return true;
    }
    const distance = dom.chatLog.scrollHeight - dom.chatLog.scrollTop - dom.chatLog.clientHeight;
    return distance <= SCROLL_BOTTOM_THRESHOLD;
  }

  function scrollChatToBottom() {
    if (!dom.chatLog) {
      return;
    }
    const maxTop = Math.max(0, dom.chatLog.scrollHeight - dom.chatLog.clientHeight);
    dom.chatLog.scrollTop = maxTop;
  }

  function scrollChatToLatestAgentMessage() {
    if (!dom.chatLog) {
      return false;
    }
    const candidateQuestionNodes = dom.chatLog.querySelectorAll(".message--agent .message__question-line");
    const questionTarget = candidateQuestionNodes.length ? candidateQuestionNodes[candidateQuestionNodes.length - 1] : null;
    const agentNodes = dom.chatLog.querySelectorAll(".message--agent");
    const target = questionTarget || agentNodes[agentNodes.length - 1];
    if (!target) {
      return false;
    }
    const logRect = dom.chatLog.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    const targetHeight = Math.max(1, targetRect.height);
    const targetTop = targetRect.top - logRect.top + dom.chatLog.scrollTop;
    const targetBottom = targetTop + targetHeight;
    const topPadding = 8;
    const bottomPadding = 12;
    const visibleTop = dom.chatLog.scrollTop + topPadding;
    const visibleBottom = dom.chatLog.scrollTop + dom.chatLog.clientHeight - bottomPadding;
    const alreadyVisible = targetTop >= visibleTop && targetBottom <= visibleBottom;
    if (!alreadyVisible) {
      let nextTop = dom.chatLog.scrollTop;
      if (targetBottom > visibleBottom) {
        nextTop = targetBottom - dom.chatLog.clientHeight + bottomPadding;
      }
      if (targetTop < visibleTop) {
        nextTop = Math.min(nextTop, targetTop - topPadding);
      }
      const maxTop = Math.max(0, dom.chatLog.scrollHeight - dom.chatLog.clientHeight);
      dom.chatLog.scrollTop = Math.min(Math.max(0, Math.round(nextTop)), maxTop);
    }
    return true;
  }

  function scheduleScrollChatToBottom() {
    const syncScroll = () => {
      if (!scrollChatToLatestAgentMessage()) {
        scrollChatToBottom();
      }
    };
    window.requestAnimationFrame(() => {
      syncScroll();
      window.requestAnimationFrame(() => {
        syncScroll();
      });
    });
    window.setTimeout(syncScroll, 72);
  }

  function renderTimeline(project, options = {}) {
    const forceBottom = Boolean(options.forceBottom);
    const keepBottom = forceBottom || state.forceScrollToBottom || isChatNearBottom();
    dom.chatLog.innerHTML = "";
    const items = project?.timeline?.length ? project.timeline : [];
    items.forEach((message) => {
      dom.chatLog.appendChild(createMessageNode(message));
    });
    if (keepBottom) {
      scheduleScrollChatToBottom();
    }
  }

  function sidePanelMode(project) {
    const status = currentStatus(project);
    const canUseArtifactOverride = isPostBriefStatus(status);
    const localOverride = normalizeText(project?.panelModeOverride);
    if (canUseArtifactOverride && localOverride === "preview" && selectedPreviewArtifact(project)) {
      return "preview";
    }
    if (canUseArtifactOverride && localOverride === "downloads" && projectArtifacts(project).length) {
      return "downloads";
    }
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
    return (currentResponse(project)?.reply_cards || []).filter((card) => {
      if (!card || card.card_kind !== "brief_summary_section") {
        return false;
      }
      const title = normalizeText(card.title).toLowerCase();
      return !(title.startsWith("версия brief") || title === "brief summary");
    });
  }

  function panelPromptCard(project) {
    const response = currentResponse(project) || {};
    const cards = Array.isArray(response.reply_cards) ? response.reply_cards : [];
    if (sidePanelMode(project) === "brief_review") {
      return null;
    }
    if (["downloads", "preview"].includes(sidePanelMode(project))) {
      return cards.find((card) => ["factory_result", "factory_result_prompt", "download_prompt"].includes(card.card_kind)) || null;
    }
    return cards.find((card) => card.card_kind === "confirmation_prompt") || null;
  }

  function renderHome(project) {
    dom.homePanel.hidden = !state.accessToken || hasConversationActivity(project);
    dom.threadPanel.hidden = !state.accessToken || !hasConversationActivity(project);
  }

  function renderSidePanelToggle(project) {
    const mode = sidePanelMode(project);
    const canOpenPanel = mode !== "hidden";
    const isOpen = canOpenPanel && Boolean(project?.sidePanelOpen);
    dom.sidePanelToggle.hidden = false;
    dom.sidePanelToggle.disabled = !canOpenPanel;
    dom.sidePanelToggle.dataset.state = isOpen ? "active" : "inactive";
    dom.sidePanelToggle.setAttribute("aria-pressed", isOpen ? "true" : "false");
    dom.sidePanelToggle.setAttribute("aria-expanded", isOpen ? "true" : "false");
    if (!canOpenPanel) {
      dom.sidePanelToggle.setAttribute("aria-label", "Правая панель пока недоступна");
      dom.sidePanelToggle.title = "Правая панель недоступна";
      return;
    }
    dom.sidePanelToggle.setAttribute(
      "aria-label",
      isOpen ? "Свернуть правую панель" : "Развернуть правую панель",
    );
    dom.sidePanelToggle.title = isOpen ? "Свернуть правую панель" : "Развернуть правую панель";
  }

  function mockArtifactMarkdown(project, artifact) {
    const briefVersion = project?.lastResponse?.status_snapshot?.brief_version || "draft";
    if (normalizeArtifactKind(artifact?.artifact_kind) === "one_page_summary") {
      return [
        "# One-page summary",
        "",
        `Проект: ${project?.title || "Demo project"}`,
        `Brief version: ${briefVersion}`,
        "",
        "## Клиент",
        "- ООО Боку до манж",
        "- Сегмент: средний корпоративный бизнес",
        "",
        "## Сделка",
        "- Цель: оборотное финансирование",
        "- Сумма: 120 млн RUB",
        "",
        "## Цена",
        "- Базовая ставка подтверждена",
        "- Нужна финальная защита на кредитном комитете",
        "",
        "## Сотрудничество",
        "- История обслуживания положительная",
        "- Требуется финальное one-page решение",
      ].join("\n");
    }
    return [
      `# ${artifact.download_name}`,
      "",
      "Mock download из browser shell.",
      `artifact_kind: ${artifact.artifact_kind}`,
      `brief_version: ${briefVersion}`,
      `project_key: ${project?.lastResponse?.browser_project_pointer?.project_key || "demo-project"}`,
      "",
      "Этот файл нужен только как placeholder до live delivery layer.",
    ].join("\n");
  }

  function createMockDownload(project, artifact) {
    const body = mockArtifactMarkdown(project, artifact);
    return URL.createObjectURL(new Blob([body], { type: "text/markdown;charset=utf-8" }));
  }

  function escapeHtml(value) {
    return normalizeText(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function renderMarkdownInline(text) {
    return escapeHtml(text)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/`(.+?)`/g, "<code>$1</code>");
  }

  function markdownToPreviewHtml(markdown) {
    const lines = normalizeText(markdown).replace(/\r\n/g, "\n").split("\n");
    const chunks = [];
    let paragraph = [];
    let listItems = [];

    const flushParagraph = () => {
      if (!paragraph.length) {
        return;
      }
      chunks.push(`<p>${paragraph.join(" ")}</p>`);
      paragraph = [];
    };

    const flushList = () => {
      if (!listItems.length) {
        return;
      }
      chunks.push(`<ul>${listItems.join("")}</ul>`);
      listItems = [];
    };

    lines.forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed) {
        flushParagraph();
        flushList();
        return;
      }
      const headingMatch = trimmed.match(/^(#{1,3})\s+(.+)$/);
      if (headingMatch) {
        flushParagraph();
        flushList();
        const level = headingMatch[1].length;
        chunks.push(`<h${level}>${renderMarkdownInline(headingMatch[2])}</h${level}>`);
        return;
      }
      const listMatch = trimmed.match(/^[-*]\s+(.+)$/);
      if (listMatch) {
        flushParagraph();
        listItems.push(`<li>${renderMarkdownInline(listMatch[1])}</li>`);
        return;
      }
      paragraph.push(renderMarkdownInline(trimmed));
    });

    flushParagraph();
    flushList();
    return chunks.join("\n");
  }

  function wrapPreviewDocument(bodyHtml, title) {
    const safeTitle = escapeHtml(title || "Preview");
    return [
      "<!doctype html>",
      '<html lang="ru">',
      "<head>",
      '<meta charset="utf-8">',
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
      `<title>${safeTitle}</title>`,
      "<style>",
      "body{margin:0;padding:28px;background:#f6f1e8;color:#181512;font:15px/1.65 \"Georgia\",\"Times New Roman\",serif;}",
      "main{max-width:860px;margin:0 auto;}",
      "h1,h2,h3{font-family:\"Inter\",\"Segoe UI\",sans-serif;line-height:1.15;color:#14110f;}",
      "h1{font-size:2rem;margin:0 0 1rem;}",
      "h2{font-size:1.2rem;margin:1.6rem 0 0.7rem;}",
      "h3{font-size:1rem;margin:1.2rem 0 0.55rem;}",
      "p{margin:0 0 0.9rem;}",
      "ul{margin:0 0 1rem;padding-left:1.2rem;}",
      "li+li{margin-top:0.35rem;}",
      "code{padding:0.12rem 0.35rem;background:rgba(20,17,15,0.08);border-radius:0.3rem;font-size:0.92em;}",
      "</style>",
      "</head>",
      "<body>",
      `<main>${bodyHtml}</main>`,
      "</body>",
      "</html>",
    ].join("");
  }

  function mockPreviewDocument(project, artifact) {
    return wrapPreviewDocument(
      markdownToPreviewHtml(mockArtifactMarkdown(project, artifact)),
      artifact?.download_name || artifactKindLabel(artifact?.artifact_kind),
    );
  }

  function previewStateFor(project, artifact) {
    const previewKey = [
      project?.id,
      normalizeText(project?.lastResponse?.web_demo_session?.web_demo_session_id || project?.sessionId),
      normalizeArtifactKind(artifact?.artifact_kind),
      normalizeText(artifact?.download_token),
      normalizeText(artifact?.brief_version),
      normalizeText(project?.lastResponse?.status_snapshot?.brief_version),
    ].join(":");
    if (!project.previewState || project.previewState.key !== previewKey) {
      project.previewState = {
        key: previewKey,
        status: "idle",
        html: "",
        error: "",
      };
    }
    return project.previewState;
  }

  async function fetchArtifactPreviewHtml(project, artifact) {
    if (state.connectionMode !== "live") {
      throw new Error("preview_unavailable_offline");
    }

    const previewUrl = artifactPreviewUrl(project, artifact);
    if (previewUrl) {
      const previewResponse = await fetchWithTimeout(
        previewUrl,
        {
          headers: { Accept: "text/html" },
          cache: "no-store",
        },
        ARTIFACT_FETCH_TIMEOUT_MS,
      );
      if (previewResponse.ok) {
        return await previewResponse.text();
      }
    }

    const downloadUrl = artifactDownloadUrl(project, artifact);
    if (downloadUrl) {
      const downloadResponse = await fetchWithTimeout(
        downloadUrl,
        {
          headers: { Accept: "text/markdown,text/plain;q=0.9,*/*;q=0.1" },
          cache: "no-store",
        },
        ARTIFACT_FETCH_TIMEOUT_MS,
      );
      if (downloadResponse.ok) {
        const markdown = await downloadResponse.text();
        return wrapPreviewDocument(
          markdownToPreviewHtml(markdown),
          artifact?.download_name || artifactKindLabel(artifact?.artifact_kind),
        );
      }
    }

    throw new Error("Preview недоступен. Endpoint /api/preview или /api/download не вернул содержимое.");
  }

  async function loadArtifactPreview(project, artifact) {
    const previewState = previewStateFor(project, artifact);
    const requestKey = previewState.key;
    try {
      const html = await fetchArtifactPreviewHtml(project, artifact);
      if (!project.previewState || project.previewState.key !== requestKey) {
        return;
      }
      project.previewState.status = "ready";
      project.previewState.html = html;
      project.previewState.error = "";
    } catch (error) {
      if (!project.previewState || project.previewState.key !== requestKey) {
        return;
      }
      project.previewState.status = "error";
      project.previewState.html = "";
      project.previewState.error = normalizeText(error?.message, "Не удалось загрузить preview.");
    }
    renderAll();
  }

  function createSecondaryArtifactRow(project, artifact) {
    const ready = artifactIsReady(artifact);
    const row = document.createElement("div");
    row.className = "artifact-link-row";

    const copy = document.createElement("div");
    copy.className = "artifact-link-row__copy";

    const title = document.createElement("span");
    title.className = "artifact-link-row__title";
    title.textContent = artifact.download_name || artifactKindLabel(artifact.artifact_kind);

    const meta = document.createElement("span");
    meta.className = "artifact-link-row__meta";
    meta.textContent = `${artifactKindLabel(artifact.artifact_kind)} · ${normalizeText(artifact.download_status, "pending")}`;

    copy.append(title, meta);
    row.appendChild(copy);

    if (ready) {
      const actions = document.createElement("div");
      actions.className = "artifact-link-row__actions";

      const previewAction = document.createElement("button");
      previewAction.type = "button";
      previewAction.className = "artifact-link-row__action";
      previewAction.textContent = "Preview";
      previewAction.addEventListener("click", () => openPanelMode(project, "preview", artifact?.artifact_kind));

      const downloadAction = document.createElement("button");
      downloadAction.type = "button";
      downloadAction.className = "artifact-link-row__action";
      downloadAction.textContent = "Скачать";
      downloadAction.addEventListener("click", () => {
        void triggerArtifactDownload(project, artifact);
      });

      actions.append(previewAction, downloadAction);
      row.appendChild(actions);
    } else {
      const stateLabel = document.createElement("span");
      stateLabel.className = "artifact-link-row__state";
      stateLabel.textContent = normalizeText(artifact.download_status, "pending");
      row.appendChild(stateLabel);
    }

    return row;
  }

  function renderSecondaryArtifacts(project, artifacts) {
    dom.artifactList.innerHTML = "";
    dom.artifactEmpty.hidden = artifacts.length > 0;
    artifacts.forEach((artifact) => {
      dom.artifactList.appendChild(createSecondaryArtifactRow(project, artifact));
    });
  }

  function renderPrimaryArtifactCard(project, artifact) {
    const ready = artifactIsReady(artifact);
    dom.primaryArtifactHeading.textContent = artifact.download_name || artifactKindLabel(artifact?.artifact_kind);
    dom.primaryArtifactKind.textContent = artifactKindLabel(artifact?.artifact_kind);
    dom.primaryArtifactState.textContent = normalizeText(artifact?.download_status, "pending");
    dom.primaryArtifactBody.textContent = artifactDescription(artifact);
    dom.primaryArtifactPreview.disabled = !ready;
    dom.primaryArtifactDownload.disabled = !ready;
    dom.primaryArtifactPreview.onclick = () => openPanelMode(project, "preview", artifact?.artifact_kind);
    dom.primaryArtifactDownload.onclick = () => {
      void triggerArtifactDownload(project, artifact);
    };
  }

  function renderPreviewPanel(project, artifact) {
    dom.previewHeading.textContent = artifact.download_name || artifactKindLabel(artifact?.artifact_kind);
    dom.previewDownload.disabled = !artifactIsReady(artifact);
    dom.previewDownload.onclick = () => {
      void triggerArtifactDownload(project, artifact);
    };

    if (!artifactIsReady(artifact)) {
      dom.previewFrame.hidden = true;
      dom.previewFrame.srcdoc = "";
      dom.previewStatus.hidden = false;
      dom.previewStatus.textContent = "Preview появится, когда артефакт будет готов к скачиванию.";
      return;
    }

    const previewState = previewStateFor(project, artifact);
    if (previewState.status === "idle") {
      previewState.status = "loading";
      previewState.html = "";
      previewState.error = "";
      void loadArtifactPreview(project, artifact);
    }

    if (previewState.status === "ready" && previewState.html) {
      dom.previewStatus.hidden = true;
      dom.previewFrame.hidden = false;
      if (dom.previewFrame.srcdoc !== previewState.html) {
        dom.previewFrame.srcdoc = previewState.html;
      }
      return;
    }

    dom.previewFrame.hidden = true;
    dom.previewFrame.srcdoc = "";
    dom.previewStatus.hidden = false;
    dom.previewStatus.textContent = previewState.status === "error"
      ? previewState.error
      : "Загружаю preview one-page…";
  }

  function createPanelCard(card) {
    const fragment = dom.panelCardTemplate.content.cloneNode(true);
    const kind = fragment.querySelector(".panel-card__kind");
    const title = fragment.querySelector(".panel-card__title");
    const body = fragment.querySelector(".panel-card__body");
    const actions = fragment.querySelector(".panel-card__actions");

    kind.textContent = "";
    kind.hidden = true;
    title.textContent = card.title || "Раздел brief";
    const bodyText = normalizeText(card.body_text);
    body.textContent = bodyText.length > 520 ? `${bodyText.slice(0, 517).trimEnd()}…` : bodyText;
    actions.innerHTML = "";
    actions.hidden = true;
    return fragment;
  }

  function renderSidePanel(project) {
    const mode = sidePanelMode(project);
    const open = Boolean(project?.sidePanelOpen) && mode !== "hidden";
    const mobileLayout = isMobileLayout();
    if (open && state.panelWidth < 420) {
      updatePanelWidth(PANEL_WIDTH_DEFAULT, { persist: true });
    }
    const fullscreen = open && (mobileLayout || Boolean(project?.sidePanelFullscreen));
    dom.workspaceShell.dataset.panelOpen = open ? "true" : "false";
    dom.workspaceShell.dataset.panelFullscreen = fullscreen ? "true" : "false";
    dom.sidePanel.hidden = !open;
    dom.sidePanel.setAttribute("aria-hidden", open ? "false" : "true");
    dom.sidePanel.dataset.mode = mode;
    if (dom.panelResizer) {
      dom.panelResizer.hidden = !(open && !mobileLayout);
    }
    if (!open) {
      return;
    }

    const artifacts = projectArtifacts(project);
    const primary = primaryArtifact(project, artifacts);
    const secondary = secondaryArtifacts(project, artifacts);
    const promptCard = panelPromptCard(project);
    if (mode === "brief_review") {
      dom.sidePanelEyebrow.textContent = "Проверка brief";
      dom.sidePanelTitle.textContent = "Проверка brief";
      dom.sidePanelSummary.textContent = "Проверь summary brief, внеси правки при необходимости и подтверди версию.";
    } else if (mode === "preview") {
      dom.sidePanelEyebrow.textContent = "Результат";
      dom.sidePanelTitle.textContent = primary?.download_name || "Просмотр one-page";
      dom.sidePanelSummary.textContent = promptCard?.body_text || "Проверь one-page и при необходимости скачай файл.";
    } else if (mode === "downloads") {
      dom.sidePanelEyebrow.textContent = "Результат";
      dom.sidePanelTitle.textContent = "One-page и материалы";
      dom.sidePanelSummary.textContent = promptCard?.body_text || "Сначала проверь one-page, затем при необходимости скачай остальные материалы.";
    } else {
      dom.sidePanelEyebrow.textContent = "Детали проекта";
      dom.sidePanelTitle.textContent = "Brief и файлы";
      dom.sidePanelSummary.textContent = "Здесь появятся brief на review и пользовательские артефакты.";
    }

    const isBriefReview = mode === "brief_review";
    if (dom.briefEditToggle) {
      dom.briefEditToggle.hidden = !isBriefReview;
      dom.briefEditToggle.dataset.state = project?.briefEditOpen ? "active" : "inactive";
      dom.briefEditToggle.setAttribute(
        "aria-label",
        project?.briefEditOpen ? "Скрыть форму правки brief" : "Открыть форму правки brief",
      );
      dom.briefEditToggle.title = project?.briefEditOpen ? "Скрыть правку" : "Исправить brief";
    }
    if (dom.briefEditSection) {
      dom.briefEditSection.hidden = !isBriefReview || !project?.briefEditOpen;
    }
    if (dom.briefEditInput) {
      dom.briefEditInput.value = normalizeText(project?.briefDraft);
      dom.briefEditInput.disabled = state.awaitingResponse;
    }
    if (dom.briefEditApply) {
      dom.briefEditApply.disabled = state.awaitingResponse;
    }
    if (dom.briefConfirm) {
      dom.briefConfirm.disabled = state.awaitingResponse;
    }
    if (dom.sidePanelFullscreen) {
      dom.sidePanelFullscreen.hidden = mobileLayout;
      dom.sidePanelFullscreen.dataset.state = fullscreen ? "active" : "inactive";
      dom.sidePanelFullscreen.setAttribute("aria-pressed", fullscreen ? "true" : "false");
      dom.sidePanelFullscreen.setAttribute("aria-expanded", fullscreen ? "true" : "false");
      dom.sidePanelFullscreen.setAttribute(
        "aria-label",
        fullscreen ? "Свернуть правую панель" : "Развернуть правую панель на весь экран",
      );
      dom.sidePanelFullscreen.title = fullscreen ? "Свернуть правую панель" : "Развернуть на весь экран";
    }

    dom.panelCardList.innerHTML = "";
    if (isBriefReview) {
      detailCards(project).forEach((card) => {
        dom.panelCardList.appendChild(createPanelCard(card));
      });
    }

    dom.primaryArtifactSection.hidden = mode !== "downloads" || !primary;
    if (!dom.primaryArtifactSection.hidden) {
      renderPrimaryArtifactCard(project, primary);
    }

    dom.previewSection.hidden = mode !== "preview" || !primary;
    if (!dom.previewSection.hidden) {
      renderPreviewPanel(project, selectedPreviewArtifact(project, artifacts) || primary);
    } else if (dom.previewFrame) {
      dom.previewFrame.hidden = true;
      dom.previewFrame.srcdoc = "";
      dom.previewStatus.hidden = false;
      dom.previewStatus.textContent = "Выбери артефакт, чтобы открыть preview.";
    }

    dom.artifactSection.hidden = !["downloads", "preview"].includes(mode);
    dom.artifactSectionHeading.textContent = "Остальные артефакты";
    renderSecondaryArtifacts(project, secondary);
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
      button.disabled = state.awaitingResponse;
      button.addEventListener("click", () => handleActionShortcut(action));
      dom.quickActions.appendChild(button);
    });
  }

  function renderComposer(project) {
    dom.composerLeadLabel.textContent = leadLabelFor(project);
    dom.composerMode.textContent = modeTextFor(project);
    if (dom.composerLead) {
      dom.composerLead.hidden = !state.accessToken;
    }
    if (dom.composerThinking) {
      dom.composerThinking.hidden = !state.awaitingResponse;
    }
    dom.composerForm.classList.toggle("is-pending", state.awaitingResponse);
    if (dom.composerHelperExample) {
      dom.composerHelperExample.textContent = "";
      dom.composerHelperExample.hidden = true;
    }
    dom.composerInput.placeholder = placeholderFor(project);
    dom.composerSubmit.textContent = state.awaitingResponse ? "■" : "↗";
    dom.composerSubmit.dataset.mode = state.awaitingResponse ? "stop" : "send";
    dom.composerSubmit.setAttribute("aria-label", state.awaitingResponse ? "Остановить ответ" : "Отправить сообщение");
    const notice = composerNoticeForProject(project);
    dom.composerNotice.textContent = notice.text;
    dom.composerNotice.hidden = !notice.text;
    dom.composerNotice.dataset.tone = notice.tone;
    dom.composerInput.value = normalizeText(project?.draftText);
    resizeComposerInput();
  }

  function renderAll() {
    const project = getActiveProject();
    applySidebarVisibility();
    applySidebarWidth();
    applyPanelWidth();
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
      || normalized === "новый."
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

  function hasBusinessIdeaSignal(text) {
    const normalized = normalizeText(text).toLowerCase();
    if (!normalized) {
      return false;
    }
    return BUSINESS_IDEA_SIGNAL_MARKERS.some((marker) => normalized.includes(marker));
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

  function ensureUniqueProjectTitle(baseTitle, projectId) {
    const normalizedBase = normalizeText(baseTitle);
    if (!normalizedBase) {
      return normalizedBase;
    }
    const taken = new Set(
      state.projects
        .filter((item) => item.id !== projectId)
        .map((item) => normalizeText(item.title).toLowerCase())
        .filter(Boolean),
    );
    if (!taken.has(normalizedBase.toLowerCase())) {
      return normalizedBase;
    }
    for (let suffix = 2; suffix <= 99; suffix += 1) {
      const candidate = `${normalizedBase} ${suffix}`;
      if (!taken.has(candidate.toLowerCase())) {
        return candidate;
      }
    }
    return `${normalizedBase} ${Date.now()}`;
  }

  function dedupeProjectTitles() {
    const used = new Set();
    state.projects.forEach((project) => {
      if (!project || typeof project !== "object") {
        return;
      }
      const base = normalizeText(project.title, DEFAULT_PROJECT_TITLE);
      let candidate = base;
      let suffix = 2;
      while (used.has(candidate.toLowerCase())) {
        candidate = `${base} ${suffix}`;
        suffix += 1;
      }
      project.title = candidate;
      used.add(candidate.toLowerCase());
    });
  }

  function maybeAutonameProject(project, userText, response) {
    if (!project || project.titleEdited) {
      return;
    }
    if (isLowSignalInput(userText)) {
      return;
    }
    const words = normalizeText(userText).split(/\s+/).filter(Boolean);
    const adequateStart = hasBusinessIdeaSignal(userText) || (normalizeText(userText).length >= 48 && words.length >= 6);
    if (!adequateStart) {
      return;
    }
    const uiTitle = normalizeText(response?.ui_projection?.display_project_title || response?.ui_projection?.project_title);
    const rawUiCandidate = !looksLikeSlug(uiTitle) && !looksLikeExcerpt(uiTitle, userText) ? prettifyTitle(uiTitle) : "";
    const uiCandidate = !isGenericProjectTitle(rawUiCandidate) ? rawUiCandidate : "";
    const rawUserCandidate = prettifyTitle(userText);
    const userCandidate = !isGenericProjectTitle(rawUserCandidate) ? rawUserCandidate : "";
    const candidate = ensureUniqueProjectTitle(userCandidate || uiCandidate, project.id);
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
      dedupeProjectTitles();
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
    dedupeProjectTitles();
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
    clearHandoffPollTimer(target);
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
      clearComposerNotice();
      if (options.activate !== false) {
        renderAll();
      }
      persist();
      return reusable;
    }
    const project = createProject();
    state.projects.unshift(project);
    state.activeProjectId = project.id;
    clearComposerNotice();
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
    return !hasUserMessages && !hasDraftText && !hasUploads;
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
    clearComposerNotice();
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

  function detectExplicitBriefFeedbackTarget(text) {
    const lowered = normalizeText(text).toLowerCase();
    if (!lowered) {
      return "";
    }
    const hasExplicitSectionReference =
      /(?:раздел|секци(?:я|ю)|section)/.test(lowered)
      || /(?:input\s*examples?|expected\s*outputs?|target\s*users?|current\s*process|constraints?|success\s*metrics?|business\s*rules?|входн(?:ые)?\s+(?:примеры|данн(?:ые)?)|ожидаем(?:ый|ые)?\s+(?:выход(?:ы)?|результат(?:ы)?)|целев(?:ой|ые)\s+пользовател(?:ь|и)|выгодоприобретател(?:ь|и)|текущ(?:ий|ая)\s+процесс|ограничени(?:е|я)|метрик(?:а|и)\s+успеха?|бизнес[-\s]*правила|правила)\s*[:\-–—]/.test(lowered);
    if (!hasExplicitSectionReference) {
      return "";
    }

    const mapping = [
      {
        target: "input_examples",
        patterns: [
          /(?:input\s*examples?|входн(?:ые)?\s+(?:примеры|данн(?:ые)?))/,
        ],
      },
      {
        target: "expected_outputs",
        patterns: [
          /(?:expected\s*outputs?|ожидаем(?:ый|ые)?\s+(?:выход(?:ы)?|результат(?:ы)?))/,
        ],
      },
      {
        target: "target_users",
        patterns: [
          /(?:target\s*users?|целев(?:ой|ые)\s+пользовател(?:ь|и)|выгодоприобретател(?:ь|и))/,
        ],
      },
      {
        target: "current_process",
        patterns: [
          /(?:current\s*process|workflow|текущ(?:ий|ая)\s+процесс)/,
        ],
      },
      {
        target: "constraints",
        patterns: [
          /(?:constraints?|ограничени(?:е|я)|compliance|policy)/,
        ],
      },
      {
        target: "success_metrics",
        patterns: [
          /(?:success\s*metrics?|kpi|sla|метрик(?:а|и)\s+успеха?)/,
        ],
      },
      {
        target: "business_rules",
        patterns: [
          /(?:business\s*rules?|бизнес[-\s]*правила|\bправила\b)/,
        ],
      },
    ];

    for (const candidate of mapping) {
      if (candidate.patterns.some((pattern) => pattern.test(lowered))) {
        return candidate.target;
      }
    }
    return "";
  }

  function buildTurnPayload(project, action, userText, queuedUploads = []) {
    const last = currentResponse(project) || {};
    const normalizedUserText = normalizeText(userText);
    const shouldSendBriefFeedbackTarget = ["request_brief_correction", "reopen_brief"].includes(action);
    const briefFeedbackTarget = shouldSendBriefFeedbackTarget
      ? detectExplicitBriefFeedbackTarget(normalizedUserText)
      : "";
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
        user_text: normalizedUserText,
        transport_mode: "browser_shell",
        linked_discovery_session_id: last.web_conversation_envelope?.linked_discovery_session_id || "",
        linked_brief_id: last.web_conversation_envelope?.linked_brief_id || "",
      },
      brief_feedback_target: briefFeedbackTarget || undefined,
      discovery_runtime_state: last.discovery_runtime_state || {},
      uploaded_files: queuedUploads.length ? serializeUploadsForTransport(queuedUploads) : undefined,
    };
  }

  function buildRequestSignal(timeoutMs, signal) {
    const timeoutSignal = (typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function")
      ? AbortSignal.timeout(timeoutMs)
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

  async function fetchWithTimeout(url, options = {}, timeoutMs = TURN_TIMEOUT_MS) {
    const requestSignal = buildRequestSignal(timeoutMs, options.signal);
    try {
      return await fetch(url, {
        ...options,
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
  }

  async function postTurn(payload, options = {}) {
    const response = await fetchWithTimeout(
      "/api/turn",
      {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify(payload),
        signal: options.signal,
        cache: "no-store",
      },
      TURN_TIMEOUT_MS,
    );
    if (!response.ok) {
      throw new Error(`adapter_http_${response.status}`);
    }
    return response.json();
  }

  async function fetchSession(sessionId) {
    const response = await fetchWithTimeout(
      `/api/session?session_id=${encodeURIComponent(sessionId)}`,
      { cache: "no-store" },
      TURN_TIMEOUT_MS,
    );
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
    if (/^(ок|ага|угу|да|нет|норм|понял|поняла|хз|лол|test|ping|123+|qwe+)$/i.test(normalized)) {
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
          body_text: "Confirmed brief передан в фабрику. Главный one-page summary уже можно проверить прямо в правой панели.",
          action_hints: ["request_status"],
        },
        {
          card_kind: "factory_result",
          title: "Цифровой актив создан",
          body_text: `Фабрика завершила one-page summary для проекта ${projectKey}. Открой preview, затем при необходимости скачай остальные материалы.`,
          action_hints: ["preview_one_page", "download_artifact"],
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
      { artifact_kind: "one_page_summary", download_name: "one-page-summary.md", download_status: "ready" },
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
        ? "Brief подтверждён. Открой one-page summary в preview, затем скачай нужные материалы или переоткрой brief."
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
        user_visible_status_label: mode === "downloads_ready" ? "One-page готов" : mode === "awaiting_confirmation" ? "Brief ждёт подтверждения" : "Сбор требований продолжается",
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
        preferred_ui_action: mode === "downloads_ready" ? "preview_one_page" : mode === "awaiting_confirmation" ? "confirm_brief" : "submit_turn",
        current_question: nextQuestion,
        current_topic: nextTopic,
        why_asking_now: mode === "discovery" ? discoveryStep.whyAskingNow : "",
        missing_coverage: discoveryStep.missing.map((topic) => topic.id),
        side_panel_mode: mode === "downloads_ready" ? "downloads" : mode === "awaiting_confirmation" ? "brief_review" : "hidden",
        primary_artifact: mode === "downloads_ready" ? "one_page_summary" : "",
        composer_helper_example: helperExampleFor(project),
        project_stage_label: mode === "downloads_ready" ? "One-page готов" : mode === "awaiting_confirmation" ? "Brief на проверке" : "Сбор требований",
        display_project_title: project.title,
        project_title: project.title,
        uploaded_file_count: uploadedFiles.length,
      },
    };
  }

  function clearHandoffPollTimer(project) {
    if (project?.handoffPollTimer) {
      window.clearTimeout(project.handoffPollTimer);
      project.handoffPollTimer = 0;
    }
  }

  function stopHandoffPolling(project) {
    if (!project) {
      return;
    }
    clearHandoffPollTimer(project);
    project.handoffPollAttempt = 0;
    project.lastAutoFollowupSource = "";
  }

  function startHandoffPolling(project, sourceRequestId) {
    if (!project || !sourceRequestId) {
      return;
    }
    clearHandoffPollTimer(project);
    project.lastAutoFollowupSource = sourceRequestId;
    project.handoffPollAttempt = 0;

    const projectId = project.id;
    const tick = () => {
      const active = state.projects.find((item) => item.id === projectId);
      if (!active || active.lastAutoFollowupSource !== sourceRequestId) {
        return;
      }
      const response = currentResponse(active) || {};
      const hasDownloads = Array.isArray(response.download_artifacts) && response.download_artifacts.length > 0;
      const status = currentStatus(active);
      if (hasDownloads || isDownloadsReadyStatus(status)) {
        clearHandoffPollTimer(active);
        active.handoffPollAttempt = 0;
        active.lastAutoFollowupSource = "";
        persist();
        return;
      }
      const attempt = Number.isFinite(active.handoffPollAttempt) ? active.handoffPollAttempt : 0;
      if (attempt >= HANDOFF_POLL_MAX_ATTEMPTS) {
        clearHandoffPollTimer(active);
        active.handoffPollAttempt = 0;
        active.lastAutoFollowupSource = "";
        persist();
        if (state.activeProjectId === active.id) {
          showComposerNotice("Фабрика ещё формирует материалы. Нажми «Обновить», чтобы проверить статус позже.", "info", active.id);
          renderComposer(active);
        }
        return;
      }
      if (state.awaitingResponse) {
        clearHandoffPollTimer(active);
        active.handoffPollTimer = window.setTimeout(tick, HANDOFF_POLL_INTERVAL_MS);
        return;
      }
      active.handoffPollAttempt = attempt + 1;
      persist();
      dispatchTurn("request_status", "", { skipUserMessage: true }).finally(() => {
        const latest = state.projects.find((item) => item.id === projectId);
        if (!latest || latest.lastAutoFollowupSource !== sourceRequestId) {
          return;
        }
        clearHandoffPollTimer(latest);
        latest.handoffPollTimer = window.setTimeout(tick, HANDOFF_POLL_INTERVAL_MS);
      });
    };

    project.handoffPollTimer = window.setTimeout(tick, HANDOFF_POLL_INTERVAL_MS);
    persist();
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
    const supportedAvailableActions = availableActions(project).filter((action) => isComposerAction(action));
    const suggestedComposerAction = [
      preferredAction,
      normalizeText(response.status_snapshot?.next_recommended_action),
      normalizeText(response.next_action),
      ACTION_PRIORITY.find((action) => supportedAvailableActions.includes(action)),
      supportedAvailableActions[0],
      "submit_turn",
    ].find((action) => isComposerAction(action));
    project.currentAction = suggestedComposerAction || "submit_turn";
    const panelMode = sidePanelMode(project);
    if (panelMode === "hidden") {
      project.sidePanelOpen = false;
      project.sidePanelFullscreen = false;
      project.panelModeOverride = "";
      project.previewArtifactKind = "";
    } else if (panelMode !== normalizeText(project.lastPanelMode)) {
      project.sidePanelOpen = true;
    }
    if (!["downloads", "preview"].includes(panelMode)) {
      project.panelModeOverride = "";
      project.previewArtifactKind = "";
    }
    if (panelMode === "hidden") {
      project.sidePanelFullscreen = false;
    }
    if (panelMode === "brief_review" && typeof project.briefEditOpen !== "boolean") {
      project.briefEditOpen = false;
    }
    if (panelMode !== "brief_review") {
      project.briefEditOpen = false;
    }
    project.lastPanelMode = panelMode;
    project.lastResumeFingerprint = normalizeText(response.resume_context?.resume_fingerprint, project.lastResumeFingerprint);
    const sourceAction = normalizeText(response.web_conversation_envelope?.ui_action);
    const sourceRequestId = normalizeText(response.web_conversation_envelope?.request_id);
    const sourceUserText = normalizeText(response.web_conversation_envelope?.user_text);
    const submitTurnConfirmation = sourceAction === "submit_turn" && isLikelyBriefConfirmationText(sourceUserText);
    const hasDownloads = Array.isArray(response.download_artifacts) && response.download_artifacts.length > 0;
    const downloadsReady = hasDownloads || isDownloadsReadyStatus(currentStatus(project));
    if (sourceAction === "confirm_brief" || submitTurnConfirmation) {
      project.sidePanelOpen = true;
      project.sidePanelFullscreen = false;
      if (downloadsReady) {
        const preferredPreview = primaryArtifact(project)?.artifact_kind || "one_page_summary";
        project.panelModeOverride = "preview";
        project.previewArtifactKind = normalizeArtifactKind(preferredPreview);
      } else {
        project.panelModeOverride = "downloads";
        project.previewArtifactKind = "";
      }
    } else if (downloadsReady && syncReason === "handoff_poll") {
      const preferredPreview = primaryArtifact(project)?.artifact_kind || "one_page_summary";
      project.sidePanelOpen = true;
      project.sidePanelFullscreen = false;
      project.panelModeOverride = "preview";
      project.previewArtifactKind = normalizeArtifactKind(preferredPreview);
    }

    persist();
    renderAll();

    if (hasDownloads || isDownloadsReadyStatus(currentStatus(project))) {
      stopHandoffPolling(project);
      persist();
      return;
    }
    if (
      connectionMode === "live"
      && sourceAction === "confirm_brief"
      && response.next_action === "start_concept_pack_handoff"
      && sourceRequestId
      && project.lastAutoFollowupSource !== sourceRequestId
    ) {
      startHandoffPolling(project, sourceRequestId);
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
    if (state.awaitingResponse) {
      return;
    }
    const queuedUploads = uniqueUploads(options.queuedUploads || []);
    const normalizedUserText = normalizeText(userText);
    const isBackgroundStatusPoll = action === "request_status" && options.skipUserMessage && !normalizedUserText && queuedUploads.length === 0;
    if (!isBackgroundStatusPoll) {
      stopHandoffPolling(project);
    }
    const payload = buildTurnPayload(project, action, userText, queuedUploads);
    const requestId = normalizeText(payload?.web_conversation_envelope?.request_id);
    const abortController = new AbortController();
    let abortedByUser = false;
    let timedOut = false;
    let backendError = null;
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
      renderTimeline(project, { forceBottom: true });
    }

    clearComposerNotice();
    state.forceScrollToBottom = true;
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
    renderAgentStatus();
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
        backendError = error;
      }
    } finally {
      if (!abortedByUser && !timedOut) {
        const elapsed = Date.now() - pendingStartedAt;
        const remaining = MIN_PENDING_VISUAL_MS - elapsed;
        if (remaining > 0) {
          await new Promise((resolve) => window.setTimeout(resolve, remaining));
        }
      }
      const restoreInput = abortedByUser || timedOut || Boolean(backendError);
      if (restoreInput) {
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
            : abortedByUser
              ? "Ответ остановлен. Можно отредактировать сообщение и отправить снова."
              : `Не удалось получить ответ от backend: ${normalizeText(backendError?.message, "unknown_error")}.`,
          timedOut ? "warning" : abortedByUser ? "info" : "error",
          project.id,
        );
      } else if (queuedUploads.length) {
        project.pendingUploads = project.pendingUploads.filter(
          (item) => !queuedUploads.some((queued) => queued.upload_id === item.upload_id),
        );
      }
      if (!restoreInput) {
        project.draftText = "";
      }
      state.awaitingResponse = false;
      state.activeAbortController = null;
      state.activeRequest = null;
      renderAll();
      if (state.forceScrollToBottom) {
        scheduleScrollChatToBottom();
      }
      state.forceScrollToBottom = false;
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
    if (state.awaitingResponse) {
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

    if (action === "preview_one_page" || action === "test_asset") {
      if (project) {
        openPanelMode(project, "preview", primaryArtifact(project)?.artifact_kind);
      }
      return;
    }

    if (action === "download_artifact") {
      if (project) {
        openPanelMode(project, "downloads");
      }
      return;
    }

    if (action === "request_brief_review") {
      if (project && hasPanelContent(project)) {
        project.sidePanelOpen = true;
        project.briefEditOpen = false;
        project.currentAction = action;
        persist();
        renderAll();
        return;
      }
      setProjectAction(project, action);
      dispatchTurn(action, "", { skipUserMessage: true });
      return;
    }

    if (action === "request_brief_correction") {
      if (project) {
        project.sidePanelOpen = true;
        project.briefEditOpen = true;
        persist();
        renderAll();
      }
      setProjectAction(project, action);
      window.setTimeout(() => {
        dom.briefEditInput?.focus();
      }, 0);
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
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            updateSidebarWidth(SIDEBAR_WIDTH_DEFAULT, { persist: true });
          }
          return;
        }
        event.preventDefault();
        const delta = event.key === "ArrowRight" ? 24 : -24;
        updateSidebarWidth(state.sidebarWidth + delta, { persist: true });
      });

      dom.sidebarResizer.addEventListener("dblclick", (event) => {
        if (event.button !== 0 || isMobileLayout()) {
          return;
        }
        event.preventDefault();
        updateSidebarWidth(SIDEBAR_WIDTH_DEFAULT, { persist: true });
      });

      window.addEventListener("resize", () => {
        let persisted = false;
        const clamped = clampSidebarWidth(state.sidebarWidth);
        if (clamped !== state.sidebarWidth) {
          updateSidebarWidth(clamped, { persist: true });
          persisted = true;
        } else {
          applySidebarWidth();
        }
        const panelClamped = clampPanelWidth(state.panelWidth);
        if (panelClamped !== state.panelWidth) {
          updatePanelWidth(panelClamped, { persist: true });
          persisted = true;
        } else {
          applyPanelWidth();
        }
        if (!persisted) {
          persist();
        }
        renderAll();
      });
    }

    if (dom.panelResizer) {
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
        const delta = resizeSession.startX - event.clientX;
        updatePanelWidth(resizeSession.startWidth + delta);
      };

      const handleResizeEnd = () => {
        finishResize(true);
      };

      dom.panelResizer.addEventListener("pointerdown", (event) => {
        if (event.button !== 0 || isMobileLayout()) {
          return;
        }
        event.preventDefault();
        resizeSession = {
          startX: event.clientX,
          startWidth: state.panelWidth,
        };
        dom.root.classList.add("is-resizing");
        window.addEventListener("pointermove", handleResizeMove);
        window.addEventListener("pointerup", handleResizeEnd);
        window.addEventListener("pointercancel", handleResizeEnd);
      });

      dom.panelResizer.addEventListener("keydown", (event) => {
        if (isMobileLayout()) {
          return;
        }
        if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            updatePanelWidth(PANEL_WIDTH_DEFAULT, { persist: true });
          }
          return;
        }
        event.preventDefault();
        const delta = event.key === "ArrowRight" ? 24 : -24;
        updatePanelWidth(state.panelWidth + delta, { persist: true });
      });

      dom.panelResizer.addEventListener("dblclick", (event) => {
        if (event.button !== 0 || isMobileLayout()) {
          return;
        }
        event.preventDefault();
        updatePanelWidth(PANEL_WIDTH_DEFAULT, { persist: true });
      });
    }

    dom.newProject.addEventListener("click", () => {
      createNewProject({ activate: true });
      focusComposerSoon();
    });

    if (dom.sidebarToggle) {
      dom.sidebarToggle.addEventListener("click", () => {
        state.sidebarVisible = !state.sidebarVisible;
        closeProjectActionsMenu();
        persist();
        renderAll();
      });
    }

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
      if (!project.sidePanelOpen) {
        project.sidePanelFullscreen = false;
      }
      persist();
      renderAll();
    });

    if (dom.sidePanelFullscreen) {
      dom.sidePanelFullscreen.addEventListener("click", () => {
        const project = getActiveProject();
        if (!project || !project.sidePanelOpen || !hasPanelContent(project)) {
          return;
        }
        project.sidePanelFullscreen = !project.sidePanelFullscreen;
        persist();
        renderAll();
      });
    }

    dom.sidePanelClose.addEventListener("click", () => {
      const project = getActiveProject();
      if (!project) {
        return;
      }
      project.sidePanelOpen = false;
      project.sidePanelFullscreen = false;
      persist();
      renderAll();
    });

    if (dom.briefEditToggle) {
      dom.briefEditToggle.addEventListener("click", () => {
        const project = getActiveProject();
        if (!project) {
          return;
        }
        project.briefEditOpen = !project.briefEditOpen;
        persist();
        renderAll();
      });
    }

    if (dom.briefEditInput) {
      dom.briefEditInput.addEventListener("input", () => {
        const project = getActiveProject();
        if (!project) {
          return;
        }
        project.briefDraft = dom.briefEditInput.value;
        persist();
      });
    }

    if (dom.briefEditApply) {
      dom.briefEditApply.addEventListener("click", () => {
        const project = getActiveProject();
        if (!project || state.awaitingResponse) {
          return;
        }
        const correctionText = normalizeText(project.briefDraft || dom.briefEditInput?.value);
        if (!correctionText) {
          showComposerNotice("Опиши правку brief, затем нажми «Применить правку».", "warning", project.id);
          renderComposer(project);
          dom.briefEditInput?.focus();
          return;
        }
        clearComposerNotice();
        project.briefDraft = "";
        if (dom.briefEditInput) {
          dom.briefEditInput.value = "";
        }
        void dispatchTurn("request_brief_correction", correctionText, { skipUserMessage: true });
      });
    }

    if (dom.briefConfirm) {
      dom.briefConfirm.addEventListener("click", () => {
        if (state.awaitingResponse) {
          return;
        }
        clearComposerNotice();
        void dispatchTurn("confirm_brief", "", { skipUserMessage: true });
      });
    }

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
      const visibleNotice = composerNoticeForProject(project);
      if (visibleNotice.text) {
        clearComposerNotice();
        renderComposer(project);
      }
      resizeComposerInput();
      persist();
    });

    dom.composerInput.addEventListener("keydown", (event) => {
      if (state.awaitingResponse || event.key !== "Enter" || event.isComposing) {
        return;
      }
      if (event.shiftKey) {
        // Shift+Enter оставляет нативный перенос строки.
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
      const effectiveAction = resolveComposerAction(project, text);
      const allowWithoutText = ["request_status", "request_brief_review", "confirm_brief"].includes(effectiveAction);
      if (!text && !queuedUploads.length && !allowWithoutText) {
        dom.composerInput.focus();
        return;
      }
      clearComposerNotice();
      project.draftText = "";
      dispatchTurn(effectiveAction, text, { queuedUploads });
      dom.composerInput.value = "";
      resizeComposerInput();
      focusComposerSoon();
    });

    if (dom.attachmentTrigger) {
      dom.attachmentTrigger.addEventListener("click", () => {
        if (!state.accessToken || state.awaitingResponse) {
          return;
        }
        if (typeof dom.attachmentInput.showPicker === "function") {
          try {
            dom.attachmentInput.showPicker();
            return;
          } catch (_error) {
            // Some Chromium builds expose showPicker but can reject it at runtime.
            // Fall through to the standard click path.
          }
        }
        dom.attachmentInput.click();
      });
    }

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
