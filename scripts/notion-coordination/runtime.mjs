import fs from 'node:fs';
import path from 'node:path';
import { digest, normalizeId, projectFile, RouteError } from './router.mjs';
import { FixedProfileClient, keychainCredentialReader } from './profiles.mjs';
import { NotionHttpTransport } from './transport.mjs';

const fail = code => { throw new RouteError(code); };
const object = value => value && typeof value === 'object' && !Array.isArray(value);
function exact(value, keys, code) {
  if (!object(value) || Object.keys(value).some(key => !keys.includes(key))) fail(code);
}
function readAccess(route, accessFile, mode) {
  if (!accessFile) fail('ACCESS_FILE_REQUIRED');
  let file, stat;
  try { file = projectFile(route.projectRoot, accessFile); stat = fs.lstatSync(file); }
  catch (error) { if (error instanceof RouteError) throw error; fail('ACCESS_UNREADABLE'); }
  if ((stat.mode & 0o077) !== 0 || stat.nlink !== 1 || process.getuid && stat.uid !== process.getuid()) fail('ACCESS_NOT_PRIVATE');
  if (stat.size > 32_000) fail('ACCESS_LIMIT');
  let fd, encoded;
  try {
    fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    const opened = fs.fstatSync(fd);
    if (opened.ino !== stat.ino || opened.dev !== stat.dev || !opened.isFile()) fail('ACCESS_CHANGED');
    encoded = fs.readFileSync(fd, 'utf8');
  } finally { if (fd !== undefined) fs.closeSync(fd); }
  if (/(?:ntn_|secret_)[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9_-]{16,}|"(?:token|apiKey|api_key|password|credential)"\s*:/i.test(encoded)) fail('CREDENTIAL_CONTENT_REFUSED');
  let access;
  try { access = JSON.parse(encoded); } catch { fail('ACCESS_INVALID'); }
  exact(access, ['schemaVersion', 'mode', 'grant', 'executionGrant', 'fixtureOrigin'], 'ACCESS_INVALID');
  if (access.schemaVersion !== 1 || !['fixture', 'live'].includes(access.mode) || access.mode !== mode || access.grant?.mode !== mode) fail('ACCESS_MODE_MISMATCH');
  return access;
}

/** Explicit connection construction only. A local file cannot grant Notion ACLs. */
const baseKeys = ['mode', 'reference', 'profileId', 'workspaceId', 'read', 'write', 'scopeTargets'];
const intentKeys = ['projectId', 'targetId', 'operationId', 'previewDigest', 'sourceDigest', 'payloadDigest', 'routeDigest'];
function validateGrant(grant, route, mode, write = false) {
  exact(grant, write ? [...baseKeys, ...intentKeys] : baseKeys, 'AUTHORIZATION_INVALID');
  if (baseKeys.some(key => !Object.hasOwn(grant, key)) || grant.mode !== mode || grant.read !== true || typeof grant.write !== 'boolean' || write && grant.write !== true || typeof grant.reference !== 'string' || !grant.reference.trim() || grant.reference.length > 500 || /[\x00-\x1f\x7f]/.test(grant.reference)) fail('AUTHORIZATION_INVALID');
  if (grant.profileId !== route.profileId || normalizeId(grant.workspaceId) !== normalizeId(route.workspaceId)) fail('AUTHORIZATION_IDENTITY_MISMATCH');
  const expected = new Set([route.target.id, ...Object.keys(route.target.allowedBlocks)].map(normalizeId));
  if (!Array.isArray(grant.scopeTargets) || grant.scopeTargets.length !== expected.size || new Set(grant.scopeTargets.map(normalizeId)).size !== expected.size || grant.scopeTargets.some(id => !expected.has(normalizeId(id)))) fail('AUTHORIZATION_SCOPE_MISMATCH');
  return structuredClone(grant);
}
function validateExecution(grant, route, mode, saved, approval) {
  validateGrant(grant, route, mode, true);
  if (!saved?.metadata || !/^[a-f0-9]{64}$/.test(approval ?? '')) fail('PREVIEW_APPROVAL_REQUIRED');
  const expected = { projectId: route.projectId, targetId: route.target.id, operationId: saved.intent.operationId, previewDigest: approval, sourceDigest: saved.metadata.sourceDigest, payloadDigest: saved.metadata.payloadDigest, routeDigest: route.routeDigest };
  if (intentKeys.some(key => grant[key] !== expected[key])) fail('EXECUTION_GRANT_MISMATCH');
  const file = path.join(route.projectRoot, 'artifacts/notion-coordination/outbox', `${digest([route.projectId, saved.intent.operationId])}.preview.${approval}.json`);
  let preview;
  try { preview = JSON.parse(fs.readFileSync(projectFile(route.projectRoot, file), 'utf8')); }
  catch { fail('PREVIEW_UNAVAILABLE'); }
  if (preview.projectId !== expected.projectId || preview.operationId !== expected.operationId || preview.preview?.previewDigest !== approval || ['sourceDigest', 'payloadDigest', 'routeDigest'].some(key => preview[key] !== expected[key])) fail('PREVIEW_BINDING_MISMATCH');
  return structuredClone(grant);
}

