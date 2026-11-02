import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { CoordinationEngine } from '../../scripts/notion-coordination/engine.mjs';
import { OperationQueue } from '../../scripts/notion-coordination/queue.mjs';
import { NotionFixture, appendRoute, appendIntent, SOURCE } from './adapters-fixture.mjs';

function liveFixture(t, { configureRegistry = null, ...overrides } = {}) {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-live-seam-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const profile = { id: 'isolated-edward', workspaceId: '20000000-0000-4000-8000-000000000001', workspaceName: 'Isolated workspace', botId: '20000000-0000-4000-8000-000000000002', secretRef: { service: 'com.notion-coordination.fixture', account: 'isolated-edward' }, capabilities: ['read', 'insert'], apiVersion: '2026-03-11', authorizationStatus: 'verified' };
  const route = { ...appendRoute(), projectRoot: root, subprojectId: null, workspaceId: profile.workspaceId, profileId: profile.id, sourceBindings: [], authorityStatus: 'confirmed', liveRead: true, liveWrite: true };
  route.targets.archive.schemaVerified = true;
  const registry = { schemaVersion: 1, revision: 'isolated-live-1', profiles: [profile], routes: [route], policy: { phoneRealtimeUpload: false, sharedOAuthRebind: false, crossHost: false, defaultLiveAccess: false } };
  configureRegistry?.(registry);
  const authorization = { mode: 'live', reference: 'explicit-local-test-read-only', profileId: profile.id, workspaceId: profile.workspaceId, read: true, write: false, scopeTargets: [SOURCE] };
  const provider = new NotionFixture();
  const factoryRequests = [];
  const clientFactory = (resolved, context) => { factoryRequests.push(context); return provider; };
  const queue = new OperationQueue(path.join(root, 'queue', 'global.sqlite'));
  t.after(() => queue.close());
  const input = path.join(root, 'input.json');
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'localtest-only' }, intent: appendIntent() }));
  const engine = new CoordinationEngine({ registry, queue, mode: 'live', clientFactory, authorization, ...overrides });
  const saved = engine.save({ projectId: 'xfit', inputFile: input });
  return { engine, queue, provider, registry, authorization, factoryRequests, input, saved, clientFactory };
}

function specificGrant(context, preview) {
  const queued = context.queue.get('xfit', 'feedback-1');
  return { ...context.authorization, write: true, reference: 'specific-localtest-write-confirmation', projectId: 'xfit', targetId: SOURCE, operationId: 'feedback-1', previewDigest: preview.previewDigest, sourceDigest: queued.sourceDigest, payloadDigest: queued.payloadDigest, routeDigest: queued.routeDigest };
}

test('explicit live-mode software can preview with a separate read grant without upgrading it into write permission', async t => {
  const { engine, queue, provider, factoryRequests } = liveFixture(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  assert.equal(preview.status, 'preview_ready');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'preview_ready');
  assert.equal(provider.effects.length, 0);
  assert.equal(factoryRequests[0].readOnly, true);
  assert.equal(factoryRequests[0].authorization.write, false);
  assert.equal(preview.executionMode, 'live');
  assert.equal(preview.verificationScope, 'fixed_profile_readback');
});

test('a live apply requires a separately confirmed grant bound to this exact preview and saved intent', async t => {
  const { engine, provider, queue, authorization, saved } = liveFixture(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  const grant = { ...authorization, write: true, reference: 'specific-localtest-write-confirmation', projectId: 'xfit', targetId: SOURCE, operationId: 'feedback-1', previewDigest: preview.previewDigest, sourceDigest: queue.get('xfit', 'feedback-1').sourceDigest, payloadDigest: queue.get('xfit', 'feedback-1').payloadDigest, routeDigest: queue.get('xfit', 'feedback-1').routeDigest };
  await assert.rejects(engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest }), error => error.code === 'WRITE_AUTHORIZATION_REQUIRED');
  assert.equal(provider.effects.length, 0);
  const result = await engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest, authorization: grant });
  assert.equal(result.status, 'readback_verified');
  assert.equal(result.executionMode, 'live');
  assert.equal(result.verificationScope, 'fixed_profile_readback');
  const receipt = JSON.parse(fs.readFileSync(result.receiptRef, 'utf8'));
  assert.equal(receipt.executionMode, 'live');
  assert.equal(receipt.verificationScope, 'fixed_profile_readback');
  assert.equal(provider.effects.length, 1);
  assert.equal(fs.statSync(saved.privateRef).mode & 0o777, 0o600);
  assert.equal((await engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest, authorization: grant })).status, 'readback_verified');
  assert.equal(provider.effects.length, 1);
});

