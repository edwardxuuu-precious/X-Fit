import test from 'node:test';
import assert from 'node:assert/strict';
import { FixedProfileClient, ProfileError, keychainCredentialReader } from '../../scripts/notion-coordination/profiles.mjs';

const EDWARD = 'c63f367d-6f39-41c0-9a28-e4ad2ce10251';
const PRIMEVIZ = '84ec1ddd-3200-8110-ae91-000338974a99';
const BOT = 'a1111111-1111-4111-8111-111111111111';
const PAGE = '6d6b5fb7-de5c-446a-a503-8b6462833486';
const OTHER_PAGE = 'b2222222-2222-4222-8222-222222222222';
const CHILD = 'c3333333-3333-4333-8333-333333333333';
const SOURCE = '09fd5db5-21f6-4d39-869d-e3ad0b2f444e';
const TOKEN = 'fixture-private-token-never-log';

function identity(workspaceId = EDWARD, botId = BOT) {
  return { status: 200, data: { object: 'user', type: 'bot', id: botId, bot: { workspace_id: workspaceId } } };
}

function setup(overrides = {}) {
  const requests = [];
  const profile = overrides.profile ?? {
    id: 'edward-xfit-private', workspaceId: EDWARD, botId: BOT,
    secretRef: { service: 'com.xfit.notion-access', account: EDWARD },
    capabilities: ['read', 'update', 'insert'], apiVersion: '2026-03-11',
  };
  const grant = Object.hasOwn(overrides, 'grant') ? overrides.grant : {
    mode: 'fixture', read: true, write: true, profileId: profile.id,
    workspaceId: profile.workspaceId, scopeTargets: [PAGE, SOURCE], reference: 'REQ-20261007-102225:fixture',
  };
  const transport = overrides.transport ?? {
    async request(request) {
      requests.push(request);
      if (request.path === '/v1/users/me') return overrides.me ?? identity(profile.workspaceId, profile.botId);
      return { status: 200, data: { object: 'page', id: PAGE, label: 'X-Fit' } };
    },
  };
  const client = new FixedProfileClient({ profile, grant, transport,
    credentialReader: overrides.credentialReader ?? (async () => TOKEN),
  });
  return { client, profile, grant, requests };
}

test('caller verifies an exact fixed profile before reading its granted page', async () => {
  const { client } = setup();
  assert.deepEqual(await client.verifyIdentity(), {
    verified: true, profileId: 'edward-xfit-private', botId: BOT, workspaceId: EDWARD,
  });
  assert.deepEqual(await client.request('GET', `/v1/pages/${PAGE}`), {
    status: 200, data: { object: 'page', id: PAGE, label: 'X-Fit' }, headers: {},
  });
});

test('a different bot cannot verify or read through the fixed profile', async () => {
  const { client } = setup({ me: identity(EDWARD, OTHER_PAGE) });
  await assert.rejects(client.verifyIdentity(), error => error instanceof ProfileError && error.code === 'BOT_MISMATCH');
  await assert.rejects(client.request('GET', `/v1/pages/${PAGE}`), { code: 'IDENTITY_NOT_VERIFIED' });
});

test('a different or absent workspace is rejected without trying a second connection', async () => {
  for (const workspaceId of [PRIMEVIZ, null]) {
    const { client, requests } = setup({ me: identity(workspaceId) });
    await assert.rejects(client.verifyIdentity(), { code: 'WORKSPACE_MISMATCH' });
    assert.equal(requests.length, 1);
  }
});

test('UUID formatting differences do not turn the same fixed identity into another workspace', async () => {
  const { client } = setup({ me: identity(EDWARD.replaceAll('-', '').toUpperCase(), BOT.toUpperCase()) });
  assert.equal((await client.verifyIdentity()).workspaceId, EDWARD);
});

