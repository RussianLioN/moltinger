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
    'input[placeholder*="Search"]',
    'input[type="search"]',
    'div[contenteditable="true"][role="textbox"]',
  ];
  for (const c of candidates) {
    const loc = page.locator(c).first();
    if (await loc.isVisible().catch(() => false)) return loc;
  }
  return null;
}

async function locateComposer(page) {
  const candidates = [
    'div[contenteditable="true"][role="textbox"]',
    'div[contenteditable="true"][data-tab]',
    'div[contenteditable="true"]',
  ];
  for (const c of candidates) {
    const loc = page.locator(c).last();
    if (await loc.isVisible().catch(() => false)) return loc;
  }
  return null;
}

async function collectVisibleMessageTexts(page) {
  const texts = await page
    .evaluate(() => {
      const selectors = [
        ".Message .text-content",
        ".Message .text-content-wrap",
        ".message .text-content",
        ".bubble-content",
      ];
      const out = [];
      for (const sel of selectors) {
        const nodes = Array.from(document.querySelectorAll(sel));
        for (const n of nodes) {
          const t = (n.textContent || "").trim();
          if (t) out.push(t);
        }
      }
      return out;
    })
    .catch(() => []);
  return Array.isArray(texts) ? texts : [];
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

  const search = await locateSearchInput(page);
  if (!search) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Telegram Web is not logged in or UI not detected",
        hint: "Run: scripts/telegram-web-user-login.mjs",
      })
    );
    process.exit(2);
  }

  await search.click({ timeout: 10_000 });
  await search.fill("");
  await search.type(target, { delay: 40 });
  await page.keyboard.press("Enter");
  await page.waitForTimeout(1200);

  const before = await collectVisibleMessageTexts(page);
  const composer = await locateComposer(page);
  if (!composer) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Cannot find message composer in Telegram Web UI",
      })
    );
    process.exit(3);
  }

  await composer.click();
  await composer.fill("");
  await composer.type(text, { delay: 20 });
  await page.keyboard.press("Enter");

  const deadline = Date.now() + timeoutSec * 1000;
  let replyText = "";

  while (Date.now() < deadline) {
    await page.waitForTimeout(1500);
    const now = await collectVisibleMessageTexts(page);
    if (now.length <= before.length) continue;
    const delta = now.slice(before.length).filter((t) => t !== text);
    if (delta.length > 0) {
      replyText = delta[delta.length - 1];
      break;
    }
  }

  if (!replyText) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Timeout waiting for reply",
        target,
        sent_text: text,
        timeout_seconds: timeoutSec,
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
      checks,
      failures,
    })
  );
  process.exit(ok ? 0 : 5);
} finally {
  await browser.close();
}
