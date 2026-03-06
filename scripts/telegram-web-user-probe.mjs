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

const DEFAULT_STATE = process.env.TELEGRAM_WEB_STATE || ".telegram-web-state.json";
const DEFAULT_TARGET = process.env.TELEGRAM_WEB_TARGET || "@moltinger_bot";
const DEFAULT_MESSAGE = process.env.TELEGRAM_WEB_MESSAGE || "/status";
const DEFAULT_TIMEOUT_SEC = Number(process.env.TELEGRAM_WEB_TIMEOUT_SECONDS || 45);
const DEFAULT_MIN_REPLY_LEN = Number(process.env.TELEGRAM_WEB_MIN_REPLY_LEN || 2);

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
const headed = hasFlag("--headed");
const debug = hasFlag("--debug");

const ERROR_RE = /(traceback|exception|stack\s*trace|panic|internal server error)/i;
const SENSITIVE_RE = /\b(api[_ -]?key|token|password|secret)\b/i;

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.log(
    JSON.stringify({
      ok: false,
      status: "fail",
      error: "Playwright is not installed",
      hint: "npm install playwright && npx playwright install chromium",
    })
  );
  process.exit(1);
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

async function findTargetChat(page, targetValue) {
  const targetLower = targetValue.toLowerCase();
  const targetNoAt = targetLower.startsWith("@") ? targetLower.slice(1) : targetLower;
  const candidates = [
    "a.chatlist-chat[data-peer-id]",
    ".chatlist-chat[data-peer-id]",
    "a.chatlist-chat",
    ".chatlist-chat",
  ];

  let firstVisible = null;
  for (const sel of candidates) {
    const rows = page.locator(sel);
    const count = Math.min(await rows.count(), 80);
    for (let i = 0; i < count; i += 1) {
      const row = rows.nth(i);
      const visible = await row.isVisible().catch(() => false);
      if (!visible) continue;
      if (!firstVisible) firstVisible = row;
      const raw = await row.innerText().catch(() => "");
      const textRow = raw.toLowerCase().replace(/\s+/g, " ").trim();
      if (textRow.includes(targetLower) || textRow.includes(targetNoAt)) return row;
    }
  }

  return firstVisible;
}

async function pageStats(page) {
  return page
    .evaluate(() => ({
      url: location.href,
      peers: document.querySelectorAll("[data-peer-id]").length,
      chats: document.querySelectorAll(".chatlist-chat, a.chatlist-chat").length,
      skeletons: document.querySelectorAll(".dialogs-placeholder-canvas, .shimmer-canvas, .skeleton").length,
      hasSearch: !!document.querySelector("input.input-search-input, input[type='search'], input[placeholder*='Search']"),
    }))
    .catch(() => ({ url: "", peers: 0, chats: 0, skeletons: 0, hasSearch: false }));
}

const browser = await chromium.launch({ headless: !headed });
if (!fs.existsSync(statePath)) {
  console.log(
    JSON.stringify({
      ok: false,
      status: "fail",
      error: "Telegram Web state file not found",
      state: statePath,
      hint: "Run: node scripts/telegram-web-user-login.mjs --state " + statePath,
    })
  );
  await browser.close();
  process.exit(2);
}

const context = await browser.newContext({ storageState: statePath });
const page = await context.newPage();

try {
  await page.goto("https://web.telegram.org/k/", { waitUntil: "domcontentloaded", timeout: 60_000 });

  const ready = await waitForTelegramUi(page);
  if (!ready.ready) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Telegram Web UI did not become ready in time",
        stats: ready.stats,
        hint: "Run: node scripts/telegram-web-user-login.mjs --state " + statePath,
      })
    );
    process.exit(2);
  }

  const search = await locateSearchInput(page);
  if (!search) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Telegram Web is not logged in or UI not detected",
        hint: "Run: scripts/telegram-web-user-login.mjs",
        stats: await pageStats(page),
      })
    );
    process.exit(2);
  }

  await search.click({ timeout: 10_000 });
  await search.fill("");
  await search.type(target, { delay: 40 });
  await page.waitForTimeout(1500);

  const chat = await findTargetChat(page, target);
  if (!chat) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Cannot locate target chat in Telegram Web UI",
        target,
        stats: await pageStats(page),
      })
    );
    process.exit(3);
  }
  await chat.click({ timeout: 10_000 });
  await page.waitForTimeout(1500);

  const beforeMessages = await collectMessages(page);
  const beforeMaxMid = beforeMessages.reduce((max, m) => {
    const mid = Number.isFinite(m.mid) ? m.mid : 0;
    return mid > max ? mid : max;
  }, 0);
  const priorVerificationPrompt = beforeMessages.some(
    (m) => m.direction === "in" && /verification code|enter the verification code/i.test(m.text)
  );
  const composer = await locateComposer(page);
  if (!composer) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Cannot find message composer in Telegram Web UI",
        stats: await pageStats(page),
      })
    );
    process.exit(3);
  }

  await composer.focus();
  await page.keyboard.press("ControlOrMeta+A");
  await page.keyboard.press("Backspace");
  await page.keyboard.type(text, { delay: 20 });
  await page.keyboard.press("Enter");

  const deadline = Date.now() + timeoutSec * 1000;
  let replyText = "";
  let replyMid = 0;

  while (Date.now() < deadline) {
    await page.waitForTimeout(1500);
    const nowMessages = await collectMessages(page);
    const incoming = nowMessages.filter(
      (m) =>
        m.direction === "in" &&
        typeof m.text === "string" &&
        m.text.length > 0 &&
        (Number.isFinite(m.mid) ? m.mid > beforeMaxMid : false)
    );
    if (incoming.length > 0) {
      const msg = incoming[incoming.length - 1];
      replyText = msg.text;
      replyMid = Number(msg.mid || 0);
      break;
    }
  }

  if (!replyText) {
    const nowMessages = await collectMessages(page);
    const outgoingSent = nowMessages.some((m) => m.direction === "out" && m.text.includes(text));
    const latestIncoming = nowMessages
      .filter((m) => m.direction === "in" && typeof m.text === "string" && m.text.length > 0)
      .slice(-1)[0];
    const verificationBlocked =
      priorVerificationPrompt ||
      Boolean(latestIncoming && /verification code|enter the verification code/i.test(latestIncoming.text));

    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Timeout waiting for reply",
        target,
        sent_text: text,
        timeout_seconds: timeoutSec,
        outgoing_sent: outgoingSent,
        possible_reason: verificationBlocked ? "bot_requires_verification_code" : undefined,
        stats: await pageStats(page),
      })
    );
    process.exit(4);
  }

  const checks = {
    non_empty: replyText.length > 0,
    min_length: replyText.length >= minReplyLen,
    error_signature_clean: !ERROR_RE.test(replyText),
    sensitive_signature_clean: !SENSITIVE_RE.test(replyText),
  };
  const failures = Object.entries(checks)
    .filter(([, ok]) => !ok)
    .map(([name]) => name);

  const ok = failures.length === 0;
  console.log(
    JSON.stringify({
      ok,
      status: ok ? "pass" : "fail",
      target,
      sent_text: text,
      reply_text: replyText,
      reply_mid: replyMid,
      checks,
      failures,
      ...(debug ? { stats: await pageStats(page) } : {}),
    })
  );
  process.exit(ok ? 0 : 5);
} finally {
  await browser.close();
}
