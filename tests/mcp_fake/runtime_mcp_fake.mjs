import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

const suiteId = process.env.TEST_SUITE_ID || 'mcp_fake_runtime';
const suiteName = process.env.TEST_SUITE_NAME || suiteId;
const lane = process.env.TEST_LANE || 'mcp_fake';
const reportPath = process.env.TEST_REPORT_PATH || '';

const cases = [];
const failures = [];
const skipped = [];

function now() {
  return Date.now();
}

function startCase(name) {
  return { id: name, name, startedAt: now() };
}

function finishCase(test, status, message = null) {
  const entry = {
    id: test.id,
    name: test.name,
    status,
    message,
    lane,
    duration_ms: now() - test.startedAt,
    suite: { id: suiteId, name: suiteName },
  };
  cases.push(entry);
  if (status === 'failed' || status === 'error') failures.push(`${test.name}: ${message}`);
  if (status === 'skipped') skipped.push(`${test.name}: ${message}`);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function encode(message) {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  return Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'utf8'), body]);
}

function createClient() {
  const serverPath = path.resolve('tests/mcp_fake/fakes/stdio_server.mjs');
  const child = spawn(process.execPath, [serverPath], { stdio: ['pipe', 'pipe', 'pipe'] });
  let buffer = Buffer.alloc(0);
  const pending = new Map();
  let nextId = 1;

  child.stdout.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (true) {
      const separatorIndex = buffer.indexOf('\r\n\r\n');
      if (separatorIndex === -1) return;
      const header = buffer.slice(0, separatorIndex).toString('utf8');
      const match = header.match(/Content-Length:\s*(\d+)/i);
      if (!match) throw new Error('Missing Content-Length');
      const length = Number(match[1]);
      const start = separatorIndex + 4;
      if (buffer.length < start + length) return;
      const body = buffer.slice(start, start + length).toString('utf8');
      buffer = buffer.slice(start + length);
      const payload = JSON.parse(body);
      const resolver = pending.get(payload.id);
      if (resolver) {
        pending.delete(payload.id);
        resolver(payload);
      }
    }
  });

  async function request(method, params = {}) {
    const id = nextId++;
    const payload = { jsonrpc: '2.0', id, method, params };
    const response = new Promise((resolve, reject) => {
      pending.set(id, resolve);
      setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`Timeout waiting for ${method}`));
        }
      }, 5000);
    });
    child.stdin.write(encode(payload));
    return response;
  }

  function notify(method, params = {}) {
    child.stdin.write(encode({ jsonrpc: '2.0', method, params }));
  }

  async function initialize() {
    const init = await request('initialize', { clientInfo: { name: 'test-client', version: '1.0.0' }, protocolVersion: '2024-11-05' });
    notify('notifications/initialized');
    return init;
  }

  async function close() {
    child.kill('SIGTERM');
    await new Promise((resolve) => child.once('exit', resolve));
  }

  return { child, request, initialize, close };
}

async function run() {
  const coldStart = startCase('mcp_fake_cold_start_initialize');
  const client = createClient();
  const init = await client.initialize();
  assert(init.result?.serverInfo?.name === 'fake-mcp-server', 'initialize should return serverInfo');
  finishCase(coldStart, 'passed');

  const toolsList = startCase('mcp_fake_tools_list');
  const list = await client.request('tools/list');
  assert(Array.isArray(list.result?.tools), 'tools/list should return tools array');
  assert(list.result.tools.some((tool) => tool.name === 'echo'), 'tools/list should expose echo tool');
  finishCase(toolsList, 'passed');

  const callTool = startCase('mcp_fake_call_tool');
  const call = await client.request('tools/call', { name: 'echo', arguments: { text: 'hello-mcp' } });
  assert(call.result?.content?.[0]?.text === 'hello-mcp', 'tools/call should echo provided text');
  finishCase(callTool, 'passed');

  const reuse = startCase('mcp_fake_single_spawn_reuse');
  const pidBefore = client.child.pid;
  await client.request('tools/list');
  assert(client.child.pid === pidBefore, 'client should reuse the same child process');
  finishCase(reuse, 'passed');

  const restart = startCase('mcp_fake_restart_after_crash');
  await client.close();
  const restarted = createClient();
  const restartedInit = await restarted.initialize();
  assert(restartedInit.result?.serverInfo?.name === 'fake-mcp-server', 'restarted server should initialize cleanly');
  await restarted.close();
  finishCase(restart, 'passed');

  const teardown = startCase('mcp_fake_teardown');
  finishCase(teardown, 'passed');
}

(async () => {
  try {
    await run();
  } catch (error) {
    const failed = startCase('mcp_fake_runtime_execution');
    finishCase(failed, 'failed', error instanceof Error ? error.message : String(error));
  }

  const status = failures.length > 0 ? 'fail' : (cases.length === 0 ? 'skip' : 'pass');
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
