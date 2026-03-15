import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createPage, getPlaywright } from '../lib/browser_runtime.mjs';

const suiteId = process.env.TEST_SUITE_ID || 'e2e_browser_agent_factory_web_demo';
const suiteName = process.env.TEST_SUITE_NAME || suiteId;
const lane = process.env.TEST_LANE || 'e2e_browser';
const reportPath = process.env.TEST_REPORT_PATH || '';
const defaultTimeoutMs = Number(process.env.TEST_TIMEOUT || '60') * 1000;

const __filename = fileURLToPath(import.meta.url);
const projectRoot = path.resolve(path.dirname(__filename), '..', '..');
const adapterScript = path.join(projectRoot, 'scripts', 'agent-factory-web-adapter.py');
const assetsRoot = path.join(projectRoot, 'web', 'agent-factory-demo');
const serverPort = 18791;
const serverUrl = `http://127.0.0.1:${serverPort}`;
const stateRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-factory-web-demo-state-'));
const uploadFixturePath = path.join(stateRoot, 'input-example-browser.txt');
fs.writeFileSync(
  uploadFixturePath,
  'Счёт №77 от тестового поставщика\nСумма: 35000\nНужно выбрать маршрут согласования.',
  'utf8',
);

const cases = [];
const failures = [];
const skipped = [];
let serverProcess = null;
let serverStdout = '';
let serverStderr = '';

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

async function runCase(id, name, fn) {
  const testCase = { id, name, startedAt: now() };
  try {
    await fn();
    finishCase(testCase, 'passed');
  } catch (error) {
    finishCase(testCase, 'failed', error instanceof Error ? error.message : String(error));
  }
}