test('no identity request happens without a matching explicit read grant', async () => {
  const { grant: valid } = setup();
  for (const [grant, code] of [
    [null, 'GRANT_REQUIRED'],
    [{ ...valid, mode: 'automatic' }, 'GRANT_INVALID'],
    [{ ...valid, reference: '' }, 'GRANT_INVALID'],
    [{ ...valid, read: false }, 'READ_GRANT_REQUIRED'],
    [{ ...valid, profileId: 'different-profile' }, 'GRANT_MISMATCH'],
    [{ ...valid, workspaceId: PRIMEVIZ }, 'GRANT_MISMATCH'],
  ]) {
    const { client, requests } = setup({ grant });
    await assert.rejects(client.verifyIdentity(), { code });
    assert.equal(requests.length, 0);
  }
});

test('missing credentials stop before remote calls and credential exceptions stay private', async () => {
  const { profile: valid } = setup();
  for (const overrides of [
    { profile: { ...valid, secretRef: null } },
    { credentialReader: async () => '' },
    { credentialReader: async () => { throw new Error(TOKEN); } },
  ]) {
    const { client, requests } = setup(overrides);
    await assert.rejects(client.verifyIdentity(), error => {
      assert.ok(['CREDENTIAL_UNCONFIGURED', 'CREDENTIAL_UNAVAILABLE'].includes(error.code));
      assert.ok(!String(error.stack).includes(TOKEN));
      assert.ok(!JSON.stringify(error).includes(TOKEN));
      return true;
    });
    assert.equal(requests.length, 0);
  }
});

test('an exact grant cannot be used to read another page or expose a token in a URL', async () => {
  const { client, requests } = setup();
  await client.verifyIdentity();
  for (const [method, path, code] of [
    ['GET', `/v1/pages/${OTHER_PAGE}`, 'TARGET_OUT_OF_SCOPE'],
    ['GET', `https://api.notion.com/v1/pages/${PAGE}`, 'ENDPOINT_FORBIDDEN'],
    ['GET', `/v1/pages/${PAGE}?token=${TOKEN}`, 'ENDPOINT_FORBIDDEN'],
    ['GET', '/v1/search', 'ENDPOINT_FORBIDDEN'],
    ['PATCH', '/v1/users/me', 'ENDPOINT_FORBIDDEN'],
    ['DELETE', `/v1/pages/${PAGE}`, 'ENDPOINT_FORBIDDEN'],
  ]) {
    await assert.rejects(client.request(method, path, {}), { code });
  }
  assert.equal(requests.length, 1);
});

test('granted page, block, markdown and source reads stay inside the narrow endpoint contract', async () => {
  const { client } = setup();
  await client.verifyIdentity();
  for (const [method, path, body] of [
    ['GET', `/v1/pages/${PAGE}/markdown`],
    ['GET', `/v1/blocks/${PAGE}`],
    ['GET', `/v1/blocks/${PAGE}/children?start_cursor=${CHILD}&page_size=25`],
    ['GET', `/v1/data_sources/${SOURCE}`],
    ['POST', `/v1/data_sources/${SOURCE}/query`, { page_size: 50, filter: { property: 'Stable ID', rich_text: { equals: 'known-id' } } }],
  ]) assert.equal((await client.request(method, path, body)).status, 200);
});

test('update and insert are separate fixed-scope operations with an exact page parent', async () => {
  const { client } = setup();
  await client.verifyIdentity();
  assert.equal((await client.request('PATCH', `/v1/pages/${PAGE}`, { properties: { Summary: { rich_text: [] } } })).status, 200);
  assert.equal((await client.request('PATCH', `/v1/blocks/${PAGE}`, { paragraph: { rich_text: [] } })).status, 200);
  assert.equal((await client.request('POST', '/v1/pages', { parent: { type: 'data_source_id', data_source_id: SOURCE }, properties: {} })).status, 200);
});