test('an unknown live-mode response is reconciled with read authority only and never inserts again', async t => {
  const context = liveFixture(t);
  const { engine, provider, queue, factoryRequests } = context;
  const preview = await engine.preview('xfit', 'feedback-1');
  const authorization = specificGrant(context, preview);
  provider.failAfterCreate = true;
  const result = await engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest, authorization });
  assert.equal(result.status, 'result_unknown');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'result_unknown');
  const reconciled = await engine.reconcile('xfit', 'feedback-1');
  assert.equal(reconciled.status, 'readback_verified');
  assert.equal(factoryRequests.at(-1).readOnly, true);
  assert.equal(factoryRequests.at(-1).authorization.write, false);
  assert.equal(provider.effects.length, 1);
});

test('cached fixture readback cannot be relabeled as live evidence by changing the execution mode', async t => {
  const context = liveFixture(t, { mode: 'fixture' });
  const preview = await context.engine.preview('xfit', 'feedback-1');
  await context.engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest });
  const live = new CoordinationEngine({ registry: context.registry, queue: context.queue, mode: 'live', clientFactory: context.clientFactory, authorization: context.authorization });
  await assert.rejects(live.reconcile('xfit', 'feedback-1'), error => error.code === 'VERIFICATION_SCOPE_MISMATCH');
  assert.equal(context.provider.effects.length, 1);
});

test('a failed unknown-result lookup stays unknown and reports an explicit error instead of retrying the write', async t => {
  const context = liveFixture(t);
  const preview = await context.engine.preview('xfit', 'feedback-1');
  context.provider.failAfterCreate = true;
  await context.engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest, authorization: specificGrant(context, preview) });
  const readOnly = new CoordinationEngine({ registry: context.registry, queue: context.queue, mode: 'live', authorization: context.authorization,
    clientFactory: () => ({ verifyIdentity: () => context.provider.verifyIdentity(), async request(method, path, body) {
      if (path.endsWith('/query')) return { status: 503, data: { object: 'error' }, headers: {} };
      return context.provider.request(method, path, body);
    } }) });
  const result = await readOnly.reconcile('xfit', 'feedback-1');
  assert.equal(result.status, 'result_unknown');
  assert.equal(result.errorCode, 'PROVIDER_503');
  assert.equal(context.queue.get('xfit', 'feedback-1').status, 'result_unknown');
  assert.equal(context.provider.effects.length, 1);
});

test('a valid single-intent live grant cannot excuse a different explicit preview approval', async t => {
  const context = liveFixture(t);
  const preview = await context.engine.preview('xfit', 'feedback-1');
  await assert.rejects(context.engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: '0'.repeat(64), authorization: specificGrant(context, preview) }), error => error.code === 'PREVIEW_APPROVAL_REQUIRED');
  assert.equal(context.provider.effects.length, 0);
});

