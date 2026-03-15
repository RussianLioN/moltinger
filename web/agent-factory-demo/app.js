(() => {
  const STORAGE_KEY = "agent-factory-web-demo-shell.v3";
  const ACCESS_TOKEN_KEY = "agent-factory-web-demo-access-token.v1";
  const DEFAULT_ACCESS_TOKEN = "demo-access-token";
  const MAX_LOCAL_UPLOAD_FILES = 4;
  const MAX_LOCAL_UPLOAD_BYTES = 512 * 1024;
  const DEFAULT_PROJECT_TITLE = "Новый проект";
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
  const dom = {
    root: document.querySelector('[data-role="app-root"]'),
    workspaceShell: document.querySelector('[data-role="workspace-shell"]'),
    gateNote: document.querySelector('[data-role="gate-note"]'),
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
    composerInput: document.querySelector('[data-role="composer-input"]'),
    composerSubmit: document.querySelector('[data-role="composer-submit"]'),
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
  };

  const state = {
    accessToken: "",
    connectionMode: "booting",
    requestCounter: 0,
    activeProjectId: "",
    projects: [],
    gateNote: "Токен запрашивается только один раз для этой браузерной сессии.",
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
      timeline: Array.isArray(record.timeline) ? record.timeline : [],
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
      state.projects = Array.isArray(saved.projects) && saved.projects.length
        ? saved.projects.map((project) => normalizeProjectRecord(project))
        : [];
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
    dom.composerSubmit.disabled = isBusy;
    dom.refreshSession.disabled = isBusy;
    dom.accessSubmit.disabled = isBusy;
    dom.projectMenu.disabled = isBusy;
    dom.newProject.disabled = isBusy;
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
    const question = currentQuestion(project);
    const action = project?.currentAction || "start_project";
    if (!hasConversationActivity(project)) {
      return "Первый вопрос";
    }
    if (question && ["submit_turn", "request_brief_correction", "reopen_brief"].includes(action)) {
      return "Текущий вопрос";
    }
    if (question && action === "confirm_brief") {
      return "Что проверить";
    }
    return "Следующий шаг";
  }

  function modeTextFor(project) {
    if (!state.accessToken) {
      return "Открыть demo";
    }
    if (!hasConversationActivity(project)) {
      return "Что нужно автоматизировать?";
    }
    const question = currentQuestion(project);
    const action = project?.currentAction || "start_project";
    if (question && ["submit_turn", "request_brief_correction", "reopen_brief", "confirm_brief"].includes(action)) {
      return question;
    }
    return ACTION_LABELS[action] || action;
  }

  function placeholderFor(project) {
    if (!state.accessToken) {
      return "Введи access token";
    }
    const action = project?.currentAction || "start_project";
    const question = currentQuestion(project);
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
    if (topic === "input_examples" || /пример|входн/i.test(question)) {
      return "Приведи 1-2 примера или прикрепи файл с примерами.";
    }
    if (topic === "expected_outputs" || /результат|выход/i.test(question)) {
      return "Опиши ожидаемый результат на выходе.";
    }
    if (topic === "current_workflow" || /как этот процесс/i.test(question)) {
      return "Опиши, как процесс работает сейчас и где теряется время.";
    }
    if (question) {
      return shorten(`Ответь на вопрос: ${question}`, 110);
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
    const question = currentQuestion(project);
    if (!hasConversationActivity(project)) {
      return "Опиши задачу простыми словами. После первого содержательного ответа проект сам получит рабочее имя.";
    }
    if (status === "awaiting_confirmation") {
      return "Brief собран. Открой правую панель, чтобы проверить summary, внести правки или подтвердить версию.";
    }
    if (status === "playground_ready" || status === "confirmed") {
      return "Материалы готовы. Открой правую панель, чтобы скачать артефакты или вернуть проект на доработку.";
    }
    if (question) {
      return shorten(`Сейчас агент уточняет контекст проекта: ${question}`, 136);
    }
    return "Можно продолжать диалог и при необходимости прикладывать файлы с примерами.";
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
    dom.gateNote.textContent = state.gateNote;
  }

  function renderShellStage(project) {
    dom.root.dataset.access = state.accessToken ? "granted" : "gated";
    dom.root.dataset.stage = state.accessToken
      ? (hasConversationActivity(project) ? "active" : "empty")
      : "gated";
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
    menu.setAttribute("aria-label", `Переименовать проект ${project.title}`);
    menu.addEventListener("click", (event) => {
      event.stopPropagation();
      promptRenameProject(project.id);
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
    const sessionUploads = uniqueUploads(activeSessionUploads(project));
    const items = [
      ...pending.map((item) => ({ ...item, scope: "pending" })),
      ...sessionUploads
        .filter((item) => !pending.some((pendingItem) => pendingItem.upload_id === item.upload_id))
        .map((item) => ({ ...item, scope: "session" })),
    ];
    dom.attachmentList.innerHTML = "";
    dom.attachmentList.hidden = items.length === 0;
    items.forEach((upload) => {
      const pill = document.createElement("div");
      pill.className = `attachment-pill${upload.scope === "session" ? " attachment-pill--session" : ""}`;
      const label = document.createElement("span");
      label.className = "attachment-pill__label";
      label.textContent = upload.name || "Файл";
      const meta = document.createElement("span");
      meta.className = "attachment-pill__meta";
      meta.textContent = summarizeUploadMeta(upload) || (upload.scope === "pending" ? "к отправке" : "в сессии");
      pill.append(label, meta);
      if (upload.scope === "pending") {
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
      }
      dom.attachmentList.appendChild(pill);
    });
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
      agent: "Фабричный агент",
      user: "Пользователь",
      system: "Система",
      artifact: "Фабрика",
    }[message.role || "agent"];
    kind.textContent = "";
    kind.hidden = true;
    const titleText = normalizeText(message.title);
    title.textContent = titleText;
    title.hidden = !titleText;
    meta.hidden = true;
    body.textContent = message.body || "";
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
    return (response?.reply_cards || [])
      .filter((card) => ["discovery_question", "clarification_prompt"].includes(card.card_kind))
      .map((card) => ({
        role: "agent",
        kind: card.card_kind || "reply_card",
        title: "",
        body: card.body_text || "",
        actions: [],
      }));
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
    dom.composerHelperExample.textContent = helperExampleFor(project);
    dom.composerInput.placeholder = placeholderFor(project);
    dom.composerSubmit.textContent = submitLabelFor(project);
    dom.composerInput.value = normalizeText(project?.draftText);
  }

  function renderAll() {
    const project = getActiveProject();
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

  function prettifyTitle(text) {
    const normalized = normalizeText(text)
      .replace(/\s+/g, " ")
      .replace(/^[\-\s]+|[\-\s]+$/g, "");
    if (!normalized) {
      return "";
    }
    const firstSentence = normalized.split(/[.!?\n]/)[0].trim();
    const cleaned = firstSentence
      .replace(/^нужен агент[,]?\s*/i, "")
      .replace(/^который\s+/i, "")
      .replace(/^хочу автоматизировать\s*/i, "")
      .replace(/^нужно автоматизировать\s*/i, "")
      .replace(/^нужна автоматизация\s*/i, "");
    const compact = shorten(cleaned || firstSentence, 58);
    return compact.charAt(0).toUpperCase() + compact.slice(1);
  }

  function maybeAutonameProject(project, userText, response) {
    if (!project || project.titleEdited) {
      return;
    }
    const uiTitle = normalizeText(response?.ui_projection?.display_project_title || response?.ui_projection?.project_title);
    const candidate = !looksLikeSlug(uiTitle) ? prettifyTitle(uiTitle) : prettifyTitle(userText);
    if (!candidate) {
      return;
    }
    if (project.title === DEFAULT_PROJECT_TITLE || project.title.startsWith(`${DEFAULT_PROJECT_TITLE} •`)) {
      project.title = candidate;
    }
  }

  function promptRenameProject(projectId) {
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

  function createNewProject(options = {}) {
    saveComposerDraft();
    const project = createProject();
    state.projects.unshift(project);
    state.activeProjectId = project.id;
    if (options.activate !== false) {
      renderAll();
    }
    persist();
    return project;
  }

  function switchProject(projectId) {
    saveComposerDraft();
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
    window.setTimeout(() => {
      dom.composerInput.focus();
    }, 0);
  }

  function unlockAccess() {
    const provided = normalizeText(dom.accessTokenInput.value, DEFAULT_ACCESS_TOKEN);
    state.accessToken = provided;
    state.gateNote = "Доступ открыт. Теперь можно начинать диалог и переключаться между проектами.";
    if (!state.projects.length) {
      state.projects = [createProject()];
    }
    if (!state.activeProjectId) {
      state.activeProjectId = state.projects[0].id;
    }
    persist();
    renderAll();
    window.setTimeout(() => {
      dom.composerInput.focus();
    }, 0);
  }

  function relockAccess(reason) {
    state.accessToken = "";
    state.gateNote = normalizeText(reason, "Нужен access token для controlled demo surface.");
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

  async function postTurn(payload) {
    const response = await fetch("/api/turn", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify(payload),
    });
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

  function mockDiscoveryPrompt(stage) {
    const prompts = {
      discovery_problem: "Какую конкретную бизнес-проблему должен решить будущий агент?",
      discovery_inputs: "Какие данные приходят на вход и в каком виде их получают сотрудники?",
      discovery_outputs: "Какой результат должен получить пользователь на выходе?",
      awaiting_confirmation: "Я собрал черновой brief. Проверь summary, попроси правки или явно подтверди текущую версию.",
      downloads_ready: "Brief подтверждён. Shell показывает подготовку concept pack и зону загрузок.",
    };
    return prompts[stage] || prompts.discovery_problem;
  }

  function mockReplyCards(stage, projectKey) {
    if (stage === "awaiting_confirmation") {
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
    if (stage === "downloads_ready") {
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
    return [
      {
        card_kind: "status_update",
        title: "Статус проекта",
        body_text: `Сессия активна. Текущий этап: ${stage}.`,
        action_hints: ["request_status"],
      },
      {
        card_kind: "discovery_question",
        title: "Следующий вопрос",
        body_text: mockDiscoveryPrompt(stage),
        action_hints: ["submit_turn"],
      },
    ];
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

    if (action === "confirm_brief") {
      project.mockStage = "downloads_ready";
    } else if (action === "request_brief_correction" || action === "reopen_brief") {
      project.mockStage = "awaiting_confirmation";
    } else if (action === "request_status" && project.lastResponse) {
      project.mockStage = project.mockStage || "discovery_problem";
    } else if (project.mockStage === "gate_pending") {
      project.mockStage = "discovery_problem";
    } else if (project.mockStage === "discovery_problem") {
      project.mockStage = "discovery_inputs";
    } else if (project.mockStage === "discovery_inputs") {
      project.mockStage = "discovery_outputs";
    } else if (project.mockStage === "discovery_outputs") {
      project.mockStage = "awaiting_confirmation";
    }

    const stage = project.mockStage;
    const brief = stage === "awaiting_confirmation" || stage === "downloads_ready"
      ? {
          brief_id: "brief-web-demo-001",
          version: stage === "downloads_ready" ? "v3" : "v2",
        }
      : {};

    return {
      status: stage === "downloads_ready" ? "confirmed" : stage === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
      next_action: stage === "downloads_ready" ? "start_concept_pack_handoff" : stage === "awaiting_confirmation" ? "await_for_confirmation" : "continue_discovery",
      next_topic: stage === "discovery_problem" ? "problem" : stage === "discovery_inputs" ? "input_examples" : "output_expectations",
      next_question: mockDiscoveryPrompt(stage),
      access_gate: {
        granted: true,
        reason: "",
      },
      web_demo_session: {
        web_demo_session_id: project.sessionId,
        session_cookie_id: `cookie-${project.sessionId}`,
        status: stage === "downloads_ready" ? "download_ready" : stage === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
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
        user_visible_status: stage === "downloads_ready" ? "playground_ready" : stage === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
        user_visible_status_label: stage === "downloads_ready" ? "Артефакты готовы" : stage === "awaiting_confirmation" ? "Brief ждёт подтверждения" : "Сбор требований продолжается",
        next_recommended_action: stage === "downloads_ready" ? "start_concept_pack_handoff" : stage === "awaiting_confirmation" ? "confirm_brief" : "submit_turn",
        next_recommended_action_label: stage === "downloads_ready" ? "Передать brief в фабрику" : stage === "awaiting_confirmation" ? "Проверить и подтвердить brief" : "Ответить на следующий вопрос",
        brief_version: brief.version || "",
        download_readiness: stage === "downloads_ready" ? "ready" : "pending",
        uploaded_file_count: uploadedFiles.length,
      },
      reply_cards: mockReplyCards(stage, projectKey),
      download_artifacts: mockArtifacts(stage),
      uploaded_files: uploadedFiles,
      discovery_runtime_state: {
        status: stage === "downloads_ready" ? "confirmed" : stage === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
        next_question: mockDiscoveryPrompt(stage),
      },
      ui_projection: {
        preferred_ui_action: stage === "downloads_ready" ? "request_status" : stage === "awaiting_confirmation" ? "confirm_brief" : "submit_turn",
        current_question: mockDiscoveryPrompt(stage),
        current_topic: stage === "discovery_problem" ? "problem" : stage === "discovery_inputs" ? "input_examples" : stage === "discovery_outputs" ? "expected_outputs" : "",
        side_panel_mode: stage === "downloads_ready" ? "downloads" : stage === "awaiting_confirmation" ? "brief_review" : "hidden",
        composer_helper_example: helperExampleFor(project),
        project_stage_label: stage === "downloads_ready" ? "Артефакты готовы" : stage === "awaiting_confirmation" ? "Brief на проверке" : "Сбор требований",
        display_project_title: project.title,
        project_title: project.title,
        uploaded_file_count: uploadedFiles.length,
      },
    };
  }

  function applyResponse(project, response, connectionMode, options = {}) {
    const appendReplyMessages = options.appendReplyMessages !== false;
    const syncReason = normalizeText(options.syncReason);

    if (response?.access_gate && response.access_gate.granted === false) {
      project.lastResponse = response;
      project.updatedAt = nowIso();
      persist();
      relockAccess(response.access_gate.reason);
      return;
    }

    state.connectionMode = connectionMode;
    project.lastResponse = response;
    project.sessionId = normalizeText(response.web_demo_session?.web_demo_session_id, project.sessionId);
    project.updatedAt = nowIso();

    const replyMessages = appendReplyMessages ? timelineMessagesFromResponse(response) : [];
    if (replyMessages.length) {
      project.timeline.push(...replyMessages);
    }

    maybeAutonameProject(project, project.timeline.find((message) => message.role === "user")?.body || "", response);

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
    const project = getActiveProject();
    if (!project) {
      return;
    }
    const queuedUploads = uniqueUploads(options.queuedUploads || []);
    const normalizedUserText = normalizeText(userText);
    if (!options.skipUserMessage && (normalizedUserText || queuedUploads.length)) {
      project.timeline.push({
        role: "user",
        kind: action,
        title: "",
        body: normalizedUserText || "Добавил файлы к ответу.",
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

    const payload = buildTurnPayload(project, action, userText, queuedUploads);
    setBusy(true);
    try {
      const response = await postTurn(payload);
      applyResponse(project, response, "live");
    } catch (_error) {
      applyResponse(project, mockAdapterTurn(project, payload), "mock");
    } finally {
      if (queuedUploads.length) {
        project.pendingUploads = project.pendingUploads.filter(
          (item) => !queuedUploads.some((queued) => queued.upload_id === item.upload_id),
        );
      }
      project.draftText = "";
      renderAll();
      setBusy(false);
    }
  }

  async function refreshActiveProject(options = {}) {
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
    const project = getActiveProject();
    if (!state.accessToken || action === "submit_access_token") {
      dom.accessTokenInput.focus();
      return;
    }

    if (action === "start_project") {
      if (!project || hasConversationActivity(project)) {
        createNewProject({ activate: true });
        persist();
        renderAll();
      }
      const active = getActiveProject();
      setProjectAction(active, "start_project");
      dom.composerInput.focus();
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
    dom.composerInput.focus();
  }

  function bindEvents() {
    dom.newProject.addEventListener("click", () => {
      createNewProject({ activate: true });
      persist();
      renderAll();
      dom.composerInput.focus();
    });

    dom.projectMenu.addEventListener("click", () => {
      const project = getActiveProject();
      if (project) {
        promptRenameProject(project.id);
      }
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
      dom.composerInput.focus();
    });

    dom.composerInput.addEventListener("input", () => {
      const project = getActiveProject();
      if (!project) {
        return;
      }
      project.draftText = dom.composerInput.value;
      persist();
    });

    dom.composerForm.addEventListener("submit", (event) => {
      event.preventDefault();
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
      project.draftText = "";
      dispatchTurn(project.currentAction, text, { queuedUploads });
      dom.composerInput.value = "";
      if (project.currentAction !== "submit_turn") {
        setProjectAction(project, "submit_turn");
      }
    });

    dom.attachmentInput.addEventListener("change", async () => {
      const project = getActiveProject();
      const selectedFiles = Array.from(dom.attachmentInput.files || []);
      dom.attachmentInput.value = "";
      if (!project || !selectedFiles.length) {
        return;
      }

      const remainingSlots = Math.max(0, MAX_LOCAL_UPLOAD_FILES - project.pendingUploads.length);
      const acceptedFiles = selectedFiles.slice(0, remainingSlots);
      const skippedCount = Math.max(0, selectedFiles.length - acceptedFiles.length);
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
        dom.composerInput.focus();
      }
    });

    dom.accessSubmit.addEventListener("click", () => {
      unlockAccess();
    });

    dom.accessTokenInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        unlockAccess();
      }
    });

    dom.refreshSession.addEventListener("click", () => {
      refreshActiveProject({ syncReason: "manual_refresh" });
    });
  }

  function init() {
    hydrate();
    bindEvents();
    dom.accessTokenInput.value = state.accessToken;
    renderAll();
    dom.root.dataset.mode = "ready";
    void restoreSessionOnLoad();
  }

  init();
})();
