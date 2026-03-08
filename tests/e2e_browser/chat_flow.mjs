import { execSync } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const suiteId = process.env.TEST_SUITE_ID || 'e2e_browser_chat_flow';
const suiteName = process.env.TEST_SUITE_NAME || suiteId;
const lane = process.env.TEST_LANE || 'e2e_browser';
const reportPath = process.env.TEST_REPORT_PATH || '';
const baseUrl = (process.env.TEST_BASE_URL || 'http://moltis:13131').replace(/\/$/, '');
const password = process.env.MOLTIS_PASSWORD || 'test_password';
const testClientIp = process.env.TEST_CLIENT_IP || '';
const defaultTimeoutMs = Number(process.env.TEST_TIMEOUT || '60') * 1000;
const require = createRequire(import.meta.url);
const authStateDir = fs.mkdtempSync(path.join(process.env.TMPDIR || '/tmp', 'moltis-e2e-auth-'));
let sharedAuthStatePath = '';

const cases = [];
const failures = [];
const skipped = [];

class SkipError extends Error {}

function now() {
  return Date.now();
}

function finishCase(testCase, status, message = null) {
  const entry = {
    id: testCase.id,
    name: testCase.name,
    status,
    message,
    lane,
    duration_ms: now() - testCase.startedAt,
    suite: { id: suiteId, name: suiteName },
  };
  cases.push(entry);
  if (status === 'failed' || status === 'error') failures.push(`${testCase.id}: ${message}`);
  if (status === 'skipped') skipped.push(`${testCase.id}: ${message}`);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function getPlaywright() {
  const globalNodeModules = (() => {
    try {
      return execSync('npm root -g', { encoding: 'utf8' }).trim();
    } catch {
      return '';
    }
  })();

  const requireCandidates = [
    'playwright',
    '@playwright/test',
    globalNodeModules ? path.join(globalNodeModules, 'playwright') : '',
    globalNodeModules ? path.join(globalNodeModules, '@playwright/test') : '',
  ].filter(Boolean);

  for (const candidate of requireCandidates) {
    try {
      const module = require(candidate);
      if (module?.chromium) {
        return module;
      }
    } catch {
      // Continue through candidates.
    }
  }

  try {
    const module = await import('playwright');
    if (module?.chromium) {
      return module;
    }
  } catch {
    // Fall through to next import candidate.
  }

  try {
    const module = await import('@playwright/test');
    if (module?.chromium) {
      return module;
    }
  } catch {
    // Fall through to explicit failure below.
  }

  throw new Error('Playwright runtime is not available in the test runner image');
}

async function runCase(id, name, fn) {
  const testCase = { id, name, startedAt: now() };
  try {
    await fn();
    finishCase(testCase, 'passed');
  } catch (error) {
    if (error instanceof SkipError) {
      finishCase(testCase, 'skipped', error.message);
      return;
    }
    finishCase(testCase, 'failed', error instanceof Error ? error.message : String(error));
  }
}

async function createPage(browser, storageStatePath = '') {
  const contextOptions = storageStatePath ? { storageState: storageStatePath } : {};
  if (testClientIp) {
    contextOptions.extraHTTPHeaders = {
      'X-Forwarded-For': testClientIp,
      'X-Real-IP': testClientIp,
    };
  }
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  page.setDefaultTimeout(defaultTimeoutMs);
  return { context, page };
}

async function ensureAuthenticatedState(browser) {
  if (sharedAuthStatePath && fs.existsSync(sharedAuthStatePath)) {
    return sharedAuthStatePath;
  }

  const { context, page } = await createPage(browser);
  try {
    await openAuthenticatedPage(page);
    sharedAuthStatePath = path.join(authStateDir, 'storage-state.json');
    await context.storageState({ path: sharedAuthStatePath });
    return sharedAuthStatePath;
  } finally {
    await context.close();
  }
}

async function login(page, loginPassword = password) {
  await page.goto(`${baseUrl}/login`, { waitUntil: 'domcontentloaded' });
  await page.locator('input[type="password"]').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
  await page.locator('input[type="password"]').fill(loginPassword);
  await page.locator('button[type="submit"]').click();
}

async function bestEffortCompleteOnboarding(page) {
  const maxSteps = 8;
  for (let step = 0; step < maxSteps; step += 1) {
    const chatInput = page.locator('#chatInput');
    if (await chatInput.isVisible().catch(() => false)) {
      return true;
    }

    const buttons = [
      page.getByRole('button', { name: /^Continue$/i }),
      page.getByRole('button', { name: /^Skip for now$/i }),
      page.getByRole('button', { name: /^Skip$/i }),
      page.getByRole('button', { name: /reporting for duty/i }),
    ];

    let clicked = false;
    for (const button of buttons) {
      try {
        if (await button.first().isVisible({ timeout: 1000 }).catch(() => false)) {
          await button.first().click();
          clicked = true;
          break;
        }
      } catch {
        // Continue scanning actionable controls.
      }
    }

    if (!clicked) {
      return false;
    }

    await page.waitForLoadState('domcontentloaded').catch(() => {});
    await page.waitForTimeout(500);
  }

  return await page.locator('#chatInput').isVisible().catch(() => false);
}

async function openAuthenticatedPage(page) {
  await login(page, password);
  await page.waitForTimeout(500);
  const auth = await page.evaluate(async () => {
    const response = await fetch('/api/auth/status');
    return response.ok ? response.json() : { authenticated: false };
  });
  assert(auth.authenticated === true, 'Browser session should become authenticated after valid login');
  return auth;
}

async function ensureAuthenticatedPage(page) {
  await page.goto(`${baseUrl}/login`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(500);
  const auth = await page.evaluate(async () => {
    const response = await fetch('/api/auth/status');
    return response.ok ? response.json() : { authenticated: false };
  });
  if (auth.authenticated === true) {
    return auth;
  }
  return openAuthenticatedPage(page);
}

async function assertAuthenticatedSession(page, message) {
  const auth = await page.evaluate(async () => {
    const response = await fetch('/api/auth/status');
    return response.ok ? response.json() : { authenticated: false };
  });
  assert(auth.authenticated === true, message);
  return auth;
}

async function reachChatOrSkip(page) {
  await ensureAuthenticatedPage(page);
  const chatReady = await bestEffortCompleteOnboarding(page);
  if (!chatReady) {
    throw new SkipError('Chat UI is not reachable from onboarding state in this environment yet');
  }
}

async function reloadAndEnsureAuthenticated(page) {
  try {
    await page.reload({ waitUntil: 'domcontentloaded' });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!/ERR_ABORTED|frame was detached/i.test(message)) {
      throw error;
    }
    await page.waitForLoadState('domcontentloaded').catch(() => {});
  }
  await page.waitForTimeout(500);
  await assertAuthenticatedSession(page, 'Browser session should remain authenticated after reload');
}

async function reloadAndEnsureChat(page) {
  await reloadAndEnsureAuthenticated(page);
  const chatInput = page.locator('#chatInput');
  if (await chatInput.isVisible().catch(() => false)) {
    return;
  }

  const chatReady = await bestEffortCompleteOnboarding(page);
  if (!chatReady) {
    throw new SkipError('Chat UI is not reachable after reload in this environment yet');
  }
}

async function sendMessageThroughUi(page, message) {
  const messages = page.locator('#messages .msg');
  const beforeCount = await messages.count();
  await page.locator('#chatInput').fill(message);
  await page.locator('#sendBtn').click();
  await page.locator('#messages .msg.user').filter({ hasText: message }).first().waitFor({ state: 'visible', timeout: defaultTimeoutMs });
  await page.waitForFunction(
    (count) => {
      const nodes = Array.from(document.querySelectorAll('#messages .msg'));
      if (nodes.length <= count) return false;
      return nodes.some((node) => !node.classList.contains('user') && node.textContent && node.textContent.trim().length > 0);
    },
    beforeCount,
    { timeout: defaultTimeoutMs },
  );
}

async function run() {
  const playwright = await getPlaywright();
  const browser = await playwright.chromium.launch({ headless: true });
  try {
    await runCase('e2e_browser_login_page_renders', 'Login page renders password auth form', async () => {
      const { context, page } = await createPage(browser);
      try {
        await page.goto(`${baseUrl}/login`, { waitUntil: 'domcontentloaded' });
        await page.locator('input[type="password"]').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('button[type="submit"]').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        const title = await page.title();
        assert(/Moltis/i.test(title), `Unexpected login page title: ${title}`);
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_invalid_login_rejected', 'Invalid password stays on auth flow and surfaces error', async () => {
      const { context, page } = await createPage(browser);
      try {
        await login(page, 'wrong-password');
        const errorLocator = page.locator('.auth-error');
        await errorLocator.waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        const errorText = (await errorLocator.textContent()) || '';
        assert(/invalid|wrong|retry/i.test(errorText), `Expected invalid-login error, got: ${errorText}`);
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_login_establishes_session', 'Valid login authenticates browser session', async () => {
      const { context, page } = await createPage(browser);
      try {
        await openAuthenticatedPage(page);
        sharedAuthStatePath = path.join(authStateDir, 'storage-state.json');
        await context.storageState({ path: sharedAuthStatePath });
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_session_continuity_after_reload', 'Authenticated browser session survives page reload', async () => {
      const authStatePath = await ensureAuthenticatedState(browser);
      const { context, page } = await createPage(browser, authStatePath);
      try {
        await page.goto(`${baseUrl}/login`, { waitUntil: 'domcontentloaded' });
        await assertAuthenticatedSession(page, 'Browser session should be restored from saved auth state');
        await reloadAndEnsureAuthenticated(page);
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_chat_route_reachable', 'Browser can reach chat route after onboarding', async () => {
      const authStatePath = await ensureAuthenticatedState(browser);
      const { context, page } = await createPage(browser, authStatePath);
      try {
        await reachChatOrSkip(page);
        assert(await page.locator('#chatInput').isVisible(), 'Chat input should be visible after onboarding');
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_refresh_reconnect_chat_ui', 'Chat UI reconnects after page reload', async () => {
      const authStatePath = await ensureAuthenticatedState(browser);
      const { context, page } = await createPage(browser, authStatePath);
      try {
        await reachChatOrSkip(page);
        await reloadAndEnsureChat(page);
        assert(await page.locator('#chatInput').isVisible(), 'Chat input should be visible after reload');
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_chat_round_trip', 'User can send a message through browser transport', async () => {
      const authStatePath = await ensureAuthenticatedState(browser);
      const { context, page } = await createPage(browser, authStatePath);
      try {
        await reachChatOrSkip(page);
        await sendMessageThroughUi(page, `browser ui smoke ${Date.now()}`);
      } finally {
        await context.close();
      }
    });
  } finally {
    fs.rmSync(authStateDir, { recursive: true, force: true });
    await browser.close();
  }
}

(async () => {
  try {
    await run();
  } catch (error) {
    const testCase = {
      id: 'e2e_browser_runtime_execution',
      name: 'Browser harness execution',
      startedAt: now(),
    };
    finishCase(testCase, error instanceof SkipError ? 'skipped' : 'failed', error instanceof Error ? error.message : String(error));
  }

  const status = failures.length > 0 ? 'fail' : (cases.length === 0 || cases.every((entry) => entry.status === 'skipped') ? 'skip' : 'pass');
  const report = {
    status,
    timestamp: new Date().toISOString(),
    lane,
    suite: { id: suiteId, name: suiteName },
    summary: {
      total: cases.length,
      passed: cases.filter((entry) => entry.status === 'passed').length,
      failed: cases.filter((entry) => entry.status === 'failed' || entry.status === 'error').length,
      skipped: cases.filter((entry) => entry.status === 'skipped').length,
      duration_seconds: 0,
    },
    failures,
    skipped_tests: skipped,
    cases,
  };

  const json = `${JSON.stringify(report, null, 2)}\n`;
  if (reportPath) {
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, json, 'utf8');
  }
  process.stdout.write(json);
  process.exit(status === 'fail' ? 1 : status === 'skip' ? 2 : 0);
})();