test('read authorization and update or insert capability never imply write authorization', async () => {
  const { profile, grant } = setup();
  const readOnly = setup({ grant: { ...grant, mode: 'live', write: false } });
  await readOnly.client.verifyIdentity();
  await assert.rejects(readOnly.client.request('PATCH', `/v1/pages/${PAGE}`, { properties: {} }), { code: 'WRITE_GRANT_REQUIRED' });
  await assert.rejects(readOnly.client.request('POST', '/v1/pages', { parent: { page_id: PAGE } }), { code: 'WRITE_GRANT_REQUIRED' });
  assert.equal(readOnly.requests.length, 1);
  for (const [capabilities, method, path, body] of [
    [['read', 'insert'], 'PATCH', `/v1/pages/${PAGE}`, { properties: {} }],
    [['read', 'update'], 'POST', '/v1/pages', { parent: { page_id: PAGE } }],
  ]) {
    const { client, requests } = setup({ profile: { ...profile, capabilities } });
    await client.verifyIdentity();
    await assert.rejects(client.request(method, path, body), { code: 'CAPABILITY_REQUIRED' });
    assert.equal(requests.length, 1);
  }
  const noRead = setup({ profile: { ...profile, capabilities: ['insert'] } });
  await assert.rejects(noRead.client.verifyIdentity(), { code: 'CAPABILITY_REQUIRED' });
  assert.equal(noRead.requests.length, 0);
});

test('provider failures produce stable safe errors instead of provider text or redirects', async () => {
  for (const [status, code] of [[401, 'PROVIDER_UNAUTHORIZED'], [403, 'PROVIDER_FORBIDDEN'],
    [404, 'PROVIDER_NOT_FOUND'], [429, 'RATE_LIMITED'], [529, 'WORKSPACE_RATE_LIMITED'], [307, 'REDIRECT_FORBIDDEN']]) {
    const { client } = setup({ transport: { async request({ path }) {
      return path === '/v1/users/me' ? identity() : {
        status, data: { message: TOKEN }, headers: { 'Retry-After': '5', Location: `https://other.invalid/${TOKEN}` },
      };
    } } });
    await client.verifyIdentity();
    await assert.rejects(client.request('GET', `/v1/pages/${PAGE}`), error => {
      assert.equal(error.code, code);
      assert.equal(error.httpStatus, status);
      assert.ok(!JSON.stringify(error).includes(TOKEN));
      assert.ok(!String(error.stack).includes(TOKEN));
      return true;
    });
  }
});

test('lost write responses are unknown, never retried, and never expose raw transport errors', async () => {
  for (const fail of [async () => { throw new Error(TOKEN); }, async () => ({ status: 503, data: { message: TOKEN } })]) {
    let writes = 0;
    const { client } = setup({ transport: { async request({ path }) {
      if (path === '/v1/users/me') return identity();
      writes += 1;
      return fail();
    } } });
    await client.verifyIdentity();
    await assert.rejects(client.request('PATCH', `/v1/pages/${PAGE}`, { properties: {} }), error => {
      assert.ok(['TRANSPORT_FAILURE', 'PROVIDER_SERVER_ERROR'].includes(error.code));
      assert.equal(error.resultUnknown, true);
      assert.equal(error.retryable, false);
      assert.ok(!String(error.stack).includes(TOKEN));
      assert.ok(!JSON.stringify(error).includes(TOKEN));
      assert.ok(!JSON.stringify(client).includes(TOKEN));
      return true;
    });
    assert.equal(writes, 1);
  }
});

test('transient GET errors can recover within three attempts, while rate limits never auto-retry', async () => {
  let reads = 0;
  const recover = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity();
    reads += 1;
    return reads < 3 ? { status: 502, data: {} } : { status: 200, data: { id: PAGE } };
  } } });
  await recover.client.verifyIdentity();
  assert.equal((await recover.client.request('GET', `/v1/pages/${PAGE}`)).data.id, PAGE);
  assert.equal(reads, 3);
  for (const [status, hint, expectedReads] of [[503, undefined, 3], [503, '7', 1], [429, undefined, 1], [529, undefined, 1]]) {
    let attempts = 0;
    const { client } = setup({ transport: { async request({ path }) {
      if (path === '/v1/users/me') return identity();
      attempts += 1;
      return { status, data: {}, headers: hint ? { 'retry-after': hint } : {} };
    } } });
    await client.verifyIdentity();
    await assert.rejects(client.request('GET', `/v1/pages/${PAGE}`), error => !error.resultUnknown && error.retryAfter === (hint ? 7 : null));
    assert.equal(attempts, expectedReads);
  }
});

