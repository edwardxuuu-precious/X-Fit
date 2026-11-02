import { ProfileError } from './profiles.mjs';

const codes = new Set(['DOCTOR_ROUTE_INVALID', 'DOCTOR_CLIENT_INVALID', 'DOCTOR_IDENTITY_MISMATCH',
  'DOCTOR_RESPONSE_INVALID', 'DOCTOR_SOURCE_INVALID', 'DOCTOR_PAGE_INVALID', 'DOCTOR_PARENT_MISMATCH',
  'DOCTOR_SCHEMA_INCOMPLETE', 'DOCTOR_MARKDOWN_INCOMPLETE', 'DOCTOR_BLOCK_INVALID',
  'DOCTOR_PAGINATION_INCOMPLETE', 'DOCTOR_DUPLICATE_OBJECT', 'DOCTOR_LIMIT', 'DOCTOR_CLIENT_FAILURE',
  'PROFILE_INVALID', 'GRANT_REQUIRED', 'GRANT_INVALID', 'GRANT_MISMATCH', 'READ_GRANT_REQUIRED',
  'TARGET_OUT_OF_SCOPE', 'CAPABILITY_REQUIRED', 'IDENTITY_NOT_VERIFIED', 'BOT_MISMATCH', 'WORKSPACE_MISMATCH',
  'CREDENTIAL_UNCONFIGURED', 'CREDENTIAL_UNAVAILABLE', 'CREDENTIAL_REF_INVALID', 'TRANSPORT_REQUIRED',
  'TRANSPORT_FAILURE', 'TRANSPORT_RESPONSE_INVALID', 'PROVIDER_UNAUTHORIZED', 'PROVIDER_FORBIDDEN',
  'PROVIDER_NOT_FOUND', 'RATE_LIMITED', 'WORKSPACE_RATE_LIMITED', 'PROVIDER_SERVER_ERROR',
  'PROVIDER_REQUEST_FAILED', 'REDIRECT_FORBIDDEN', 'ENDPOINT_FORBIDDEN', 'REQUEST_BODY_INVALID',
  'HTTP_CONFIG_INVALID', 'HTTP_INPUT_INVALID', 'HTTP_PATH_FORBIDDEN', 'HTTP_REQUEST_BUDGET',
  'HTTP_REQUEST_TOO_LARGE', 'HTTP_RESPONSE_TOO_LARGE', 'HTTP_TIMEOUT', 'HTTP_CONNECTION_FAILED',
  'HTTP_REDIRECT_FORBIDDEN', 'HTTP_RESPONSE_INVALID']);

export class DoctorError extends Error {
  constructor(code) {
    const safe = codes.has(code) ? code : 'DOCTOR_CLIENT_FAILURE';
    super(safe); this.name = 'DoctorError'; this.code = safe; this.resultUnknown = false;
  }
  toJSON() { return { code: this.code, resultUnknown: false }; }
}

const fail = code => { throw new DoctorError(code); };
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const uuid = value => typeof value === 'string' && /^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.test(value)
  ? value.replaceAll('-', '').toLowerCase() : null;
const same = (left, right) => uuid(left) && uuid(left) === uuid(right);
const shortText = value => typeof value === 'string' && value.length > 0 && value.length <= 256 && !/[\x00-\x1f\x7f]/.test(value);
const cursorText = value => typeof value === 'string' && value.length > 0 && value.length <= 2048 && !/[\x00-\x1f\x7f]/.test(value);

function validateList(value) {
  if (value.object !== 'list' || !Array.isArray(value.results) || typeof value.has_more !== 'boolean' ||
      value.results.length > 100 || (value.has_more ? !value.results.length || !cursorText(value.next_cursor) : value.next_cursor !== null)) {
    fail('DOCTOR_PAGINATION_INCOMPLETE');
  }
}

