import { createHash } from 'node:crypto';

export class AdapterError extends Error {
  constructor(code, message = code, options = {}) {
    super(message);
    this.name = 'AdapterError';
    this.code = code;
    this.resultUnknown = options.resultUnknown === true;
  }
}

const fail = (code, message) => { throw new AdapterError(code, message); };
const uuid = value => typeof value === 'string' && /^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.test(value);
const propertyTypes = new Set(['rich_text', 'title', 'number', 'checkbox', 'url']);
const textBlocks = new Set(['paragraph', 'heading_1', 'heading_2', 'heading_3', 'bulleted_list_item', 'numbered_list_item', 'quote', 'callout', 'toggle']);
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const sameId = (left, right) => typeof left === 'string' && typeof right === 'string' && left.replaceAll('-', '').toLowerCase() === right.replaceAll('-', '').toLowerCase();
const canonical = value => JSON.stringify(value, (_, item) => object(item) ? Object.fromEntries(Object.keys(item).sort().map(key => [key, item[key]])) : item);
const hash = value => createHash('sha256').update(canonical(value)).digest('hex');

function validateRoute(route, client) {
  if (!object(route) || typeof route.projectId !== 'string' || !route.projectId.trim() || !['xfit-append', 'owned-update'].includes(route.adapterId)) fail('scope_unknown');
  if (!object(route.targets) || !Object.keys(route.targets).length) fail('scope_empty');
  if (!client || typeof client.verifyIdentity !== 'function' || typeof client.request !== 'function') fail('client_invalid');
  for (const target of Object.values(route.targets)) {
    if (!object(target) || !uuid(target.id) || !['page', 'data_source'].includes(target.kind)) fail('target_invalid');
    if (!object(target.allowedProperties) || !object(target.allowedBlocks) || !Array.isArray(target.humanProperties)) fail('scope_unknown');
    if (Object.values(target.allowedProperties).some(type => !propertyTypes.has(type)) || Object.entries(target.allowedBlocks).some(([id, type]) => !uuid(id) || !textBlocks.has(type))) fail('scope_invalid');
    if (target.humanProperties.some(name => typeof name !== 'string') || target.humanProperties.some(name => Object.hasOwn(target.allowedProperties, name))) fail('human_scope_overlap');
    if (route.adapterId === 'owned-update' && !Object.keys(target.allowedProperties).length && !Object.keys(target.allowedBlocks).length) fail('scope_empty');
    if (route.adapterId === 'xfit-append' && (target.kind !== 'data_source' || target.allowedProperties[target.stableIdProperty] !== 'rich_text' || Object.values(target.allowedProperties).filter(type => type === 'title').length !== 1)) fail('append_schema_unknown');
  }
}

