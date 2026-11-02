import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectAdapter, AdapterError } from '../../scripts/notion-coordination/adapters.mjs';
import { NotionFixture, appendRoute, appendIntent, updateRoute, SOURCE, PAGE, BLOCK } from './adapters-fixture.mjs';

test('unknown or empty project scope cannot create a writable adapter', () => {
  const client = { async verifyIdentity() {}, async request() { assert.fail('unknown scope must not access the provider'); } };
  assert.throws(() => createProjectAdapter({ route: { projectId: 'xfit', adapterId: 'unknown', targets: {} }, client }), AdapterError);
  assert.throws(() => createProjectAdapter({ route: { projectId: 'xfit', adapterId: 'xfit-append', targets: {} }, client }), AdapterError);
});

test('owned update changes only an explicit property and text block, preserving human values and block styling', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  const intent = { operationId: 'engineering-1', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '本地验证通过，真实接入待核验。' }, { blockId: BLOCK, value: '新的工程摘要' }] };
  const preview = await adapter.prepare(intent);
  assert.equal(preview.action, 'update');
  const result = await adapter.apply(intent, preview);
  assert.equal(result.status, 'readback_verified');
  const saved = await client.request('GET', `/pages/${PAGE}`);
  assert.equal(saved.data.properties['人工批准'].checkbox, false);
  assert.equal(saved.data.properties['工程摘要'].rich_text[0].text.content, '本地验证通过，真实接入待核验。');
  const block = await client.request('GET', `/blocks/${BLOCK}`);
  assert.equal(block.data.paragraph.rich_text[0].text.content, '新的工程摘要');
  assert.equal(block.data.paragraph.color, 'purple');
  assert.equal((await adapter.prepare(intent)).action, 'no_op');
});

test('X-Fit appends a new stable record and verifies its actual content without touching old records', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  const intent = appendIntent();
  const preview = await adapter.prepare(intent);
  assert.equal(preview.action, 'append');
  const result = await adapter.apply(intent, preview);
  assert.equal(result.status, 'readback_verified');
  const found = await client.request('POST', `/data_sources/${SOURCE}/query`, { filter: { property: '记录ID', rich_text: { equals: 'feedback-1' } } });
  assert.equal(found.data.results.length, 1);
  const saved = await client.request('GET', `/pages/${found.data.results[0].id}/markdown`);
  assert.equal(saved.data.markdown, '今天没有肘部不适。');
  assert.equal(found.data.results[0].properties['本人反馈'].rich_text[0].text.content, '训练感觉偏轻，具体RIR未知。');
  const repeat = await adapter.prepare(intent);
  assert.equal(repeat.action, 'no_op');
  await adapter.apply(intent, repeat);
  assert.equal(client.effects.length, 1);
});

test('a partially applied owned batch stops as unknown and read-only reconciliation does not repeat writes', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  const intent = { operationId: 'engineering-partial', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '已写入的属性' }, { blockId: BLOCK, value: '尚未写入的块' }] };
  const preview = await adapter.prepare(intent);
  client.blockUpdateStatus = 403;
  await assert.rejects(adapter.apply(intent, preview), error => error instanceof AdapterError && error.resultUnknown === true);
  await assert.rejects(adapter.reconcile(intent, preview), error => error.code === 'readback_mismatch');
  assert.equal(client.effects.length, 1);
  const actual = await client.request('GET', `/pages/${PAGE}`);
  assert.equal(actual.data.properties['工程摘要'].rich_text[0].text.content, '已写入的属性');
});

test('unsupported Markdown tags cannot masquerade as a complete page even when completion flags are clear', async () => {
  const client = new NotionFixture();
  client.markdownFlags.markdown = '<unknown-block/>';
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  const intent = { operationId: 'engineering-incomplete', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '不能覆盖不完整页面' }] };
  await assert.rejects(adapter.prepare(intent), error => error.code === 'page_incomplete');
  assert.equal(client.effects.length, 0);
});

