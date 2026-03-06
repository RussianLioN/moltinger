#!/usr/bin/env node
/**
 * telegram-web-user-login.mjs
 * One-time interactive login to Telegram Web and save browser state.
 *
 * No API_ID/API_HASH required.
 */

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const DEFAULT_STATE = process.env.TELEGRAM_WEB_STATE || ".telegram-web-state.json";
const DEFAULT_TIMEOUT_MS = Number(process.env.TELEGRAM_WEB_LOGIN_TIMEOUT_MS || 10 * 60 * 1000);

function getArg(name, fallback = "") {
  const idx = process.argv.indexOf(name);
  if (idx >= 0 && idx + 1 < process.argv.length) return process.argv[idx + 1];
  return fallback;
}

const statePath = path.resolve(getArg("--state", DEFAULT_STATE));
const timeoutMs = Number(getArg("--timeout-ms", String(DEFAULT_TIMEOUT_MS)));

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

const browser = await chromium.launch({ headless: false });
const context = await browser.newContext();
const page = await context.newPage();

try {
  await page.goto("https://web.telegram.org/k/", { waitUntil: "domcontentloaded", timeout: 60_000 });

  // Telegram Web is considered logged in only when real chat peers are visible.
  // Previous heuristics based on generic textboxes caused false positives.
  const loggedInSelectorCandidates = ['[data-peer-id]'];

  const deadline = Date.now() + timeoutMs;
  let loggedIn = false;

  while (Date.now() < deadline) {
    for (const sel of loggedInSelectorCandidates) {
      const found = await page.locator(sel).first().isVisible().catch(() => false);
      if (found) {
        loggedIn = true;
        break;
      }
    }
    if (loggedIn) break;
    await page.waitForTimeout(1000);
  }

  if (!loggedIn) {
    console.log(
      JSON.stringify({
        ok: false,
        status: "fail",
        error: "Login timeout. Complete login in browser and retry.",
        timeout_ms: timeoutMs,
      })
    );
    process.exitCode = 2;
  } else {
    await context.storageState({ path: statePath, indexedDB: true });
    console.log(
      JSON.stringify({
        ok: true,
        status: "pass",
        message: "Telegram Web login state saved (cookies + localStorage + indexedDB)",
        state: statePath,
      })
    );
  }
} finally {
  await browser.close();
}
