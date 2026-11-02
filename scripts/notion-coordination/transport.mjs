import http from 'node:http';
import https from 'node:https';
import { ProfileError } from './profiles.mjs';

export class TransportError extends ProfileError {}

const UUID_PATH = '(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})';

function validatePath(method, path) {
  const fail = () => { throw new TransportError('HTTP_PATH_FORBIDDEN'); };
  if (!['GET', 'POST', 'PATCH'].includes(method) || typeof path !== 'string' || path.length > 12288 || /[#\\\x00-\x20\x7f]/.test(path)) fail();
  if (method === 'GET' && path === '/v1/users/me' || method === 'POST' && path === '/v1/pages') return;
  const [base, query, extra] = path.split('?');
  const match = base.match(new RegExp(`^/v1/(pages|blocks|data_sources)/(${UUID_PATH})(/markdown|/children|/query)?$`));
  if (!match || extra !== undefined) fail();
  const [, resource, , suffix = ''] = match;
  const allowed = method === 'GET' && (resource === 'pages' && ['', '/markdown'].includes(suffix) ||
    resource === 'blocks' && ['', '/children'].includes(suffix) || resource === 'data_sources' && suffix === '') ||
    method === 'POST' && resource === 'data_sources' && suffix === '/query' ||
    method === 'PATCH' && ['pages', 'blocks'].includes(resource) && suffix === '';
  if (!allowed) fail();
  if (query !== undefined) {
    if (method !== 'GET' || resource !== 'blocks' || suffix !== '/children' || !query ||
        query.split('&').some(pair => !pair || !pair.includes('='))) fail();
    try { decodeURIComponent(query); } catch { fail(); }
    const params = new URLSearchParams(query);
    const seen = new Set();
    for (const [key, value] of params) {
      if (seen.has(key) || (key === 'start_cursor' ? !value || value.length > 2048 || /[\x00-\x1f\x7f]/.test(value) :
        key === 'page_size' ? !/^(?:[1-9]|[1-9][0-9]|100)$/.test(value) : true)) fail();
      seen.add(key);
    }
  }
}

/** Wire adapter only; callers still need independent profile, route and grant gates. */
export class NotionHttpTransport {
  #origin;
  #mode;
  #timeoutMs;
  #maxResponseBytes;
  #maxRequests;
  #requestsUsed = 0;

  constructor(options = {}) {
    try {
      const { mode, origin, timeoutMs = 10000, maxResponseBytes = 2 * 1024 * 1024, maxRequests = 100 } = options;
      if (!['live', 'fixture'].includes(mode) ||
          (mode === 'live' && origin !== undefined && origin !== 'https://api.notion.com') ||
          (mode === 'fixture' && (typeof origin !== 'string' || !/^http:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}$/.test(origin) || new URL(origin).port > 65535)) ||
          !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30000 ||
          !Number.isInteger(maxResponseBytes) || maxResponseBytes < 1 || maxResponseBytes > 8 * 1024 * 1024 ||
          !Number.isInteger(maxRequests) || maxRequests < 1 || maxRequests > 300) throw new Error();
      this.#mode = mode;
      this.#origin = mode === 'live' ? 'https://api.notion.com' : origin;
      this.#timeoutMs = timeoutMs;
      this.#maxResponseBytes = maxResponseBytes;
      this.#maxRequests = maxRequests;
    } catch {
      throw new TransportError('HTTP_CONFIG_INVALID');
    }
  }

  async request(options) {
    let method, path, body, token, apiVersion, encoded;
    try {
      ({ method, path, body, token, apiVersion } = options);
    } catch { throw new TransportError('HTTP_INPUT_INVALID'); }
    validatePath(method, path);
    try {
      if (typeof token !== 'string' || !/^[\x21-\x7e]{1,8192}$/.test(token) ||
          typeof apiVersion !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(apiVersion) ||
          (method === 'GET' ? body !== undefined : !body || typeof body !== 'object' || Array.isArray(body))) throw new Error();
      if (body !== undefined && ![Object.prototype, null].includes(Object.getPrototypeOf(body))) throw new Error();
      if (body !== undefined) encoded = JSON.stringify(structuredClone(body));
    } catch { throw new TransportError('HTTP_INPUT_INVALID'); }
    if (encoded !== undefined && Buffer.byteLength(encoded, 'utf8') > 500000) throw new TransportError('HTTP_REQUEST_TOO_LARGE');
    if (this.#requestsUsed >= this.#maxRequests) throw new TransportError('HTTP_REQUEST_BUDGET');
    this.#requestsUsed += 1;
    const url = new URL(path, this.#origin);
    const write = method === 'PATCH' || method === 'POST' && path === '/v1/pages';
    return new Promise((resolve, reject) => {
      let finished = false;
      let timer;
      let dispatched = false;
      const fail = (code, status = null) => {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        reject(new TransportError(code, { resultUnknown: write && dispatched, httpStatus: status }));
      };
      let request;
      try {
      request = (url.protocol === 'https:' ? https : http).request(url, {
        method, agent: false, headers: { Authorization: `Bearer ${token}`, 'Notion-Version': apiVersion, 'Content-Type': 'application/json' },
      }, response => {
        if (response.statusCode >= 300 && response.statusCode < 400) {
          fail('HTTP_REDIRECT_FORBIDDEN', response.statusCode);
          response.destroy();
          request.destroy();
          return;
        }
        const chunks = [];
        let bytes = 0;
        response.on('data', chunk => {
          bytes += chunk.length;
          if (bytes > this.#maxResponseBytes) {
            fail('HTTP_RESPONSE_TOO_LARGE', response.statusCode);
            response.destroy();
            request.destroy();
          } else chunks.push(chunk);
        });
        response.on('error', () => fail('HTTP_CONNECTION_FAILED', response.statusCode));
        response.on('aborted', () => fail('HTTP_CONNECTION_FAILED', response.statusCode));
        response.on('end', () => {
          if (finished) return;
          try {
            const status = response.statusCode;
            const rawHint = response.headers['retry-after'];
            const headers = rawHint === undefined ? {} : { 'retry-after': /^\d{1,10}$/.test(String(rawHint)) ? String(rawHint) : 'present' };
            const data = status >= 200 && status < 300 ? JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))) : {};
            if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error();
            finished = true;
            clearTimeout(timer);
            resolve({ status, data, headers });
          } catch { fail('HTTP_RESPONSE_INVALID', response.statusCode); }
        });
      });
      request.on('error', () => fail('HTTP_CONNECTION_FAILED'));
      timer = setTimeout(() => { fail('HTTP_TIMEOUT'); request.destroy(); }, this.#timeoutMs);
      dispatched = true;
      request.end(encoded);
      } catch { fail('HTTP_CONNECTION_FAILED'); request?.destroy(); }
    });
  }

  toJSON() { return { mode: this.#mode, origin: this.#origin, requestsUsed: this.#requestsUsed,
    maxRequests: this.#maxRequests, maxResponseBytes: this.#maxResponseBytes, timeoutMs: this.#timeoutMs }; }
}