test('a lost append response is reconciled read-only and is never blindly re-appended', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  const intent = appendIntent();
  const preview = await adapter.prepare(intent);
  client.failAfterCreate = true;
  await assert.rejects(adapter.apply(intent, preview), error => error.resultUnknown === true);
  assert.equal((await adapter.reconcile(intent, preview)).status, 'readback_verified');
  await assert.rejects(adapter.apply(intent, preview), error => error.code === 'preview_stale');
  assert.equal(client.effects.length, 1);
});

test('preview snapshots the submitted intent instead of following caller mutations during provider reads', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  const submitted = appendIntent();
  const pending = adapter.prepare(submitted);
  submitted.record.body = '另一个还未提交的草稿';
  const preview = await pending;
  const original = appendIntent();
  assert.equal((await adapter.apply(original, preview)).status, 'readback_verified');
  const found = await client.request('POST', `/data_sources/${SOURCE}/query`, { filter: { property: '记录ID', rich_text: { equals: 'feedback-1' } } });
  const saved = await client.request('GET', `/pages/${found.data.results[0].id}/markdown`);
  assert.equal(saved.data.markdown, '今天没有肘部不适。');
});

test('human approval is never writable through an engineering-owned adapter', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  await assert.rejects(adapter.prepare({ operationId: 'human-write', kind: 'owned-update', target: 'summary', changes: [{ property: '人工批准', value: true }] }), error => error.code === 'property_not_owned');
  assert.equal(client.effects.length, 0);
});

test('an existing stable ID with changed content is a conflict, not an append or update', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  const intent = appendIntent();
  await adapter.apply(intent, await adapter.prepare(intent));
  intent.record.body = '未经确认的新内容';
  await assert.rejects(adapter.prepare(intent), error => error.code === 'stable_id_conflict');
  assert.equal(client.effects.length, 1);
});

test('duplicate provider rows for one stable ID block further writes', async () => {
  const client = new NotionFixture();
  const properties = { '记录ID': { rich_text: [{ type: 'text', text: { content: 'feedback-1' } }] }, '名称': { title: [{ type: 'text', text: { content: '训练反馈' } }] }, '本人反馈': { rich_text: [{ type: 'text', text: { content: '训练感觉偏轻，具体RIR未知。' } }] } };
  await client.request('POST', '/pages', { parent: { data_source_id: SOURCE }, properties, markdown: '今天没有肘部不适。' });
  await client.request('POST', '/pages', { parent: { data_source_id: SOURCE }, properties, markdown: '今天没有肘部不适。' });
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  await assert.rejects(adapter.prepare(appendIntent()), error => error.code === 'stable_id_duplicate');
  assert.equal(client.effects.length, 2);
});

test('readback does not declare success if the provider rewrites unowned text styling', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  const intent = { operationId: 'styling-check', kind: 'owned-update', target: 'summary', changes: [{ blockId: BLOCK, value: '新的文字，样式不应改变' }] };
  const preview = await adapter.prepare(intent);
  client.rewriteStyle = true;
  await assert.rejects(adapter.apply(intent, preview), error => error.code === 'protected_changed' && error.resultUnknown === true);
  assert.equal(client.effects.length, 1);
});

test('text updates preserve an existing link without sending provider read-only rich-text fields', async () => {
  const client = new NotionFixture();
  const block = client.blocks.get(BLOCK);
  block.paragraph.rich_text[0].text.link = { url: 'https://example.test/reference' };
  block.paragraph.rich_text[0].href = 'https://example.test/reference';
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  const intent = { operationId: 'link-check', kind: 'owned-update', target: 'summary', changes: [{ blockId: BLOCK, value: '只更改文字' }] };
  const result = await adapter.apply(intent, await adapter.prepare(intent));
  assert.equal(result.status, 'readback_verified');
  const saved = await client.request('GET', `/blocks/${BLOCK}`);
  assert.equal(saved.data.paragraph.rich_text[0].text.link.url, 'https://example.test/reference');
});

