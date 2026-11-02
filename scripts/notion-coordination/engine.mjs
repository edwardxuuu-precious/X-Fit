import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { digest, fileDigest, projectFile, resolveRoute, normalizeId, validateRegistry } from './router.mjs';
import { createProjectAdapter } from './adapters.mjs';

export class CoordinationError extends Error {
  constructor(code, { resultUnknown = false } = {}) { super(code); this.code = code; this.resultUnknown = resultUnknown; }
  toJSON() { return { code: this.code }; }
}
const fail = code => { throw new CoordinationError(code); };
const safeErrorCode = error => typeof error?.code === 'string' && /^[a-zA-Z][a-zA-Z0-9_]{0,90}$/.test(error.code) ? error.code.toUpperCase() : 'EXECUTION_UNKNOWN';
const ID = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/;
function assertInput(input) {
  if (!input || typeof input !== 'object' || Object.keys(input).some(key => !['source', 'intent'].includes(key))) fail('INVALID_FEEDBACK');
  const source = input.source;
  if (!source || typeof source.author !== 'string' || !source.author || !['user_feedback', 'project_observation', 'proposed_decision'].includes(source.kind) || typeof source.reference !== 'string' || !source.reference || source.reference.length > 500 || Object.keys(source).some(key => !['author', 'kind', 'reference', 'observedAt'].includes(key))) fail('SOURCE_PROVENANCE_REQUIRED');
  if (!input.intent || !ID.test(input.intent.operationId) || !['append-record', 'owned-update'].includes(input.intent.kind) || typeof input.intent.target !== 'string') fail('INVALID_INTENT');
  const encoded = JSON.stringify(input);
  if (Buffer.byteLength(encoded) > 500_000) fail('FEEDBACK_LIMIT');
  if (/(?:ntn_|secret_)[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9_-]{16,}|"(?:token|apiKey|api_key|password|credential)"\s*:/i.test(encoded)) fail('CREDENTIAL_CONTENT_REFUSED');
}
function privateDirectory(route) {
  const root = fs.realpathSync(route.projectRoot);
  let dir = root;
  for (const segment of ['artifacts', 'notion-coordination', 'outbox']) {
    dir = path.join(dir, segment);
    try { fs.mkdirSync(dir, { mode: 0o700 }); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    // Another caller may have created the directory; never chmod or trust it
    // merely because mkdir returned EEXIST.
    const stat = fs.lstatSync(dir);
    if (stat.isSymbolicLink() || !stat.isDirectory()) fail('PRIVATE_PATH_UNSAFE');
  }
  if ((fs.statSync(dir).mode & 0o077) !== 0) fail('PRIVATE_DIRECTORY_PERMISSIONS');
  return dir;
}
function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { fail('PRIVATE_RECORD_UNREADABLE'); }
}
function persist(file, value) {
  const verifyExisting = () => {
    const stat = fs.lstatSync(file);
    if (stat.isSymbolicLink() || !stat.isFile()) fail('PRIVATE_RECORD_CONFLICT');
    if ((stat.mode & 0o077) !== 0) fail('PRIVATE_RECORD_PERMISSIONS');
    if (digest(readJson(file)) !== digest(value)) fail('PRIVATE_RECORD_CONFLICT');
  };
  if (fs.existsSync(file)) { verifyExisting(); return; }
  // Publish only a fully written, fsynced file. link is atomic and refuses to
  // overwrite a concurrent caller's immutable record, unlike rename.
  const temporary = `${file}.pending.${crypto.randomUUID()}`;
  const fd = fs.openSync(temporary, 'wx', 0o600);
  try {
    try { fs.writeFileSync(fd, JSON.stringify(value, null, 2) + '\n'); fs.fsyncSync(fd); }
    finally { fs.closeSync(fd); }
    try { fs.linkSync(temporary, file); }
    catch (error) { if (error.code !== 'EEXIST') throw error; verifyExisting(); }
    const directoryFd = fs.openSync(path.dirname(file), 'r');
    try { fs.fsyncSync(directoryFd); } finally { fs.closeSync(directoryFd); }
  } finally {
    // This exact temporary file is created by this invocation, not user data.
    fs.unlinkSync(temporary);
  }
}

