import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { FixedProfileClient } from '../../scripts/notion-coordination/profiles.mjs';
import { NotionHttpTransport } from '../../scripts/notion-coordination/transport.mjs';
import { inspectConnection, DoctorError } from '../../scripts/notion-coordination/doctor.mjs';

const WORKSPACE = 'c63f367d-6f39-41c0-9a28-e4ad2ce10251';
const BOT = 'a1111111-1111-4111-8111-111111111111';
const PAGE = '6d6b5fb7-de5c-446a-a503-8b6462833486';
const SOURCE = '09fd5db5-21f6-4d39-869d-e3ad0b2f444e';
const OTHER = 'b2222222-2222-4222-8222-222222222222';
const BLOCK = 'c3333333-3333-4333-8333-333333333333';
const NESTED = 'd4444444-4444-4444-8444-444444444444';
const TOKEN = 'fixture-doctor-private-not-production';
const PRIVATE = 'private-human-note-never-export';
const list = (results = [], has_more = false, next_cursor = null) => ({ object: 'list', results, has_more, next_cursor });
const block = (id = BLOCK, parent = PAGE, type = 'page_id', has_children = false) => ({
  object: 'block', id, type: 'paragraph', parent: { type, [type]: parent }, has_children,
  archived: false, in_trash: false, paragraph: { rich_text: [{ type: 'text', text: { content: PRIVATE } }] },
});

async function setup(t, { kind = 'page', respond, grant: grantOverride } = {}) {
  const profile = { id: 'doctor-edward-fixed', workspaceId: WORKSPACE, botId: BOT,
    secretRef: { service: 'com.xfit.notion-access', account: WORKSPACE },
    capabilities: ['read', 'insert', 'update'], apiVersion: '2026-03-11' };
  const target = { id: kind === 'page' ? PAGE : SOURCE, kind, stableIdProperty: null,
    allowedProperties: {}, allowedBlocks: {}, humanProperties: [], schemaVerified: false };
  const route = { projectId: 'doctor-fixture', profileId: profile.id, workspaceId: WORKSPACE, profile,
    targetAlias: 'selected', target, targets: { selected: structuredClone(target), decoy: { ...target, id: OTHER } } };
  const model = {
    identity: { object: 'user', id: BOT, type: 'bot', name: PRIVATE, bot: { workspace_id: WORKSPACE } },
    source: { object: 'data_source', id: SOURCE, archived: false, in_trash: false,
      properties: { Name: { id: 'title', name: 'Name', type: 'title', title: {} } } },
    page: { object: 'page', id: PAGE, archived: false, in_trash: false, parent: { type: 'data_source_id', data_source_id: SOURCE },
      properties: { Name: { id: 'title', type: 'title', title: [{ plain_text: PRIVATE }] } } },
    markdown: { object: 'page_markdown', id: PAGE, markdown: PRIVATE, truncated: false, unknown_block_ids: [] },
    query: list([{ object: 'page', id: PAGE, parent: { type: 'data_source_id', data_source_id: SOURCE } }]),
    trees: new Map([[PAGE, list([block()])]]),
  };
  const requests = [];
  const server = http.createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : undefined;
    const url = new URL(req.url, 'http://127.0.0.1');
    requests.push({ method: req.method, path: req.url, body });
    let data;
    if (url.pathname === '/v1/users/me') data = model.identity;
    else if (url.pathname === `/v1/data_sources/${SOURCE}`) data = model.source;
    else if (url.pathname === `/v1/data_sources/${SOURCE}/query`) data = model.query;
    else if (url.pathname === `/v1/pages/${PAGE}`) data = model.page;
    else if (url.pathname === `/v1/pages/${PAGE}/markdown`) data = model.markdown;
    else if (/^\/v1\/blocks\/.+\/children$/.test(url.pathname)) data = model.trees.get(url.pathname.split('/')[3]) ?? list();
    else data = { unexpected: true };
    data = structuredClone(data);
    if (respond) data = await respond({ method: req.method, path: req.url, url, body, data, model });
    res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(data));
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(async () => { const closed = once(server, 'close'); server.closeAllConnections(); server.close(); await closed; });
  const transport = new NotionHttpTransport({ mode: 'fixture', origin: `http://127.0.0.1:${server.address().port}`, maxRequests: 300 });
  const grant = { mode: 'fixture', read: true, write: false, profileId: profile.id, workspaceId: WORKSPACE,
    scopeTargets: [target.id], reference: 'doctor-fixture-read-only', ...grantOverride };
  const client = new FixedProfileClient({ profile, grant, credentialReader: async () => TOKEN, transport });
  return { route, client, model, requests };
}

