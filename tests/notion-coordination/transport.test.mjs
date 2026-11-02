import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { NotionHttpTransport, TransportError } from '../../scripts/notion-coordination/transport.mjs';

const TOKEN = 'fixture-transport-private-not-production';
const PAGE = '6d6b5fb7-de5c-446a-a503-8b6462833486';
const SOURCE = '09fd5db5-21f6-4d39-869d-e3ad0b2f444e';

async function fixture(t, handler) {
  const server = http.createServer(handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    const closed = once(server, 'close');
    server.closeAllConnections();
    server.close();
    await closed;
  });
  return `http://127.0.0.1:${server.address().port}`;
}

const input = (method = 'GET', path = '/v1/users/me', body) => ({ method, path, body, token: TOKEN, apiVersion: '2026-03-11' });

test('explicit fixture transport reaches only its loopback server and sends the declared API version', async t => {
  const origin = await fixture(t, (req, res) => {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ authorized: req.headers.authorization === `Bearer ${TOKEN}`, version: req.headers['notion-version'] }));
  });
  const transport = new NotionHttpTransport({ mode: 'fixture', origin });
  assert.deepEqual(await transport.request(input()), { status: 200, data: { authorized: true, version: '2026-03-11' }, headers: {} });
  assert.ok(!JSON.stringify(transport).includes(TOKEN));
});

test('origins and mode are explicit and cannot select another host or alias of loopback', () => {
  for (const options of [{}, { mode: 'fixture' }, { mode: 'fixture', origin: 'https://api.notion.com' },
    { mode: 'fixture', origin: 'http://localhost:1234' }, { mode: 'fixture', origin: 'http://127.1:1234' },
    { mode: 'fixture', origin: 'http://127.0.0.1:1234/path' }, { mode: 'fixture', origin: 'http://127.0.0.1:0' },
    { mode: 'fixture', origin: 'http://127.0.0.1:65536' },
    { mode: 'live', origin: 'http://127.0.0.1:1234' }, { mode: 'live', origin: 'https://api.notion.com.evil.invalid' }]) {
    assert.throws(() => new NotionHttpTransport(options), { code: 'HTTP_CONFIG_INVALID' });
  }
  assert.equal(new NotionHttpTransport({ mode: 'live' }).toJSON().origin, 'https://api.notion.com');
});

test('request paths cannot escape the fixed origin, endpoint or query allowlists', async t => {
  let calls = 0;
  const origin = await fixture(t, (_req, res) => { calls += 1; res.end('{}'); });
  const transport = new NotionHttpTransport({ mode: 'fixture', origin });
  for (const path of [`${origin}/v1/users/me`, `${origin.replace('http:', '')}/v1/users/me`,
    '/v1/../users/me', '/v1/pages/%2e%2e/users/me', '/v1/users/me#secret', '/v1/users/me?token=private',
    `/v1/blocks/${PAGE}/children?host=127.0.0.1`, `/v1/blocks/${PAGE}/children?start_cursor=%0A`,
    `/v1/blocks/${PAGE}/children?page_size=101`, `/v1/blocks/${PAGE}/children?page_size=1&page_size=2`,
    '/v1/search', `/v1/pages/${PAGE}/%6darkdown`, `/v1/blocks/${PAGE}/children?start_cursor=%`]) {
    await assert.rejects(transport.request(input('GET', path)), { code: 'HTTP_PATH_FORBIDDEN' });
  }
  await assert.rejects(transport.request(input('PATCH', '/v1/users/me', {})), { code: 'HTTP_PATH_FORBIDDEN' });
  await assert.rejects(transport.request(input('DELETE', `/v1/pages/${PAGE}`)), { code: 'HTTP_PATH_FORBIDDEN' });
  assert.equal(calls, 0);
  const cursor = 'opaque v2: cursor/+?&=雪';
  await transport.request(input('GET', `/v1/blocks/${PAGE}/children?start_cursor=${encodeURIComponent(cursor)}&page_size=100`));
  await transport.request(input('POST', `/v1/data_sources/${SOURCE}/query`, { page_size: 100, start_cursor: cursor }));
  assert.equal(calls, 2);
});

test('request configuration, inputs and request count stay within explicit finite bounds', async t => {
  let calls = 0;
  const origin = await fixture(t, (_req, res) => { calls += 1; res.end('{}'); });
  for (const limits of [{ timeoutMs: 0 }, { timeoutMs: 30001 }, { timeoutMs: NaN },
    { maxResponseBytes: 0 }, { maxResponseBytes: 8388609 }, { maxRequests: 0 }, { maxRequests: 301 }]) {
    assert.throws(() => new NotionHttpTransport({ mode: 'fixture', origin, ...limits }), { code: 'HTTP_CONFIG_INVALID' });
  }
  const transport = new NotionHttpTransport({ mode: 'fixture', origin, maxRequests: 1 });
  const cyclic = {}; cyclic.self = cyclic;
  for (const request of [{ ...input(), token: '' }, { ...input(), token: 'bad\r\nheader' },
    { ...input(), token: 'bad token' }, { ...input(), token: 'x'.repeat(8193) }, { ...input(), apiVersion: 'bad\nversion' },
    input('GET', '/v1/users/me', {}), input('POST', '/v1/pages'), input('POST', '/v1/pages', []),
    input('POST', `/v1/data_sources/${SOURCE}/query`, new Date()),
    input('POST', `/v1/data_sources/${SOURCE}/query`, new Map()),
    input('PATCH', `/v1/pages/${PAGE}`, cyclic)]) {
    await assert.rejects(transport.request(request), { code: 'HTTP_INPUT_INVALID', resultUnknown: false });
  }
  await assert.rejects(transport.request(input('POST', '/v1/pages', { private: 'x'.repeat(500001) })),
    { code: 'HTTP_REQUEST_TOO_LARGE', resultUnknown: false });
  assert.equal(calls, 0);
  await transport.request(input());
  await assert.rejects(transport.request(input('PATCH', `/v1/pages/${PAGE}`, {})),
    { code: 'HTTP_REQUEST_BUDGET', resultUnknown: false });
  assert.equal(calls, 1);
  assert.equal(transport.toJSON().requestsUsed, 1);
});