test('storage loss after provider commit reports unknown and a surviving executing lease is not stolen for recovery', async t => {
  const context = liveFixture(t);
  const preview = await context.engine.preview('xfit', 'feedback-1');
  const authorization = specificGrant(context, preview);
  const interrupted = new CoordinationEngine({ registry: context.registry, queue: context.queue, mode: 'live', authorization: context.authorization,
    clientFactory: () => ({ verifyIdentity: () => context.provider.verifyIdentity(), async request(method, path, body) {
      const result = await context.provider.request(method, path, body);
      if (method === 'POST' && path === '/v1/pages') context.queue.close();
      return result;
    } }) });
  const result = await interrupted.apply('xfit', 'feedback-1', { owner: 'shutdown-session', approval: preview.previewDigest, authorization });
  assert.equal(result.status, 'result_unknown');
  assert.equal(result.storageErrorCode, 'QUEUE_CLOSED');
  assert.equal(result.leaseRetained, true);
  assert.equal(context.provider.effects.length, 1);
  const reopened = new OperationQueue(path.join(path.dirname(context.input), 'queue', 'global.sqlite'));
  t.after(() => reopened.close());
  assert.equal(reopened.get('xfit', 'feedback-1').status, 'executing');
  const recovery = new CoordinationEngine({ registry: context.registry, queue: reopened, mode: 'live', authorization: context.authorization, clientFactory() { assert.fail('an unresolved execution lease must stop before new provider access'); } });
  await assert.rejects(recovery.preview('xfit', 'feedback-1'), error => error.code === 'EXECUTION_LEASE_UNRESOLVED');
  await assert.rejects(recovery.reconcile('xfit', 'feedback-1'), error => error.code === 'EXECUTION_LEASE_UNRESOLVED');
  await assert.rejects(recovery.apply('xfit', 'feedback-1', { owner: 'new-session', approval: preview.previewDigest, authorization }), error => error.code === 'EXECUTION_LEASE_UNRESOLVED');
  assert.equal(context.provider.effects.length, 1);
});

test('a fixture operation on a multi-target route reads and writes only its separately granted selected target', async t => {
  const other = '40000000-0000-4000-8000-000000000004';
  const context = liveFixture(t, { mode: 'fixture', configureRegistry(registry) {
    registry.routes[0].targets.unselected = { ...structuredClone(registry.routes[0].targets.archive), id: other };
  } });
  let otherReads = 0;
  const engine = new CoordinationEngine({ registry: context.registry, queue: context.queue, mode: 'fixture',
    clientFactory: () => ({ verifyIdentity: () => context.provider.verifyIdentity(), async request(method, endpoint, body) {
      if (endpoint.includes(other)) { otherReads++; throw new Error('outside selected target grant'); }
      if (method === 'POST' && endpoint === '/v1/pages') assert.equal(body.parent.data_source_id, SOURCE);
      return context.provider.request(method, endpoint, body);
    } }) });
  const preview = await engine.preview('xfit', 'feedback-1');
  const result = await engine.apply('xfit', 'feedback-1', { owner: 'selected-only-session', approval: preview.previewDigest });
  assert.equal(result.status, 'readback_verified');
  assert.equal(otherReads, 0);
  assert.equal(context.provider.effects.length, 1);
});

test('every single-intent authorization binding must match, and missing binding fields authorize zero writes', async t => {
  const context = liveFixture(t);
  const preview = await context.engine.preview('xfit', 'feedback-1');
  const valid = specificGrant(context, preview);
  const bindings = ['projectId', 'targetId', 'operationId', 'previewDigest', 'sourceDigest', 'payloadDigest', 'routeDigest'];
  for (const field of bindings) {
    const missing = { ...valid }; delete missing[field];
    await assert.rejects(context.engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest, authorization: missing }), error => error.code === 'WRITE_AUTHORIZATION_REQUIRED');
    const wrong = { ...valid, [field]: field === 'targetId' ? '40000000-0000-4000-8000-000000000004' : field.endsWith('Digest') ? '0'.repeat(64) : 'another-operation-or-project' };
    await assert.rejects(context.engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest, authorization: wrong }), error => error.code === 'AUTHORIZATION_BINDING_MISMATCH');
  }
  assert.equal(context.provider.effects.length, 0);
  assert.equal(context.queue.get('xfit', 'feedback-1').status, 'preview_ready');
});