test('unknown actual database schema stops the X-Fit append contract without guessing property names', async () => {
  const client = new NotionFixture();
  delete client.source.properties['记录ID'];
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  await assert.rejects(adapter.prepare(appendIntent()), error => error.code === 'source_schema_mismatch');
  assert.equal(client.effects.length, 0);
});

test('missing completion flags remain unknown rather than an empty or complete page', async () => {
  const client = new NotionFixture();
  client.markdownFlags.truncated = undefined;
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  await assert.rejects(adapter.prepare({ operationId: 'missing-flags', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '不能写' }] }), error => error.code === 'page_incomplete');
  assert.equal(client.effects.length, 0);
});

test('a moved owned block is not updated under its old page grant', async () => {
  const client = new NotionFixture();
  client.blocks.get(BLOCK).parent = { type: 'page_id', page_id: '20000000-0000-4000-8000-000000000004' };
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  await assert.rejects(adapter.prepare({ operationId: 'moved-block', kind: 'owned-update', target: 'summary', changes: [{ blockId: BLOCK, value: '不能越界写' }] }), error => error.code === 'block_scope_moved');
  assert.equal(client.effects.length, 0);
});

test('an incomplete stable-ID query is not treated as absence and cannot create a record', async () => {
  const provider = new NotionFixture();
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, path, body) {
    const response = await provider.request(method, path, body);
    if (method === 'POST' && path.endsWith('/query')) response.data.has_more = true;
    return response;
  } };
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  await assert.rejects(adapter.prepare(appendIntent()), error => error.code === 'query_incomplete');
  assert.equal(provider.effects.length, 0);
});

test('a concurrent human edit makes the old preview stale and remains untouched', async () => {
  const client = new NotionFixture();
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  const intent = { operationId: 'human-race', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: 'AI的新摘要' }] };
  const preview = await adapter.prepare(intent);
  await client.request('PATCH', `/pages/${PAGE}`, { properties: { '人工批准': { checkbox: true } } });
  await assert.rejects(adapter.apply(intent, preview), error => error.code === 'preview_stale');
  const page = await client.request('GET', `/pages/${PAGE}`);
  assert.equal(page.data.properties['人工批准'].checkbox, true);
  assert.equal(page.data.properties['工程摘要'].rich_text[0].text.content, '原工程摘要');
  assert.equal(client.effects.length, 1);
});

test('archived target pages cannot produce a writable preview', async () => {
  const client = new NotionFixture();
  client.pages.get(PAGE).page.archived = true;
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  await assert.rejects(adapter.prepare({ operationId: 'archived-target', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '不能恢复归档页来写' }] }), error => error.code === 'page_invalid');
  assert.equal(client.effects.length, 0);
});

test('partially hyphenated identifiers are rejected locally rather than routed to the provider', () => {
  const route = updateRoute();
  route.targets.summary.id = '100000000000-4000-8000-000000000002';
  assert.throws(() => createProjectAdapter({ route, client: new NotionFixture() }), error => error.code === 'target_invalid');
});

test('a known fixed-profile permission denial remains a permission gate, not an unknown committed write', async () => {
  const provider = new NotionFixture();
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, path, body) {
    if (method === 'POST' && path === '/v1/pages') {
      const error = new Error('sensitive provider text is not forwarded');
      error.code = 'PROVIDER_FORBIDDEN';
      error.resultUnknown = false;
      throw error;
    }
    return provider.request(method, path, body);
  } };
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  const intent = appendIntent();
  await assert.rejects(adapter.apply(intent, await adapter.prepare(intent)), error => error.code === 'PROVIDER_FORBIDDEN' && error.resultUnknown === false && !error.message.includes('sensitive'));
  assert.equal(provider.effects.length, 0);
});

test('a query result with an inconsistent parent type cannot be accepted as a bound database record', async () => {
  const provider = new NotionFixture();
  const base = createProjectAdapter({ route: appendRoute(), client: provider });
  const intent = appendIntent();
  await base.apply(intent, await base.prepare(intent));
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, path, body) {
    const response = await provider.request(method, path, body);
    if (path.endsWith('/query')) response.data.results[0].parent.type = 'page_id';
    return response;
  } };
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  await assert.rejects(adapter.prepare(intent), error => error.code === 'query_invalid');
  assert.equal(provider.effects.length, 1);
});