export function createRuntime({ route, mode = 'offline', accessFile, command = 'doctor', saved, approval } = {}) {
  if (!['fixture', 'live'].includes(mode)) fail('LIVE_ACCESS_NOT_ENABLED');
  const access = readAccess(route, accessFile, mode);
  if (!['doctor', 'preview', 'apply', 'reconcile'].includes(command)) fail('INVALID_RUNTIME_COMMAND');
  if (mode === 'live' && !route.liveRead) fail('LIVE_READ_NOT_GRANTED');
  if (mode === 'live' && command === 'apply' && !route.liveWrite) fail('LIVE_WRITE_NOT_GRANTED');
  if (!route.profile?.botId || !route.profile.secretRef || route.profile.authorizationStatus !== 'verified') fail('PROFILE_AUTHORIZATION_REQUIRED');
  if (!route.target.id || route.authorityStatus !== 'confirmed') fail('SCOPE_UNVERIFIED');
  if (route.gateReasons.includes('BINDING_SOURCE_UNAVAILABLE')) fail('BINDING_SOURCE_UNAVAILABLE');
  if (command !== 'doctor' && !route.target.schemaVerified) fail('SCOPE_UNVERIFIED');
  const authorization = { ...validateGrant(access.grant, route, mode), write: false };
  const executionGrant = command === 'apply' ? validateExecution(access.executionGrant, route, mode, saved, approval) : null;
  if (mode === 'live' && Object.hasOwn(access, 'fixtureOrigin')) fail('ACCESS_ORIGIN_FORBIDDEN');
  const transport = new NotionHttpTransport({ mode, ...(mode === 'fixture' ? { origin: access.fixtureOrigin } : {}) });
  const stats = { productionCredentialReads: 0, calls: 0 };
  const credentialReader = mode === 'fixture' ? async () => 'fixture-only-local-token' : async ref => { stats.productionCredentialReads++; return keychainCredentialReader(ref); };
  const wire = { request: request => { stats.calls++; return transport.request(request); } };
  const clientFactory = (selected, options = {}) => {
    if (selected.routeDigest !== route.routeDigest || options.mode && options.mode !== mode) fail('RUNTIME_ROUTE_MISMATCH');
    const write = options.readOnly === false;
    if (write && command !== 'apply') fail('READ_ONLY_CAPABILITY');
    if (write && (!executionGrant || digest(options.authorization) !== digest(executionGrant))) fail('EXECUTION_GRANT_MISMATCH');
    const grant = write ? executionGrant : authorization;
    return new FixedProfileClient({ profile: route.profile, grant: Object.fromEntries(baseKeys.map(key => [key, key === 'write' ? write : grant[key]])), transport: wire, credentialReader });
  };
  return { mode, clientFactory, authorization, executionGrant,
    get productionCredentialReadPerformed() { return stats.productionCredentialReads > 0; },
    get remoteCalls() { return stats.calls; } };
}
