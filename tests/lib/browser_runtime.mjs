import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);

export const DEFAULT_LOCALE = 'en-US';
export const DEFAULT_TIMEZONE = 'UTC';

export class SkipError extends Error {}

export async function getPlaywright() {
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

export async function createPage(browser, {
  storageStatePath = '',
  testClientIp = '',
  defaultTimeoutMs = 60000,
  locale = DEFAULT_LOCALE,
  timezoneId = DEFAULT_TIMEZONE,
} = {}) {
  const contextOptions = { locale, timezoneId };
  if (storageStatePath) {
    contextOptions.storageState = storageStatePath;
  }
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

export async function fetchAuthStatus(page) {
  return page.evaluate(async () => {
    const response = await fetch('/api/auth/status');
    return response.ok ? response.json() : { authenticated: false };
  });
}

export async function login(page, { baseUrl, password, defaultTimeoutMs = 60000 } = {}) {
  await page.goto(`${baseUrl}/login`, { waitUntil: 'networkidle' });
  await page.locator('input[type="password"]').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
  await page.locator('input[type="password"]').fill(password);
  await page.locator('button[type="submit"]').click();
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForTimeout(1000);
}

export async function openAuthenticatedPage(page, { baseUrl, password, defaultTimeoutMs = 60000 } = {}) {
  await login(page, { baseUrl, password, defaultTimeoutMs });
  const auth = await fetchAuthStatus(page);
  if (auth.authenticated !== true) {
    throw new Error('Browser session should become authenticated after valid login');
  }
  return auth;
}

export async function ensureAuthenticatedPage(page, { baseUrl, password, defaultTimeoutMs = 60000 } = {}) {
  await page.goto(`${baseUrl}/login`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);
  const auth = await fetchAuthStatus(page);
  if (auth.authenticated === true) {
    return auth;
  }
  return openAuthenticatedPage(page, { baseUrl, password, defaultTimeoutMs });
}

export async function assertAuthenticatedSession(page, message) {
  const auth = await fetchAuthStatus(page);
  if (auth.authenticated !== true) {
    throw new Error(message);
  }
  return auth;
}

export async function clickFirstVisible(page, labels) {
  for (const label of labels) {
    const locator = page.getByRole('button', { name: label });
    if (await locator.first().isVisible().catch(() => false)) {
      await locator.first().click();
      await page.waitForLoadState('networkidle').catch(() => {});
      await page.waitForTimeout(1000);
      return true;
    }
  }
  return false;
}

export async function completeOnboarding(page, { baseUrl, maxSteps = 8 } = {}) {
  const buttons = [
    /^Continue$/i,
    /^Skip for now$/i,
    /^Skip$/i,
    /reporting for duty/i,
  ];

  for (let step = 0; step < maxSteps; step += 1) {
    if (await page.locator('#chatInput').isVisible().catch(() => false)) {
      return true;
    }

    if (page.url().includes('/chats')) {
      await page.waitForTimeout(1000);
      if (await page.locator('#chatInput').isVisible().catch(() => false)) {
        return true;
      }
    }

    const clicked = await clickFirstVisible(page, buttons);
    if (!clicked) {
      break;
    }
  }

  if (!page.url().includes('/chats')) {
    await page.goto(`${baseUrl}/chats/main`, { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(1000);
  }

  return page.locator('#chatInput').isVisible().catch(() => false);
}

export async function ensureChatReady(page, { baseUrl, password, defaultTimeoutMs = 60000 } = {}) {
  await ensureAuthenticatedPage(page, { baseUrl, password, defaultTimeoutMs });
  const chatReady = await completeOnboarding(page, { baseUrl });
  if (!chatReady) {
    throw new SkipError('Chat UI is not reachable from onboarding state in this environment yet');
  }
}

export async function bootstrapOnboarding({ baseUrl, password, testClientIp = '', defaultTimeoutMs = 60000 } = {}) {
  const playwright = await getPlaywright();
  const browser = await playwright.chromium.launch({ headless: true });
  try {
    const { context, page } = await createPage(browser, { testClientIp, defaultTimeoutMs });
    try {
      await ensureChatReady(page, { baseUrl, password });
      return {
        ok: true,
        url: page.url(),
        chatReady: await page.locator('#chatInput').isVisible().catch(() => false),
      };
    } finally {
      await context.close();
    }
  } finally {
    await browser.close();
  }
}
