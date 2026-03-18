import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { normalizeText } from "./utils.js";

const sessions = new Map();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DEFAULT_PROJECT_TITLE = "Новый проект";
const SESSION_EVICT_MS = 60 * 60 * 1000;
const SESSION_STORAGE_DIR = path.join(__dirname, "..", "data", "sessions");

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

function ensureStorageDir() {
  try {
    fs.mkdirSync(SESSION_STORAGE_DIR, { recursive: true });
  } catch (error) {
    console.error("[asc-demo] sessions.ensureStorageDir:", error?.message || error);
  }
}

function sessionFilePath(sessionId) {
  const normalized = normalizeText(sessionId);
  if (!normalized) {
    return "";
  }
  const safeName = encodeURIComponent(normalized);
  return path.join(SESSION_STORAGE_DIR, `${safeName}.json`);
}

function serializeSession(session) {
  return {
    ...session,
    coveredTopics: Array.from(ensureSet(session.coveredTopics)),
    summaryPromise: null,
    lastAccessAt: normalizeText(session.lastAccessAt, nowIso()),
  };
}

function hydrateSession(rawValue) {
  const value = rawValue && typeof rawValue === "object" ? rawValue : {};
  const base = createSession(normalizeText(value.sessionId), {
    projectKey: normalizeText(value.projectKey),
    displayProjectTitle: normalizeText(value.displayProjectTitle, DEFAULT_PROJECT_TITLE),
  });

  Object.assign(base, value);
  base.coveredTopics = ensureSet(value.coveredTopics);
  base.summaryPromise = null;
  base.summaryState = normalizeText(value.summaryState, "idle");
  base.conversationHistory = Array.isArray(value.conversationHistory) ? value.conversationHistory : [];
  base.topicAnswers = { ...emptyTopicAnswers(), ...(value.topicAnswers || {}) };
  base.uploadedFiles = Array.isArray(value.uploadedFiles) ? value.uploadedFiles : [];
  base.artifacts = Array.isArray(value.artifacts) ? value.artifacts : [];
  base.missingCoverage = Array.isArray(value.missingCoverage) ? value.missingCoverage : [];
  base.displayProjectTitle = normalizeText(value.displayProjectTitle, DEFAULT_PROJECT_TITLE);
  base.createdAt = normalizeText(value.createdAt, base.createdAt);
  base.updatedAt = normalizeText(value.updatedAt, base.updatedAt);
  base.lastAccessAt = normalizeText(value.lastAccessAt, nowIso());
  return base;
}

function persistSession(session) {
  const filePath = sessionFilePath(session?.sessionId);
  if (!filePath) {
    return;
  }
  try {
    ensureStorageDir();
    fs.writeFileSync(filePath, JSON.stringify(serializeSession(session), null, 2), "utf-8");
  } catch (error) {
    console.error("[asc-demo] sessions.persistSession:", error?.message || error);
  }
}

function loadSessionFromDisk(sessionId) {
  const filePath = sessionFilePath(sessionId);
  if (!filePath || !fs.existsSync(filePath)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(filePath, "utf-8");
    const parsed = JSON.parse(raw);
    return hydrateSession(parsed);
  } catch (error) {
    console.error("[asc-demo] sessions.loadSessionFromDisk:", error?.message || error);
    return null;
  }
}

function touchSession(session) {
  if (!session) {
    return;
  }
  session.lastAccessAt = nowIso();
  sessions.set(session.sessionId, session);
}

function evictStaleSessions() {
  const threshold = Date.now() - SESSION_EVICT_MS;
  for (const [sessionId, session] of sessions.entries()) {
    if (normalizeText(session?.summaryState) === "running") {
      continue;
    }
    const referenceTime = Date.parse(
      normalizeText(session?.lastAccessAt, normalizeText(session?.updatedAt)),
    );
    if (Number.isFinite(referenceTime) && referenceTime < threshold) {
      sessions.delete(sessionId);
    }
  }
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
    lastAccessAt: now,
    lastResponse: null,
  };
}

export function getOrCreateSession(sessionId, seed = {}) {
  evictStaleSessions();
  const id = sessionId || `web-demo-session-${randomUUID()}`;
  const existing = getSession(id);
  if (existing) {
    return existing;
  }
  const session = createSession(id, seed);
  touchSession(session);
  persistSession(session);
  return session;
}

export function getSession(sessionId) {
  const id = normalizeText(sessionId);
  if (!id) {
    return null;
  }
  evictStaleSessions();
  const cached = sessions.get(id);
  if (cached) {
    touchSession(cached);
    return cached;
  }
  const loaded = loadSessionFromDisk(id);
  if (!loaded) {
    return null;
  }
  touchSession(loaded);
  return loaded;
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
  touchSession(target);
  persistSession(target);
  return target;
}

export function setSessionResponse(session, response) {
  session.lastResponse = response;
  session.updatedAt = nowIso();
  touchSession(session);
  persistSession(session);
}

export function setSessionArtifacts(session, artifacts = []) {
  session.artifacts = artifacts;
  session.updatedAt = nowIso();
  touchSession(session);
  persistSession(session);
}

export function setSessionSummaryPromise(session, promise) {
  session.summaryPromise = promise;
  session.updatedAt = nowIso();
  touchSession(session);
  persistSession(session);
}

export function listSessions() {
  evictStaleSessions();
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
