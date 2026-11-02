import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export class RouteError extends Error {
  constructor(code) { super(code); this.code = code; }
  toJSON() { return { code: this.code }; }
}
const fail = code => { throw new RouteError(code); };
const stableId = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(value);
const isObject = value => !!value && typeof value === 'object' && !Array.isArray(value);
export function normalizeId(value) {
  if (typeof value !== 'string' || !/^(?:[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/i.test(value)) fail('INVALID_UUID');
  return value.replaceAll('-', '').toLowerCase();
}
export function digest(value) {
  const canonical = item => Array.isArray(item) ? item.map(canonical) : isObject(item)
    ? Object.fromEntries(Object.keys(item).sort().map(key => [key, canonical(item[key])])) : item;
  return crypto.createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}
export const fileDigest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
export function projectFile(root, file) {
  if (!path.isAbsolute(root) || typeof file !== 'string' || /[\r\n\0]/.test(file)) fail('INVALID_SOURCE_PATH');
  const base = fs.realpathSync(root);
  const absolute = path.resolve(base, file);
  const relative = path.relative(base, absolute);
  if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) fail('SOURCE_OUTSIDE_PROJECT');
  for (let cursor = absolute; cursor !== base; cursor = path.dirname(cursor)) {
    if (fs.lstatSync(cursor).isSymbolicLink()) fail('SOURCE_SYMLINK_REFUSED');
  }
  if (!fs.statSync(absolute).isFile() || fs.statSync(absolute).size > 8_000_000) fail('SOURCE_NOT_REGULAR_OR_TOO_LARGE');
  return absolute;
}
function exactKeys(value, allowed) {
  if (!isObject(value) || Object.keys(value).some(key => !allowed.includes(key))) fail('INVALID_SCHEMA');
}
export function validateRegistry(registry) {
  exactKeys(registry, ['schemaVersion', 'revision', 'profiles', 'routes', 'policy']);
  if (registry.schemaVersion !== 1 || !stableId(registry.revision) || !Array.isArray(registry.profiles) || !Array.isArray(registry.routes)) fail('INVALID_REGISTRY');
  if (registry.routes.length > 50 || registry.profiles.length > 50) fail('REGISTRY_LIMIT');
  exactKeys(registry.policy, ['phoneRealtimeUpload', 'sharedOAuthRebind', 'crossHost', 'defaultLiveAccess']);
  if (Object.values(registry.policy).some(Boolean) || Object.keys(registry.policy).length !== 4) fail('UNAPPROVED_POLICY');
  const profiles = new Map();
  for (const profile of registry.profiles) {
    exactKeys(profile, ['id', 'workspaceId', 'workspaceName', 'botId', 'secretRef', 'capabilities', 'apiVersion', 'authorizationStatus']);
    if (!stableId(profile.id) || profiles.has(profile.id)) fail('DUPLICATE_PROFILE');
    normalizeId(profile.workspaceId);
    if (profile.botId !== null) normalizeId(profile.botId);
    if (profile.apiVersion !== '2026-03-11' || !Array.isArray(profile.capabilities) || profile.capabilities.some(item => !['read', 'update', 'insert'].includes(item))) fail('INVALID_PROFILE');
    if (!['unconfigured', 'candidate', 'verified'].includes(profile.authorizationStatus)) fail('INVALID_PROFILE_STATUS');
    if (profile.secretRef !== null) {
      exactKeys(profile.secretRef, ['service', 'account']);
      if (!/^(?:com\.xfit\.notion-access|com\.notion-coordination\.[A-Za-z0-9.-]+)$/.test(profile.secretRef.service) || !stableId(profile.secretRef.account)) fail('INVALID_SECRET_REFERENCE');
    }
    profiles.set(profile.id, profile);
  }
  const ids = new Set();
  for (const route of registry.routes) {
    exactKeys(route, ['projectId', 'projectRoot', 'subprojectId', 'workspaceId', 'profileId', 'adapterId', 'targets', 'sourceBindings', 'authorityStatus', 'liveRead', 'liveWrite']);
    if (!stableId(route.projectId) || ids.has(route.projectId)) fail('DUPLICATE_PROJECT');
    ids.add(route.projectId);
    if (!path.isAbsolute(route.projectRoot) || /[\r\n\0]/.test(route.projectRoot)) fail('INVALID_PROJECT_ROOT');
    if (route.subprojectId !== null && !stableId(route.subprojectId)) fail('INVALID_SUBPROJECT');
    if (route.workspaceId !== null) normalizeId(route.workspaceId);
    if (route.profileId !== null) {
      const profile = profiles.get(route.profileId);
      if (!profile || route.workspaceId === null || normalizeId(profile.workspaceId) !== normalizeId(route.workspaceId)) fail('PROFILE_WORKSPACE_MISMATCH');
    }
    if (!['xfit-append', 'owned-update', 'draft-only'].includes(route.adapterId) || !isObject(route.targets)) fail('INVALID_ADAPTER');
    if (typeof route.liveRead !== 'boolean' || typeof route.liveWrite !== 'boolean') fail('INVALID_LIVE_GATE');
    if (!['confirmed', 'candidate', 'conflict'].includes(route.authorityStatus)) fail('INVALID_AUTHORITY_STATUS');
    for (const [alias, target] of Object.entries(route.targets)) {
      if (!stableId(alias)) fail('INVALID_TARGET_ALIAS');
      exactKeys(target, ['id', 'kind', 'stableIdProperty', 'allowedProperties', 'allowedBlocks', 'humanProperties', 'schemaVerified']);
      if (target.id !== null) normalizeId(target.id);
      if (!['page', 'data_source'].includes(target.kind) || !isObject(target.allowedProperties) || !isObject(target.allowedBlocks) || !Array.isArray(target.humanProperties) || typeof target.schemaVerified !== 'boolean') fail('INVALID_TARGET');
      if (Object.keys(target.allowedProperties).some(name => target.humanProperties.includes(name))) fail('HUMAN_FIELD_OWNERSHIP_CONFLICT');
      for (const [blockId, type] of Object.entries(target.allowedBlocks)) {
        normalizeId(blockId);
        if (!['paragraph', 'callout', 'heading_1', 'heading_2', 'heading_3', 'bulleted_list_item', 'numbered_list_item', 'quote', 'toggle'].includes(type)) fail('INVALID_BLOCK_SCOPE');
      }
      if (Object.values(target.allowedProperties).some(type => !['rich_text', 'title', 'number', 'checkbox', 'url'].includes(type))) fail('INVALID_PROPERTY_SCOPE');
    }
    if (!Array.isArray(route.sourceBindings) || route.sourceBindings.some(file => !path.isAbsolute(file) || /[\r\n\0]/.test(file))) fail('INVALID_BINDING_REFERENCE');
  }
  return { status: 'PASS', revision: registry.revision, profiles: profiles.size, routes: ids.size, remoteCalls: 0 };
}
export function loadRegistry(file) {
  let value;
  try { value = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { fail('REGISTRY_UNREADABLE'); }
  validateRegistry(value);
  return value;
}
export function resolveRoute(registry, query) {
  validateRegistry(registry);
  exactKeys(query, ['projectId', 'projectRoot', 'subprojectId', 'target']);
  let candidates = registry.routes;
  if (query.projectId !== undefined) candidates = candidates.filter(route => route.projectId === query.projectId);
  if (query.projectRoot !== undefined) {
    if (!path.isAbsolute(query.projectRoot)) fail('INVALID_PROJECT_ROOT');
    let root;
    try { root = fs.realpathSync(query.projectRoot); } catch { fail('PROJECT_ROOT_UNAVAILABLE'); }
    candidates = candidates.filter(route => {
      try { return fs.realpathSync(route.projectRoot) === root; } catch { return false; }
    });
  }
  if (query.subprojectId !== undefined) candidates = candidates.filter(route => route.subprojectId === query.subprojectId);
  if (!candidates.length) fail('PROJECT_NOT_REGISTERED');
  if (candidates.length !== 1) fail('PROJECT_AMBIGUOUS');
  const route = candidates[0];
  const aliases = Object.keys(route.targets);
  const alias = query.target ?? (aliases.length === 1 ? aliases[0] : null);
  if (!alias || !Object.hasOwn(route.targets, alias)) fail('TARGET_NOT_REGISTERED');
  const target = route.targets[alias];
  const profile = registry.profiles.find(item => item.id === route.profileId) ?? null;
  const gateReasons = [];
  if (!route.workspaceId) gateReasons.push('WORKSPACE_UNBOUND');
  if (!target.id) gateReasons.push('TARGET_UNBOUND');
  if (!profile) gateReasons.push('PROFILE_UNBOUND');
  else {
    if (!profile.botId) gateReasons.push('BOT_UNVERIFIED');
    if (!profile.secretRef || profile.authorizationStatus !== 'verified') gateReasons.push('CREDENTIAL_AUTHORIZATION_PENDING');
  }
  if (!target.schemaVerified) gateReasons.push('OWNED_SCOPE_UNVERIFIED');
  if (route.authorityStatus !== 'confirmed') gateReasons.push('AUTHORITY_UNCONFIRMED');
  if (!route.liveRead) gateReasons.push('LIVE_ACCESS_NOT_GRANTED');
  const bindingVersions = route.sourceBindings.map(file => {
    try { return { path: file, sha256: fileDigest(projectFile(route.projectRoot, file)) }; }
    catch { gateReasons.push('BINDING_SOURCE_UNAVAILABLE'); return { path: file, sha256: null }; }
  });
  return { ...structuredClone(route), targetAlias: alias, target: structuredClone(target), profile: structuredClone(profile), bindingVersions, routeDigest: digest({ revision: registry.revision, route, profile, bindingVersions }), accessStatus: gateReasons.length ? 'blocked_access' : 'route_ready', gateReasons: [...new Set(gateReasons)], remoteCalls: 0 };
}