test('live read gates reject missing authorization, wrong identity or unconfigured scope before requesting a client', async t => {
  const gates = [
    ['missing read authorization', {}, null, 'AUTHORIZATION_REQUIRED'],
    ['closed read gate', { liveRead: false }, undefined, 'LIVE_READ_NOT_GRANTED'],
    ['unconfirmed ownership', { authorityStatus: 'candidate' }, undefined, 'SCOPE_UNVERIFIED'],
    ['unknown actual schema', {}, undefined, 'SCOPE_UNVERIFIED'],
    ['unconfigured profile', {}, undefined, 'PROFILE_AUTHORIZATION_REQUIRED'],
    ['wrong workspace', {}, 'wrong-workspace', 'AUTHORIZATION_IDENTITY_MISMATCH'],
  ];
  for (const [name, routeOverrides, grantOverride, expected] of gates) await t.test(name, async inner => {
    const context = liveFixture(inner, { configureRegistry(registry) {
      Object.assign(registry.routes[0], routeOverrides);
      if (name === 'unknown actual schema') registry.routes[0].targets.archive.schemaVerified = false;
      if (name === 'unconfigured profile') registry.profiles[0].authorizationStatus = 'candidate';
    } });
    const authorization = grantOverride === null ? null : grantOverride === 'wrong-workspace' ? { ...context.authorization, workspaceId: '40000000-0000-4000-8000-000000000004' } : context.authorization;
    const engine = new CoordinationEngine({ registry: context.registry, queue: context.queue, mode: 'live', authorization, clientFactory() { assert.fail('input and scope gates run before client acquisition'); } });
    await assert.rejects(engine.preview('xfit', 'feedback-1'), error => error.code === expected);
    assert.equal(context.provider.effects.length, 0);
  });
});

test('a closed live-write route permits a read preview but cannot acquire a writer even with a specific approval', async t => {
  const context = liveFixture(t, { configureRegistry(registry) { registry.routes[0].liveWrite = false; } });
  const preview = await context.engine.preview('xfit', 'feedback-1');
  const callsBeforeWrite = context.factoryRequests.length;
  await assert.rejects(context.engine.apply('xfit', 'feedback-1', { owner: 'localtest-session', approval: preview.previewDigest, authorization: specificGrant(context, preview) }), error => error.code === 'LIVE_WRITE_NOT_GRANTED');
  assert.equal(context.factoryRequests.length, callsBeforeWrite);
  assert.equal(context.provider.effects.length, 0);
  assert.equal(context.queue.get('xfit', 'feedback-1').status, 'preview_ready');
});

test('read grants with broader or duplicate scope, unknown fields, or a false read flag fail before client acquisition', async t => {
  const context = liveFixture(t);
  const other = '40000000-0000-4000-8000-000000000004';
  const invalid = [
    [{ ...context.authorization, scopeTargets: [SOURCE, other] }, 'AUTHORIZATION_SCOPE_MISMATCH'],
    [{ ...context.authorization, scopeTargets: [SOURCE, SOURCE] }, 'AUTHORIZATION_SCOPE_MISMATCH'],
    [{ ...context.authorization, scopeTargets: [other] }, 'AUTHORIZATION_SCOPE_MISMATCH'],
    [{ ...context.authorization, unknownPermission: true }, 'AUTHORIZATION_INVALID'],
    [{ ...context.authorization, read: false }, 'AUTHORIZATION_INVALID'],
  ];
  for (const [authorization, expected] of invalid) {
    const engine = new CoordinationEngine({ registry: context.registry, queue: context.queue, mode: 'live', authorization, clientFactory() { assert.fail('unconfirmed scope must not acquire a provider client'); } });
    await assert.rejects(engine.preview('xfit', 'feedback-1'), error => error.code === expected);
  }
  assert.equal(context.provider.effects.length, 0);
  assert.equal(context.queue.get('xfit', 'feedback-1').status, 'saved_local');
});