function schema(properties) {
  if (!object(properties) || Object.keys(properties).length > 1000) fail('DOCTOR_SCHEMA_INCOMPLETE');
  const seen = new Set();
  return Object.keys(properties).sort().map(name => {
    const item = properties[name];
    if (!shortText(name) || !object(item) || !shortText(item.id) || seen.has(item.id) ||
        !/^[a-z][a-z0-9_]{0,63}$/.test(item.type) || !Object.hasOwn(item, item.type) ||
        item.name !== undefined && item.name !== name || item.has_more === true) fail('DOCTOR_SCHEMA_INCOMPLETE');
    seen.add(item.id);
    return { name, id: item.id, type: item.type };
  });
}

/** Evidence candidates only. Never changes routing, ACLs or owned-field allowlists. */
export async function inspectConnection(options = {}) {
  try {
    const { route, client } = options;
    let selected;
    try { selected = structuredClone(route); } catch { fail('DOCTOR_ROUTE_INVALID'); }
    if (!object(selected) || !shortText(selected.targetAlias) || !object(selected.target) ||
        !uuid(selected.target.id) || !['page', 'data_source'].includes(selected.target.kind) ||
        !object(selected.profile) || !uuid(selected.workspaceId) || !uuid(selected.profile.botId) ||
        selected.profileId !== selected.profile.id || !same(selected.workspaceId, selected.profile.workspaceId)) fail('DOCTOR_ROUTE_INVALID');
    if (!client || typeof client.verifyIdentity !== 'function' || typeof client.request !== 'function') fail('DOCTOR_CLIENT_INVALID');
    const identity = structuredClone(await client.verifyIdentity());
    if (identity?.verified !== true || identity.profileId !== selected.profileId ||
        !same(identity.botId, selected.profile.botId) || !same(identity.workspaceId, selected.workspaceId)) fail('DOCTOR_IDENTITY_MISMATCH');
    const counts = { pages: 0, blocks: 0, queryPages: 0, blockListPages: 0 };
    let readRequests = 1;
    async function read(method, path, body) {
      if (readRequests >= 300) fail('DOCTOR_LIMIT');
      readRequests += 1;
      const response = structuredClone(await client.request(method, path, body));
      if (!response || !Number.isInteger(response.status) || response.status < 200 || response.status >= 300 || !object(response.data)) fail('DOCTOR_RESPONSE_INVALID');
      return response.data;
    }
    const { target } = selected;
    const seen = new Set();
    if (target.kind === 'data_source') seen.add(uuid(target.id));
    async function tree(parentId, parentType = 'page_id', depth = 0) {
      if (depth > 8) fail('DOCTOR_LIMIT');
      let cursor;
      const seenCursors = new Set();
      for (;;) {
        if (counts.blockListPages >= 20) fail('DOCTOR_LIMIT');
        const path = `/v1/blocks/${parentId}/children?page_size=100${cursor === undefined ? '' : `&start_cursor=${encodeURIComponent(cursor)}`}`;
        const blocks = await read('GET', path);
        counts.blockListPages += 1;
        validateList(blocks);
        for (const block of blocks.results) {
          if (block?.object !== 'block' || !uuid(block.id) || typeof block.has_children !== 'boolean' ||
              block.archived !== false || block.in_trash !== false || typeof block.type !== 'string' ||
              !/^[a-z][a-z0-9_]{0,63}$/.test(block.type) || block.type === 'unsupported' ||
              !Object.hasOwn(block, block.type) || !object(block[block.type])) fail('DOCTOR_BLOCK_INVALID');
          if (seen.has(uuid(block.id))) fail('DOCTOR_DUPLICATE_OBJECT');
          if (block.parent?.type !== parentType || !same(block.parent[parentType], parentId)) fail('DOCTOR_PARENT_MISMATCH');
          seen.add(uuid(block.id)); counts.blocks += 1;
          if (counts.pages + counts.blocks > 1000) fail('DOCTOR_LIMIT');
          if (block.has_children) await tree(block.id, 'block_id', depth + 1);
        }
        if (!blocks.has_more) break;
        if (seenCursors.has(blocks.next_cursor)) fail('DOCTOR_PAGINATION_INCOMPLETE');
        cursor = blocks.next_cursor; seenCursors.add(cursor);
      }
    }
    function sourceParent(parent) {
      return object(parent) && parent.type === 'data_source_id' && same(parent.data_source_id, target.id) &&
        (parent.database_id === undefined || uuid(parent.database_id)) &&
        Object.keys(parent).every(key => ['type', 'data_source_id', 'database_id'].includes(key));
    }
    async function page(id) {
      if (seen.has(uuid(id))) fail('DOCTOR_DUPLICATE_OBJECT');
      seen.add(uuid(id));
      const value = await read('GET', `/v1/pages/${id}`);
      if (value.object !== 'page' || !same(value.id, id) || value.archived !== false || value.in_trash !== false) fail('DOCTOR_PAGE_INVALID');
      if (target.kind === 'data_source' && !sourceParent(value.parent)) fail('DOCTOR_PARENT_MISMATCH');
      const observed = schema(value.properties);
      counts.pages += 1;
      if (counts.pages + counts.blocks > 1000) fail('DOCTOR_LIMIT');
      const markdown = await read('GET', `/v1/pages/${id}/markdown`);
      if (markdown.object !== 'page_markdown' || !same(markdown.id, id) || markdown.truncated !== false ||
          !Array.isArray(markdown.unknown_block_ids) || markdown.unknown_block_ids.length ||
          typeof markdown.markdown !== 'string' || /<unknown(?:[\s/>_-])/i.test(markdown.markdown)) fail('DOCTOR_MARKDOWN_INCOMPLETE');
      await tree(id);
      return observed;
    }
    let observedSchema;
    if (target.kind === 'page') observedSchema = await page(target.id);
    else {
      const source = await read('GET', `/v1/data_sources/${target.id}`);
      if (source.object !== 'data_source' || !same(source.id, target.id) || source.archived !== false || source.in_trash !== false) fail('DOCTOR_SOURCE_INVALID');
      observedSchema = schema(source.properties);
      let cursor;
      const seenCursors = new Set();
      for (;;) {
        if (counts.queryPages >= 20) fail('DOCTOR_LIMIT');
        const query = await read('POST', `/v1/data_sources/${target.id}/query`,
          { page_size: 100, ...(cursor === undefined ? {} : { start_cursor: cursor }) });
        counts.queryPages += 1;
        validateList(query);
        for (const record of query.results) {
          if (record?.object !== 'page' || !uuid(record.id)) fail('DOCTOR_PAGE_INVALID');
          if (!sourceParent(record.parent)) fail('DOCTOR_PARENT_MISMATCH');
          await page(record.id);
        }
        if (!query.has_more) break;
        if (seenCursors.has(query.next_cursor)) fail('DOCTOR_PAGINATION_INCOMPLETE');
        cursor = query.next_cursor; seenCursors.add(cursor);
      }
    }
    return { status: 'inspection_verified', identity: { verified: true, profileId: selected.profileId,
      botId: selected.profile.botId, workspaceId: selected.workspaceId },
      target: { alias: selected.targetAlias, id: target.id, kind: target.kind }, counts,
      completeness: { schema: true, records: true, markdown: true, blockTree: true },
      evidenceScope: { records: 'page_enumeration_only', schema: 'observed_metadata_only', propertyValues: 'not_inspected' },
      observedSchema, permissionsActivated: false, writes: 0 };
  } catch (error) {
    if (error instanceof DoctorError || error instanceof ProfileError) {
      let safe;
      try { safe = new DoctorError(error.code); } catch { /* Do not forward exception getters. */ }
      if (safe) throw safe;
    }
    throw new DoctorError('DOCTOR_CLIENT_FAILURE');
  }
}
