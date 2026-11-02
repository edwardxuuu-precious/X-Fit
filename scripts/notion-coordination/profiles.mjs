/** Fixed, explicitly granted connection adapter. No default network transport. */
import { execFile } from 'node:child_process';
function uuid(value) {
  if (typeof value !== 'string' || !/^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.test(value)) return null;
  const raw = value.replaceAll('-', '').toLowerCase();
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}-${raw.slice(16, 20)}-${raw.slice(20)}`;
}

const UUID_PATH = '(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})';

function safeHeaders(headers) {
  const value = headers && typeof headers === 'object' ? Object.entries(headers).find(([key]) => key.toLowerCase() === 'retry-after')?.[1] : undefined;
  if (value === undefined) return {};
  const text = String(value);
  return /^\d{1,10}$/.test(text) ? { 'retry-after': text } : {};
}

function statusError(status, headers, write) {
  let code = 'PROVIDER_REQUEST_FAILED';
  if (status >= 300 && status < 400) code = 'REDIRECT_FORBIDDEN';
  else if (status === 401) code = 'PROVIDER_UNAUTHORIZED';
  else if (status === 403) code = 'PROVIDER_FORBIDDEN';
  else if (status === 404) code = 'PROVIDER_NOT_FOUND';
  else if (status === 429) code = 'RATE_LIMITED';
  else if (status === 529) code = 'WORKSPACE_RATE_LIMITED';
  else if (status >= 500) code = 'PROVIDER_SERVER_ERROR';
  return new ProfileError(code, { httpStatus: status, resultUnknown: write && status >= 500 && status !== 529,
    retryable: !write && (status === 429 || status === 529 || status >= 500),
    retryAfter: headers['retry-after'] === undefined ? null : Number(headers['retry-after']) });
}

function parentTarget(body) {
  const parent = body?.parent;
  if (!parent || typeof parent !== 'object' || Array.isArray(parent)) throw new ProfileError('REQUEST_BODY_INVALID');
  const keys = ['page_id', 'data_source_id', 'database_id'].filter(key => Object.hasOwn(parent, key));
  if (keys.length !== 1 || !uuid(parent[keys[0]]) || (parent.type !== undefined && parent.type !== keys[0]) ||
      Object.keys(parent).some(key => !['type', keys[0]].includes(key))) throw new ProfileError('REQUEST_BODY_INVALID');
  return { id: uuid(parent[keys[0]]), type: keys[0] };
}

function providerParent(body) {
  const parent = body?.parent;
  if (parent?.type === 'data_source_id' && uuid(parent.data_source_id) &&
      (parent.database_id === undefined || uuid(parent.database_id)) &&
      Object.keys(parent).every(key => ['type', 'data_source_id', 'database_id'].includes(key))) {
    return { id: uuid(parent.data_source_id), type: 'data_source_id' };
  }
  return parentTarget(body);
}

function endpoint(method, path, body) {
  if (typeof path !== 'string' || !['GET', 'POST', 'PATCH'].includes(method)) throw new ProfileError('ENDPOINT_FORBIDDEN');
  if (method === 'POST' && path === '/v1/pages') {
    if (['archived', 'in_trash'].some(key => Object.hasOwn(body ?? {}, key))) throw new ProfileError('REQUEST_BODY_INVALID');
    const parent = parentTarget(body);
    return { target: parent.id, parentType: parent.type, path, write: true, capability: 'insert', resource: 'pages', suffix: '' };
  }
  const [base, query, extra] = path.split('?');
  if (extra !== undefined) throw new ProfileError('ENDPOINT_FORBIDDEN');
  const match = base.match(new RegExp(`^/v1/(pages|blocks|data_sources)/(${UUID_PATH})(/markdown|/children|/query)?$`));
  if (!match) throw new ProfileError('ENDPOINT_FORBIDDEN');
  const [, resource, id, suffix = ''] = match;
  const read = method === 'GET' && (
    (resource === 'pages' && ['', '/markdown'].includes(suffix)) ||
    (resource === 'blocks' && ['', '/children'].includes(suffix)) ||
    (resource === 'data_sources' && suffix === '')
  ) || (method === 'POST' && resource === 'data_sources' && suffix === '/query');
  const write = method === 'PATCH' && ['pages', 'blocks'].includes(resource) && suffix === '';
  if (!read && !write) throw new ProfileError('ENDPOINT_FORBIDDEN');
  if (write && (!body || typeof body !== 'object' || Array.isArray(body) ||
      ['parent', 'archived', 'in_trash'].some(key => Object.hasOwn(body, key)))) throw new ProfileError('REQUEST_BODY_INVALID');
  if (query !== undefined) {
    if (method !== 'GET' || resource !== 'blocks' || suffix !== '/children' || !query) throw new ProfileError('ENDPOINT_FORBIDDEN');
    if (query.split('&').some(pair => !pair || !pair.includes('='))) throw new ProfileError('ENDPOINT_FORBIDDEN');
    try { decodeURIComponent(query); } catch { throw new ProfileError('ENDPOINT_FORBIDDEN'); }
    const params = new URLSearchParams(query);
    const seen = new Set();
    for (const [key, value] of params) {
      if (seen.has(key) || (key === 'start_cursor' ? !value || value.length > 2048 || /[\x00-\x1f\x7f]/.test(value) :
        key === 'page_size' ? !/^(?:[1-9]|[1-9][0-9]|100)$/.test(value) : true)) throw new ProfileError('ENDPOINT_FORBIDDEN');
      seen.add(key);
    }
  }
  return { target: uuid(id), path: `/v1/${resource}/${uuid(id)}${suffix}${query === undefined ? '' : `?${query}`}`,
    write, capability: write ? 'update' : 'read', resource, suffix };
}

const ERROR_CODES = new Set(['PROFILE_FAILURE', 'PROFILE_INVALID', 'GRANT_REQUIRED', 'GRANT_INVALID',
  'GRANT_MISMATCH', 'READ_GRANT_REQUIRED', 'WRITE_GRANT_REQUIRED', 'TARGET_OUT_OF_SCOPE',
  'CAPABILITY_REQUIRED', 'IDENTITY_NOT_VERIFIED', 'BOT_MISMATCH', 'WORKSPACE_MISMATCH',
  'CREDENTIAL_UNCONFIGURED', 'CREDENTIAL_UNAVAILABLE', 'CREDENTIAL_REF_INVALID',
  'TRANSPORT_REQUIRED', 'TRANSPORT_FAILURE', 'TRANSPORT_RESPONSE_INVALID',
  'PROVIDER_UNAUTHORIZED', 'PROVIDER_FORBIDDEN', 'PROVIDER_NOT_FOUND', 'RATE_LIMITED',
  'WORKSPACE_RATE_LIMITED', 'PROVIDER_SERVER_ERROR', 'PROVIDER_REQUEST_FAILED',
  'REDIRECT_FORBIDDEN', 'ENDPOINT_FORBIDDEN', 'REQUEST_BODY_INVALID',
  'HTTP_CONFIG_INVALID', 'HTTP_INPUT_INVALID', 'HTTP_PATH_FORBIDDEN', 'HTTP_REQUEST_BUDGET',
  'HTTP_REQUEST_TOO_LARGE', 'HTTP_RESPONSE_TOO_LARGE', 'HTTP_TIMEOUT',
  'HTTP_CONNECTION_FAILED', 'HTTP_REDIRECT_FORBIDDEN', 'HTTP_RESPONSE_INVALID']);

export class ProfileError extends Error {
  constructor(code, { resultUnknown = false, retryable = false, retryAfter = null, httpStatus = null } = {}) {
    const safeCode = typeof code === 'string' && ERROR_CODES.has(code) ? code : 'PROFILE_FAILURE';
    super(safeCode);
    this.name = 'ProfileError';
    this.code = safeCode;
    this.resultUnknown = resultUnknown === true;
    this.retryable = retryable === true;
    this.retryAfter = Number.isSafeInteger(retryAfter) && retryAfter >= 0 ? retryAfter : null;
    this.httpStatus = Number.isInteger(httpStatus) && httpStatus >= 100 && httpStatus <= 599 ? httpStatus : null;
  }

  toJSON() {
    return { code: this.code, resultUnknown: this.resultUnknown, retryable: this.retryable,
      retryAfter: this.retryAfter, httpStatus: this.httpStatus };
  }
}

function credentialReference(ref) {
  if (!ref || typeof ref !== 'object' || Array.isArray(ref) || Object.keys(ref).some(key => !['service', 'account'].includes(key)) ||
      typeof ref.service !== 'string' || !(ref.service === 'com.xfit.notion-access' || /^com\.notion-coordination\.[a-z0-9][a-z0-9._-]{0,95}$/.test(ref.service)) ||
      typeof ref.account !== 'string' || !ref.account.trim() || ref.account !== ref.account.trim() ||
      ref.account.length > 256 || /[\x00-\x1f\x7f]/.test(ref.account) ||
      (ref.service === 'com.xfit.notion-access' && !uuid(ref.account))) {
    throw new ProfileError('CREDENTIAL_REF_INVALID');
  }
  return { service: ref.service, account: ref.account };
}

/** Explicit opt-in macOS reader; not used automatically and never writes credentials. */
export async function keychainCredentialReader(ref) {
  const { service, account } = credentialReference(ref);
  if (process.platform !== 'darwin') throw new ProfileError('CREDENTIAL_UNAVAILABLE');
  try {
    const token = await new Promise((resolve, reject) => {
      // Only non-secret identity is in argv; the token stays in captured stdout.
      execFile('/usr/bin/security', ['find-generic-password', '-s', service, '-a', account, '-w'],
        { encoding: 'utf8', shell: false, timeout: 5000, maxBuffer: 65536 },
        (error, stdout) => error ? reject(error) : resolve(stdout));
    });
    const trimmed = typeof token === 'string' ? token.trim() : '';
    if (!trimmed || /[\r\n\0]/.test(trimmed)) throw new ProfileError('CREDENTIAL_UNAVAILABLE');
    return trimmed;
  } catch {
    throw new ProfileError('CREDENTIAL_UNAVAILABLE');
  }
}

export class FixedProfileClient {
  #profile;
  #grant;
  #credentialReader;
  #transport;
  #token;
  #verified = false;
  #readPages = new Set();
  #sourcePageTrees = new Set();
  #readBlocks = new Set();

  /**
   * transport.request({method,path,body,token,apiVersion}) -> {status,data,headers?}.
   * No reader or network defaults: production access is a separate explicit gate.
   * A grant documents caller authority; it does not create Notion permissions.
   * Project adapters must additionally enforce owned fields and full readback.
   */
  constructor({ profile, grant, credentialReader, transport } = {}) {
    try { this.#profile = structuredClone(profile); }
    catch { throw new ProfileError('PROFILE_INVALID'); }
    try { this.#grant = structuredClone(grant); }
    catch { throw new ProfileError('GRANT_INVALID'); }
    this.#credentialReader = credentialReader;
    this.#transport = transport;
  }

  #assertConfig() {
    const profile = this.#profile;
    if (!profile || typeof profile.id !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(profile.id) ||
        !uuid(profile.workspaceId) || !uuid(profile.botId) || typeof profile.apiVersion !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}$/.test(profile.apiVersion) || !Array.isArray(profile.capabilities) ||
        profile.capabilities.some(value => !['read', 'update', 'insert'].includes(value))) {
      throw new ProfileError('PROFILE_INVALID');
    }
    if (!this.#transport || typeof this.#transport.request !== 'function') throw new ProfileError('TRANSPORT_REQUIRED');
  }

  #assertGrant(write = false) {
    const grant = this.#grant;
    if (!grant) throw new ProfileError('GRANT_REQUIRED');
    if (!['fixture', 'live'].includes(grant.mode) || typeof grant.reference !== 'string' ||
        !grant.reference.trim() || grant.reference.length > 512 || /[\x00-\x1f\x7f]/.test(grant.reference) ||
        typeof grant.write !== 'boolean' || !Array.isArray(grant.scopeTargets) ||
        grant.scopeTargets.some(target => !uuid(target)) ||
        new Set(grant.scopeTargets.map(uuid)).size !== grant.scopeTargets.length) throw new ProfileError('GRANT_INVALID');
    if (grant.profileId !== this.#profile.id || !uuid(grant.workspaceId) ||
        uuid(grant.workspaceId) !== uuid(this.#profile.workspaceId)) throw new ProfileError('GRANT_MISMATCH');
    if (grant.read !== true) throw new ProfileError('READ_GRANT_REQUIRED');
    if (write && grant.write !== true) throw new ProfileError('WRITE_GRANT_REQUIRED');
  }

  #assertCapability(capability) {
    if (!Array.isArray(this.#profile.capabilities) || !this.#profile.capabilities.includes(capability)) {
      throw new ProfileError('CAPABILITY_REQUIRED');
    }
  }

  async #perform(method, path, body, write = false) {
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      let response;
      try {
        response = await this.#transport.request({ method, path, body,
          token: this.#token, apiVersion: this.#profile.apiVersion });
      } catch (error) {
        // Rebuild only our finite wire error contract; never carry provider text/cause.
        let safeError;
        try {
          if (error instanceof ProfileError && ERROR_CODES.has(error.code) && error.code.startsWith('HTTP_')) {
            safeError = new ProfileError(error.code, { resultUnknown: error.resultUnknown, httpStatus: error.httpStatus });
          }
        } catch { /* Malformed exception metadata falls back to a safe transport failure. */ }
        if (safeError) throw safeError;
        throw new ProfileError('TRANSPORT_FAILURE', { resultUnknown: write, retryable: !write });
      }
      try { response = structuredClone(response); }
      catch { throw new ProfileError('TRANSPORT_RESPONSE_INVALID', { resultUnknown: write }); }
      if (!response || !Number.isInteger(response.status) || response.status < 100 || response.status > 599 ||
          !response.data || typeof response.data !== 'object' || Array.isArray(response.data)) {
        throw new ProfileError('TRANSPORT_RESPONSE_INVALID', { resultUnknown: write });
      }
      const headers = safeHeaders(response.headers);
      const hasWaitingHint = response.headers && typeof response.headers === 'object' &&
        Object.keys(response.headers).some(key => key.toLowerCase() === 'retry-after');
      if (response.status < 200 || response.status >= 300) {
        if (method === 'GET' && !write && [500, 502, 503, 504].includes(response.status) &&
            !hasWaitingHint && attempt < 3) continue;
        throw statusError(response.status, headers, write);
      }
      return { status: response.status, data: response.data, headers };
    }
  }

  async verifyIdentity() {
    this.#verified = false;
    this.#token = undefined;
    this.#readPages.clear();
    this.#sourcePageTrees.clear();
    this.#readBlocks.clear();
    this.#assertConfig();
    this.#assertGrant();
    this.#assertCapability('read');
    if (!this.#profile.secretRef) throw new ProfileError('CREDENTIAL_UNCONFIGURED');
    const ref = credentialReference(this.#profile.secretRef);
    if (ref.service === 'com.xfit.notion-access' && uuid(ref.account) !== uuid(this.#profile.workspaceId)) {
      throw new ProfileError('CREDENTIAL_REF_INVALID');
    }
    try {
      const token = await this.#credentialReader(ref);
      if (typeof token !== 'string' || !token.trim() || /[\r\n\0]/.test(token) || token.length > 65536) {
        throw new ProfileError('CREDENTIAL_UNAVAILABLE');
      }
      this.#token = token.trim();
    } catch {
      throw new ProfileError('CREDENTIAL_UNAVAILABLE');
    }
    const response = await this.#perform('GET', '/v1/users/me', undefined);
    if (response.data?.type !== 'bot' || uuid(response.data.id) !== uuid(this.#profile.botId)) {
      throw new ProfileError('BOT_MISMATCH');
    }
    if (!uuid(response.data.bot?.workspace_id) || uuid(response.data.bot.workspace_id) !== uuid(this.#profile.workspaceId)) {
      throw new ProfileError('WORKSPACE_MISMATCH');
    }
    this.#verified = true;
    return { verified: true, profileId: this.#profile.id, botId: this.#profile.botId,
      workspaceId: this.#profile.workspaceId };
  }

  async request(method, path, body) {
    if (!this.#verified) throw new ProfileError('IDENTITY_NOT_VERIFIED');
    let input;
    try { input = structuredClone(body); }
    catch { throw new ProfileError('REQUEST_BODY_INVALID'); }
    const allowed = endpoint(method, path, input);
    this.#assertGrant(allowed.write);
    this.#assertCapability(allowed.capability);
    if (!this.#grant.scopeTargets.some(target => uuid(target) === allowed.target) &&
        !(method === 'GET' && allowed.resource === 'pages' && this.#readPages.has(allowed.target)) &&
        !(method === 'GET' && allowed.resource === 'blocks' && allowed.suffix === '/children' && this.#sourcePageTrees.has(allowed.target)) &&
        !(method === 'GET' && allowed.resource === 'blocks' && this.#readBlocks.has(allowed.target))) {
      throw new ProfileError('TARGET_OUT_OF_SCOPE');
    }
    const response = await this.#perform(method, allowed.path, input, allowed.write);
    if (method === 'POST' && allowed.resource === 'pages') {
      try {
        const actualParent = providerParent(response.data);
        if (response.data.object === 'page' && uuid(response.data.id) &&
            allowed.target === actualParent.id && allowed.parentType === actualParent.type) {
          this.#readPages.add(uuid(response.data.id));
        }
      } catch { /* Unverifiable provider parent never expands read scope. */ }
    }
    if (method === 'POST' && allowed.resource === 'data_sources' && allowed.suffix === '/query' && Array.isArray(response.data.results)) {
      for (const page of response.data.results) {
        try {
          const parent = providerParent(page);
          if (page.object === 'page' && uuid(page.id) && parent.type === 'data_source_id' && parent.id === allowed.target) {
            this.#readPages.add(uuid(page.id));
            this.#sourcePageTrees.add(uuid(page.id));
          }
        } catch { /* Invalid/unrelated result does not grant child access. */ }
      }
    }
    if (method === 'GET' && allowed.resource === 'blocks' && allowed.suffix === '/children' && Array.isArray(response.data.results)) {
      for (const block of response.data.results) {
        const parent = block?.parent;
        const parentId = parent?.type === 'page_id' ? parent.page_id : parent?.type === 'block_id' ? parent.block_id : null;
        if (block?.object === 'block' && uuid(block.id) && typeof block.type === 'string' &&
            typeof block.has_children === 'boolean' && uuid(parentId) === allowed.target) {
          this.#readBlocks.add(uuid(block.id));
        }
      }
    }
    return response;
  }

  toJSON() {
    return { profileId: this.#profile.id, workspaceId: this.#profile.workspaceId, verified: this.#verified };
  }
}
