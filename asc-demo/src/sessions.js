import { randomUUID } from "node:crypto";

const sessions = new Map();

const DEFAULT_PROJECT_TITLE = "Новый проект";

function nowIso() {
  return new Date().toISOString();
}

function emptyTopicAnswers() {
  return {
    problem: "",
    target_users: "",
    current_workflow: "",
    input_examples: "",
    expected_outputs: "",
    branching_rules: "",
    success_metrics: "",
  };
}

function ensureSet(value) {
  if (value instanceof Set) {
    return value;
  }
  if (Array.isArray(value)) {
    return new Set(value.filter(Boolean));
  }
  return new Set();
}

export function createSession(sessionId, seed = {}) {
  const now = nowIso();
  const id = sessionId || `web-demo-session-${randomUUID()}`;
  const projectKey = seed.projectKey || "";
  return {
    sessionId: id,
    projectKey,
    stage: "gate_pending",
    accessGranted: false,
    conversationHistory: [],
    coveredTopics: new Set(),
    topicAnswers: emptyTopicAnswers(),
    uploadedFiles: [],
    briefText: "",
    briefVersion: 0,
    artifacts: [],
    summaryPromise: null,
    summaryState: "idle",
    currentQuestion: "",
    currentTopic: "",
    whyAskingNow: "",
    missingCoverage: [],
    displayProjectTitle: seed.displayProjectTitle || DEFAULT_PROJECT_TITLE,
    createdAt: now,
    updatedAt: now,
    lastResponse: null,
  };
}

export function getOrCreateSession(sessionId, seed = {}) {
  const id = sessionId || `web-demo-session-${randomUUID()}`;
  const existing = sessions.get(id);
  if (existing) {
    return existing;
  }
  const session = createSession(id, seed);
  sessions.set(id, session);
  return session;
}

export function getSession(sessionId) {
  return sessions.get(sessionId) || null;
}

export function updateSession(session, patch = {}) {
  const target = session;
  Object.entries(patch).forEach(([key, value]) => {
    if (key === "coveredTopics") {
      target.coveredTopics = ensureSet(value);
      return;
    }
    target[key] = value;
  });
  target.updatedAt = nowIso();
  sessions.set(target.sessionId, target);
  return target;
}

export function setSessionResponse(session, response) {
  session.lastResponse = response;
  session.updatedAt = nowIso();
  sessions.set(session.sessionId, session);
}

export function setSessionArtifacts(session, artifacts = []) {
  session.artifacts = artifacts;
  session.updatedAt = nowIso();
  sessions.set(session.sessionId, session);
}

export function setSessionSummaryPromise(session, promise) {
  session.summaryPromise = promise;
  session.updatedAt = nowIso();
  sessions.set(session.sessionId, session);
}

export function listSessions() {
  return Array.from(sessions.values());
}

export function getArtifact(sessionId, artifactKind) {
  const session = getSession(sessionId);
  if (!session) {
    return null;
  }
  return (
    session.artifacts.find((item) => item.artifact_kind === artifactKind)
    || null
  );
}

export function clearAllSessions() {
  sessions.clear();
}