test('a malformed response after a write is unknown rather than successful', async () => {
  for (const response of [undefined, { status: '200', data: {} }, { status: 200, data: null }, { status: 200, data: [] }]) {
    const { client } = setup({ transport: { async request({ path }) { return path === '/v1/users/me' ? identity() : response; } } });
    await client.verifyIdentity();
    await assert.rejects(client.request('PATCH', `/v1/pages/${PAGE}`, { properties: {} }), error =>
      error.code === 'TRANSPORT_RESPONSE_INVALID' && error.resultUnknown === true);
  }
});

test('a created child with a verified scoped parent may be read back but never updated by implied permission', async () => {
  const { client } = setup({ transport: { async request({ method, path }) {
    if (path === '/v1/users/me') return identity();
    if (method === 'POST') return { status: 200, data: { object: 'page', id: CHILD, parent: { type: 'data_source_id', data_source_id: SOURCE } } };
    return { status: 200, data: { object: 'page', id: CHILD } };
  } } });
  await client.verifyIdentity();
  await client.request('POST', '/v1/pages', { parent: { data_source_id: SOURCE }, properties: {} });
  assert.equal((await client.request('GET', `/v1/pages/${CHILD}/markdown`)).data.id, CHILD);
  await assert.rejects(client.request('PATCH', `/v1/pages/${CHILD}`, { properties: {} }), { code: 'TARGET_OUT_OF_SCOPE' });
  await assert.rejects(client.request('GET', `/v1/blocks/${CHILD}`), { code: 'TARGET_OUT_OF_SCOPE' });
});

test('a source query grants child readback only for pages with that same verified parent', async () => {
  const { client } = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity();
    if (path.endsWith('/query')) return { status: 200, data: { object: 'list', results: [
      { object: 'page', id: CHILD, parent: { data_source_id: SOURCE } },
      { object: 'page', id: OTHER_PAGE, parent: { data_source_id: PAGE } },
    ] } };
    return { status: 200, data: { id: CHILD } };
  } } });
  await client.verifyIdentity();
  await client.request('POST', `/v1/data_sources/${SOURCE}/query`, { page_size: 100 });
  assert.equal((await client.request('GET', `/v1/pages/${CHILD}`)).data.id, CHILD);
  await assert.rejects(client.request('GET', `/v1/pages/${OTHER_PAGE}`), { code: 'TARGET_OUT_OF_SCOPE' });
});

test('a scoped block tree permits descendant reads only for exact provider-returned ancestry', async () => {
  const { client } = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity();
    if (path === `/v1/blocks/${PAGE}/children`) return { status: 200, data: { object: 'list', results: [
      { object: 'block', id: CHILD, type: 'paragraph', has_children: true, parent: { type: 'page_id', page_id: PAGE } },
      { object: 'block', id: OTHER_PAGE, type: 'paragraph', has_children: true, parent: { type: 'block_id', block_id: SOURCE } },
    ] } };
    return { status: 200, data: { object: 'list', results: [] } };
  } } });
  await client.verifyIdentity();
  await client.request('GET', `/v1/blocks/${PAGE}/children`);
  assert.equal((await client.request('GET', `/v1/blocks/${CHILD}/children`)).status, 200);
  await assert.rejects(client.request('PATCH', `/v1/blocks/${CHILD}`, { paragraph: {} }), { code: 'TARGET_OUT_OF_SCOPE' });
  await assert.rejects(client.request('GET', `/v1/blocks/${OTHER_PAGE}/children`), { code: 'TARGET_OUT_OF_SCOPE' });
});