function projectDefinition(registry, projectId) {
  validateRegistry(registry);
  const candidates = registry.routes.filter(route => route.projectId === projectId);
  if (!candidates.length) fail('PROJECT_NOT_REGISTERED');
  if (candidates.length !== 1) fail('PROJECT_AMBIGUOUS');
  return candidates[0];
}

/** Public, side-effect-free parsing seam for CLI validation before queue open. */
export function inspectFeedbackInput(registry, { projectId, inputFile }) {
  const definition = projectDefinition(registry, projectId);
  const sourceRef = projectFile(definition.projectRoot, inputFile);
  const input = readJson(sourceRef);
  assertInput(input);
  const route = resolveRoute(registry, { projectId, target: input.intent.target });
  return { route, input, sourceRef };
}

/** Reads only an existing immutable intent; missing paths are never created. */
export function readSavedIntent(registry, { projectId, operationId }) {
  if (!ID.test(operationId)) fail('INVALID_OPERATION_ID');
  const definition = projectDefinition(registry, projectId);
  let root;
  try { root = fs.realpathSync(definition.projectRoot); } catch { fail('PROJECT_ROOT_UNAVAILABLE'); }
  const directory = path.join(root, 'artifacts', 'notion-coordination', 'outbox');
  const file = path.join(directory, `${digest([projectId, operationId])}.json`);
  try { projectFile(root, file); }
  catch (error) { if (error.code === 'ENOENT') fail('PRIVATE_RECORD_UNREADABLE'); throw error; }
  if ((fs.statSync(directory).mode & 0o077) !== 0) fail('PRIVATE_DIRECTORY_PERMISSIONS');
  if ((fs.statSync(file).mode & 0o077) !== 0) fail('PRIVATE_RECORD_PERMISSIONS');
  const saved = readJson(file);
  if (saved.schemaVersion !== 1 || saved.projectId !== projectId || !saved.intent || saved.intent.operationId !== operationId || !saved.metadata) fail('PRIVATE_RECORD_CONFLICT');
  assertInput({ source: saved.source, intent: saved.intent });
  resolveRoute(registry, { projectId, target: saved.intent.target });
  return saved;
}

