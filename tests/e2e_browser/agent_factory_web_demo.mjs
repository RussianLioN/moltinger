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
  await page.waitForFunction(() => {
    const submit = document.querySelector('#sendBtn');
    return submit?.dataset?.mode === 'send';
  }, { timeout: defaultTimeoutMs });
}

async function sendComposerReply(page, text) {
  const messageCountBefore = await page.locator('#messages .message').count();
  await page.locator('#chatInput').fill(text);
  await page.locator('#sendBtn').click();
  try {
    await page.waitForFunction(
      (previousCount) => {
        const messageCount = document.querySelectorAll('#messages .message').length;
        const submit = document.querySelector('#sendBtn');
        const isSendMode = submit?.dataset?.mode === 'send';
        return messageCount > previousCount && isSendMode;
      },
      messageCountBefore,
      { timeout: defaultTimeoutMs },
    );
  } catch (error) {
    const status = ((await page.locator('[data-role="status-user-visible"]').textContent()) || '').trim();
    const nextAction = ((await page.locator('[data-role="status-next-action"]').textContent()) || '').trim();
    const submitMode = (await page.locator('#sendBtn').getAttribute('data-mode')) || '';
    const messageCountNow = await page.locator('#messages .message').count();
    throw new Error(
      [
        `sendComposerReply-timeout: ${error instanceof Error ? error.message : String(error)}`,
        `text=${text.slice(0, 120)}`,
        `status=${status}`,
        `nextAction=${nextAction}`,
        `submitMode=${submitMode}`,
        `messageCountBefore=${messageCountBefore}`,
        `messageCountNow=${messageCountNow}`,
      ].join(' | '),
    );
  }
}

async function ensureAwaitingConfirmation(page) {
  const fallbackAnswer = "Фиксирую контракт результата: итоговый формат one-page PDF и markdown, обязательные блоки — профиль клиента, ключевые риски, рекомендация и итоговое решение.";
  const isAwaitingConfirmation = async () => {
    const status = ((await page.locator('[data-role="status-user-visible"]').textContent()) || '').trim().toLowerCase();
    const nextAction = ((await page.locator('[data-role="status-next-action"]').textContent()) || '').trim().toLowerCase();
    const panelMode = (((await page.locator('[data-role="side-panel"]').getAttribute('data-mode')) || '').trim()).toLowerCase();
    return (
      status === 'awaiting_confirmation'
      || status.includes('подтверж')
      || panelMode === 'brief_review'
      || nextAction.includes('подтверд')
    );
  };
  for (let attempt = 0; attempt < 4; attempt += 1) {
    if (await isAwaitingConfirmation()) {
      return;
    }
    try {
      await sendComposerReply(page, fallbackAnswer);
    } catch (error) {
      const nextAction = ((await page.locator('[data-role="status-next-action"]').textContent()) || '').trim();
      const panelMode = (await page.locator('[data-role="side-panel"]').getAttribute('data-mode')) || '';
      const submitMode = (await page.locator('#sendBtn').getAttribute('data-mode')) || '';
      const lastMessage = ((await page.locator('#messages .message').last().innerText()) || '').trim().slice(0, 220);
      throw new Error(
        [
          `awaiting-confirmation-timeout[${attempt + 1}]: ${error instanceof Error ? error.message : String(error)}`,
          `status=${((await page.locator('[data-role="status-user-visible"]').textContent()) || '').trim()}`,
          `nextAction=${nextAction}`,
          `panelMode=${panelMode}`,
          `submitMode=${submitMode}`,
          `lastMessage=${lastMessage}`,
        ].join(' | '),
      );
    }
  }
  const status = ((await page.locator('[data-role="status-user-visible"]').textContent()) || '').trim();
  const nextAction = ((await page.locator('[data-role="status-next-action"]').textContent()) || '').trim();
  const panelMode = (await page.locator('[data-role="side-panel"]').getAttribute('data-mode')) || '';
  const lastAgentMessage = ((await page.locator('#messages .message').last().innerText()) || '').trim();
  throw new Error(`Expected awaiting_confirmation stage before brief confirm, got status=${status}, nextAction=${nextAction}, panelMode=${panelMode}, last=${lastAgentMessage.slice(0, 200)}`);
}

