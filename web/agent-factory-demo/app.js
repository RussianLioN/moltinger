(() => {
  const STORAGE_KEY = "agent-factory-web-demo-shell.v2";
  const DEFAULT_ACCESS_TOKEN = "demo-access-token";
  const MAX_LOCAL_UPLOAD_FILES = 4;
  const MAX_LOCAL_UPLOAD_BYTES = 512 * 1024;
  const ACTION_LABELS = {
    start_project: "Новый проект",
    submit_turn: "Ответить",
    request_status: "Статус",
    request_brief_review: "Показать brief",
    request_brief_correction: "Исправить brief",
    confirm_brief: "Подтвердить brief",
    reopen_brief: "Переоткрыть brief",
    download_artifact: "Скачать артефакт",
    submit_access_token: "Открыть demo",
  };
  const ACTION_PRIORITY = [
    "submit_turn",
    "confirm_brief",
    "request_brief_correction",
    "request_status",
    "reopen_brief",
    "download_artifact",
    "start_project",
  ];

  const dom = {
    root: document.querySelector('[data-role="app-root"]'),
    connectionState: document.querySelector('[data-role="connection-state"]'),
    sessionBadge: document.querySelector('[data-role="session-badge"]'),
    projectTitle: document.querySelector('[data-role="project-title"]'),
    accessBanner: document.querySelector('[data-role="access-banner"]'),
    accessTokenInput: document.querySelector('[data-role="access-token-input"]'),
    accessSubmit: document.querySelector('[data-role="access-submit"]'),
    chatLog: document.querySelector('[data-role="chat-log"]'),
    chatEmpty: document.querySelector('[data-role="chat-empty"]'),
    quickActions: document.querySelector('[data-role="quick-actions"]'),
    composerForm: document.querySelector('[data-role="composer-form"]'),
    composerMode: document.querySelector('[data-role="composer-mode"]'),
    composerInput: document.querySelector('[data-role="composer-input"]'),
    composerSubmit: document.querySelector('[data-role="composer-submit"]'),
    attachmentInput: document.querySelector('[data-role="attachment-input"]'),
    attachmentList: document.querySelector('[data-role="attachment-list"]'),
    refreshSession: document.querySelector('[data-role="refresh-session"]'),
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
  };

  const state = {
    currentAction: "start_project",
    connectionMode: "booting",
    accessToken: "",
    timeline: [],
    lastResponse: null,
    sessionId: "",
    requestCounter: 0,
    mockStage: "gate_pending",
    lastAutoFollowupSource: "",
    lastResumeFingerprint: "",
    pendingUploads: [],
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

  function activeSessionUploads() {
    return Array.isArray(state.lastResponse?.uploaded_files) ? state.lastResponse.uploaded_files : [];
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

  function hydrate() {
    const saved = safeJsonParse(window.localStorage.getItem(STORAGE_KEY) || "null", null);
    if (!saved || typeof saved !== "object") {
      state.timeline = [buildWelcomeMessage()];
      return;
    }

    state.currentAction = normalizeText(saved.currentAction, "start_project");
    state.connectionMode = normalizeText(saved.connectionMode, "booting");
    state.accessToken = normalizeText(saved.accessToken);
    state.timeline = Array.isArray(saved.timeline) && saved.timeline.length ? saved.timeline : [buildWelcomeMessage()];
    state.lastResponse = saved.lastResponse && typeof saved.lastResponse === "object" ? saved.lastResponse : null;
    state.sessionId = normalizeText(saved.sessionId);
    state.requestCounter = Number.isFinite(saved.requestCounter) ? saved.requestCounter : 0;
    state.mockStage = normalizeText(saved.mockStage, "gate_pending");
    state.lastAutoFollowupSource = normalizeText(saved.lastAutoFollowupSource);
    state.lastResumeFingerprint = normalizeText(saved.lastResumeFingerprint);
  }

  function persist() {
    window.localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        currentAction: state.currentAction,
        connectionMode: state.connectionMode,
        accessToken: state.accessToken,
        timeline: state.timeline,
        lastResponse: state.lastResponse,
        sessionId: state.sessionId,
        requestCounter: state.requestCounter,
        mockStage: state.mockStage,
        lastAutoFollowupSource: state.lastAutoFollowupSource,
        lastResumeFingerprint: state.lastResumeFingerprint,
      }),
    );
  }

  function setBusy(isBusy) {
    dom.root.dataset.mode = isBusy ? "busy" : "ready";
    dom.composerSubmit.disabled = isBusy;
    dom.refreshSession.disabled = isBusy;
    dom.accessSubmit.disabled = isBusy;
  }

  function buildWelcomeMessage() {
    return {
      role: "agent",
      kind: "initial_shell",
      title: "Готов к первому проекту",
      body:
        "Опиши идею автоматизации как бизнес-пользователь. Shell отрисует ответные карточки, статус и зону артефактов даже до появления полного live backend.",
      actions: ["start_project", "request_status"],
    };
  }

  function buildSystemMessage(title, body, kind = "system_update") {
    return {
      role: "system",
      kind,
      title,
      body,
      actions: ["request_status"],
    };
  }

  function nextRequestId(action) {
    state.requestCounter += 1;
    return `browser-${slugify(action, "turn")}-${String(state.requestCounter).padStart(4, "0")}`;
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

  function setCurrentAction(action) {
    state.currentAction = action;
    dom.composerMode.textContent = ACTION_LABELS[action] || action;
    [...dom.quickActions.querySelectorAll("[data-ui-action]")].forEach((button) => {
      button.classList.toggle("is-active", button.dataset.uiAction === action);
    });
    persist();
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

  function renderSessionBadge() {
    const sessionId = state.lastResponse?.web_demo_session?.web_demo_session_id || state.sessionId;
    dom.sessionBadge.textContent = sessionId ? `Сессия ${sessionId}` : "Сессия ещё не открыта";
  }

  function renderStatus() {
    const response = state.lastResponse || {};
    const statusSnapshot = response.status_snapshot || {};
    const session = response.web_demo_session || {};
    const pointer = response.browser_project_pointer || {};
    const accessGate = response.access_gate || {};
    const resumeContext = response.resume_context || {};

    dom.projectTitle.textContent = pointer.project_key || "Новый проект фабрики";
    dom.statusUserVisible.textContent =
      statusSnapshot.user_visible_status_label ||
      statusSnapshot.user_visible_status ||
      response.status ||
      "gate_pending";
    dom.statusNextAction.textContent =
      statusSnapshot.next_recommended_action_label ||
      ACTION_LABELS[statusSnapshot.next_recommended_action] ||
      statusSnapshot.next_recommended_action ||
      ACTION_LABELS[response.next_action] ||
      response.next_action ||
      "request_demo_access";
    dom.statusBriefVersion.textContent = statusSnapshot.brief_version
      ? `${statusSnapshot.brief_version}${statusSnapshot.brief_status_label ? ` · ${statusSnapshot.brief_status_label}` : ""}`
      : "ещё нет";
    dom.statusUploadCount.textContent = String(
      uniqueUploads([...activeSessionUploads(), ...state.pendingUploads]).length,
    );
    dom.statusDownloadReadiness.textContent = statusSnapshot.download_readiness || "pending";
    dom.statusProjectKey.textContent = pointer.project_key || "не выбран";
    dom.statusSessionId.textContent = session.web_demo_session_id || state.sessionId || "не открыт";
    dom.statusOperatorAttention.textContent = accessGate.granted
      ? (resumeContext.summary_text || "Сессия открыта. Shell ждёт следующий turn пользователя или обновление статуса.")
      : accessGate.reason || "Нужен access token для controlled demo surface.";

    const shouldShowBanner = !accessGate.granted;
    dom.accessBanner.hidden = !shouldShowBanner;
    renderSessionBadge();
  }

  function renderAttachmentList() {
    const pending = uniqueUploads(state.pendingUploads);
    const sessionUploads = uniqueUploads(activeSessionUploads());
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
          state.pendingUploads = state.pendingUploads.filter((item) => item.upload_id !== upload.upload_id);
          renderAttachmentList();
          renderStatus();
          persist();
        });
        pill.appendChild(remove);
      }
      dom.attachmentList.appendChild(pill);
    });
  }

  function createMessageNode(message) {
    const fragment = dom.messageTemplate.content.cloneNode(true);
    const article = fragment.querySelector(".message");
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
      system: "Shell",
      artifact: "Фабрика",
    }[message.role || "agent"];
    kind.textContent = message.kind || "reply_card";
    title.textContent = message.title || "Ответ";
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

    (message.actions || []).forEach((action) => {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "chip";
      chip.dataset.uiAction = action;
      chip.textContent = ACTION_LABELS[action] || action;
      chip.addEventListener("click", () => handleActionShortcut(action));
      actions.appendChild(chip);
    });
    return fragment;
  }

  function renderTimeline() {
    dom.chatLog.innerHTML = "";
    const items = state.timeline.length ? state.timeline : [buildWelcomeMessage()];
    items.forEach((message) => {
      dom.chatLog.appendChild(createMessageNode(message));
    });
    dom.chatEmpty.hidden = true;
    dom.chatLog.scrollTop = dom.chatLog.scrollHeight;
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

  function createMockDownload(artifact) {
    const briefVersion = state.lastResponse?.status_snapshot?.brief_version || "draft";
    const body = [
      `# ${artifact.download_name}`,
      "",
      "Mock download из initial browser shell.",
      `artifact_kind: ${artifact.artifact_kind}`,
      `brief_version: ${briefVersion}`,
      `project_key: ${state.lastResponse?.browser_project_pointer?.project_key || "demo-project"}`,
      "",
      "Этот файл нужен только как placeholder до live delivery layer.",
      "",
      state.lastResponse?.reply_cards?.map((card) => `- ${card.title}: ${card.body_text}`).join("\n") || "",
    ].join("\n");
    return URL.createObjectURL(new Blob([body], { type: "text/markdown;charset=utf-8" }));
  }

  function renderArtifacts() {
    const responseArtifacts = Array.isArray(state.lastResponse?.download_artifacts)
      ? state.lastResponse.download_artifacts
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
      body.textContent =
        artifact.description ||
        (ready
          ? "Артефакт готов к скачиванию из той же browser session."
          : "Появится после confirmed brief и downstream handoff.");
      button.disabled = !ready;
      button.textContent = ready ? "Скачать" : "Пока не готов";

      button.addEventListener("click", () => {
        if (!ready) {
          state.timeline.push(
            buildSystemMessage(
              "Загрузка ещё недоступна",
              "Сначала нужно довести проект до confirmed brief и закончить downstream handoff.",
              "artifact_pending",
            ),
          );
          renderTimeline();
          persist();
          return;
        }
        const href = artifact.download_url || createMockDownload(artifact);
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

  function updateQuickActions(actions) {
    const unique = [...new Set((actions || []).filter(Boolean))];
    const selected = unique.length ? unique : ["start_project", "submit_turn", "request_status"];
    dom.quickActions.innerHTML = "";
    selected.forEach((action) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "chip";
      button.dataset.uiAction = action;
      button.textContent = ACTION_LABELS[action] || action;
      button.addEventListener("click", () => handleActionShortcut(action));
      dom.quickActions.appendChild(button);
    });
    const preferredAction = selected.find((action) => action === state.currentAction)
      || ACTION_PRIORITY.find((action) => selected.includes(action))
      || selected[0];
    setCurrentAction(preferredAction);
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

  function buildResumeNotice(response, reason) {
    const resumeContext = response?.resume_context || {};
    const summary = normalizeText(resumeContext.summary_text);
    const currentLabel = normalizeText(resumeContext.current_status_label);
    const briefVersion = normalizeText(resumeContext.latest_brief_version || response?.status_snapshot?.brief_version);
    if (reason === "manual_refresh") {
      return {
        title: "Сессия обновлена",
        body: summary || (currentLabel ? `Shell перечитал статус проекта: ${currentLabel}.` : "Shell перечитал актуальное состояние проекта через GET /api/session."),
        kind: "session_refresh",
      };
    }
    return {
      title: "Сессия восстановлена",
      body:
        summary
        || (
          briefVersion
            ? `Shell восстановил проект и версию brief ${briefVersion} из сохранённого состояния.`
            : "Shell восстановил проект из сохранённого состояния и перечитал текущий статус."
        ),
      kind: "session_resume",
    };
  }

  function replyCardsToMessages(cards) {
    return (cards || []).map((card) => ({
      role:
        card.card_kind === "download_prompt"
          ? "artifact"
          : card.card_kind === "status_update"
            ? "system"
            : "agent",
      kind: card.card_kind || "reply_card",
      title: card.title || "Ответ фабрики",
      body: card.body_text || "",
      actions: Array.isArray(card.action_hints) ? card.action_hints : [],
    }));
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

  function buildTurnPayload(action, userText, queuedUploads = []) {
    const last = state.lastResponse || {};
    const payload = {
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
        web_demo_session_id: last.web_demo_session?.web_demo_session_id || state.sessionId || "",
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
        request_id: nextRequestId(action),
        ui_action: action,
        user_text: normalizeText(userText),
        transport_mode: "browser_shell",
        linked_discovery_session_id: last.web_conversation_envelope?.linked_discovery_session_id || "",
        linked_brief_id: last.web_conversation_envelope?.linked_brief_id || "",
      },
      discovery_runtime_state: last.discovery_runtime_state || {},
    };
    if (queuedUploads.length) {
      payload.uploaded_files = serializeUploadsForTransport(queuedUploads);
    }
    return payload;
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
      awaiting_confirmation:
        "Я собрал черновой brief. Проверь summary, попроси правки или явно подтверди текущую версию.",
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
          card_kind: "brief_summary_section",
          title: "Проблема и желаемый результат",
          body_text: "Проблема:\nНужно автоматически разбирать входящие обращения и выбирать следующий маршрут обработки.\n\nЖелаемый результат:\nПользователь получает structured summary, маршрут заявки и причину выбора.",
          action_hints: ["request_brief_correction", "confirm_brief"],
        },
        {
          card_kind: "brief_summary_section",
          title: "Пользователи и процесс",
          body_text: "Кто пользуется результатом:\n- Оператор первой линии\n- Руководитель смены\n\nТекущий процесс:\nОператор вручную читает обращение, ищет подходящий маршрут и только потом эскалирует кейс дальше.",
          action_hints: ["request_brief_correction", "confirm_brief"],
        },
        {
          card_kind: "brief_summary_section",
          title: "Примеры входов и выходов",
          body_text: "Входные примеры:\n- Новый запрос клиента на выплату\n- Уточнение по статусу открытого кейса\n\nОжидаемые выходы:\n- Категория обращения\n- Следующий маршрут обработки",
          action_hints: ["request_brief_correction", "confirm_brief"],
        },
        {
          card_kind: "brief_summary_section",
          title: "Правила, исключения и риски",
          body_text: "Бизнес-правила:\n- Подозрение на мошенничество всегда эскалируется эксперту\n\nИсключения:\n- VIP-клиенты идут по отдельному сценарию\n\nОткрытые риски:\n- Нужно отдельно описать обращения от партнёрских СТО",
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
          card_kind: "brief_summary_section",
          title: "Версия brief v3 подтверждена",
          body_text: "Зафиксирована версия v3. Следующий этап фабрики может использовать только эту подтверждённую редакцию.",
          action_hints: ["request_status", "reopen_brief"],
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
      uploaded_at: new Date().toISOString(),
    }));
  }

  function mockAdapterTurn(payload) {
    const action = payload.web_conversation_envelope?.ui_action || "submit_turn";
    const userText = normalizeText(payload.web_conversation_envelope?.user_text);
    const uploadedFiles = sanitizeMockUploads(payload.uploaded_files || []);
    const accessGranted = Boolean(state.accessToken);
    const projectKey =
      state.lastResponse?.browser_project_pointer?.project_key ||
      `factory-${slugify(userText || "demo-project", "project")}`;

    if (!accessGranted) {
      state.mockStage = "gate_pending";
      return {
        status: "gate_pending",
        next_action: "request_demo_access",
        next_topic: "",
        next_question: "Укажи активный demo access token, чтобы открыть рабочую сессию фабрики.",
        access_gate: {
          granted: false,
          reason: "Укажи активный demo access token, чтобы открыть рабочую сессию фабрики.",
          demo_access_grant_id: "",
          grant_type: "shared_demo_token",
          grant_value_hash: "",
          status: "missing",
          expires_at: "",
        },
        web_demo_session: {
          web_demo_session_id: state.sessionId || "web-demo-shell-session",
          session_cookie_id: "cookie-web-demo-shell-session",
          status: "gate_pending",
          active_project_key: "",
        },
        browser_project_pointer: {
          pointer_id: "browser-pointer-web-demo-shell",
          project_key: "",
          selection_mode: selectionModeFor(action),
          pointer_status: "active",
        },
        status_snapshot: {
          user_visible_status: "gate_pending",
          next_recommended_action: "request_demo_access",
          brief_version: "",
          download_readiness: "pending",
          uploaded_file_count: uploadedFiles.length,
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
      state.mockStage = "downloads_ready";
    } else if (action === "request_brief_correction" || action === "reopen_brief") {
      state.mockStage = "awaiting_confirmation";
    } else if (action === "request_status" && state.lastResponse) {
      state.mockStage = state.mockStage || "discovery_problem";
    } else if (state.mockStage === "gate_pending") {
      state.mockStage = "discovery_problem";
    } else if (state.mockStage === "discovery_problem") {
      state.mockStage = "discovery_inputs";
    } else if (state.mockStage === "discovery_inputs") {
      state.mockStage = "discovery_outputs";
    } else if (state.mockStage === "discovery_outputs") {
      state.mockStage = "awaiting_confirmation";
    }

    const stage = state.mockStage;
    const brief =
      stage === "awaiting_confirmation" || stage === "downloads_ready"
        ? {
            brief_id: "brief-web-demo-001",
            version: stage === "downloads_ready" ? "v3" : "v2",
            problem_statement: "Нужно автоматизировать triage входящих заявок и сократить ручную сортировку.",
            desired_outcome:
              "Будущий агент собирает краткое summary, категорию, приоритет и предлагает маршрут обработки.",
          }
        : {};

    return {
      status: stage === "downloads_ready" ? "confirmed" : stage === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
      next_action:
        stage === "downloads_ready"
          ? "start_concept_pack_handoff"
          : stage === "awaiting_confirmation"
            ? "await_for_confirmation"
            : "continue_discovery",
      next_topic: stage === "discovery_problem" ? "problem" : stage === "discovery_inputs" ? "input_examples" : "output_expectations",
      next_question: mockDiscoveryPrompt(stage),
      access_gate: {
        granted: true,
        reason: "",
        demo_access_grant_id: "access-web-demo-shell",
        grant_type: "shared_demo_token",
        grant_value_hash: "mock-token-hash",
        status: "active",
        expires_at: "",
      },
      web_demo_session: {
        web_demo_session_id: state.sessionId || "web-demo-shell-session",
        session_cookie_id: "cookie-web-demo-shell-session",
        status: stage === "downloads_ready" ? "download_ready" : stage === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
        active_project_key: projectKey,
      },
      browser_project_pointer: {
        pointer_id: "browser-pointer-web-demo-shell",
        project_key: projectKey,
        selection_mode: selectionModeFor(action),
        linked_discovery_session_id: "discovery-web-demo-001",
        linked_brief_id: brief.brief_id || "",
        linked_brief_version: brief.version || "",
        pointer_status: "active",
      },
      status_snapshot: {
        user_visible_status:
          stage === "downloads_ready" ? "playground_ready" : stage === "awaiting_confirmation" ? "awaiting_confirmation" : "awaiting_user_reply",
        user_visible_status_label:
          stage === "downloads_ready" ? "Артефакты готовы" : stage === "awaiting_confirmation" ? "Brief ждёт подтверждения" : "Сбор требований продолжается",
        next_recommended_action:
          stage === "downloads_ready"
            ? "start_concept_pack_handoff"
            : stage === "awaiting_confirmation"
              ? "confirm_brief"
              : "submit_turn",
        next_recommended_action_label:
          stage === "downloads_ready"
            ? "Передать brief в фабрику"
            : stage === "awaiting_confirmation"
              ? "Проверить и подтвердить brief"
              : "Ответить на следующий вопрос",
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
        requirement_brief: brief,
        discovery_session: {
          discovery_session_id: "discovery-web-demo-001",
          project_key: projectKey,
        },
      },
      ui_projection: {
        preferred_ui_action:
          stage === "downloads_ready"
            ? "request_status"
            : stage === "awaiting_confirmation"
              ? "confirm_brief"
              : "submit_turn",
        current_question: mockDiscoveryPrompt(stage),
        current_topic:
          stage === "discovery_problem"
            ? "problem"
            : stage === "discovery_inputs"
              ? "input_examples"
              : stage === "discovery_outputs"
                ? "expected_outputs"
                : "",
        project_title: projectKey,
        uploaded_file_count: uploadedFiles.length,
      },
    };
  }

  function applyResponse(response, connectionMode, options = {}) {
    const appendReplyMessages = options.appendReplyMessages !== false;
    const syncReason = normalizeText(options.syncReason);
    state.connectionMode = connectionMode;
    state.lastResponse = response;
    state.sessionId = response.web_demo_session?.web_demo_session_id || state.sessionId;

    const replyMessages = appendReplyMessages ? replyCardsToMessages(response.reply_cards) : [];
    if (replyMessages.length) {
      state.timeline.push(...replyMessages);
    } else if (appendReplyMessages && response.next_question) {
      state.timeline.push({
        role: "agent",
        kind: "next_question",
        title: "Следующий вопрос",
        body: response.next_question,
        actions: ["submit_turn"],
      });
    }

    const preferredAction = response.ui_projection?.preferred_ui_action;
    updateQuickActions(responseActions(response));
    if (preferredAction) {
      setCurrentAction(preferredAction);
    }

    const resumeFingerprint = normalizeText(response.resume_context?.resume_fingerprint);
    if (syncReason === "manual_refresh") {
      const notice = buildResumeNotice(response, syncReason);
      state.timeline.push(buildSystemMessage(notice.title, notice.body, notice.kind));
      if (resumeFingerprint) {
        state.lastResumeFingerprint = resumeFingerprint;
      }
    } else if (syncReason && resumeFingerprint && state.lastResumeFingerprint !== resumeFingerprint) {
      const notice = buildResumeNotice(response, syncReason);
      state.timeline.push(buildSystemMessage(notice.title, notice.body, notice.kind));
      state.lastResumeFingerprint = resumeFingerprint;
    }

    renderConnection();
    renderStatus();
    renderTimeline();
    renderArtifacts();
    renderAttachmentList();
    persist();

    const sourceAction = normalizeText(response.web_conversation_envelope?.ui_action);
    const sourceRequestId = normalizeText(response.web_conversation_envelope?.request_id);
    if (
      connectionMode === "live"
      && sourceAction === "confirm_brief"
      && response.next_action === "start_concept_pack_handoff"
      && !Array.isArray(response.download_artifacts)
      && sourceRequestId
      && state.lastAutoFollowupSource !== sourceRequestId
    ) {
      state.lastAutoFollowupSource = sourceRequestId;
      persist();
      window.setTimeout(() => {
        dispatchTurn("request_status", "", { skipUserMessage: true });
      }, 120);
    }
  }

  async function dispatchTurn(action, userText, options = {}) {
    const queuedUploads = uniqueUploads(options.queuedUploads || []);
    const normalizedUserText = normalizeText(userText);
    if (!options.skipUserMessage && (normalizedUserText || queuedUploads.length)) {
      state.timeline.push({
        role: "user",
        kind: action,
        title: ACTION_LABELS[action] || "Сообщение",
        body: normalizedUserText || "Прикрепил файлы к текущему вопросу.",
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
      renderTimeline();
    }

    const payload = buildTurnPayload(action, userText, queuedUploads);
    setBusy(true);
    try {
      const response = await postTurn(payload);
      applyResponse(response, "live");
    } catch (_error) {
      applyResponse(mockAdapterTurn(payload), "mock");
    } finally {
      if (queuedUploads.length) {
        state.pendingUploads = state.pendingUploads.filter(
          (item) => !queuedUploads.some((queued) => queued.upload_id === item.upload_id),
        );
        renderAttachmentList();
        renderStatus();
      }
      setBusy(false);
    }
  }

  async function refreshSession(options = {}) {
    const syncReason = normalizeText(options.syncReason, "manual_refresh");
    const suppressFailureBanner = Boolean(options.suppressFailureBanner);
    if (!state.sessionId) {
      state.timeline.push(
        buildSystemMessage(
          "Сессия ещё не создана",
          "Сначала открой проект или отправь первый turn, после этого shell сможет дергать GET /api/session.",
          "session_missing",
        ),
      );
      renderTimeline();
      persist();
      return;
    }

    setBusy(true);
    try {
      const response = await fetchSession(state.sessionId);
      applyResponse(response, "live", { appendReplyMessages: false, syncReason });
    } catch (_error) {
      state.connectionMode = state.lastResponse ? state.connectionMode : "mock";
      renderConnection();
      if (!suppressFailureBanner) {
        state.timeline.push(
          buildSystemMessage(
            "Live session недоступна",
            "GET /api/session пока не ответил. Shell остаётся в mock/local режиме и не теряет текущее состояние.",
            "session_refresh_failed",
          ),
        );
        renderTimeline();
        persist();
      }
    } finally {
      setBusy(false);
    }
  }

  async function restoreSessionOnLoad() {
    if (!state.sessionId) {
      return;
    }
    await refreshSession({ syncReason: "auto_resume", suppressFailureBanner: true });
  }

  function handleActionShortcut(action) {
    if (action === "submit_access_token") {
      dom.accessTokenInput.focus();
      return;
    }

    if (action === "request_status" || action === "request_brief_review" || action === "confirm_brief") {
      setCurrentAction(action);
      dispatchTurn(action, "", { skipUserMessage: true });
      return;
    }

    setCurrentAction(action);
    dom.composerInput.focus();
  }

  function bindEvents() {
    dom.quickActions.addEventListener("click", (event) => {
      const target = event.target.closest("[data-ui-action]");
      if (!target) {
        return;
      }
      handleActionShortcut(target.dataset.uiAction);
    });

    dom.composerForm.addEventListener("submit", (event) => {
      event.preventDefault();
      const text = normalizeText(dom.composerInput.value);
      const queuedUploads = uniqueUploads(state.pendingUploads);
      if (!text && !queuedUploads.length && !["request_status", "request_brief_review", "confirm_brief"].includes(state.currentAction)) {
        dom.composerInput.focus();
        return;
      }
      dispatchTurn(state.currentAction, text, { queuedUploads });
      dom.composerInput.value = "";
      if (state.currentAction !== "submit_turn") {
        setCurrentAction("submit_turn");
      }
    });

    dom.attachmentInput.addEventListener("change", async () => {
      const selectedFiles = Array.from(dom.attachmentInput.files || []);
      dom.attachmentInput.value = "";
      if (!selectedFiles.length) {
        return;
      }

      const remainingSlots = Math.max(0, MAX_LOCAL_UPLOAD_FILES - state.pendingUploads.length);
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
        state.pendingUploads = uniqueUploads([...state.pendingUploads, ...loadedUploads]).slice(0, MAX_LOCAL_UPLOAD_FILES);
        renderAttachmentList();
        renderStatus();
        persist();
        dom.composerInput.focus();
      }

      if (skippedCount || failedUploads.length) {
        const details = [];
        if (skippedCount) {
          details.push(`Лишние файлы не добавлены: лимит ${MAX_LOCAL_UPLOAD_FILES} файла на один turn.`);
        }
        if (failedUploads.length) {
          details.push(`Не удалось прочитать: ${failedUploads.join(", ")}.`);
        }
        state.timeline.push(
          buildSystemMessage(
            "Не все файлы добавлены",
            details.join(" "),
            "upload_warning",
          ),
        );
        renderTimeline();
        persist();
      }
    });

    dom.accessSubmit.addEventListener("click", () => {
      state.accessToken = normalizeText(dom.accessTokenInput.value, DEFAULT_ACCESS_TOKEN);
      dom.accessTokenInput.value = state.accessToken;
      state.timeline.push(
        buildSystemMessage(
          "Демо-доступ сохранён",
          "Access token записан в shell. Теперь можно открыть проект и отправить первый turn в фабрику.",
          "access_token_saved",
        ),
      );
      renderTimeline();
      renderStatus();
      persist();
    });

    dom.refreshSession.addEventListener("click", () => {
      refreshSession({ syncReason: "manual_refresh" });
    });
  }

  function init() {
    hydrate();
    dom.accessTokenInput.value = state.accessToken;
    bindEvents();
    renderConnection();
    renderStatus();
    renderTimeline();
    renderArtifacts();
    renderAttachmentList();
    if (state.lastResponse) {
      updateQuickActions(responseActions(state.lastResponse));
      const preferredAction = normalizeText(state.lastResponse.ui_projection?.preferred_ui_action);
      if (preferredAction) {
        setCurrentAction(preferredAction);
      }
    } else {
      updateQuickActions(["start_project", "submit_turn", "request_status"]);
    }
    dom.root.dataset.mode = "ready";
    void restoreSessionOnLoad();
  }

  init();
})();
