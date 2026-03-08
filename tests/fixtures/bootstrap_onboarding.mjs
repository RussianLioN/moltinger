import { bootstrapOnboarding } from '../lib/browser_runtime.mjs';

const baseUrl = (process.env.TEST_BASE_URL || 'http://moltis:13131').replace(/\/$/, '');
const password = process.env.MOLTIS_PASSWORD || 'test_password';
const testClientIp = process.env.TEST_CLIENT_IP || '';
const defaultTimeoutMs = Number(process.env.TEST_TIMEOUT || '60') * 1000;

try {
  const result = await bootstrapOnboarding({ baseUrl, password, testClientIp, defaultTimeoutMs });
  process.stdout.write(`${JSON.stringify({ status: 'ok', ...result }, null, 2)}\n`);
  process.exit(0);
} catch (error) {
  process.stdout.write(`${JSON.stringify({
    status: 'error',
    message: error instanceof Error ? error.message : String(error),
  }, null, 2)}\n`);
  process.exit(1);
}