test('a selected page with unknown owned fields is inspected read-only without activating or exporting private content', async t => {
  const { route, client, requests } = await setup(t);
  const before = JSON.stringify(route);
  const result = await inspectConnection({ route, client });
  assert.deepEqual(result, {
    status: 'inspection_verified', identity: { verified: true, profileId: route.profileId, botId: BOT, workspaceId: WORKSPACE },
    target: { alias: 'selected', id: PAGE, kind: 'page' }, counts: { pages: 1, blocks: 1, queryPages: 0, blockListPages: 1 },
    completeness: { schema: true, records: true, markdown: true, blockTree: true },
    evidenceScope: { records: 'page_enumeration_only', schema: 'observed_metadata_only', propertyValues: 'not_inspected' },
    observedSchema: [{ name: 'Name', id: 'title', type: 'title' }], permissionsActivated: false, writes: 0,
  });
  assert.equal(JSON.stringify(route), before);
  assert.ok(!JSON.stringify(result).includes(PRIVATE)); assert.ok(!JSON.stringify(result).includes(TOKEN));
  assert.ok(requests.every(request => request.method === 'GET'));
  assert.ok(requests.every(request => !request.path.includes(OTHER) && !request.path.includes(SOURCE)));
});

test('a full nested block tree follows opaque cursors exactly and never adds descendant write permission', async t => {
  const cursor = 'opaque:block v2/+?&=雪';
  const tail = 'e5555555-5555-4555-8555-555555555555';
  const { route, client, model, requests } = await setup(t, { respond: ({ url, data }) => {
    if (url.pathname === `/v1/blocks/${PAGE}/children` && url.searchParams.has('start_cursor')) {
      assert.equal(url.searchParams.get('start_cursor'), cursor);
      return list([block(tail)]);
    }
    return data;
  } });
  model.trees.set(PAGE, list([block(BLOCK, PAGE, 'page_id', true)], true, cursor));
  model.trees.set(BLOCK, list([block(NESTED, BLOCK, 'block_id')]));
  const result = await inspectConnection({ route, client });
  assert.equal(result.counts.blocks, 3); assert.equal(result.counts.blockListPages, 3);
  assert.equal(requests.filter(request => request.path.includes('start_cursor')).length, 1);
  assert.ok(requests.every(request => request.method === 'GET'));
  await assert.rejects(client.request('PATCH', `/v1/blocks/${NESTED}`, { paragraph: { rich_text: [] } }),
    { code: 'WRITE_GRANT_REQUIRED' });
  assert.equal(requests.filter(request => request.method === 'PATCH').length, 0);
});

test('a selected data source is inspected through finite read-only POST queries and complete child reads', async t => {
  const cursor = 'opaque:query next/+?&=雪';
  const { route, client, requests } = await setup(t, { kind: 'data_source', respond: ({ path, body, data, model }) => {
    if (path === `/v1/data_sources/${SOURCE}/query`) {
      assert.equal(body.page_size, 100);
      if (body.start_cursor === undefined) return list([model.query.results[0]], true, cursor);
      assert.equal(body.start_cursor, cursor);
      return list([{ object: 'page', id: OTHER, parent: { type: 'data_source_id', data_source_id: SOURCE } }]);
    }
    if (path === `/v1/pages/${OTHER}`) return { ...model.page, id: OTHER };
    if (path === `/v1/pages/${OTHER}/markdown`) return { ...model.markdown, id: OTHER };
    if (path.startsWith(`/v1/blocks/${OTHER}/children`)) return list();
    return data;
  } });
  const result = await inspectConnection({ route, client });
  assert.deepEqual(result.counts, { pages: 2, blocks: 1, queryPages: 2, blockListPages: 2 });
  assert.deepEqual(result.observedSchema, [{ name: 'Name', id: 'title', type: 'title' }]);
  assert.equal(result.permissionsActivated, false); assert.equal(route.target.schemaVerified, false);
  assert.ok(!JSON.stringify(result).includes(PRIVATE));
  assert.ok(requests.filter(request => request.method === 'POST').every(request => request.path === `/v1/data_sources/${SOURCE}/query`));
  assert.equal(requests.filter(request => request.path === '/v1/pages' || request.method === 'PATCH').length, 0);
});