async function completeDiscoveryToAwaitingConfirmation(page, options = {}) {
  const withUpload = Boolean(options.withUpload);
  await sendComposerReply(page, 'Пользователь — клиентский менеджер, выгодоприобретатели — члены кредитного комитета.');
  await sendComposerReply(page, 'Сейчас менеджер вручную собирает данные из CSV и Word, затем готовит PDF; много времени уходит на сверку и правки.');
  await sendComposerReply(page, 'На выходе нужен one-page PDF и markdown. Обязательные блоки: профиль клиента, ключевые риски, рекомендация и итоговое решение.');
  await sendComposerReply(page, 'В первую очередь агент помогает клиентскому менеджеру перед кредитным комитетом по каждой новой сделке.');
  if (withUpload) {
    await page.locator('#fileInput').setInputFiles(uploadFixturePath);
    await sendComposerReply(page, 'Примеры входных данных прикрепил файлом.');
  } else {
    await sendComposerReply(page, 'CSV-выгрузка по клиенту и комментарий менеджера по сделке.');
  }
  await sendComposerReply(page, 'Если данных не хватает или есть противоречия — обязательная эскалация; обязательные поля должны быть заполнены.');
  await sendComposerReply(page, 'Сократить время подготовки на 50% и снизить долю ошибок до 2%.');
  await ensureAwaitingConfirmation(page);
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

    await runCase('e2e_browser_web_demo_attachment_chip_is_one_shot', 'Attachment chip is cleared after send and not auto-reused', async () => {
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
        await page.waitForFunction(() => {
          const submit = document.querySelector('#sendBtn');
          return submit?.dataset?.mode === 'send';
        }, { timeout: defaultTimeoutMs });

        const composerAttachmentCount = await page.locator('[data-role="attachment-list"] .attachment-pill').count();
        assert(composerAttachmentCount === 0, `Composer attachment list should be cleared after successful send, got ${composerAttachmentCount}`);

        await page.locator('#chatInput').fill('Второй ответ без вложений.');
        await page.locator('#sendBtn').click();
        await page.waitForFunction(() => {
          const submit = document.querySelector('#sendBtn');
          return submit?.dataset?.mode === 'send';
        }, { timeout: defaultTimeoutMs });

        const secondUserMessage = page.locator('#messages .message--user').last();
        assert(await secondUserMessage.isVisible(), 'Second user bubble should be visible');
        const secondMessageAttachment = secondUserMessage.locator('.attachment-pill');
        assert((await secondMessageAttachment.count()) === 0, 'Second user bubble should not inherit previous attachment chips');
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_web_demo_pending_indicator_visible_during_response', 'Agent pending indicator is shown while awaiting response', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await page.locator('#accessToken').fill('asc-demo-shared');
        await page.locator('[data-role="access-submit"]').click();
        await page.locator('#chatInput').waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.locator('#chatInput').fill('Автоматизировать маршрутизацию согласования заявок на оплату.');
        await page.locator('#sendBtn').click();

        await page.waitForFunction(() => {
          const submit = document.querySelector('#sendBtn');
          const status = document.querySelector('[data-role="agent-status"]');
          return submit?.dataset?.mode === 'stop' && status && !status.hasAttribute('hidden');
        }, { timeout: defaultTimeoutMs });

        await page.waitForFunction(() => {
          const submit = document.querySelector('#sendBtn');
          const status = document.querySelector('[data-role="agent-status"]');
          return submit?.dataset?.mode === 'send' && Boolean(status?.hasAttribute('hidden'));
        }, { timeout: defaultTimeoutMs });
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

    await runCase('e2e_browser_web_demo_topbar_sticky_with_scroll', 'Topbar controls stay visible and sticky while chat scrolls', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await sendFirstIdea(page);
        await completeDiscoveryToAwaitingConfirmation(page);

        const topBefore = await page.locator('.workspace-topbar').boundingBox();
        await page.locator('[data-role="chat-log"]').evaluate((node) => {
          node.scrollTop = node.scrollHeight;
        });
        await page.waitForTimeout(100);
        const topAfter = await page.locator('.workspace-topbar').boundingBox();

        const delta = Math.abs((topAfter?.y || 0) - (topBefore?.y || 0));
        assert(delta <= 1, `Topbar should remain sticky while chat scrolls, delta=${delta}`);
        assert(await page.locator('[data-role="sidebar-toggle"]').isVisible(), 'Left topbar toggle should remain visible');
        assert(await page.locator('[data-role="side-panel-toggle"]').isVisible(), 'Right topbar toggle should remain visible');
      } finally {
        await context.close();
      }
    });

    await runCase('e2e_browser_web_demo_reopens_right_panel_after_text_confirm', 'Text confirmation reopens right panel in post-brief flow', async () => {
      const { context, page } = await createPage(browser, { defaultTimeoutMs });
      try {
        await page.goto(serverUrl, { waitUntil: 'domcontentloaded' });
        await sendFirstIdea(page);
        await completeDiscoveryToAwaitingConfirmation(page, { withUpload: true });
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

        try {
          await sendComposerReply(page, 'Подтверждаю brief.');
        } catch (error) {
          const status = ((await page.locator('[data-role="status-user-visible"]').textContent()) || '').trim();
          const nextAction = ((await page.locator('[data-role="status-next-action"]').textContent()) || '').trim();
          const panelHidden = await sidePanel.evaluate((node) => node.hasAttribute('hidden')).catch(() => true);
          const panelModeNow = (await sidePanel.getAttribute('data-mode')) || '';
          const toggleNow = (await sidePanelToggle.getAttribute('aria-pressed')) || '';
          const submitMode = (await page.locator('#sendBtn').getAttribute('data-mode')) || '';
          const lastAgentMessageNow = ((await page.locator('#messages .message').last().innerText()) || '').trim().slice(0, 220);
          throw new Error(
            [
              `confirm-send-timeout: ${error instanceof Error ? error.message : String(error)}`,
              `status=${status}`,
              `nextAction=${nextAction}`,
              `panelHidden=${panelHidden}`,
              `panelMode=${panelModeNow}`,
              `togglePressed=${toggleNow}`,
              `submitMode=${submitMode}`,
              `lastMessage=${lastAgentMessageNow}`,
            ].join(' | '),
          );
        }

        try {
          await page.waitForFunction(() => {
            const panel = document.querySelector('[data-role="side-panel"]');
            return Boolean(panel && !panel.hasAttribute('hidden'));
          }, { timeout: defaultTimeoutMs });
        } catch (error) {
          const status = ((await page.locator('[data-role="status-user-visible"]').textContent()) || '').trim();
          const nextAction = ((await page.locator('[data-role="status-next-action"]').textContent()) || '').trim();
          const panelHidden = await sidePanel.evaluate((node) => node.hasAttribute('hidden')).catch(() => true);
          const panelModeNow = (await sidePanel.getAttribute('data-mode')) || '';
          const toggleNow = (await sidePanelToggle.getAttribute('aria-pressed')) || '';
          const lastAgentMessageNow = ((await page.locator('#messages .message').last().innerText()) || '').trim().slice(0, 220);
          throw new Error(
            [
              error instanceof Error ? error.message : String(error),
              `status=${status}`,
              `nextAction=${nextAction}`,
              `panelHidden=${panelHidden}`,
              `panelMode=${panelModeNow}`,
              `togglePressed=${toggleNow}`,
              `lastMessage=${lastAgentMessageNow}`,
            ].join(' | '),
          );
        }
        const panelMode = await sidePanel.getAttribute('data-mode');
        const togglePressed = await sidePanelToggle.getAttribute('aria-pressed');

        assert(['downloads', 'preview'].includes((panelMode || '').toLowerCase()), `Expected right panel mode downloads/preview after text confirm, got: ${panelMode}`);
        assert(togglePressed === 'true', `Right panel toggle should be pressed after text confirm, got: ${togglePressed}`);

        const previewSection = page.locator('[data-role="preview-section"]');
        if (!(await previewSection.isVisible().catch(() => false))) {
          const previewButton = page.locator('[data-role="primary-artifact-preview"]');
          if (await previewButton.isVisible().catch(() => false)) {
            await previewButton.click();
          }
        }
        await previewSection.waitFor({ state: 'visible', timeout: defaultTimeoutMs });
        await page.waitForFunction(() => {
          const frame = document.querySelector('[data-role="preview-frame"]');
          return Boolean(frame && !frame.hasAttribute('hidden') && frame.getAttribute('srcdoc'));
        }, { timeout: defaultTimeoutMs });
        const previewSrcdoc = await page.locator('[data-role="preview-frame"]').getAttribute('srcdoc');
        assert(/One-page Summary|One-page summary/i.test(previewSrcdoc || ''), 'Preview should render one-page heading');
        assert((previewSrcdoc || '').length > 400, 'Preview should contain rendered one-page HTML content');
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