test('a provider source parent may include validated database metadata without granting that database access', async () => {
  const { client } = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity();
    if (path === '/v1/pages') return { status: 200, data: { object: 'page', id: CHILD,
      parent: { type: 'data_source_id', data_source_id: SOURCE, database_id: OTHER_PAGE } } };
    return { status: 200, data: { id: CHILD } };
  } } });
  await client.verifyIdentity();
  await client.request('POST', '/v1/pages', { parent: { data_source_id: SOURCE }, properties: {} });
  assert.equal((await client.request('GET', `/v1/pages/${CHILD}`)).data.id, CHILD);
  await assert.rejects(client.request('GET', `/v1/pages/${OTHER_PAGE}`), { code: 'TARGET_OUT_OF_SCOPE' });
});

test('a failed identity recheck revokes previous verification and dynamic readback scope', async () => {
  let checks = 0;
  const { client } = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity(++checks === 1 ? EDWARD : PRIMEVIZ);
    return { status: 200, data: { id: PAGE } };
  } } });
  await client.verifyIdentity();
  await assert.rejects(client.verifyIdentity(), { code: 'WORKSPACE_MISMATCH' });
  await assert.rejects(client.request('GET', `/v1/pages/${PAGE}`), { code: 'IDENTITY_NOT_VERIFIED' });
  assert.equal(client.toJSON().verified, false);
});

test('a fixed profile has no default network transport and rejects malformed local identity before credentials', async () => {
  const { profile, grant } = setup();
  let credentialReads = 0;
  const credentialReader = async () => { credentialReads += 1; return TOKEN; };
  const noTransport = new FixedProfileClient({ profile, grant, credentialReader });
  await assert.rejects(noTransport.verifyIdentity(), { code: 'TRANSPORT_REQUIRED' });
  for (const invalid of [{ ...profile, workspaceId: 'guess' }, { ...profile, botId: null },
    { ...profile, apiVersion: '2026-03-11\nAuthorization: secret' }, { ...profile, capabilities: ['read', 'delete'] }]) {
    const client = new FixedProfileClient({ profile: invalid, grant, credentialReader, transport: { async request() { return identity(); } } });
    await assert.rejects(client.verifyIdentity(), { code: 'PROFILE_INVALID' });
  }
  assert.equal(credentialReads, 0);
});

test('credential references cannot read arbitrary Keychain services or malformed accounts', async () => {
  const invalidRefs = [null, { service: 'com.apple.login', account: EDWARD },
    { service: 'com.notion-coordination.', account: EDWARD },
    { service: 'com.xfit.notion-access', account: 'arbitrary-account' },
    { service: 'com.notion-coordination.primeviz', account: 'bad\naccount' }];
  for (const ref of invalidRefs) await assert.rejects(keychainCredentialReader(ref), { code: 'CREDENTIAL_REF_INVALID' });
  const { profile } = setup();
  let credentialReads = 0;
  const { client, requests } = setup({ profile: { ...profile, secretRef: { service: 'com.xfit.notion-access', account: PRIMEVIZ } },
    credentialReader: async () => { credentialReads += 1; return TOKEN; } });
  await assert.rejects(client.verifyIdentity(), { code: 'CREDENTIAL_REF_INVALID' });
  assert.equal(credentialReads, 0);
  assert.equal(requests.length, 0);
});

test('a scoped write cannot move, archive, restore or invent an ambiguous parent', async () => {
  const { client, requests } = setup();
  await client.verifyIdentity();
  for (const body of [{ archived: true }, { archived: false }, { in_trash: true }, { parent: { page_id: OTHER_PAGE } }, null]) {
    await assert.rejects(client.request('PATCH', `/v1/pages/${PAGE}`, body), { code: 'REQUEST_BODY_INVALID' });
  }
  for (const parent of [{ workspace: true }, { page_id: PAGE, data_source_id: SOURCE },
    { page_id: PAGE, type: 'data_source_id' }, { page_id: OTHER_PAGE }]) {
    await assert.rejects(client.request('POST', '/v1/pages', { parent }), error => ['REQUEST_BODY_INVALID', 'TARGET_OUT_OF_SCOPE'].includes(error.code));
  }
  assert.equal(requests.length, 1);
});

