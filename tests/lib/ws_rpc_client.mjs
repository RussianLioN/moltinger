const DEFAULT_CLIENT = {
  id: 'test-suite',
  version: '0.1.0',
  platform: 'node',
  mode: 'operator',
};

function normalizeBaseUrl(baseUrl) {
  return (baseUrl || 'http://moltis:13131').replace(/\/$/, '');
}

function wsUrlFromBase(baseUrl) {
  const normalized = normalizeBaseUrl(baseUrl);
  return normalized.replace(/^http/, 'ws') + '/ws/chat';
}

function cookieHeaderFromLoginResponse(response) {
  if (typeof response.headers.getSetCookie === 'function') {
    const cookies = response.headers.getSetCookie();
    if (cookies.length > 0) {
      return cookies.map((value) => value.split(';')[0]).join('; ');
    }
  }

  const merged = response.headers.get('set-cookie') || '';
  return merged
    .split(/,(?=[^;]+=[^;]+)/)
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => value.split(';')[0])
    .join('; ');
}

export async function loginAndGetCookie({ baseUrl, password, testClientIp = '' } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (testClientIp) {
    headers['X-Forwarded-For'] = testClientIp;
    headers['X-Real-IP'] = testClientIp;
  }

  const response = await fetch(`${normalizeBaseUrl(baseUrl)}/api/auth/login`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ password }),
    redirect: 'manual',
  });

  return {
    status: response.status,
    cookieHeader: cookieHeaderFromLoginResponse(response),
  };
}

export class WsRpcClient {
  constructor({ baseUrl, cookieHeader = '', testClientIp = '', timeoutMs = 15000, client = {} } = {}) {
    this.baseUrl = normalizeBaseUrl(baseUrl);
    this.cookieHeader = cookieHeader;
    this.testClientIp = testClientIp;
    this.timeoutMs = timeoutMs;
    this.client = { ...DEFAULT_CLIENT, ...client };
    this.ws = null;
    this.reqId = 0;
    this.pending = new Map();
    this.events = [];
  }

  async open() {
    const headers = {};
    if (this.cookieHeader) {
      headers.Cookie = this.cookieHeader;
    }
    if (this.testClientIp) {
      headers['X-Forwarded-For'] = this.testClientIp;
      headers['X-Real-IP'] = this.testClientIp;
    }

    this.ws = new WebSocket(wsUrlFromBase(this.baseUrl), Object.keys(headers).length > 0 ? { headers } : undefined);
    this.ws.addEventListener('message', (event) => {
      const data = typeof event.data === 'string' ? event.data : event.data.toString();
      let frame;
      try {
        frame = JSON.parse(data);
      } catch {
        this.events.push({ type: 'raw', data });
        return;
      }

      if (frame.type === 'res' && frame.id && this.pending.has(frame.id)) {
        this.pending.get(frame.id).resolve(frame);
        this.pending.delete(frame.id);
        return;
      }
      this.events.push(frame);
    });

    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('ws open timeout')), this.timeoutMs);
      this.ws.addEventListener('open', () => {
        clearTimeout(timer);
        resolve();
      }, { once: true });
      this.ws.addEventListener('close', (event) => {
        clearTimeout(timer);
        reject(new Error(`ws closed before open (${event.code})`));
      }, { once: true });
      this.ws.addEventListener('error', () => {
        // close handler will carry the failure.
      }, { once: true });
    });
  }

  async connect({ locale = 'en-US', timezone = 'UTC' } = {}) {
    return this.request('connect', {
      protocol: { min: 3, max: 4 },
      client: this.client,
      locale,
      timezone,
    });
  }

  async request(method, params = {}) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error('WebSocket is not open');
    }

    const id = `${this.client.id}-${++this.reqId}`;
    const promise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`rpc timeout: ${method}`));
      }, this.timeoutMs);
      this.pending.set(id, {
        resolve: (frame) => {
          clearTimeout(timer);
          resolve(frame);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        },
      });
    });

    this.ws.send(JSON.stringify({ type: 'req', id, method, params }));
    return promise;
  }

  async subscribe(events) {
    return this.request('subscribe', { events });
  }

  async waitForEvent(predicate, timeoutMs = this.timeoutMs) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const match = this.events.find(predicate);
      if (match) {
        return match;
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error('event wait timeout');
  }

  async sendRawFrame(raw) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error('WebSocket is not open');
    }
    this.ws.send(raw);
  }

  async close() {
    if (!this.ws) {
      return;
    }
    if (this.ws.readyState === WebSocket.CLOSED) {
      return;
    }
    await new Promise((resolve) => {
      this.ws.addEventListener('close', () => resolve(), { once: true });
      this.ws.close();
      setTimeout(resolve, 1000);
    });
  }
}

export async function createAuthenticatedClient({ baseUrl, password, testClientIp = '', timeoutMs = 15000, client = {} } = {}) {
  const login = await loginAndGetCookie({ baseUrl, password, testClientIp });
  const rpc = new WsRpcClient({ baseUrl, cookieHeader: login.cookieHeader, testClientIp, timeoutMs, client });
  return { login, rpc };
}