export class CoordinationEngine {
  constructor({ registry, queue, mode = 'offline', clientFactory = null, authorization = null }) {
    if (!['offline', 'fixture', 'live'].includes(mode)) fail('LIVE_ACCESS_NOT_ENABLED');
    this.registry = registry; this.queue = queue; this.mode = mode; this.clientFactory = clientFactory;
    this.authorization = structuredClone(authorization);
  }
  save({ projectId, inputFile }) {
    const { route: selected, input, sourceRef } = inspectFeedbackInput(this.registry, { projectId, inputFile });
    const privateRef = path.join(privateDirectory(selected), `${digest([projectId, input.intent.operationId])}.json`);
    const metadata = { projectId, operationId: input.intent.operationId, sourceRef, sourceDigest: fileDigest(sourceRef), payloadDigest: digest(input), routeDigest: selected.routeDigest, targetId: selected.target.id ?? 'unresolved', profileId: selected.profileId ?? 'unresolved', adapterId: selected.adapterId };
    // A project-local immutable record survives a process dying before enqueue.
    // Repeating this same intent then completes enqueue without a second record.
    persist(privateRef, { schemaVersion: 1, projectId, ...input, metadata });
    const queued = this.queue.enqueue(metadata);
    return { projectId, operationId: input.intent.operationId, status: queued.status, privateRef, accessStatus: selected.accessStatus, gateReasons: selected.gateReasons, remoteCalls: 0 };
  }
  read(projectId, operationId) {
    return readSavedIntent(this.registry, { projectId, operationId });
  }
  #current(projectId, operationId) {
    const saved = this.read(projectId, operationId);
    const route = resolveRoute(this.registry, { projectId, target: saved.intent.target });
    const source = projectFile(route.projectRoot, saved.metadata.sourceRef);
    const conflict = code => {
      const existing = this.queue.get(projectId, operationId);
      if (existing && ['saved_local', 'preview_ready', 'blocked_access'].includes(existing.status)) this.queue.block(projectId, operationId, { code, status: 'conflict' });
      fail(code);
    };
    if (fileDigest(source) !== saved.metadata.sourceDigest) conflict('SOURCE_CHANGED');
    if (digest({ source: saved.source, intent: saved.intent }) !== saved.metadata.payloadDigest) conflict('PAYLOAD_CHANGED');
    if (route.routeDigest !== saved.metadata.routeDigest) conflict('ROUTE_CHANGED');
    const queued = this.queue.get(projectId, operationId);
    if (!queued || Object.entries(saved.metadata).some(([key, value]) => queued[key] !== value)) fail('QUEUE_INTENT_MISMATCH');
    return { saved, route };
  }
  #adapter(route, client = null) {
    if (!['fixture', 'live'].includes(this.mode)) fail('LIVE_ACCESS_NOT_ENABLED');
    if (!route.profile?.botId || !route.target.schemaVerified || route.authorityStatus !== 'confirmed') fail('SCOPE_UNVERIFIED');
    if (!this.clientFactory && !client) fail('FIXTURE_CLIENT_REQUIRED');
    const scopedRoute = { ...route, targets: { [route.targetAlias]: route.target } };
    return createProjectAdapter({ route: scopedRoute, client: client ?? this.clientFactory(route) });
  }
  #verification() { return this.mode === 'live' ? 'fixed_profile_readback' : 'fixture_only_not_live'; }
  #liveGrant(route, saved, queued, { authorization = this.authorization, write = false } = {}) {
    if (this.mode !== 'live') return authorization ? structuredClone(authorization) : null;
    if (!route.liveRead) fail('LIVE_READ_NOT_GRANTED');
    if (!route.profile?.botId || !route.profile.secretRef || route.profile.authorizationStatus !== 'verified') fail('PROFILE_AUTHORIZATION_REQUIRED');
    if (!route.target.id || !route.target.schemaVerified || route.authorityStatus !== 'confirmed') fail('SCOPE_UNVERIFIED');
    if (route.gateReasons.includes('BINDING_SOURCE_UNAVAILABLE')) fail('BINDING_SOURCE_UNAVAILABLE');
    const keys = ['mode', 'reference', 'profileId', 'workspaceId', 'read', 'write', 'scopeTargets'];
    const bindings = ['projectId', 'targetId', 'operationId', 'previewDigest', 'sourceDigest', 'payloadDigest', 'routeDigest'];
    if (!authorization || typeof authorization !== 'object' || Array.isArray(authorization)) fail('AUTHORIZATION_REQUIRED');
    const grant = structuredClone(authorization);
    if (Object.keys(grant).some(key => ![...keys, ...bindings].includes(key)) || keys.some(key => !Object.hasOwn(grant, key)) || grant.mode !== 'live' || grant.read !== true || typeof grant.write !== 'boolean' || typeof grant.reference !== 'string' || !grant.reference.trim() || grant.reference.length > 500 || /[\x00-\x1f\x7f]/.test(grant.reference) || /(?:ntn_|secret_|Bearer\s+)/i.test(grant.reference)) fail('AUTHORIZATION_INVALID');
    const normalized = value => { try { return normalizeId(value); } catch { fail('AUTHORIZATION_INVALID'); } };
    if (grant.profileId !== route.profileId || normalized(grant.workspaceId) !== normalized(route.workspaceId)) fail('AUTHORIZATION_IDENTITY_MISMATCH');
    const expected = new Set([route.target.id, ...Object.keys(route.target.allowedBlocks)].map(normalized));
    if (!Array.isArray(grant.scopeTargets) || grant.scopeTargets.length !== expected.size || new Set(grant.scopeTargets.map(normalized)).size !== expected.size || grant.scopeTargets.some(id => !expected.has(normalized(id)))) fail('AUTHORIZATION_SCOPE_MISMATCH');
    if (write && !route.liveWrite) fail('LIVE_WRITE_NOT_GRANTED');
    if (write && grant.write !== true) fail('WRITE_AUTHORIZATION_REQUIRED');
    if (write && bindings.some(key => !Object.hasOwn(grant, key))) fail('WRITE_AUTHORIZATION_REQUIRED');
    const expectedBindings = { projectId: route.projectId, targetId: route.target.id, operationId: saved.intent.operationId, previewDigest: queued?.previewDigest, sourceDigest: saved.metadata.sourceDigest, payloadDigest: saved.metadata.payloadDigest, routeDigest: route.routeDigest };
    for (const key of bindings) if (Object.hasOwn(grant, key) && (key === 'targetId' ? normalized(grant[key]) !== normalized(expectedBindings[key]) : grant[key] !== expectedBindings[key])) fail('AUTHORIZATION_BINDING_MISMATCH');
    return grant;
  }
  #readClient(route, authorization) {
    if (!this.clientFactory) fail(this.mode === 'live' ? 'CLIENT_REQUIRED' : 'FIXTURE_CLIENT_REQUIRED');
    const raw = this.clientFactory(route, { mode: this.mode, authorization: authorization ? { ...authorization, write: false } : null, readOnly: true });
    if (!raw || typeof raw.verifyIdentity !== 'function' || typeof raw.request !== 'function') fail('CLIENT_REQUIRED');
    const stats = { calls: 0 };
    const limited = async action => { if (stats.calls >= 300) fail('FINITE_CALL_BUDGET'); stats.calls++; return action(); };
    const client = { verifyIdentity: () => limited(() => raw.verifyIdentity()), request: (method, endpoint, body) => {
      if (method !== 'GET' && !(method === 'POST' && /^\/v1\/data_sources\/[a-fA-F0-9-]+\/query$/.test(endpoint))) fail('READ_ONLY_CAPABILITY');
      return limited(() => raw.request(method, endpoint, body));
    } };
    return { client, stats };
  }
  async preview(projectId, operationId) {
    const { saved, route } = this.#current(projectId, operationId);
    const queued = this.queue.get(projectId, operationId);
    if (queued.status === 'result_unknown') fail('RECONCILE_REQUIRED');
    if (queued.status === 'executing') fail('EXECUTION_LEASE_UNRESOLVED');
    if (!['saved_local', 'preview_ready', 'blocked_access'].includes(queued.status)) fail('PREVIEW_STATE_REQUIRED');
    if (this.mode === 'offline') {
      const blocked = this.queue.block(projectId, operationId, { code: route.gateReasons[0] ?? 'LIVE_ACCESS_NOT_ENABLED' });
      return { projectId, operationId, status: blocked.status, gateReasons: route.gateReasons, remoteCalls: 0 };
    }
    const authorization = this.#liveGrant(route, saved, queued);
    const { client, stats } = this.#readClient(route, authorization);
    const preview = await this.#adapter(route, client).prepare(saved.intent);
    const ref = path.join(privateDirectory(route), `${digest([projectId, operationId])}.preview.${preview.previewDigest}.json`);
    persist(ref, { projectId, operationId, sourceDigest: saved.metadata.sourceDigest, payloadDigest: saved.metadata.payloadDigest, routeDigest: route.routeDigest, executionMode: this.mode, verificationScope: this.#verification(), preview });
    const result = this.queue.preview(projectId, operationId, { previewDigest: preview.previewDigest });
    return { projectId, operationId, status: result.status, previewDigest: preview.previewDigest, previewRef: ref, summary: preview.summary, executionMode: this.mode, verificationScope: this.#verification(), requestCalls: stats.calls, remoteCalls: this.mode === 'live' ? stats.calls : 0 };
  }
  #previewRecord(route, projectId, operationId, queued, saved) {
    if (!queued?.previewDigest) fail('PREVIEW_REQUIRED');
    const ref = path.join(privateDirectory(route), `${digest([projectId, operationId])}.preview.${queued.previewDigest}.json`);
    projectFile(route.projectRoot, ref);
    const stored = readJson(ref);
    if (stored.projectId !== projectId || stored.operationId !== operationId || stored.routeDigest !== route.routeDigest || stored.preview?.previewDigest !== queued.previewDigest) fail('PREVIEW_CHANGED');
    if (stored.sourceDigest !== saved.metadata.sourceDigest || stored.payloadDigest !== saved.metadata.payloadDigest) fail('PREVIEW_CHANGED');
    if (stored.executionMode !== undefined && stored.executionMode !== this.mode || stored.verificationScope !== undefined && stored.verificationScope !== this.#verification() || this.mode === 'live' && stored.executionMode !== 'live') fail('VERIFICATION_SCOPE_MISMATCH');
    return stored.preview;
  }
  #cachedReceipt(route, projectId, operationId, queued) {
    if (!queued.receiptRef) fail('READBACK_NOT_VERIFIED');
    const ref = projectFile(route.projectRoot, queued.receiptRef);
    if ((fs.statSync(ref).mode & 0o077) !== 0) fail('PRIVATE_RECORD_PERMISSIONS');
    const receipt = readJson(ref);
    if (receipt.projectId !== projectId || receipt.operationId !== operationId || receipt.routeDigest !== route.routeDigest || receipt.status !== 'readback_verified' || receipt.readbackDigest !== queued.readbackDigest) fail('RECEIPT_CHANGED');
    if (receipt.verificationScope !== this.#verification() || receipt.executionMode !== undefined && receipt.executionMode !== this.mode || this.mode === 'live' && receipt.executionMode !== 'live') fail('VERIFICATION_SCOPE_MISMATCH');
    return { projectId, operationId, status: queued.status, receiptRef: ref, executionMode: this.mode, verificationScope: this.#verification(), remoteCalls: 0 };
  }
  #receipt(route, projectId, operationId, result) {
    if (result.status !== 'readback_verified' || !/^[a-f0-9]{64}$/.test(result.readbackDigest) || !Array.isArray(result.providerIds)) fail('READBACK_NOT_VERIFIED');
    const ref = path.join(privateDirectory(route), `${digest([projectId, operationId])}.receipt.${result.readbackDigest}.json`);
    persist(ref, { schemaVersion: 1, projectId, operationId, routeDigest: route.routeDigest, executionMode: this.mode, verificationScope: this.#verification(), ...result });
    return ref;
  }
  async apply(projectId, operationId, { owner, approval, authorization = this.authorization }) {
    if (!['fixture', 'live'].includes(this.mode)) fail('LIVE_ACCESS_NOT_ENABLED');
    const { saved, route } = this.#current(projectId, operationId);
    const queued = this.queue.get(projectId, operationId);
    const grant = this.#liveGrant(route, saved, queued, { authorization, write: true });
    if (approval !== queued.previewDigest) fail('PREVIEW_APPROVAL_REQUIRED');
    if (queued.status === 'readback_verified') return this.#cachedReceipt(route, projectId, operationId, queued);
    if (queued.status === 'result_unknown') fail('RECONCILE_REQUIRED');
    if (queued.status === 'executing') fail('EXECUTION_LEASE_UNRESOLVED');
    const preview = this.#previewRecord(route, projectId, operationId, queued, saved);
    const raw = this.clientFactory?.(route, { mode: this.mode, authorization: grant, readOnly: false });
    if (!raw) fail(this.mode === 'live' ? 'CLIENT_REQUIRED' : 'FIXTURE_CLIENT_REQUIRED');
    const lease = this.queue.claim({ owner, projectId, operationId });
    let calls = 0;
    let writesAccepted = 0;
    const tracked = async action => {
      if (calls >= 300) fail('FINITE_CALL_BUDGET');
      calls++;
      const callId = crypto.randomUUID();
      this.queue.beginCall(lease, callId);
      let outcome = 'failed';
      try { const value = await action(); outcome = 'success'; return value; }
      catch (error) { outcome = error.resultUnknown ? 'unknown' : 'failed'; throw error; }
      finally { this.queue.endCall(lease, callId, { outcome }); }
    };
    const client = { verifyIdentity: () => tracked(() => raw.verifyIdentity()), request: (...args) => tracked(async () => {
      const result = await raw.request(...args);
      if (args[0] === 'PATCH' || args[0] === 'POST' && /\/(?:v1\/)?pages$/.test(args[1])) writesAccepted++;
      return result;
    }) };
    try {
      const result = await this.#adapter(route, client).apply(saved.intent, preview);
      const receiptRef = this.#receipt(route, projectId, operationId, result);
      this.queue.finish(lease, { status: 'readback_verified', receiptRef, readbackDigest: result.readbackDigest });
      return { projectId, operationId, status: 'readback_verified', receiptRef, executionMode: this.mode, verificationScope: this.#verification(), requestCalls: calls, fixtureCalls: this.mode === 'fixture' ? calls : 0, remoteCalls: this.mode === 'live' ? calls : 0 };
    } catch (error) {
      const code = safeErrorCode(error);
      const status = error.resultUnknown || writesAccepted > 0 ? 'result_unknown' : /CHANGED|STALE|CONFLICT|MISMATCH/.test(code) ? 'conflict' : 'blocked_access';
      try { this.queue.finish(lease, { status, errorCode: code }); }
      catch (storageError) {
        // Do not release, reacquire, or rewrite after local settlement fails.
        // The durable lease may still be executing with a pending provider call.
        return { projectId, operationId, status: 'result_unknown', errorCode: code, storageErrorCode: safeErrorCode(storageError), leaseRetained: true, durableState: 'unresolved', executionMode: this.mode, verificationScope: this.#verification(), requestCalls: calls, fixtureCalls: this.mode === 'fixture' ? calls : 0, remoteCalls: this.mode === 'live' ? calls : 0 };
      }
      return { projectId, operationId, status, errorCode: code, executionMode: this.mode, verificationScope: this.#verification(), requestCalls: calls, fixtureCalls: this.mode === 'fixture' ? calls : 0, remoteCalls: this.mode === 'live' ? calls : 0 };
    }
  }
  async reconcile(projectId, operationId) {
    if (!['fixture', 'live'].includes(this.mode)) fail('LIVE_ACCESS_NOT_ENABLED');
    const { saved, route } = this.#current(projectId, operationId);
    const queued = this.queue.get(projectId, operationId);
    const authorization = this.#liveGrant(route, saved, queued);
    if (queued.status === 'readback_verified') return this.#cachedReceipt(route, projectId, operationId, queued);
    if (queued.status === 'executing') fail('EXECUTION_LEASE_UNRESOLVED');
    if (queued.status !== 'result_unknown') fail('RECONCILE_STATE_REQUIRED');
    const preview = this.#previewRecord(route, projectId, operationId, queued, saved);
    const { client, stats } = this.#readClient(route, authorization);
    try {
      const result = await this.#adapter(route, client).reconcile(saved.intent, preview);
      const receiptRef = this.#receipt(route, projectId, operationId, result);
      this.queue.reconcile(projectId, operationId, { receiptRef, readbackDigest: result.readbackDigest });
      return { projectId, operationId, status: 'readback_verified', receiptRef, executionMode: this.mode, verificationScope: this.#verification(), requestCalls: stats.calls, remoteCalls: this.mode === 'live' ? stats.calls : 0 };
    } catch (error) {
      // Reconciliation never retries or invents a remote write. Its existing
      // uncertainty is preserved on lookup, receipt, or durable-state failure.
      return { projectId, operationId, status: 'result_unknown', errorCode: safeErrorCode(error), executionMode: this.mode, verificationScope: this.#verification(), requestCalls: stats.calls, remoteCalls: this.mode === 'live' ? stats.calls : 0 };
    }
  }
}
