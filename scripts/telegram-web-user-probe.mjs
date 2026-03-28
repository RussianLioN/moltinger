#!/usr/bin/env node
/**
 * telegram-web-user-probe.mjs
 * Sends a message via Telegram Web as logged-in user and validates bot reply.
 *
 * No API_ID/API_HASH required.
 */

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const DEFAULT_STATE = process.env.TELEGRAM_WEB_STATE || ".telegram-web-state.json";
const DEFAULT_TARGET = process.env.TELEGRAM_WEB_TARGET || "@moltinger_bot";
const DEFAULT_MESSAGE = process.env.TELEGRAM_WEB_MESSAGE || "/status";
const DEFAULT_TIMEOUT_SEC = Number(process.env.TELEGRAM_WEB_TIMEOUT_SECONDS || 45);
const DEFAULT_MIN_REPLY_LEN = Number(process.env.TELEGRAM_WEB_MIN_REPLY_LEN || 2);
const DEFAULT_COMPOSER_RETRIES = Number(process.env.TELEGRAM_WEB_COMPOSER_RETRIES || 2);
const DEFAULT_QUIET_WINDOW_MS = Number(process.env.TELEGRAM_WEB_QUIET_WINDOW_MS || 3000);
const DEFAULT_REPLY_SETTLE_MS = Number(process.env.TELEGRAM_WEB_REPLY_SETTLE_MS || 5000);
const INTERNAL_TELEMETRY_RE =
  /(?:^|[•\n])\s*(?:[\p{Extended_Pictographic}\uFE0F]+\s*)?(?:activity log(?:\s*[•:-]|\b)|running:\s*`?|searching memory(?:\.\.\.)?|memory[_ ]search(?:[_ ]started)?\b|thinking(?:\.\.\.)?|tool(?:[_ ]call)?(?:[_ ](?:started|progress))?\b|mcp__[\p{L}\p{N}_:.-]+)/iu;
const PROGRESS_PREFACE_RE =
  /^(?:сначала(?:\s|$)|сперва(?:\s|$)|сейчас(?:\s|$)|для начала(?:\s|$)|первым делом(?:\s|$)|я\s+(?:сначала\s+)?(?:проверю|посмотрю|открою|изучу|поищу|быстро посмотрю)(?:\s|$)|(?:проверю|посмотрю|открою|изучу|поищу|быстро посмотрю)(?:\s|$)|let me(?:\s|$)|i(?:'|’)ll(?:\s|$)|first[, ]+i(?:'|’)ll(?:\s|$)|checking(?:\s|$)|opening(?:\s|$)|looking up(?:\s|$))/iu;
const INTERIM_PROGRESS_RE =
  /^(?:сейчас\s+)?(?:проверяю|смотрю|ищу|открываю|открою|попробую|запускаю|зайду|перехожу|достаю|подожди|секунду|one moment|working on it|checking|looking|opening|navigating|fetching|let me|i(?:'ll| will)\b)/iu;

function getArg(name, fallback = "") {
  const idx = process.argv.indexOf(name);
  if (idx >= 0 && idx + 1 < process.argv.length) return process.argv[idx + 1];
  return fallback;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

const statePath = path.resolve(getArg("--state", DEFAULT_STATE));
const target = getArg("--target", DEFAULT_TARGET);
const text = getArg("--text", DEFAULT_MESSAGE);
const timeoutSec = Number(getArg("--timeout", String(DEFAULT_TIMEOUT_SEC)));
const minReplyLen = Number(getArg("--min-reply-len", String(DEFAULT_MIN_REPLY_LEN)));
const composerRetries = Math.max(0, Number(getArg("--composer-retries", String(DEFAULT_COMPOSER_RETRIES))) || 0);
const quietWindowMs = Math.max(500, Number(getArg("--quiet-window-ms", String(DEFAULT_QUIET_WINDOW_MS))) || 0);
const replySettleMs = Math.max(1000, Number(getArg("--reply-settle-ms", String(DEFAULT_REPLY_SETTLE_MS))) || 0);
const headed = hasFlag("--headed");
const debug = hasFlag("--debug");

const ERROR_RE =
  /(traceback|exception|stack\s*trace|panic|internal server error|timed?\s*out|timeout|model[^\n]{0,120}not found|no authenticated providers|provider[^\n]{0,40}(unauth|unauthorized|auth(?:entication)?\s+failed)|missing\s+'action'\s+parameter)/i;
const SENSITIVE_RE = /\b(api[_ -]?key|token|password|secret)\b/i;

let stage = "login";
let retriesUsed = 0;
let chatOpenVerified = false;
let lastChatOpenCheck = null;

function normalizeMessageText(value) {
  return String(value || "")
    .replace(/[\u200e\u200f]/g, " ")
    .replace(/[\uE000-\uF8FF]/g, " ")
    .replace(/\s+/g, " ")
    .replace(/(?:\s+\d{1,2}:\d{2}(?:\s*(?:AM|PM))?)+$/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

export function isLikelyInterimReplyText(value) {
  const normalized = normalizeMessageText(value);
  if (!normalized) return false;
  if (INTERNAL_TELEMETRY_RE.test(normalized)) return false;
  return INTERIM_PROGRESS_RE.test(normalized);
}

export function isReplyErrorSignature(value) {
  const normalized = normalizeMessageText(value);
  return ERROR_RE.test(normalized) || INTERNAL_TELEMETRY_RE.test(normalized);
}

export function isLikelyProgressPreface(value) {
  const normalized = normalizeMessageText(value);
  if (!normalized) return false;
  return PROGRESS_PREFACE_RE.test(normalized);
}

function safeMid(value) {
  const mid = Number(value || 0);
  return Number.isFinite(mid) ? mid : 0;
}

function normalizeProbeMessage(message) {
  return {
    mid: safeMid(message?.mid),
    direction: String(message?.direction || "unknown"),
    text: normalizeMessageText(message?.text),
  };
}

function messageFingerprint(message) {
  const normalized = normalizeProbeMessage(message);
  return `${normalized.mid}:${normalized.direction}:${normalized.text}`;
}

function previewText(value, limit = 160) {
  const normalized = normalizeMessageText(value);
  if (normalized.length <= limit) return normalized;
  return `${normalized.slice(0, Math.max(0, limit - 1))}...`;
}

function maxObservedMid(messages) {
  return messages.reduce((max, message) => {
    const mid = safeMid(message?.mid);
    return mid > max ? mid : max;
  }, 0);
}

export function findOutgoingProbeMessage(messages, probeText, minMidExclusive = 0) {
  const normalizedProbeText = normalizeMessageText(probeText);
  let latestExact = null;
  let latestPrefix = null;

  for (const rawMessage of messages) {
    const message = normalizeProbeMessage(rawMessage);
    if (message.direction !== "out") continue;
    if (message.mid <= minMidExclusive) continue;
    if (message.text === normalizedProbeText) {
      if (!latestExact || message.mid > latestExact.mid) {
        latestExact = message;
      }
      continue;
    }
    if (
      normalizedProbeText.length > 0 &&
      message.text.length > normalizedProbeText.length &&
      message.text.startsWith(normalizedProbeText)
    ) {
      if (!latestPrefix || message.mid > latestPrefix.mid) {
        latestPrefix = message;
      }
    }
  }

  return latestExact || latestPrefix;
}

export function findAttributedReply(messages, sentMid) {
  let earliest = null;

  for (const rawMessage of messages) {
    const message = normalizeProbeMessage(rawMessage);
    if (message.direction !== "in") continue;
    if (message.mid <= sentMid) continue;
    if (!message.text) continue;
    if (!earliest || message.mid < earliest.mid) {
      earliest = message;
    }
  }

  return earliest;
}

export function findAttributedReplies(messages, sentMid) {
  return messages
    .map(normalizeProbeMessage)
    .filter((message) => message.direction === "in" && message.mid > sentMid && message.text.length > 0)
    .sort((left, right) => left.mid - right.mid);
}

export function findInvalidIncomingActivityMessages(messages) {
  return (Array.isArray(messages) ? messages : [])
    .map(normalizeProbeMessage)
    .filter(
      (message) =>
        message.direction === "in" &&
        message.text.length > 0 &&
        isReplyErrorSignature(message.text)
    )
    .map(summarizeMessage)
    .filter(Boolean);
}

function summarizeMessage(message) {
  if (!message) return null;
  const normalized = normalizeProbeMessage(message);
  return {
    mid: normalized.mid,
    direction: normalized.direction,
    text: previewText(normalized.text),
  };
}

function normalizeTarget(value) {
  const normalized = (value || "").toLowerCase().trim();
  return {
    raw: normalized,
    noAt: normalized.startsWith("@") ? normalized.slice(1) : normalized,
  };
}

function buildBasePayload() {
  return {
    stage,
    retries_used: retriesUsed,
    chat_open_verified: chatOpenVerified,
  };
}

function buildCorrelationWindow(details) {
  return {
    strategy: "quiet_window_then_stable_incoming_after_sent_mid",
    quiet_window_ms: details.quietWindowMs,
    quiet_window_wait_ms: details.quietWindowWaitMs,
    reply_settle_ms: details.replySettleMs || null,
    reply_settle_wait_ms: details.replySettleWaitMs || null,
    baseline_max_message_id: details.baselineMaxMid,
    sent_observed_at_ms: details.sentObservedAtMs || null,
    reply_observed_at_ms: details.replyObservedAtMs || null,
    sent_message: summarizeMessage(details.sentMessage),
    preface_reply: summarizeMessage(details.prefaceReplyMessage),
    preface_followup_wait_ms: details.prefaceFollowupWaitMs || null,
    matched_reply: summarizeMessage(details.replyMessage),
    latest_seen_incoming: summarizeMessage(details.latestIncoming),
    last_pre_send_activity: details.lastPreSendActivity || null,
  };
}

export async function extendReplySettlePastProgressPreface({
  initialResult,
  deadlineMs,
  waitForReplySettleFn,
  nowMs = () => Date.now(),
}) {
  const prefaceReply = initialResult?.replyMessage;
  if (!prefaceReply || !isLikelyProgressPreface(prefaceReply.text)) {
    return {
      ...initialResult,
      prefaceReplyMessage: null,
      prefaceFollowupWaitMs: null,
    };
  }

  const remainingMs = Math.max(0, deadlineMs - nowMs());
  if (remainingMs === 0) {
    return {
      ...initialResult,
      prefaceReplyMessage: prefaceReply,
      prefaceFollowupWaitMs: 0,
    };
  }

  const followupResult = await waitForReplySettleFn(prefaceReply.mid, remainingMs);
  if (followupResult?.replyMessage) {
    return {
      ...followupResult,
      prefaceReplyMessage: prefaceReply,
      prefaceFollowupWaitMs: followupResult.settleWaitMs ?? null,
    };
  }

  return {
    ...initialResult,
    latestIncoming: followupResult?.latestIncoming ?? initialResult.latestIncoming,
    prefaceReplyMessage: prefaceReply,
    prefaceFollowupWaitMs: followupResult?.settleWaitMs ?? null,
  };
}

export function classifyFailure(code, stageName = stage) {
  const registry = {
    missing_session_state: {
      summary: "Telegram Web session is missing, stale, or not logged in",
      actionability: "operator",
      fallback_relevant: true,
      recommended_action: "Re-authenticate Telegram Web and rerun the authoritative check.",
    },
    ui_drift: {
      summary: "Telegram Web UI structure no longer matches the probe contract",
      actionability: "engineering",
      fallback_relevant: true,
      recommended_action: "Inspect restricted debug evidence, update selectors, and rerun the authoritative check.",
    },
    chat_open_failure: {
      summary: "The target Telegram chat could not be opened reliably",
      actionability: "operator",
      fallback_relevant: true,
      recommended_action: "Confirm the target chat/user mapping and rerun after restoring chat visibility.",
    },
    stale_chat_noise: {
      summary: "The chat remained noisy, so attribution could not be proven safely",
      actionability: "operator",
      fallback_relevant: false,
      recommended_action: "Wait for the chat to settle or isolate the chat noise, then rerun the authoritative check.",
    },
    pre_send_invalid_activity: {
      summary: "A recent incoming Telegram message already leaked internal activity/tool-progress before the probe began",
      actionability: "operator",
      fallback_relevant: false,
      recommended_action: "Clear or reconcile the chat/session noise and rerun the authoritative check after the last invalid incoming reply is no longer present.",
    },
    send_failure: {
      summary: "The probe message was not observed after the send action",
      actionability: "engineering",
      fallback_relevant: true,
      recommended_action: "Inspect Telegram Web send diagnostics and rerun after fixing the send path or selector drift.",
    },
    bot_no_response: {
      summary: "The bot did not produce an attributable reply for the current run",
      actionability: "operator",
      fallback_relevant: true,
      recommended_action: "Check bot/runtime health and polling logs, then rerun the authoritative check.",
    },
    environment_precondition: {
      summary: "The authoritative Telegram Web probe is missing runtime prerequisites",
      actionability: "operator",
      fallback_relevant: true,
      recommended_action: "Restore the required runtime prerequisites and rerun the authoritative check.",
    },
  };

  const resolved = registry[code] || {
    summary: "The authoritative Telegram Web probe failed unexpectedly",
    actionability: "engineering",
    fallback_relevant: true,
    recommended_action: "Inspect restricted debug evidence and rerun after narrowing the root cause.",
  };

  return {
    code,
    stage: stageName,
    summary: resolved.summary,
    actionability: resolved.actionability,
    fallback_relevant: resolved.fallback_relevant,
    recommended_action: resolved.recommended_action,
  };
}

function sanitizeStats(stats) {
  if (!stats) return null;
  return {
    url: stats.url || "",
    peers: Number(stats.peers || 0),
    chats: Number(stats.chats || 0),
    skeletons: Number(stats.skeletons || 0),
    hasSearch: Boolean(stats.hasSearch),
    loginInputs: Number(stats.loginInputs || 0),
  };
}

function buildAttributionEvidence(correlation, confidence) {
  if (!correlation) {
    return {
      attribution_confidence: confidence,
    };
  }

  return {
    quiet_window_ms: correlation.quiet_window_ms,
    quiet_window_wait_ms: correlation.quiet_window_wait_ms,
    baseline_max_message_id: correlation.baseline_max_message_id,
    last_pre_send_activity: correlation.last_pre_send_activity || null,
    sent_message_fingerprint: correlation.sent_message || null,
    sent_message_id: correlation.sent_message?.mid || null,
    matched_reply_fingerprint: correlation.matched_reply || null,
    matched_reply_id: correlation.matched_reply?.mid || null,
    latest_seen_incoming: correlation.latest_seen_incoming || null,
    reply_observed_at_ms: correlation.reply_observed_at_ms || null,
    attribution_confidence: confidence,
  };
}

function failurePayload({ code, hint, diagnosticContext, correlation, stats, extra = {} }) {
  const failure = classifyFailure(code);
  const safeStats = sanitizeStats(stats);

  return {
    ok: false,
    status: "fail",
    ...buildBasePayload(),
    failure,
    attribution_evidence: buildAttributionEvidence(
      correlation,
      code === "stale_chat_noise" ? "invalidated" : "absent"
    ),
    diagnostic_context: {
      ...(diagnosticContext || {}),
      ...(safeStats ? { stats: safeStats } : {}),
    },
    recommended_action: failure.recommended_action,
    ...(hint ? { hint } : {}),
    ...extra,
  };
}

export function buildSendDebugSnapshot(rawSnapshot, probeText, minMidExclusive = 0) {
  const messages = Array.isArray(rawSnapshot?.bubbles)
    ? rawSnapshot.bubbles.map(normalizeProbeMessage)
    : [];
  const normalizedProbeText = normalizeMessageText(probeText);
  const exactOutgoingMatches = messages
    .filter(
      (message) =>
        message.direction === "out" &&
        message.mid > minMidExclusive &&
        message.text === normalizedProbeText
    )
    .slice(-5)
    .map(summarizeMessage);
  const prefixOutgoingMatches = messages
    .filter(
      (message) =>
        message.direction === "out" &&
        message.mid > minMidExclusive &&
        normalizedProbeText.length > 0 &&
        message.text.length > normalizedProbeText.length &&
        message.text.startsWith(normalizedProbeText)
    )
    .slice(-5)
    .map(summarizeMessage);

  return {
    url: String(rawSnapshot?.url || ""),
    hash: String(rawSnapshot?.hash || ""),
    composer: {
      present: Boolean(rawSnapshot?.composer?.present),
      contenteditable: Boolean(rawSnapshot?.composer?.contenteditable),
      peer_id: rawSnapshot?.composer?.peerId ?? null,
      draft_text_length: Number(rawSnapshot?.composer?.draftTextLength || 0),
      draft_text_preview: previewText(rawSnapshot?.composer?.draftTextPreview || ""),
      draft_matches_probe:
        normalizeMessageText(rawSnapshot?.composer?.draftTextPreview || "") === normalizedProbeText,
    },
    send_button: {
      present: Boolean(rawSnapshot?.sendButton?.present),
      enabled: Boolean(rawSnapshot?.sendButton?.enabled),
      aria_label: previewText(rawSnapshot?.sendButton?.ariaLabel || "", 80),
      title: previewText(rawSnapshot?.sendButton?.title || "", 80),
    },
    active_element: {
      tag: String(rawSnapshot?.activeElement?.tag || ""),
      role: String(rawSnapshot?.activeElement?.role || ""),
      aria_label: previewText(rawSnapshot?.activeElement?.ariaLabel || "", 80),
      class_name: previewText(rawSnapshot?.activeElement?.className || "", 120),
    },
    verification_prompt_present: Boolean(rawSnapshot?.verificationPromptPresent),
    bubble_count: messages.length,
    exact_outgoing_probe_candidates: exactOutgoingMatches,
    prefixed_outgoing_probe_candidates: prefixOutgoingMatches,
    last_bubbles: messages.slice(-8).map(summarizeMessage),
  };
}

function successPayload({ targetValue, sentText, sentMessage, replyMessage, correlation, checks, failures, stats }) {
  const safeStats = sanitizeStats(stats);
  const ok = failures.length === 0;
  const recommendedAction = ok
    ? "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
    : "Inspect the reply quality checks and rerun after correcting the authoritative path.";

  return {
    ok,
    status: ok ? "pass" : "fail",
    ...buildBasePayload(),
    target: targetValue,
    sent_text: sentText,
    sent_mid: sentMessage.mid,
    reply_text: replyMessage.text,
    reply_mid: replyMessage.mid,
    checks,
    failures,
    failure: ok
      ? null
      : {
          ...classifyFailure("bot_no_response", "wait_reply"),
          summary: "The bot reply was observed but failed reply-quality checks",
        },
    attribution_evidence: buildAttributionEvidence(correlation, ok ? "proven" : "invalidated"),
    diagnostic_context: {
      ...(safeStats ? { stats: safeStats } : {}),
    },
    recommended_action: recommendedAction,
  };
}

async function locateSearchInput(page) {
  const candidates = [
    "input.input-search-input",
    'input[placeholder*="Search"]',
    'input[type="search"]',
    ".input-search input",
    ".sidebar-header input[type='text']",
  ];
  for (const c of candidates) {
    const loc = page.locator(c).first();
    if (await loc.isVisible().catch(() => false)) return loc;
  }
  return null;
}

async function locateComposer(page) {
  const candidates = [
    'div.input-message-input[contenteditable="true"][data-peer-id]',
    '.input-message-container div.input-message-input[contenteditable="true"]',
    'div.input-message-input[contenteditable="true"]',
    '.input-message-container [contenteditable="true"]',
    'div[contenteditable="true"]',
  ];
  for (const c of candidates) {
    const loc = page.locator(c).first();
    if (await loc.isVisible().catch(() => false)) return loc;
  }
  return null;
}

async function locateSendButton(page) {
  const candidates = [
    'button[aria-label*="Send" i]',
    'button[title*="Send" i]',
    ".btn-send",
    "button.send",
    ".new-message-send",
  ];
  for (const candidate of candidates) {
    const locator = page.locator(candidate).first();
    if (await locator.isVisible().catch(() => false)) return locator;
  }
  return null;
}

async function waitForOutgoingProbe(page, probeText, minMidExclusive, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await page.waitForTimeout(400);
    const nowMessages = await collectMessages(page);
    const sentMessage = findOutgoingProbeMessage(nowMessages, probeText, minMidExclusive);
    if (sentMessage) return sentMessage;
  }
  return null;
}

async function waitForTelegramUi(page, timeoutMs = 45_000) {
  const deadline = Date.now() + timeoutMs;
  let lastStats = null;

  while (Date.now() < deadline) {
    const search = await locateSearchInput(page);
    const stats = await page
      .evaluate(() => ({
        peers: document.querySelectorAll("[data-peer-id]").length,
        chats: document.querySelectorAll(".chatlist-chat, a.chatlist-chat").length,
        skeletons: document.querySelectorAll(".dialogs-placeholder-canvas, .shimmer-canvas, .skeleton").length,
        loginInputs: document.querySelectorAll(
          'input[type="tel"], input[autocomplete="tel"], [class*="qr" i], [data-testid*="qr" i]'
        ).length,
      }))
      .catch(() => ({ peers: 0, chats: 0, skeletons: 0, loginInputs: 0 }));

    lastStats = stats;

    if (search && (stats.peers > 0 || stats.chats > 0)) {
      return { ready: true, stats };
    }
    await page.waitForTimeout(1000);
  }

  return { ready: false, stats: lastStats };
}

async function collectMessages(page) {
  const messages = await page
    .evaluate(() => {
      const out = [];
      const bubbles = Array.from(document.querySelectorAll(".bubble"));
      for (const bubble of bubbles) {
        const className = (bubble.className || "").toString();
        const textNode =
          bubble.querySelector(".translatable-message") ||
          bubble.querySelector(".bubble-content") ||
          bubble;
        const text = (textNode.textContent || "").replace(/\s+/g, " ").trim();
        if (!text) continue;
        const midRaw = bubble.closest("[data-mid]")?.getAttribute("data-mid");
        const mid = midRaw ? Number(midRaw) : null;
        let direction = "unknown";
        if (className.includes(" is-in ")) direction = "in";
        if (className.includes(" is-out ")) direction = "out";
        if (className.includes(" service ")) direction = "service";
        out.push({ mid, direction, text });
      }
      return out.slice(-200);
    })
    .catch(() => []);
  return Array.isArray(messages) ? messages : [];
}

export async function waitForQuietWindowWithCollector({ collectMessagesFn, sleepFn, quietMs, maxWaitMs, baselineMaxMid }) {
  const startedAt = Date.now();
  let quietStartedAt = Date.now();
  let observedBaselineMaxMid = baselineMaxMid;
  let lastActivity = null;

  while (Date.now() - startedAt < maxWaitMs) {
    const messages = await collectMessagesFn();
    const newMessages = messages
      .map(normalizeProbeMessage)
      .filter((message) => message.mid > observedBaselineMaxMid)
      .sort((left, right) => left.mid - right.mid);

    if (newMessages.length > 0) {
      observedBaselineMaxMid = newMessages[newMessages.length - 1].mid;
      quietStartedAt = Date.now();
      lastActivity = {
        observed_max_mid: observedBaselineMaxMid,
        messages: newMessages.slice(-5).map(summarizeMessage),
      };
    }

    if (Date.now() - quietStartedAt >= quietMs) {
      return {
        ok: true,
        quietWindowWaitMs: Date.now() - startedAt,
        baselineMaxMid: observedBaselineMaxMid,
        lastActivity,
      };
    }

    await sleepFn(Math.min(1000, Math.max(250, Math.floor(quietMs / 3))));
  }

  const finalMessages = await collectMessagesFn();
  return {
    ok: false,
    quietWindowWaitMs: Date.now() - startedAt,
    baselineMaxMid: maxObservedMid(finalMessages),
    lastActivity,
    recentMessages: finalMessages.slice(-8).map(normalizeProbeMessage).map(summarizeMessage),
  };
}

async function waitForQuietWindow(page, quietMs, maxWaitMs, baselineMaxMid) {
  return waitForQuietWindowWithCollector({
    collectMessagesFn: () => collectMessages(page),
    sleepFn: (ms) => page.waitForTimeout(ms),
    quietMs,
    maxWaitMs,
    baselineMaxMid,
  });
}

export async function waitForReplySettleWithCollector({
  collectMessagesFn,
  sleepFn,
  settleMs,
  maxWaitMs,
  sentMid,
}) {
  const startedAt = Date.now();
  let firstReplyObservedAtMs = null;
  let lastChangeAt = null;
  let lastFingerprint = null;
  let latestIncoming = null;
  let stableReply = null;
  let stableReplyIsInterim = false;

  while (Date.now() - startedAt < maxWaitMs) {
    const messages = await collectMessagesFn();
    const replies = findAttributedReplies(messages, sentMid);
    latestIncoming = replies.length > 0 ? replies[replies.length - 1] : null;

    if (latestIncoming) {
      const currentFingerprint = messageFingerprint(latestIncoming);
      if (firstReplyObservedAtMs === null) {
        firstReplyObservedAtMs = Date.now();
      }
      if (currentFingerprint !== lastFingerprint) {
        lastFingerprint = currentFingerprint;
        lastChangeAt = Date.now();
        stableReply = latestIncoming;
        stableReplyIsInterim = isLikelyInterimReplyText(latestIncoming.text);
      }
      if (!stableReplyIsInterim && lastChangeAt !== null && Date.now() - lastChangeAt >= settleMs) {
        return {
          ok: true,
          settled: true,
          settleWaitMs: Date.now() - startedAt,
          replyObservedAtMs: firstReplyObservedAtMs,
          replyMessage: stableReply,
          latestIncoming,
        };
      }
    }

    await sleepFn(Math.min(1000, Math.max(250, Math.floor(settleMs / 3))));
  }

  return {
    ok: stableReply !== null && !stableReplyIsInterim,
    settled: false,
    settleWaitMs: Date.now() - startedAt,
    replyObservedAtMs: firstReplyObservedAtMs,
    replyMessage: stableReply,
    latestIncoming,
  };
}

async function waitForReplySettle(page, settleMs, maxWaitMs, sentMid) {
  return waitForReplySettleWithCollector({
    collectMessagesFn: () => collectMessages(page),
    sleepFn: (ms) => page.waitForTimeout(ms),
    settleMs,
    maxWaitMs,
    sentMid,
  });
}

async function findTargetChat(page, targetValue) {
  const targetParts = normalizeTarget(targetValue);
  const candidates = [
    "a.chatlist-chat[data-peer-id]",
    ".chatlist-chat[data-peer-id]",
    "a.chatlist-chat",
    ".chatlist-chat",
  ];

  let best = null;
  let bestScore = 0;

  const getScore = (textValue) => {
    const normalized = textValue.toLowerCase().replace(/\s+/g, " ").trim();
    if (!normalized) return 0;
    if (targetParts.raw && normalized.includes(targetParts.raw)) return 3;
    if (targetParts.noAt && normalized.includes(`@${targetParts.noAt}`)) return 2;
    if (targetParts.noAt && normalized.includes(targetParts.noAt)) return 1;
    return 0;
  };

  for (const sel of candidates) {
    const rows = page.locator(sel);
    const count = Math.min(await rows.count(), 80);
    for (let i = 0; i < count; i += 1) {
      const row = rows.nth(i);
      const visible = await row.isVisible().catch(() => false);
      if (!visible) continue;
      const raw = await row.innerText().catch(() => "");
      const score = getScore(raw);
      if (score > bestScore) {
        best = row;
        bestScore = score;
      }
      if (score >= 3) {
        return row;
      }
    }
  }

  return bestScore > 0 ? best : null;
}

async function verifyChatOpen(page, targetValue) {
  const targetParts = normalizeTarget(targetValue);
  return page
    .evaluate((parts) => {
      const hash = (location.hash || "").toLowerCase();
      const hashHasTarget = Boolean(parts.noAt && hash.includes(parts.noAt));
      const hasComposer = Boolean(
        document.querySelector(
          'div.input-message-input[contenteditable="true"][data-peer-id], .input-message-container [contenteditable="true"]'
        )
      );
      const hasChatPane = Boolean(document.querySelector(".chat, .chat-info-wrapper, .new-message-wrapper"));
      return {
        open: hashHasTarget || (hasComposer && hasChatPane),
        hashHasTarget,
        hasComposer,
        hasChatPane,
      };
    }, targetParts)
    .catch(() => ({ open: false, hashHasTarget: false, hasComposer: false, hasChatPane: false }));
}

async function collectSendDebugSnapshot(page, probeText, minMidExclusive = 0) {
  const rawSnapshot = await page
    .evaluate(() => {
      const composer =
        document.querySelector('div.input-message-input[contenteditable="true"][data-peer-id]') ||
        document.querySelector('.input-message-container div.input-message-input[contenteditable="true"]') ||
        document.querySelector('.input-message-container [contenteditable="true"]') ||
        document.querySelector('div[contenteditable="true"]');
      const sendButton =
        document.querySelector('button[aria-label*="Send" i]') ||
        document.querySelector('button[title*="Send" i]') ||
        document.querySelector('.btn-send, .send, .new-message-send');
      const activeElement = document.activeElement;
      const bubbles = Array.from(document.querySelectorAll(".bubble")).map((bubble) => {
        const className = (bubble.className || "").toString();
        const textNode =
          bubble.querySelector(".translatable-message") ||
          bubble.querySelector(".bubble-content") ||
          bubble;
        const text = (textNode.textContent || "").replace(/\s+/g, " ").trim();
        const midRaw = bubble.closest("[data-mid]")?.getAttribute("data-mid");
        let direction = "unknown";
        if (className.includes(" is-in ")) direction = "in";
        if (className.includes(" is-out ")) direction = "out";
        if (className.includes(" service ")) direction = "service";
        return {
          mid: midRaw ? Number(midRaw) : null,
          direction,
          text,
        };
      });

      return {
        url: location.href,
        hash: location.hash || "",
        composer: composer
          ? {
              present: true,
              contenteditable: composer.getAttribute("contenteditable") === "true",
              peerId: composer.getAttribute("data-peer-id"),
              draftTextLength: (composer.textContent || "").replace(/\s+/g, " ").trim().length,
              draftTextPreview: (composer.textContent || "").replace(/\s+/g, " ").trim(),
            }
          : { present: false },
        sendButton: sendButton
          ? {
              present: true,
              enabled: !sendButton.disabled && sendButton.getAttribute("aria-disabled") !== "true",
              ariaLabel: sendButton.getAttribute("aria-label") || "",
              title: sendButton.getAttribute("title") || "",
            }
          : { present: false },
        activeElement: activeElement
          ? {
              tag: activeElement.tagName || "",
              role: activeElement.getAttribute?.("role") || "",
              ariaLabel: activeElement.getAttribute?.("aria-label") || "",
              className: (activeElement.className || "").toString(),
            }
          : null,
        verificationPromptPresent: /verification code|enter the verification code/i.test(document.body?.innerText || ""),
        bubbles,
      };
    })
    .catch((error) => ({
      evaluate_error: error?.message || "send_debug_capture_failed",
      bubbles: [],
    }));

  const snapshot = buildSendDebugSnapshot(rawSnapshot, probeText, minMidExclusive);
  if (rawSnapshot?.evaluate_error) {
    snapshot.capture_error = rawSnapshot.evaluate_error;
  }
  return snapshot;
}

async function openTargetChat(page, search, targetValue, maxRetries = 1) {
  for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
    stage = "search";
    await search.click({ timeout: 10_000 });
    await search.fill("");
    await search.type(targetValue, { delay: 40 });
    await page.waitForTimeout(1200 + attempt * 400);

    stage = "chat_open";
    const chat = await findTargetChat(page, targetValue);
    if (chat) {
      await chat.click({ timeout: 10_000 });
      await page.waitForTimeout(1000 + attempt * 300);
      const verified = await verifyChatOpen(page, targetValue);
      lastChatOpenCheck = verified;
      if (verified.open) {
        chatOpenVerified = true;
        return true;
      }
    }

    if (attempt < maxRetries) {
      retriesUsed += 1;
      await page.keyboard.press("Escape").catch(() => {});
      await page.waitForTimeout(600 * (attempt + 1));
    }
  }
  return false;
}

async function pageStats(page) {
  return page
    .evaluate(() => ({
      url: location.href,
      peers: document.querySelectorAll("[data-peer-id]").length,
      chats: document.querySelectorAll(".chatlist-chat, a.chatlist-chat").length,
      skeletons: document.querySelectorAll(".dialogs-placeholder-canvas, .shimmer-canvas, .skeleton").length,
      hasSearch: !!document.querySelector("input.input-search-input, input[type='search'], input[placeholder*='Search']"),
      loginInputs: document.querySelectorAll(
        'input[type="tel"], input[autocomplete="tel"], [class*="qr" i], [data-testid*="qr" i]'
      ).length,
    }))
    .catch(() => ({ url: "", peers: 0, chats: 0, skeletons: 0, hasSearch: false, loginInputs: 0 }));
}

async function main() {
  let chromium;
  try {
    ({ chromium } = await import("playwright"));
  } catch {
    console.log(
      JSON.stringify(
        failurePayload({
          code: "environment_precondition",
          hint: "npm install playwright && npx playwright install chromium",
          diagnosticContext: {
            reason: "playwright_not_installed",
          },
        })
      )
    );
    process.exit(1);
  }

  const browser = await chromium.launch({ headless: !headed });
  if (!fs.existsSync(statePath)) {
    console.log(
      JSON.stringify(
        failurePayload({
          code: "missing_session_state",
          hint: `Run: node scripts/telegram-web-user-login.mjs --state ${statePath}`,
          diagnosticContext: {
            target,
            state_present: false,
            state_file: path.basename(statePath),
          },
        })
      )
    );
    await browser.close();
    process.exit(2);
  }

  const context = await browser.newContext({ storageState: statePath });
  const page = await context.newPage();

  try {
    await page.goto("https://web.telegram.org/k/", { waitUntil: "domcontentloaded", timeout: 60_000 });

    stage = "login";
    const ready = await waitForTelegramUi(page);
    if (!ready.ready) {
      console.log(
        JSON.stringify(
          failurePayload({
            code: ready.stats?.loginInputs > 0 ? "missing_session_state" : "ui_drift",
            hint: `Run: node scripts/telegram-web-user-login.mjs --state ${statePath}`,
            diagnosticContext: {
              target,
              state_present: true,
              login_state: ready.stats?.loginInputs > 0 ? "login_required" : "unknown",
            },
            stats: ready.stats,
          })
        )
      );
      process.exit(2);
    }

    stage = "search";
    const search = await locateSearchInput(page);
    if (!search) {
      console.log(
        JSON.stringify(
          failurePayload({
            code: "missing_session_state",
            hint: "Run: scripts/telegram-web-user-login.mjs",
            diagnosticContext: {
              target,
              state_present: true,
              login_state: "not_logged_in_or_ui_missing",
            },
            stats: await pageStats(page),
          })
        )
      );
      process.exit(2);
    }

    stage = "chat_open";
    const chatOpened = await openTargetChat(page, search, target, 2);
    if (!chatOpened) {
      console.log(
        JSON.stringify(
          failurePayload({
            code: "chat_open_failure",
            diagnosticContext: {
              target,
              chat_open_check: lastChatOpenCheck,
            },
            stats: await pageStats(page),
          })
        )
      );
      process.exit(3);
    }

    const initialMessages = await collectMessages(page);
    const initialBaselineMaxMid = maxObservedMid(initialMessages);

    stage = "quiet_window";
    const quietWindow = await waitForQuietWindow(
      page,
      quietWindowMs,
      Math.min(timeoutSec * 1000, Math.max(quietWindowMs * 4, 12_000)),
      initialBaselineMaxMid
    );

    if (!quietWindow.ok) {
      const correlation = buildCorrelationWindow({
        quietWindowMs,
        quietWindowWaitMs: quietWindow.quietWindowWaitMs,
        baselineMaxMid: quietWindow.baselineMaxMid,
        sentObservedAtMs: null,
        replyObservedAtMs: null,
        sentMessage: null,
        replyMessage: null,
        latestIncoming: null,
        lastPreSendActivity: quietWindow.lastActivity,
      });
      console.log(
        JSON.stringify(
          failurePayload({
            code: "stale_chat_noise",
            correlation,
            diagnosticContext: {
              target,
              recent_messages: quietWindow.recentMessages,
            },
            stats: await pageStats(page),
          })
        )
      );
      process.exit(3);
    }

    const beforeMessages = await collectMessages(page);
    const beforeMaxMid = maxObservedMid(beforeMessages);
    const priorVerificationPrompt = beforeMessages.some(
      (message) => message.direction === "in" && /verification code|enter the verification code/i.test(message.text)
    );
    const quietWindowWaitMs = quietWindow.quietWindowWaitMs;
    const lastPreSendActivity = quietWindow.lastActivity;
    const preSendInvalidIncoming = findInvalidIncomingActivityMessages(lastPreSendActivity?.messages || []);

    if (preSendInvalidIncoming.length > 0) {
      const correlation = buildCorrelationWindow({
        quietWindowMs,
        quietWindowWaitMs,
        baselineMaxMid: beforeMaxMid,
        sentObservedAtMs: null,
        replyObservedAtMs: null,
        sentMessage: null,
        replyMessage: null,
        latestIncoming: null,
        lastPreSendActivity,
      });
      console.log(
        JSON.stringify(
          failurePayload({
            code: "pre_send_invalid_activity",
            correlation,
            diagnosticContext: {
              target,
              recent_invalid_incoming: preSendInvalidIncoming,
            },
            stats: await pageStats(page),
          })
        )
      );
      process.exit(3);
    }

    stage = "composer";
    let composer = await locateComposer(page);
    for (let attempt = 0; !composer && attempt < composerRetries; attempt += 1) {
      retriesUsed += 1;
      await page.waitForTimeout(500 * (attempt + 1));
      await openTargetChat(page, search, target, 0);
      composer = await locateComposer(page);
    }

    if (!composer) {
      console.log(
        JSON.stringify(
          failurePayload({
            code: "ui_drift",
            diagnosticContext: {
              target,
              selector: "composer",
            },
            stats: await pageStats(page),
          })
        )
      );
      process.exit(3);
    }

    stage = "send";
    await composer.focus();
    await page.keyboard.press("ControlOrMeta+A");
    await page.keyboard.press("Backspace");
    await page.keyboard.type(text, { delay: 20 });
    const preSendDebug = debug ? await collectSendDebugSnapshot(page, text, beforeMaxMid) : null;
    let sendMethod = "enter";
    const sendButton = await locateSendButton(page);
    if (sendButton) {
      sendMethod = "button";
      await sendButton.click({ timeout: 5_000 }).catch(async () => {
        sendMethod = "enter";
        await page.keyboard.press("Enter");
      });
    } else {
      await page.keyboard.press("Enter");
    }

    const sentObservedAtMs = Date.now();
    let sentMessage = await waitForOutgoingProbe(page, text, beforeMaxMid, 2_500);

    if (!sentMessage && sendMethod === "button") {
      await composer.focus().catch(() => {});
      await page.keyboard.press("Enter").catch(() => {});
      sendMethod = "button_then_enter";
      sentMessage = await waitForOutgoingProbe(page, text, beforeMaxMid, Math.min(timeoutSec * 1000, 10_000));
    } else if (!sentMessage && sendMethod === "enter") {
      const retrySendButton = await locateSendButton(page);
      if (retrySendButton) {
        await retrySendButton.click({ timeout: 5_000 }).catch(() => {});
        sendMethod = "enter_then_button";
        sentMessage = await waitForOutgoingProbe(page, text, beforeMaxMid, Math.min(timeoutSec * 1000, 10_000));
      }
    }

    if (!sentMessage) {
      const postSendDebug = debug ? await collectSendDebugSnapshot(page, text, beforeMaxMid) : null;
      const correlation = buildCorrelationWindow({
        quietWindowMs,
        quietWindowWaitMs,
        baselineMaxMid: beforeMaxMid,
        sentObservedAtMs,
        replyObservedAtMs: null,
        sentMessage: null,
        replyMessage: null,
        latestIncoming: null,
        lastPreSendActivity,
      });
      console.log(
        JSON.stringify(
          failurePayload({
            code: "send_failure",
            correlation,
            diagnosticContext: {
              target,
              sent_text: text,
              send_method_attempted: sendMethod,
              chat_open_check: lastChatOpenCheck,
            },
            stats: await pageStats(page),
            extra:
              debug && (preSendDebug || postSendDebug)
                ? {
                    restricted_debug: {
                      send_method_attempted: sendMethod,
                      pre_send_snapshot: preSendDebug,
                      post_send_snapshot: postSendDebug,
                    },
                  }
                : {},
          })
        )
      );
      process.exit(4);
    }

    stage = "wait_reply";
    const deadline = Date.now() + timeoutSec * 1000;
    let settledReply = await waitForReplySettle(page, replySettleMs, timeoutSec * 1000, sentMessage.mid);
    settledReply = await extendReplySettlePastProgressPreface({
      initialResult: settledReply,
      deadlineMs: deadline,
      waitForReplySettleFn: (afterMid, maxWaitMs) => waitForReplySettle(page, replySettleMs, maxWaitMs, afterMid),
    });
    let replyMessage = settledReply.replyMessage;
    let latestIncoming = settledReply.latestIncoming;
    let replyObservedAtMs = settledReply.replyObservedAtMs;

    if (!replyMessage) {
      const nowMessages = await collectMessages(page);
      const outgoingSent = Boolean(findOutgoingProbeMessage(nowMessages, text, beforeMaxMid));
      const currentLatestIncoming = nowMessages
        .map(normalizeProbeMessage)
        .filter((message) => message.direction === "in" && message.text.length > 0)
        .slice(-1)[0];
      const verificationBlocked =
        priorVerificationPrompt ||
        Boolean(currentLatestIncoming && /verification code|enter the verification code/i.test(currentLatestIncoming.text));
      const correlation = buildCorrelationWindow({
        quietWindowMs,
        quietWindowWaitMs,
        replySettleMs,
        replySettleWaitMs: settledReply.settleWaitMs,
        baselineMaxMid: beforeMaxMid,
        sentObservedAtMs,
        replyObservedAtMs: null,
        sentMessage,
        replyMessage: null,
        latestIncoming: currentLatestIncoming,
        lastPreSendActivity,
      });

      console.log(
        JSON.stringify(
          failurePayload({
            code: "bot_no_response",
            correlation,
            diagnosticContext: {
              target,
              sent_text: text,
              send_method_attempted: sendMethod,
              timeout_seconds: timeoutSec,
              outgoing_sent: outgoingSent,
              possible_reason: verificationBlocked ? "bot_requires_verification_code" : null,
            },
            stats: await pageStats(page),
          })
        )
      );
      process.exit(5);
    }

    const replyText = replyMessage.text;
    const checks = {
      non_empty: replyText.length > 0,
      min_length: replyText.length >= minReplyLen,
      reply_settled: settledReply.settled === true,
      error_signature_clean: !isReplyErrorSignature(replyText),
      sensitive_signature_clean: !SENSITIVE_RE.test(replyText),
    };
    const failures = Object.entries(checks)
      .filter(([, ok]) => !ok)
      .map(([name]) => name);
    const correlation = buildCorrelationWindow({
      quietWindowMs,
      quietWindowWaitMs,
      replySettleMs,
      replySettleWaitMs: settledReply.settleWaitMs,
      baselineMaxMid: beforeMaxMid,
      sentObservedAtMs,
      replyObservedAtMs,
      sentMessage,
      replyMessage,
      latestIncoming,
      lastPreSendActivity,
    });
    const payload = successPayload({
      targetValue: target,
      sentText: text,
      sentMessage,
      replyMessage,
      correlation,
      checks,
      failures,
      stats: debug ? await pageStats(page) : null,
    });

    console.log(JSON.stringify(payload));
    process.exit(payload.ok ? 0 : 6);
  } finally {
    await browser.close();
  }
}

function isEntrypoint() {
  if (!process.argv[1]) return false;
  return import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isEntrypoint()) {
  await main();
}