test('a grant with malformed or duplicate target identities cannot reach the provider', async () => {
  const { grant } = setup();
  for (const scopeTargets of [[PAGE, 'guess'], [PAGE, PAGE.replaceAll('-', '')]]) {
    const { client, requests } = setup({ grant: { ...grant, scopeTargets } });
    await assert.rejects(client.verifyIdentity(), { code: 'GRANT_INVALID' });
    assert.equal(requests.length, 0);
  }
});

test('two fixed profiles alternate without replacing shared authentication or borrowing another token', async () => {
  const primePage = '3dac1ddd-3200-804e-8659-d24dc06f16df';
  const transport = { async request({ token, path }) {
    const prime = token === 'fixture-primeviz-private';
    if (token !== TOKEN && !prime) return { status: 401, data: {} };
    if (path === '/v1/users/me') return identity(prime ? PRIMEVIZ : EDWARD, prime ? OTHER_PAGE : BOT);
    if (path !== `/v1/pages/${prime ? primePage : PAGE}`) return { status: 404, data: {} };
    return { status: 200, data: { workspace: prime ? 'PrimeViz' : "Edward’s Notion" } };
  } };
  const edward = setup({ transport }).client;
  const primeProfile = { id: 'primeviz-football', workspaceId: PRIMEVIZ, botId: OTHER_PAGE,
    secretRef: { service: 'com.notion-coordination.primeviz', account: PRIMEVIZ }, capabilities: ['read'], apiVersion: '2026-03-11' };
  const prime = setup({ profile: primeProfile, transport, credentialReader: async () => 'fixture-primeviz-private', grant: {
    mode: 'fixture', read: true, write: false, profileId: 'primeviz-football', workspaceId: PRIMEVIZ,
    scopeTargets: [primePage], reference: 'REQ-20261007-102225:second-profile-fixture',
  } }).client;
  await edward.verifyIdentity();
  await prime.verifyIdentity();
  const workspaces = [];
  workspaces.push((await edward.request('GET', `/v1/pages/${PAGE}`)).data.workspace);
  workspaces.push((await prime.request('GET', `/v1/pages/${primePage}`)).data.workspace);
  workspaces.push((await edward.request('GET', `/v1/pages/${PAGE}`)).data.workspace);
  assert.deepEqual(workspaces, ["Edward’s Notion", 'PrimeViz', "Edward’s Notion"]);
});

test('in-flight requests retain their approved parent even if caller input changes', async () => {
  let resolveWrite;
  let sentBody;
  const { client } = setup({ transport: { async request({ path, body }) {
    if (path === '/v1/users/me') return identity();
    if (path === '/v1/pages') {
      sentBody = body;
      return new Promise(resolve => { resolveWrite = resolve; });
    }
    return { status: 200, data: { id: CHILD } };
  } } });
  await client.verifyIdentity();
  const input = { parent: { page_id: PAGE }, properties: {} };
  const pending = client.request('POST', '/v1/pages', input);
  input.parent.page_id = OTHER_PAGE;
  assert.equal(sentBody.parent.page_id, PAGE);
  resolveWrite({ status: 200, data: { object: 'page', id: CHILD, parent: { page_id: PAGE } } });
  await pending;
  assert.equal((await client.request('GET', `/v1/pages/${CHILD}`)).data.id, CHILD);
});

test('an unparseable provider waiting hint still prevents automatic GET retry', async () => {
  let attempts = 0;
  const { client } = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity();
    attempts += 1;
    return { status: 503, data: {}, headers: { 'Retry-After': 'Wed, 07 Oct 2026 03:00:00 GMT' } };
  } } });
  await client.verifyIdentity();
  await assert.rejects(client.request('GET', `/v1/pages/${PAGE}`), { code: 'PROVIDER_SERVER_ERROR' });
  assert.equal(attempts, 1);
});