test('unknown routes, client contracts, grants and identities stop before unrelated reads', async t => {
  const { route, client, model, requests } = await setup(t);
  for (const change of [{ targetAlias: '' }, { target: { id: 'unknown', kind: 'page' } },
    { profileId: 'wrong-profile' }, { workspaceId: OTHER }]) {
    await assert.rejects(inspectConnection({ route: { ...route, ...change }, client }), { code: 'DOCTOR_ROUTE_INVALID' });
  }
  await assert.rejects(inspectConnection({ route, client: {} }), { code: 'DOCTOR_CLIENT_INVALID' });
  assert.equal(requests.length, 0);
  model.identity.bot.workspace_id = OTHER;
  await assert.rejects(inspectConnection({ route, client }), { code: 'WORKSPACE_MISMATCH' });
  assert.equal(requests.length, 1);
  const blocked = await setup(t, { grant: { read: false } });
  await assert.rejects(inspectConnection(blocked), { code: 'READ_GRANT_REQUIRED' });
  assert.equal(blocked.requests.length, 0);
});

test('truncated, unknown or wrong-id Markdown stops without following unknown block identifiers', async t => {
  const { route, client, model, requests } = await setup(t);
  for (const change of [{ id: OTHER }, { truncated: true }, { unknown_block_ids: [OTHER] },
    { unknown_block_ids: null }, { markdown: '<unknown-block/>' }, { markdown: '<unknown url="private"/>' },
    { object: 'page' }, { markdown: null }]) {
    const original = model.markdown; model.markdown = { ...original, ...change };
    const start = requests.length;
    await assert.rejects(inspectConnection({ route, client }), { code: 'DOCTOR_MARKDOWN_INCOMPLETE' });
    assert.ok(requests.slice(start).every(request => !request.path.includes(OTHER) && !request.path.includes('/blocks/')));
    model.markdown = original;
  }
});

test('source and page identities, explicit schema fields and child parent mismatches remain incomplete', async t => {
  const { route, client, model, requests } = await setup(t, { kind: 'data_source' });
  for (const [field, change, code] of [
    ['source', { id: OTHER }, 'DOCTOR_SOURCE_INVALID'], ['source', { archived: true }, 'DOCTOR_SOURCE_INVALID'],
    ['source', { properties: { Name: { type: 'title', title: {} } } }, 'DOCTOR_SCHEMA_INCOMPLETE'],
    ['source', { properties: { Name: { id: 'title', name: 'wrong', type: 'title', title: {} } } }, 'DOCTOR_SCHEMA_INCOMPLETE'],
    ['query', { results: [{ object: 'page', id: PAGE, parent: { type: 'data_source_id', data_source_id: OTHER } }] }, 'DOCTOR_PARENT_MISMATCH'],
    ['query', { results: [{ object: 'page', id: 'fake-page', parent: { type: 'data_source_id', data_source_id: SOURCE } }] }, 'DOCTOR_PAGE_INVALID'],
    ['page', { id: OTHER }, 'DOCTOR_PAGE_INVALID'], ['page', { archived: true }, 'DOCTOR_PAGE_INVALID'],
    ['page', { parent: { type: 'data_source_id', data_source_id: OTHER } }, 'DOCTOR_PARENT_MISMATCH'],
    ['page', { properties: { Name: { id: 'title', type: 'title', title: [], has_more: true } } }, 'DOCTOR_SCHEMA_INCOMPLETE'],
  ]) {
    const original = model[field]; model[field] = { ...original, ...change };
    const start = requests.length;
    await assert.rejects(inspectConnection({ route, client }), { code });
    assert.ok(requests.slice(start).every(request => !request.path.includes(OTHER) && !request.path.includes('fake-page')));
    model[field] = original;
  }
});

