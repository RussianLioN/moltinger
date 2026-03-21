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
  await page.locator('[data-role="project-list"]').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
  await page.locator('#chatInput').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
  await page.locator('#chatInput').fill('Нужен агент, который помогает быстрее разбирать заявки на оплату счетов и подсказывает, когда нужна эскалация.');
  await page.locator('#sendBtn').click();
  await page.locator('#messages .message').filter({ hasText: 'Кто будет основным пользователем или выгодоприобретателем результата?' }).first().waitFor({ state: 'visible', timeout: defaultTimeoutMs });
}

async function sendComposerReply(page, text) {
  const messageCountBefore = await page.locator('#messages .message').count();
  await page.locator('#chatInput').fill(text);
  await page.locator('#sendBtn').click();
  await page.waitForFunction(
    (previousCount) => document.querySelectorAll('#messages .message').length > previousCount,
    messageCountBefore,
    { timeout: defaultTimeoutMs },
  );
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
        await page.getByText('Открой доступ к фабрике').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        assert(!(await page.locator('#chatInput').isVisible().catch(() => false)), 'Chat input should stay hidden before access is granted');

        await page.locator('#accessToken').fill('asc-demo-shared');
        await page.locator('[data-role="access-submit"]').click();
        await page.locator('#chatInput').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('[data-role="project-list"]').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('#messages .message').filter({ hasText: 'Какую конкретную бизнес-проблему должен решить будущий агент?' }).first().waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        assert(!(await page.locator('[data-role="home-panel"]').isVisible().catch(() => false)), 'Home screen should stay hidden when the default project already started');
        assert(!(await page.getByText('Подключен live adapter').isVisible().catch(() => false)), 'Primary workspace should not expose live adapter noise');
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_web_demo_new_project_followup', 'Browser user gets the first live discovery follow-up question', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await sendFirstIdea(page);
        await page.waitForFunction(() => {
          const sendButton = document.querySelector('#sendBtn');
          return sendButton?.dataset?.mode === 'send';
        }, { timeout: defaultTimeoutMs });

        const composerMode = (await page.locator('[data-role="composer-mode"]').textContent()) || '';
        const composerPlaceholder = (await page.locator('#chatInput').getAttribute('placeholder')) || '';
        const projectTitle = ((await page.locator('[data-role="project-title"]').textContent()) || '').trim();

        assert(/Ответ агенту-архитектору/i.test(composerMode), `Composer label should stay stable and concise, got: ${composerMode}`);
        assert(/Ответь на вопрос агента/i.test(composerPlaceholder), `Composer placeholder should prompt the next reply, got: ${composerPlaceholder}`);
        assert(projectTitle !== 'Новый проект', `Project title should be auto-generated after the first turn, got: ${projectTitle}`);
        assert(await page.locator('#messages .message').filter({ hasText: 'Кто будет основным пользователем' }).first().isVisible(), 'Chat transcript should render the first discovery follow-up question');
        assert(!(await page.locator('[data-role="home-panel"]').isVisible().catch(() => false)), 'Landing home screen should collapse after the first user turn');
        assert(!(await page.getByText('Подключен live adapter').isVisible().catch(() => false)), 'Live adapter details should stay outside the primary viewport');
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
        await page.locator('#chatInput').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('#fileInput').setInputFiles(uploadFixturePath);
        await page.getByText('input-example-browser.txt').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('#chatInput').fill('Примеры приложил файлом.');
        await page.locator('#sendBtn').click();
        await page.locator('#messages .message').filter({ hasText: 'Кто будет основным пользователем' }).first().waitFor({ state: 'visible', timeout: defaultTimeoutMs });

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

        const projectTitleBeforeReload = ((await page.locator('[data-role="project-title"]').textContent()) || '').trim();
        assert(projectTitleBeforeReload && projectTitleBeforeReload !== 'Новый проект', `Expected a generated project title before reload, got: ${projectTitleBeforeReload}`);

        await page.reload({ waitUntil: 'domcontentloaded' });
        await page.locator('#messages .message').filter({ hasText: 'Кто будет основным пользователем' }).first().waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        assert(!(await page.locator('#messages .message').filter({ hasText: 'Сессия восстановлена' }).first().isVisible().catch(() => false)), 'Resume should not inject extra system banners into chat feed');

        const projectTitleAfterReload = ((await page.locator('[data-role="project-title"]').textContent()) || '').trim();
        const composerModeAfterReload = ((await page.locator('[data-role="composer-mode"]').textContent()) || '').trim();

        assert(projectTitleAfterReload === projectTitleBeforeReload, `Expected the same project title after reload, got: ${projectTitleAfterReload}`);
        assert(/Ответ агенту-архитектору/i.test(composerModeAfterReload), `Composer should keep stable label after resume, got: ${composerModeAfterReload}`);

        await page.locator('#chatInput').fill('Оператор первой линии и руководитель смены.');
        await page.locator('#sendBtn').click();
        await page.locator('#messages .message__body').filter({ hasText: 'Как этот процесс работает сейчас и где основные потери?' }).waitFor({ state: 'visible', timeout: defaultTimeoutMs });
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_web_demo_reopens_right_panel_after_text_confirm', 'Text confirmation reopens right panel in post-brief flow', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await sendFirstIdea(page);

        await sendComposerReply(page, 'Пользователь — клиентский менеджер, выгодоприобретатели — члены кредитного комитета.');
        await sendComposerReply(page, 'Сейчас менеджер вручную собирает данные из CSV и Word, затем готовит PDF; много времени уходит на сверку и правки.');
        await sendComposerReply(page, 'На выходе нужен one-page PDF и markdown. Обязательные блоки: профиль клиента, ключевые риски, рекомендация и итоговое решение.');
        await sendComposerReply(page, 'В первую очередь агент помогает клиентскому менеджеру перед кредитным комитетом по каждой новой сделке.');
        await sendComposerReply(page, 'CSV-выгрузка по клиенту и комментарий менеджера по сделке.');
        await sendComposerReply(page, 'Если данных не хватает или есть противоречия — обязательная эскалация; обязательные поля должны быть заполнены.');
        await sendComposerReply(page, 'Сократить время подготовки на 50% и снизить долю ошибок до 2%.');

        const lastAgentMessage = ((await page.locator('#messages .message').last().innerText()) || '').trim();
        if (/контракт результата|формате агент отда[её]т итог|обязательные блоки/i.test(lastAgentMessage)) {
          await sendComposerReply(page, 'Итоговый формат: one-page PDF и markdown. Обязательные блоки: профиль клиента, ключевые риски, рекомендация и итоговое решение.');
        }

        await page.locator('#messages .message').filter({ hasText: 'подтверди' }).last().waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        const sidePanel = page.locator('[data-role="side-panel"]');
        const sidePanelClose = page.locator('[data-role="side-panel-close"]');
        const sidePanelToggle = page.locator('[data-role="side-panel-toggle"]');

        if (await sidePanelClose.isVisible().catch(() => false)) {
          await sidePanelClose.click();
          await page.waitForFunction(() => {
            const panel = document.querySelector('[data-role="side-panel"]');
            return Boolean(panel?.hasAttribute('hidden'));
          }, { timeout: defaultTimeoutMs });
        }

        await sendComposerReply(page, 'Подтверждаю brief.');

        await page.waitForFunction(() => {
          const panel = document.querySelector('[data-role="side-panel"]');
          return Boolean(panel && !panel.hasAttribute('hidden'));
        }, { timeout: defaultTimeoutMs });
        const panelMode = await sidePanel.getAttribute('data-mode');
        const togglePressed = await sidePanelToggle.getAttribute('aria-pressed');

        assert(['downloads', 'preview'].includes((panelMode || '').toLowerCase()), `Expected right panel mode downloads/preview after text confirm, got: ${panelMode}`);
        assert(togglePressed === 'true', `Right panel toggle should be pressed after text confirm, got: ${togglePressed}`);
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