test('unexpected provider objects and unsafe error inputs serialize only stable safe metadata', async () => {
  const { client } = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity();
    return { status: 200, data: {}, get headers() { throw new Error(TOKEN); } };
  } } });
  await client.verifyIdentity();
  await assert.rejects(client.request('PATCH', `/v1/pages/${PAGE}`, { properties: {} }), error => {
    assert.equal(error.code, 'TRANSPORT_RESPONSE_INVALID');
    assert.equal(error.resultUnknown, true);
    assert.ok(!String(error.stack).includes(TOKEN));
    return true;
  });
  const unsafe = new ProfileError(TOKEN, { resultUnknown: TOKEN, retryAfter: TOKEN, httpStatus: TOKEN });
  assert.deepEqual(unsafe.toJSON(), { code: 'PROFILE_FAILURE', resultUnknown: false, retryable: false, retryAfter: null, httpStatus: null });
  assert.ok(!String(unsafe.stack).includes(TOKEN));
});

test('unsupported local configuration objects fail safely without retaining their raw exceptions', () => {
  const { profile, grant } = setup();
  const unsafeProfile = { get id() { throw new Error(TOKEN); } };
  assert.throws(() => new FixedProfileClient({ profile: unsafeProfile, grant }), error => {
    assert.equal(error.code, 'PROFILE_INVALID');
    assert.ok(!String(error.stack).includes(TOKEN));
    return true;
  });
  const unsafeGrant = { get reference() { throw new Error(TOKEN); } };
  assert.throws(() => new FixedProfileClient({ profile, grant: unsafeGrant }), { code: 'GRANT_INVALID' });
});

test('malformed pagination and destructive creation flags never reach the provider', async () => {
  const { client, requests } = setup();
  await client.verifyIdentity();
  for (const query of ['&&', 'page_size=0', 'page_size=101', 'page_size=5&page_size=6', 'start_cursor=%0A', 'start_cursor=%', 'token=hidden']) {
    await assert.rejects(client.request('GET', `/v1/blocks/${PAGE}/children?${query}`), { code: 'ENDPOINT_FORBIDDEN' });
  }
  await assert.rejects(client.request('POST', '/v1/pages', { parent: { page_id: PAGE }, archived: true }), { code: 'REQUEST_BODY_INVALID' });
  assert.equal(requests.length, 1);
});

test('a transport cannot mutate the requested parent to expand derived readback permission', async () => {
  const { client } = setup({ transport: { async request({ path, body }) {
    if (path === '/v1/users/me') return identity();
    if (path === '/v1/pages') {
      body.parent.page_id = OTHER_PAGE;
      return { status: 200, data: { object: 'page', id: CHILD, parent: { page_id: OTHER_PAGE } } };
    }
    return { status: 200, data: { id: CHILD } };
  } } });
  await client.verifyIdentity();
  await client.request('POST', '/v1/pages', { parent: { page_id: PAGE }, properties: {} });
  await assert.rejects(client.request('GET', `/v1/pages/${CHILD}`), { code: 'TARGET_OUT_OF_SCOPE' });
});

test('opaque pagination cursors are passed unchanged without relaxing entity UUID scope', async () => {
  const { client, requests } = setup();
  await client.verifyIdentity();
  const cursor = 'opaque v2: cursor/+?&=雪';
  const path = `/v1/blocks/${PAGE}/children?page_size=100&start_cursor=${encodeURIComponent(cursor)}`;
  await client.request('GET', path);
  assert.equal(new URL(requests.at(-1).path, 'https://fixture.invalid').searchParams.get('start_cursor'), cursor);
  await assert.rejects(client.request('GET', '/v1/blocks/opaque-entity/children'), { code: 'ENDPOINT_FORBIDDEN' });
});