test('response bytes, successful object shape and provider error metadata are bounded and sanitized', async t => {
  const origin = await fixture(t, (req, res) => {
    if (req.url.includes('/markdown')) return res.end(JSON.stringify({ private: 'x'.repeat(200) }));
    if (req.url === '/v1/users/me') return res.end('["not an object"]');
    res.statusCode = 429;
    res.setHeader('Retry-After', '7');
    res.setHeader('Set-Cookie', TOKEN);
    res.end(JSON.stringify({ message: TOKEN }));
  });
  const transport = new NotionHttpTransport({ mode: 'fixture', origin, maxResponseBytes: 128 });
  await assert.rejects(transport.request(input('GET', `/v1/pages/${PAGE}/markdown`)),
    { code: 'HTTP_RESPONSE_TOO_LARGE', resultUnknown: false });
  await assert.rejects(transport.request(input()), { code: 'HTTP_RESPONSE_INVALID' });
  assert.deepEqual(await transport.request(input('GET', `/v1/pages/${PAGE}`)),
    { status: 429, data: {}, headers: { 'retry-after': '7' } });
});

test('a total deadline ends silent reads and classifies writes as unknown without a blind retry', async t => {
  let calls = 0;
  const origin = await fixture(t, () => { calls += 1; });
  for (const [method, path, body, resultUnknown] of [['GET', '/v1/users/me', undefined, false],
    ['POST', `/v1/data_sources/${SOURCE}/query`, {}, false], ['PATCH', `/v1/pages/${PAGE}`, {}, true]]) {
    const transport = new NotionHttpTransport({ mode: 'fixture', origin, timeoutMs: 25 });
    let deadline;
    try {
      await assert.rejects(Promise.race([transport.request(input(method, path, body)),
        new Promise((_resolve, reject) => { deadline = setTimeout(() => reject(new Error('TEST_DEADLINE')), 400); })]),
      { code: 'HTTP_TIMEOUT', resultUnknown });
    } finally { clearTimeout(deadline); }
  }
  assert.equal(calls, 3);
});

test('redirects are not followed and all wire failures exclude token, provider body and location', async t => {
  let followed = 0;
  const origin = await fixture(t, (req, res) => {
    if (req.url === '/redirect-destination') { followed += 1; res.end('{}'); return; }
    res.statusCode = 302;
    res.setHeader('Location', `/redirect-destination?secret=${TOKEN}`);
    res.end(JSON.stringify({ message: TOKEN }));
  });
  for (const [method, path, body, resultUnknown] of [['GET', '/v1/users/me', undefined, false],
    ['POST', '/v1/pages', { parent: { page_id: PAGE } }, true]]) {
    const transport = new NotionHttpTransport({ mode: 'fixture', origin });
    await assert.rejects(transport.request(input(method, path, body)), error => {
      assert.ok(error instanceof TransportError);
      assert.equal(error.code, 'HTTP_REDIRECT_FORBIDDEN');
      assert.equal(error.resultUnknown, resultUnknown);
      assert.equal(error.httpStatus, 302);
      assert.ok(!JSON.stringify(error).includes(TOKEN));
      assert.ok(!String(error).includes(TOKEN));
      return true;
    });
  }
  assert.equal(followed, 0);
});

test('aborted, malformed and oversized write responses remain unknown; read query outcomes do not', async t => {
  let calls = 0;
  const origin = await fixture(t, (req, res) => {
    calls += 1;
    if (req.url.endsWith('/query')) { req.socket.destroy(); return; }
    if (req.method === 'PATCH') { res.writeHead(200); res.end('not-json'); return; }
    res.end(JSON.stringify({ body: 'x'.repeat(400) }));
  });
  for (const [method, path, body, code, resultUnknown] of [
    ['POST', `/v1/data_sources/${SOURCE}/query`, {}, 'HTTP_CONNECTION_FAILED', false],
    ['PATCH', `/v1/pages/${PAGE}`, {}, 'HTTP_RESPONSE_INVALID', true],
    ['POST', '/v1/pages', { parent: { page_id: PAGE } }, 'HTTP_RESPONSE_TOO_LARGE', true]]) {
    const transport = new NotionHttpTransport({ mode: 'fixture', origin, maxResponseBytes: 100 });
    await assert.rejects(transport.request(input(method, path, body)), error => {
      assert.equal(error.code, code); assert.equal(error.resultUnknown, resultUnknown);
      assert.equal(error.cause, undefined); assert.ok(!String(error.stack).includes(TOKEN));
      return true;
    });
  }
  assert.equal(calls, 3);
});

test('an opaque waiting hint prevents retries without exposing private provider headers or body', async t => {
  const origin = await fixture(t, (_req, res) => {
    res.statusCode = 503; res.setHeader('Retry-After', TOKEN); res.end(TOKEN);
  });
  const transport = new NotionHttpTransport({ mode: 'fixture', origin });
  const response = await transport.request(input());
  assert.deepEqual(response, { status: 503, data: {}, headers: { 'retry-after': 'present' } });
  assert.equal(transport.toJSON().requestsUsed, 1);
});