test('block ancestry, duplicate normalized IDs and unsupported structures cannot be declared complete', async t => {
  const { route, client, model, requests } = await setup(t);
  for (const [blocks, code] of [
    [[{ ...block(), parent: { type: 'page_id', page_id: OTHER } }], 'DOCTOR_PARENT_MISMATCH'],
    [[{ ...block(), parent: { type: 'block_id', block_id: PAGE } }], 'DOCTOR_PARENT_MISMATCH'],
    [[block(), block(BLOCK.replaceAll('-', '').toUpperCase())], 'DOCTOR_DUPLICATE_OBJECT'],
    [[{ ...block(), id: 'not-a-uuid' }], 'DOCTOR_BLOCK_INVALID'],
    [[{ ...block(), has_children: null }], 'DOCTOR_BLOCK_INVALID'],
    [[{ ...block(), archived: true }], 'DOCTOR_BLOCK_INVALID'],
    [[{ ...block(), type: 'unsupported', unsupported: {} }], 'DOCTOR_BLOCK_INVALID'],
  ]) {
    model.trees.set(PAGE, list(blocks)); const start = requests.length;
    await assert.rejects(inspectConnection({ route, client }), { code });
    assert.ok(requests.slice(start).every(request => !request.path.includes(OTHER)));
  }
});

test('missing, empty and malformed pagination flags cannot mean a complete page or source', async t => {
  for (const kind of ['page', 'data_source']) {
    const { route, client, model } = await setup(t, { kind });
    for (const change of [{ has_more: undefined }, { has_more: true, next_cursor: 'next', results: [] },
      { has_more: true, next_cursor: null }, { has_more: false, next_cursor: 'unexpected' },
      { has_more: true, next_cursor: '\nunsafe' }, { has_more: true, next_cursor: 'x'.repeat(2049) },
      { results: {} }, { object: 'page' }]) {
      const original = kind === 'page' ? model.trees.get(PAGE) : model.query;
      if (kind === 'page') model.trees.set(PAGE, { ...original, ...change });
      else model.query = { ...original, ...change };
      await assert.rejects(inspectConnection({ route, client }), { code: 'DOCTOR_PAGINATION_INCOMPLETE' });
      if (kind === 'page') model.trees.set(PAGE, original); else model.query = original;
    }
  }
});

test('repeated cursors and cyclic block IDs stop within finite reads', async t => {
  let blockPages = 0;
  const { route, client, model, requests } = await setup(t, { respond: ({ url, data }) => {
    if (url.pathname === `/v1/blocks/${PAGE}/children`) {
      blockPages += 1;
      return list([block(blockPages === 1 ? BLOCK : NESTED)], true, 'opaque-repeat');
    }
    return data;
  } });
  await assert.rejects(inspectConnection({ route, client }), { code: 'DOCTOR_PAGINATION_INCOMPLETE' });
  assert.equal(blockPages, 2);
  const cyclic = await setup(t);
  cyclic.model.trees.set(PAGE, list([block(BLOCK, PAGE, 'page_id', true)]));
  cyclic.model.trees.set(BLOCK, list([block(NESTED, BLOCK, 'block_id', true)]));
  cyclic.model.trees.set(NESTED, list([block(BLOCK, NESTED, 'block_id')]));
  await assert.rejects(inspectConnection(cyclic), { code: 'DOCTOR_DUPLICATE_OBJECT' });
  assert.equal(cyclic.requests.filter(request => request.path.includes('/blocks/')).length, 3);
  assert.ok(requests.every(request => request.method === 'GET'));
});