test('stable-ID lookup passes an opaque pagination cursor unchanged rather than requiring a UUID', async () => {
  const provider = new NotionFixture();
  const cursor = 'opaque/page+2== &not-an-id';
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, path, body) {
    if (path.endsWith('/query') && !Object.hasOwn(body, 'start_cursor')) return { status: 200, data: { object: 'list', results: [], has_more: true, next_cursor: cursor }, headers: {} };
    if (path.endsWith('/query')) assert.equal(body.start_cursor, 'opaque/page+2== &not-an-id');
    return provider.request(method, path, body);
  } };
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  assert.equal((await adapter.prepare(appendIntent())).action, 'append');
  assert.equal(provider.effects.length, 0);
});

test('block-tree pagination encodes then decodes an opaque cursor without changing its value', async () => {
  const provider = new NotionFixture();
  const cursor = 'opaque/block+page== &next';
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, path, body) {
    if (path.includes('/children')) {
      const url = new URL(path, 'https://fixture.invalid');
      if (!url.searchParams.has('start_cursor')) return { status: 200, data: { object: 'list', results: [], has_more: true, next_cursor: cursor }, headers: {} };
      assert.equal(url.searchParams.get('start_cursor'), 'opaque/block+page== &next');
    }
    return provider.request(method, path, body);
  } };
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  assert.equal((await adapter.prepare({ operationId: 'opaque-block', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '合法分页读取后才预览' }] })).action, 'update');
  assert.equal(provider.effects.length, 0);
});

test('a nonadjacent repeated opaque query cursor stops instead of looping or treating the lookup as absence', async () => {
  const provider = new NotionFixture();
  const cursors = ['opaque first +/==', 'opaque second +/==', 'opaque first +/=='];
  let queries = 0;
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, endpoint, body) {
    if (endpoint.endsWith('/query')) return { status: 200, data: { object: 'list', results: [], has_more: true, next_cursor: cursors[queries++] }, headers: {} };
    return provider.request(method, endpoint, body);
  } };
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  await assert.rejects(adapter.prepare(appendIntent()), error => error.code === 'query_incomplete');
  assert.equal(queries, 3);
  assert.equal(provider.effects.length, 0);
});

test('an unfinished stable-ID lookup stops at the declared twenty-page query budget', async () => {
  const provider = new NotionFixture();
  let queries = 0;
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, endpoint, body) {
    if (endpoint.endsWith('/query')) return { status: 200, data: { object: 'list', results: [], has_more: true, next_cursor: `opaque page ${++queries} +/==` }, headers: {} };
    return provider.request(method, endpoint, body);
  } };
  const adapter = createProjectAdapter({ route: appendRoute(), client });
  await assert.rejects(adapter.prepare(appendIntent()), error => error.code === 'query_incomplete');
  assert.equal(queries, 20);
  assert.equal(provider.effects.length, 0);
});

test('an unfinished block tree stops at its declared twenty-request budget without widening the page grant', async () => {
  const provider = new NotionFixture();
  let childReads = 0;
  const client = { verifyIdentity: () => provider.verifyIdentity(), async request(method, endpoint, body) {
    if (endpoint.includes('/children')) {
      assert.equal(new URL(endpoint, 'https://fixture.invalid').pathname, `/v1/blocks/${PAGE}/children`);
      return { status: 200, data: { object: 'list', results: [], has_more: true, next_cursor: `opaque block page ${++childReads} +/==` }, headers: {} };
    }
    return provider.request(method, endpoint, body);
  } };
  const adapter = createProjectAdapter({ route: updateRoute(), client });
  await assert.rejects(adapter.prepare({ operationId: 'bounded-tree', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '不能覆盖未完整读取的页' }] }), error => error.code === 'block_tree_limit');
  assert.equal(childReads, 20);
  assert.equal(provider.effects.length, 0);
});