test('the public client preserves sanitized wire budget and unknown-outcome codes without provider text', async () => {
  for (const [code, resultUnknown] of [['HTTP_REQUEST_BUDGET', false], ['HTTP_TIMEOUT', true]]) {
    const transport = { async request({ path }) {
      if (path === '/v1/users/me') return identity();
      const error = new ProfileError(code, { resultUnknown });
      error.message = TOKEN; error.details = TOKEN;
      throw error;
    } };
    const { client } = setup({ transport });
    await client.verifyIdentity();
    await assert.rejects(client.request('PATCH', `/v1/pages/${PAGE}`, { properties: {} }), error => {
      assert.equal(error.code, code); assert.equal(error.resultUnknown, resultUnknown);
      assert.ok(!JSON.stringify(error).includes(TOKEN)); assert.ok(!String(error.stack).includes(TOKEN));
      assert.equal(error.cause, undefined);
      return true;
    });
  }
});

test('a source-verified child page permits only its read-only root block listing, not arbitrary block reads or writes', async () => {
  const requests = [];
  const { client } = setup({ transport: { async request({ path, method }) {
    requests.push({ path, method });
    if (path === '/v1/users/me') return identity();
    if (path.endsWith('/query')) return { status: 200, data: { object: 'list', results: [
      { object: 'page', id: CHILD, parent: { type: 'data_source_id', data_source_id: SOURCE } }], has_more: false, next_cursor: null } };
    return { status: 200, data: { object: 'list', results: [], has_more: false, next_cursor: null } };
  } } });
  await client.verifyIdentity();
  await client.request('POST', `/v1/data_sources/${SOURCE}/query`, { page_size: 100 });
  assert.equal((await client.request('GET', `/v1/blocks/${CHILD}/children?page_size=100`)).data.object, 'list');
  await assert.rejects(client.request('GET', `/v1/blocks/${CHILD}`), { code: 'TARGET_OUT_OF_SCOPE' });
  await assert.rejects(client.request('PATCH', `/v1/blocks/${CHILD}`, { paragraph: {} }), { code: 'TARGET_OUT_OF_SCOPE' });
  await assert.rejects(client.request('GET', `/v1/blocks/${OTHER_PAGE}/children`), { code: 'TARGET_OUT_OF_SCOPE' });
  assert.equal(requests.length, 3);
});

test('wrong source parents, forged child UUIDs and unrelated creations cannot grant root tree reads', async () => {
  for (const record of [
    { object: 'page', id: CHILD, parent: { type: 'data_source_id', data_source_id: OTHER_PAGE } },
    { object: 'page', id: CHILD, parent: { type: 'page_id', page_id: SOURCE } },
    { object: 'page', id: 'fake-child', parent: { type: 'data_source_id', data_source_id: SOURCE } },
    { object: 'page', id: CHILD, parent: { type: 'data_source_id', data_source_id: SOURCE, extra: OTHER_PAGE } },
  ]) {
    const { client } = setup({ transport: { async request({ path }) {
      if (path === '/v1/users/me') return identity();
      return { status: 200, data: { object: 'list', results: [record], has_more: false, next_cursor: null } };
    } } });
    await client.verifyIdentity();
    await client.request('POST', `/v1/data_sources/${SOURCE}/query`, {});
    await assert.rejects(client.request('GET', `/v1/blocks/${CHILD}/children`), { code: 'TARGET_OUT_OF_SCOPE' });
  }
  const { client } = setup({ transport: { async request({ path }) {
    if (path === '/v1/users/me') return identity();
    return { status: 200, data: { object: 'page', id: CHILD, parent: { type: 'page_id', page_id: PAGE } } };
  } } });
  await client.verifyIdentity();
  await client.request('POST', '/v1/pages', { parent: { page_id: PAGE }, properties: {} });
  await assert.rejects(client.request('GET', `/v1/blocks/${CHILD}/children`), { code: 'TARGET_OUT_OF_SCOPE' });
});