export function createProjectAdapter({ route, client }) {
  validateRoute(route, client);
  route = structuredClone(route);
  const routeDigest = hash(route);

  async function request(method, path, body) {
    let response;
    try { response = await client.request(method, `/v1${path}`, body); }
    catch (error) {
      const write = method !== 'GET' && !path.endsWith('/query');
      // The fixed-profile boundary exposes safe machine reasons. Never forward
      // its raw message, credential, transport body, or a provider stack.
      if (typeof error?.code === 'string' && /^[A-Z][A-Z0-9_]{0,80}$/.test(error.code) && typeof error.resultUnknown === 'boolean') {
        throw new AdapterError(error.code, 'Fixed-profile request is gated or unresolved.', { resultUnknown: error.resultUnknown || write && error.httpStatus === 408 });
      }
      throw new AdapterError('transport_failed', 'Provider request did not return a known result.', { resultUnknown: write });
    }
    if (!response || !Number.isInteger(response.status) || !object(response.data)) throw new AdapterError('response_unknown', 'Provider response is not verifiable.', { resultUnknown: method !== 'GET' && !path.endsWith('/query') });
    if (response.status < 200 || response.status >= 300) throw new AdapterError(`provider_${response.status}`, 'Provider request was not successful.', { resultUnknown: (response.status >= 500 || response.status === 408) && method !== 'GET' && !path.endsWith('/query') });
    return response.data;
  }

  async function identity() {
    const result = await client.verifyIdentity();
    if (!result || result.verified !== true) fail('identity_unverified');
  }

  function resolve(intent) {
    if (!object(intent) || typeof intent.operationId !== 'string' || !intent.operationId.trim() || typeof intent.target !== 'string' || !Object.hasOwn(route.targets, intent.target)) fail('intent_invalid');
    const target = route.targets[intent.target];
    if (route.adapterId === 'owned-update') {
      if (intent.kind !== 'owned-update' || target.kind !== 'page' || !Array.isArray(intent.changes) || !intent.changes.length || intent.changes.length > 100) fail('operation_not_allowed');
      const propertyChanges = {}, blockChanges = {};
      for (const change of intent.changes) {
        if (!object(change) || Object.keys(change).length !== 2 || !Object.hasOwn(change, 'value')) fail('change_invalid');
        if (typeof change.property === 'string') {
          if (target.humanProperties.includes(change.property) || !Object.hasOwn(target.allowedProperties, change.property) || Object.hasOwn(propertyChanges, change.property)) fail('property_not_owned');
          encodeValue(target.allowedProperties[change.property], change.value);
          propertyChanges[change.property] = change.value;
        } else if (uuid(change.blockId)) {
          const blockId = Object.keys(target.allowedBlocks).find(id => sameId(id, change.blockId));
          if (!blockId || Object.hasOwn(blockChanges, blockId) || typeof change.value !== 'string' || change.value.length > 2000) fail('block_not_owned');
          blockChanges[blockId] = change.value;
        } else fail('change_invalid');
      }
      return { target, propertyChanges, blockChanges };
    }
    if (intent.kind !== 'append-record') fail('operation_not_allowed');
    const record = intent.record;
    if (!object(record) || typeof record.recordId !== 'string' || !record.recordId.trim() || typeof record.title !== 'string' || !record.title.trim() || typeof record.body !== 'string' || !object(record.properties)) fail('record_invalid');
    if (record.body.length > 100000 || record.recordId.length > 2000 || record.title.length > 2000) fail('record_too_large');
    const titleProperty = Object.keys(target.allowedProperties).find(name => target.allowedProperties[name] === 'title');
    const values = { ...record.properties, [target.stableIdProperty]: record.recordId, [titleProperty]: record.title };
    if (Object.hasOwn(record.properties, target.stableIdProperty) || Object.hasOwn(record.properties, titleProperty)) fail('identity_property_override');
    const properties = {};
    for (const [name, value] of Object.entries(values)) {
      if (target.humanProperties.includes(name) || !Object.hasOwn(target.allowedProperties, name)) fail('property_not_owned');
      properties[name] = encodeValue(target.allowedProperties[name], value);
    }
    return { target, properties, values, record };
  }

  function encodeValue(type, value) {
    if (['rich_text', 'title'].includes(type)) {
      if (typeof value !== 'string' || value.length > 2000) fail('property_value_invalid');
      return { [type]: value ? [{ type: 'text', text: { content: value } }] : [] };
    }
    if (type === 'number' && (value === null || (typeof value === 'number' && Number.isFinite(value)))) return { number: value };
    if (type === 'checkbox' && typeof value === 'boolean') return { checkbox: value };
    if (type === 'url' && (value === null || typeof value === 'string' && /^https?:\/\//.test(value))) return { url: value };
    fail('property_value_invalid');
  }

  function actualValue(property, type) {
    if (!object(property) || property.type !== type || property.has_more === true) fail('property_incomplete');
    if (['rich_text', 'title'].includes(type)) {
      if (!Array.isArray(property[type])) fail('property_incomplete');
      return property[type].map(item => {
        if (!object(item) || typeof item.text?.content !== 'string' && typeof item.plain_text !== 'string') fail('property_incomplete');
        return item.plain_text ?? item.text.content;
      }).join('');
    }
    if (!Object.hasOwn(property, type)) fail('property_incomplete');
    return property[type];
  }

  async function source(target) {
    const result = await request('GET', `/data_sources/${target.id}`);
    if (result.object !== 'data_source' || !sameId(result.id, target.id) || !object(result.properties) || result.archived === true || result.in_trash === true) fail('source_invalid');
    for (const [name, type] of Object.entries(target.allowedProperties)) if (result.properties[name]?.type !== type) fail('source_schema_mismatch');
    return { object: result.object, id: result.id, properties: result.properties, ...(result.parent ? { parent: result.parent } : {}) };
  }

  async function readPage(id, target) {
    const page = await request('GET', `/pages/${id}`);
    if (page.object !== 'page' || !sameId(page.id, id) || page.archived !== false || page.in_trash !== false || !object(page.properties)) fail('page_invalid');
    if (target.kind === 'data_source' && (page.parent?.type !== 'data_source_id' || !sameId(page.parent?.data_source_id, target.id))) fail('page_parent_mismatch');
    const markdown = await request('GET', `/pages/${id}/markdown`);
    if (markdown.object !== 'page_markdown' || !sameId(markdown.id, id) || markdown.truncated !== false || !Array.isArray(markdown.unknown_block_ids) || markdown.unknown_block_ids.length || typeof markdown.markdown !== 'string' || /<unknown(?:[\s/>_-])/i.test(markdown.markdown)) fail('page_incomplete');
    return { page, markdown: markdown.markdown };
  }

  // Full block tree is the conservation witness for owned block updates. No
  // unsupported/missing pagination flags are interpreted as a complete read.
  async function readTree(pageId) {
    const blocks = [];
    const seenIds = new Set();
    let budget = 20;
    async function children(parentId, depth) {
      if (depth > 8) fail('block_tree_limit');
      let cursor;
      const seenCursors = new Set();
      for (;;) {
        if (--budget < 0) fail('block_tree_limit');
        const path = `/blocks/${parentId}/children?page_size=100${cursor ? `&start_cursor=${encodeURIComponent(cursor)}` : ''}`;
        const list = await request('GET', path);
        if (list.object !== 'list' || !Array.isArray(list.results) || typeof list.has_more !== 'boolean') fail('blocks_incomplete');
        for (const block of list.results) {
          if (block.object !== 'block' || !uuid(block.id) || seenIds.has(block.id) || typeof block.has_children !== 'boolean' || block.archived !== false || block.in_trash !== false || !object(block[block.type])) fail('block_invalid');
          if (block.parent?.type !== (depth === 0 ? 'page_id' : 'block_id')) fail('block_parent_mismatch');
          const parent = block.parent[block.parent.type];
          if (!sameId(parent, parentId)) fail('block_parent_mismatch');
          seenIds.add(block.id);
          blocks.push(block);
          if (blocks.length > 1000) fail('block_tree_limit');
          if (block.has_children) await children(block.id, depth + 1);
        }
        if (!list.has_more) { if (list.next_cursor !== null) fail('blocks_incomplete'); break; }
        if (typeof list.next_cursor !== 'string' || !list.next_cursor.length || seenCursors.has(list.next_cursor)) fail('blocks_incomplete');
        cursor = list.next_cursor;
        seenCursors.add(cursor);
      }
    }
    await children(pageId, 0);
    return blocks;
  }

  async function ownedPage(target) {
    const result = await readPage(target.id, target);
    for (const [name, type] of Object.entries(target.allowedProperties)) actualValue(result.page.properties[name], type);
    for (const name of target.humanProperties) if (!Object.hasOwn(result.page.properties, name)) fail('human_field_unknown');
    const blocks = await readTree(target.id);
    for (const [id, type] of Object.entries(target.allowedBlocks)) if (!blocks.some(block => sameId(block.id, id) && block.type === type)) fail('block_scope_moved');
    return { ...result, blocks };
  }

  async function matches(target, record) {
    const pages = [];
    const seen = new Set();
    const seenCursors = new Set();
    let cursor;
    for (let step = 0; step < 20; step++) {
      const list = await request('POST', `/data_sources/${target.id}/query`, { filter: { property: target.stableIdProperty, rich_text: { equals: record.recordId } }, page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
      if (list.object !== 'list' || !Array.isArray(list.results) || typeof list.has_more !== 'boolean') fail('query_incomplete');
      for (const page of list.results) {
        if (page.object !== 'page' || !uuid(page.id) || page.parent?.type !== 'data_source_id' || !sameId(page.parent?.data_source_id, target.id) || seen.has(page.id)) fail('query_invalid');
        seen.add(page.id);
        const complete = await readPage(page.id, target);
        if (actualValue(complete.page.properties[target.stableIdProperty], 'rich_text') !== record.recordId) fail('query_wrong_record');
        pages.push(complete);
      }
      if (!list.has_more) { if (list.next_cursor !== null) fail('query_incomplete'); break; }
      if (typeof list.next_cursor !== 'string' || !list.next_cursor.length || seenCursors.has(list.next_cursor) || step === 19) fail('query_incomplete');
      cursor = list.next_cursor;
      seenCursors.add(cursor);
    }
    if (pages.length > 1) fail('stable_id_duplicate');
    return pages;
  }

  function recordValues(page, spec) {
    return { values: Object.fromEntries(Object.keys(spec.values).map(name => [name, actualValue(page.page.properties[name], spec.target.allowedProperties[name])])), body: page.markdown };
  }

  async function snapshot(spec) {
    const scopes = {};
    for (const [alias, target] of Object.entries(route.targets)) scopes[alias] = target.kind === 'data_source' ? await source(target) : await ownedPage(target);
    const records = route.adapterId === 'xfit-append' ? await matches(spec.target, spec.record) : [];
    return { scopes, records };
  }

  function updateValues(current, spec, intent) {
    const page = current.scopes[intent.target];
    return { properties: Object.fromEntries(Object.keys(spec.propertyChanges).map(name => [name, actualValue(page.page.properties[name], spec.target.allowedProperties[name])])), blocks: Object.fromEntries(Object.keys(spec.blockChanges).map(id => [id, actualValue({ type: 'rich_text', rich_text: page.blocks.find(block => sameId(block.id, id))[spec.target.allowedBlocks[id]].rich_text }, 'rich_text')])) };
  }

  function withoutVolatile(value) {
    if (Array.isArray(value)) return value.map(withoutVolatile);
    if (!object(value)) return value;
    return Object.fromEntries(Object.entries(value).filter(([key]) => !['last_edited_time', 'last_edited_by', 'request_id'].includes(key)).map(([key, entry]) => [key, withoutVolatile(entry)]));
  }

  function protectedSnapshot(current, spec, intent) {
    if (route.adapterId === 'xfit-append') return current.scopes;
    const scopes = withoutVolatile(current.scopes);
    const target = scopes[intent.target];
    // Property-only changes leave Markdown unchanged. For block updates the
    // complete tree protects every unowned block; its changed Markdown is not
    // itself an independent conservation witness.
    if (Object.keys(spec.blockChanges).length) delete target.markdown;
    for (const name of Object.keys(spec.propertyChanges)) {
      const property = target.page.properties[name];
      const type = spec.target.allowedProperties[name];
      if (['title', 'rich_text'].includes(type)) property[type] = textStyle(property[type]);
      else delete property[type];
    }
    for (const id of Object.keys(spec.blockChanges)) {
      const block = target.blocks.find(item => sameId(item.id, id));
      block[block.type].rich_text = textStyle(block[block.type].rich_text);
    }
    return scopes;
  }

  function textStyle(entries) {
    return entries.map(item => {
      const copy = structuredClone(item);
      delete copy.plain_text;
      delete copy.href;
      if (copy.text) delete copy.text.content;
      return copy;
    });
  }

  function preserveText(existing, value) {
    if (!Array.isArray(existing) || existing.length > 1 || existing.some(item => item.type !== 'text' || !object(item.text))) fail('rich_text_structure_unknown');
    if (!existing.length) return encodeValue('rich_text', value).rich_text;
    const entry = structuredClone(existing[0]);
    delete entry.plain_text;
    delete entry.href;
    entry.text.content = value;
    return [entry];
  }

  function checkPreview(intent, preview) {
    if (!object(preview)) fail('preview_invalid');
    const { previewDigest, ...signed } = preview;
    if (hash(signed) !== previewDigest || preview.intentDigest !== hash(intent) || preview.routeDigest !== routeDigest) fail('preview_changed');
  }

  async function prepare(intent) {
    intent = structuredClone(intent);
    const spec = resolve(intent);
    await identity();
    const current = await snapshot(spec);
    const desired = route.adapterId === 'xfit-append' ? { values: spec.values, body: spec.record.body } : { properties: spec.propertyChanges, blocks: spec.blockChanges };
    const desiredDigest = hash(desired);
    let action;
    if (route.adapterId === 'xfit-append') {
      if (current.records.length && hash(recordValues(current.records[0], spec)) !== desiredDigest) fail('stable_id_conflict');
      action = current.records.length ? 'no_op' : 'append';
    } else {
      const targetPage = current.scopes[intent.target];
      for (const [id, value] of Object.entries(spec.blockChanges)) preserveText(targetPage.blocks.find(block => sameId(block.id, id))[spec.target.allowedBlocks[id]].rich_text, value);
      for (const [name, value] of Object.entries(spec.propertyChanges)) if (['title', 'rich_text'].includes(spec.target.allowedProperties[name])) preserveText(targetPage.page.properties[name][spec.target.allowedProperties[name]], value);
      action = hash(updateValues(current, spec, intent)) === desiredDigest ? 'no_op' : 'update';
    }
    const signed = { intentDigest: hash(intent), routeDigest, desiredDigest, baselineDigest: hash(current), protectedDigest: hash(protectedSnapshot(current, spec, intent)), action, summary: { projectId: route.projectId, target: intent.target, ...(spec.record ? { recordId: spec.record.recordId, propertyCount: Object.keys(spec.properties).length, bodyCharacters: spec.record.body.length } : { propertyCount: Object.keys(spec.propertyChanges).length, blockCount: Object.keys(spec.blockChanges).length }) }, snapshot: current };
    return { ...signed, previewDigest: hash(signed) };
  }

  async function reconcile(intent, preview) {
    intent = structuredClone(intent);
    preview = structuredClone(preview);
    checkPreview(intent, preview);
    const spec = resolve(intent);
    await identity();
    const current = await snapshot(spec);
    if (hash(protectedSnapshot(current, spec, intent)) !== preview.protectedDigest) fail('protected_changed');
    if (route.adapterId === 'xfit-append') {
      if (current.records.length !== 1 || hash(recordValues(current.records[0], spec)) !== preview.desiredDigest) fail('readback_mismatch');
      if (preview.snapshot.records.length && hash(current.records) !== hash(preview.snapshot.records)) fail('protected_changed');
    } else if (hash(updateValues(current, spec, intent)) !== preview.desiredDigest) fail('readback_mismatch');
    return { status: 'readback_verified', readbackDigest: preview.desiredDigest, providerIds: route.adapterId === 'xfit-append' ? [current.records[0].page.id] : [spec.target.id, ...Object.keys(spec.blockChanges)] };
  }

  async function apply(intent, preview) {
    intent = structuredClone(intent);
    preview = structuredClone(preview);
    checkPreview(intent, preview);
    const spec = resolve(intent);
    const refreshed = await prepare(intent);
    if (refreshed.baselineDigest !== preview.baselineDigest || refreshed.desiredDigest !== preview.desiredDigest || refreshed.action !== preview.action) fail('preview_stale');
    if (preview.action === 'no_op') return reconcile(intent, preview);
    let started = false;
    let committed = 0;
    try {
      started = true;
      if (route.adapterId === 'xfit-append') {
        const result = await request('POST', '/pages', { parent: { data_source_id: spec.target.id }, properties: spec.properties, markdown: spec.record.body });
        committed++;
        if (result.object !== 'page' || !uuid(result.id) || result.parent?.type !== 'data_source_id' || !sameId(result.parent?.data_source_id, spec.target.id)) throw new AdapterError('create_result_unknown', undefined, { resultUnknown: true });
      } else {
        const original = preview.snapshot.scopes[intent.target];
        const properties = {};
        for (const [name, value] of Object.entries(spec.propertyChanges)) {
          const type = spec.target.allowedProperties[name];
          properties[name] = ['rich_text', 'title'].includes(type) ? { [type]: preserveText(original.page.properties[name][type], value) } : encodeValue(type, value);
        }
        if (Object.keys(properties).length) { await request('PATCH', `/pages/${spec.target.id}`, { properties }); committed++; }
        for (const [id, value] of Object.entries(spec.blockChanges)) {
          const block = original.blocks.find(item => sameId(item.id, id));
          await request('PATCH', `/blocks/${id}`, { [block.type]: { rich_text: preserveText(block[block.type].rich_text, value) } });
          committed++;
        }
      }
      return await reconcile(intent, preview);
    } catch (error) {
      if (started) throw new AdapterError(error.code ?? 'apply_result_unknown', 'Write result requires read-only reconciliation.', { resultUnknown: committed > 0 || error.resultUnknown === true || !error.code || error.code.startsWith('readback') || error.code.startsWith('protected') || error.code === 'page_incomplete' || error.code === 'transport_failed' });
      throw error;
    }
  }

  return { prepare, apply, reconcile };
}