async function waitForHealth(url, timeoutMs) {
  const startedAt = now();
  while (now() - startedAt < timeoutMs) {
    if (serverProcess?.exitCode !== null) {
      throw new Error(`Web demo server exited early: ${serverStderr || serverStdout || 'no logs'}`);
    }
    try {
      const response = await fetch(`${url}/health`);
      if (response.ok) {
        return;
      }
    } catch {
      // Retry until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${url}/health`);
}

async function startServer() {
  serverProcess = spawn(
    'python3',
    [
      adapterScript,
      'serve',
      '--host',
      '127.0.0.1',
      '--port',
      String(serverPort),
      '--state-root',
      stateRoot,
      '--assets-root',
      assetsRoot,
    ],
    {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );

  serverProcess.stdout.on('data', (chunk) => {
    serverStdout += chunk.toString();
  });
  serverProcess.stderr.on('data', (chunk) => {
    serverStderr += chunk.toString();
  });

  await waitForHealth(serverUrl, defaultTimeoutMs);
}

async function stopServer() {
  if (!serverProcess) {
    return;
  }
  const processRef = serverProcess;
  if (processRef.exitCode === null) {
    processRef.kill('SIGINT');
    await new Promise((resolve) => setTimeout(resolve, 400));
  }
  if (processRef.exitCode === null) {
    processRef.kill('SIGKILL');
  }
  serverProcess = null;
}

async function sendFirstIdea(page) {
  await page.locator('#accessToken').fill('asc-demo-shared');
  await page.locator('[data-role="access-submit"]').click();
  await page.locator('#chatInput').fill('Нужен агент, который помогает быстрее разбирать заявки на оплату счетов и подсказывает, когда нужна эскалация.');
  await page.locator('#sendBtn').click();
  await page.locator('[data-role="connection-state"]').filter({ hasText: 'Подключен live adapter' }).waitFor({ state: 'visible', timeout: defaultTimeoutMs });
  await page.getByText('Кто будет основным пользователем или выгодоприобретателем результата?').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
}

async function run() {
  await startServer();
  const playwright = await getPlaywright();
  const browser = await playwright.chromium.launch({ headless: true });
  try {
    await runCase('e2e_browser_web_demo_shell_renders', 'Web demo shell renders browser entry surface', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await page.locator('#accessToken').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('#chatInput').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.getByText('Фабричный агент-бизнес-аналитик').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_web_demo_new_project_followup', 'Browser user gets the first live discovery follow-up question', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await sendFirstIdea(page);

        const visibleStatus = (await page.locator('[data-role="status-user-visible"]').textContent()) || '';
        const nextAction = (await page.locator('[data-role="status-next-action"]').textContent()) || '';
        const composerMode = (await page.locator('[data-role="composer-mode"]').textContent()) || '';

        assert(/Сбор требований продолжается/i.test(visibleStatus), `Expected browser-readable discovery status, got: ${visibleStatus}`);
        assert(/Ответить на следующий вопрос/i.test(nextAction), `Expected browser-readable next action, got: ${nextAction}`);
        assert(/Ответить/i.test(composerMode), `Composer should default to reply mode after the first follow-up, got: ${composerMode}`);
        assert(await page.locator('#messages .message').filter({ hasText: 'Кто будет основным пользователем' }).first().isVisible(), 'Chat transcript should render the first discovery follow-up question');
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_web_demo_accepts_file_attachment', 'Browser user can attach a file inside the chat composer', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await page.locator('#accessToken').fill('asc-demo-shared');
        await page.locator('[data-role="access-submit"]').click();
        await page.locator('#fileInput').setInputFiles(uploadFixturePath);
        await page.getByText('input-example-browser.txt').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('#chatInput').fill('Примеры приложил файлом.');
        await page.locator('#sendBtn').click();
        await page.locator('[data-role="connection-state"]').filter({ hasText: 'Подключен live adapter' }).waitFor({ state: 'visible', timeout: defaultTimeoutMs });

        const uploadCount = ((await page.locator('[data-role="status-upload-count"]').textContent()) || '').trim();
        assert(uploadCount === '1', `Expected one uploaded file in browser status, got: ${uploadCount}`);
        assert(
          await page.locator('#messages .message').filter({ hasText: 'input-example-browser.txt' }).first().isVisible(),
          'Chat transcript should render the attached file in the user message',
        );
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_web_demo_refresh_restores_session', 'Browser reload restores the active project and continues discovery', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await sendFirstIdea(page);

        const sessionBadgeBeforeReload = ((await page.locator('[data-role="session-badge"]').textContent()) || '').trim();
        assert(sessionBadgeBeforeReload.includes('web-demo-session-'), `Expected a persisted browser session badge before reload, got: ${sessionBadgeBeforeReload}`);

        await page.reload({ waitUntil: 'domcontentloaded' });
        await page.getByText('Сессия восстановлена').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('[data-role="status-operator-attention"]').filter({ hasText: 'Возобновляю browser-сессию' }).waitFor({ state: 'visible', timeout: defaultTimeoutMs });

        const sessionBadgeAfterReload = ((await page.locator('[data-role="session-badge"]').textContent()) || '').trim();
        const composerModeAfterReload = ((await page.locator('[data-role="composer-mode"]').textContent()) || '').trim();

        assert(sessionBadgeAfterReload === sessionBadgeBeforeReload, `Expected the same browser session after reload, got: ${sessionBadgeAfterReload}`);
        assert(/Ответить/i.test(composerModeAfterReload), `Composer should stay in reply mode after resume, got: ${composerModeAfterReload}`);

        await page.locator('#chatInput').fill('Оператор первой линии и руководитель смены.');
        await page.locator('#sendBtn').click();
        await page.getByText('Как этот процесс работает сейчас и где основные потери?').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
      } finally {
        await context.close();
      }
    });
  } finally {
    await browser.close();
    await stopServer();
    fs.rmSync(stateRoot, { recursive: true, force: true });
  }
}

(async () => {
  try {
    await run();
  } catch (error) {
    const testCase = {
      id: 'e2e_browser_web_demo_runtime_execution',
      name: 'Web demo browser harness execution',
      startedAt: now(),
    };
    const message = error instanceof Error ? error.message : String(error);
    finishCase(testCase, 'failed', `${message}\n${serverStderr || serverStdout}`.trim());
    await stopServer();
    fs.rmSync(stateRoot, { recursive: true, force: true });
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
})();
