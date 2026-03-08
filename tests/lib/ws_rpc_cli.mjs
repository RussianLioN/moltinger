import { WsRpcClient, createAuthenticatedClient, loginAndGetCookie } from './ws_rpc_client.mjs';

function parseArgs(argv) {
  const args = { command: '', method: '', params: '{}', waitMs: 0, subscribe: [], noAuth: false, raw: '' };
  const items = [...argv];
  args.command = items.shift() || 'request';
  while (items.length > 0) {
    const arg = items.shift();
    switch (arg) {
      case '--method':
        args.method = items.shift() || '';
        break;
      case '--params':
        args.params = items.shift() || '{}';
        break;
      case '--wait-ms':
        args.waitMs = Number(items.shift() || '0');
        break;
      case '--subscribe':
        args.subscribe = (items.shift() || '').split(',').map((value) => value.trim()).filter(Boolean);
        break;
      case '--no-auth':
        args.noAuth = true;
        break;
      case '--raw':
        args.raw = items.shift() || '';
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));
const baseUrl = (process.env.TEST_BASE_URL || 'http://moltis:13131').replace(/\/$/, '');
const password = process.env.MOLTIS_PASSWORD || 'test_password';
const testClientIp = process.env.TEST_CLIENT_IP || '';
const timeoutMs = Number(process.env.TEST_TIMEOUT || '20') * 1000;
const reusedCookieHeader = process.env.TEST_COOKIE_HEADER || '';

let login = null;
let rpc;

try {
  if (args.noAuth) {
    rpc = new WsRpcClient({ baseUrl, testClientIp, timeoutMs, client: { id: 'suite-cli-noauth' } });
  } else if (reusedCookieHeader) {
    login = { status: 200, cookieHeader: reusedCookieHeader, reused: true };
    rpc = new WsRpcClient({
      baseUrl,
      cookieHeader: reusedCookieHeader,
      testClientIp,
      timeoutMs,
      client: { id: 'suite-cli-auth' },
    });
  } else {
    const client = await createAuthenticatedClient({
      baseUrl,
      password,
      testClientIp,
      timeoutMs,
      client: { id: 'suite-cli-auth' },
    });
    login = client.login;
    rpc = client.rpc;
  }

  await rpc.open();

  let connect;
  try {
    connect = await rpc.connect();
  } catch (error) {
    process.stdout.write(`${JSON.stringify({ ok: false, stage: 'connect', login, message: error.message }, null, 2)}\n`);
    process.exit(1);
  }

  if (args.subscribe.length > 0) {
    await rpc.subscribe(args.subscribe);
  }

  let result;
  if (args.command === 'request') {
    if (!args.method) {
      throw new Error('--method is required for request');
    }
    result = await rpc.request(args.method, JSON.parse(args.params || '{}'));
  } else if (args.command === 'invalid-frame') {
    if (!args.raw) {
      throw new Error('--raw is required for invalid-frame');
    }
    await rpc.sendRawFrame(args.raw);
    if (args.waitMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, args.waitMs));
    }
    result = await rpc.request('health', {});
  } else if (args.command === 'login') {
    result = { ok: true, payload: login ?? await loginAndGetCookie({ baseUrl, password, testClientIp }) };
  } else {
    throw new Error(`Unknown command: ${args.command}`);
  }

  if (args.waitMs > 0 && args.command !== 'invalid-frame') {
    await new Promise((resolve) => setTimeout(resolve, args.waitMs));
  }

  process.stdout.write(`${JSON.stringify({ ok: true, login, connect, result, events: rpc.events }, null, 2)}\n`);
  await rpc.close();
  process.exit(0);
} catch (error) {
  process.stdout.write(`${JSON.stringify({ ok: false, login, message: error instanceof Error ? error.message : String(error) }, null, 2)}\n`);
  if (rpc) {
    await rpc.close().catch(() => {});
  }
  process.exit(1);
}