test('duplicate query pages and source cursor loops do not re-read forever or add a record', async t => {
  const duplicate = await setup(t, { kind: 'data_source' });
  duplicate.model.query.results.push({ ...duplicate.model.query.results[0], id: PAGE.replaceAll('-', '').toUpperCase() });
  await assert.rejects(inspectConnection(duplicate), { code: 'DOCTOR_DUPLICATE_OBJECT' });
  assert.equal(duplicate.requests.filter(request => request.path === `/v1/pages/${PAGE}`).length, 1);
  let queryPages = 0;
  const repeated = await setup(t, { kind: 'data_source', respond: ({ path, data, model }) => {
    if (path === `/v1/data_sources/${SOURCE}/query`) {
      queryPages += 1;
      return list([{ object: 'page', id: queryPages === 1 ? PAGE : OTHER,
        parent: { type: 'data_source_id', data_source_id: SOURCE } }], true, 'same-opaque-query');
    }
    if (path === `/v1/pages/${OTHER}`) return { ...model.page, id: OTHER };
    if (path === `/v1/pages/${OTHER}/markdown`) return { ...model.markdown, id: OTHER };
    return data;
  } });
  await assert.rejects(inspectConnection(repeated), { code: 'DOCTOR_PAGINATION_INCOMPLETE' });
  assert.equal(queryPages, 2);
  assert.ok(repeated.requests.filter(request => request.method === 'POST').every(request => request.path.endsWith('/query')));
});

test('tree depth, pagination and cumulative object limits fail closed rather than claiming partial completeness', async t => {
  const deep = await setup(t);
  let parent = PAGE;
  for (let depth = 0; depth <= 8; depth += 1) {
    const id = `${String(depth + 1).padStart(8, '0')}-1111-4111-8111-111111111111`;
    deep.model.trees.set(parent, list([block(id, parent, depth === 0 ? 'page_id' : 'block_id', true)]));
    parent = id;
  }
  await assert.rejects(inspectConnection(deep), { code: 'DOCTOR_LIMIT' });
  assert.equal(deep.requests.filter(request => request.path.includes('/blocks/')).length, 9);
  let pages = 0;
  const paged = await setup(t, { respond: ({ url, data }) => {
    if (url.pathname === `/v1/blocks/${PAGE}/children`) {
      pages += 1;
      return list([block(`${String(pages).padStart(8, '0')}-2222-4222-8222-222222222222`)], true, `cursor-${pages}`);
    }
    return data;
  } });
  await assert.rejects(inspectConnection(paged), { code: 'DOCTOR_LIMIT' });
  assert.equal(pages, 20);
  let total = 0;
  const many = await setup(t, { respond: ({ url, data }) => {
    if (url.pathname === `/v1/blocks/${PAGE}/children`) {
      const records = Array.from({ length: 100 }, () => block(`${String(++total).padStart(8, '0')}-3333-4333-8333-333333333333`));
      return list(records, true, `many-${total}`);
    }
    return data;
  } });
  await assert.rejects(inspectConnection(many), { code: 'DOCTOR_LIMIT' });
  assert.equal(many.requests.filter(request => request.path.includes('/blocks/')).length, 10);
});

test('raw client failures, malicious metadata getters and error text cannot escape doctor output', async t => {
  const { route } = await setup(t);
  const safeIdentity = { verified: true, profileId: route.profileId, botId: BOT, workspaceId: WORKSPACE };
  for (const client of [
    { async verifyIdentity() { throw new Error(`${TOKEN} ${PRIVATE}`); }, async request() {} },
    { async verifyIdentity() { return safeIdentity; }, async request() { return { status: 200, data: {}, get headers() { throw new Error(TOKEN); } }; } },
  ]) {
    await assert.rejects(inspectConnection({ route, client }), error => {
      assert.ok(error instanceof DoctorError); assert.equal(error.code, 'DOCTOR_CLIENT_FAILURE');
      assert.ok(!JSON.stringify(error).includes(TOKEN)); assert.ok(!String(error.stack).includes(PRIVATE));
      assert.equal(error.cause, undefined); return true;
    });
  }
  await assert.rejects(inspectConnection({ get route() { throw new Error(TOKEN); } }), error => {
    assert.equal(error.code, 'DOCTOR_CLIENT_FAILURE'); assert.ok(!String(error.stack).includes(TOKEN)); return true;
  });
});
