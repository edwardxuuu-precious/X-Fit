import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { CoordinationEngine } from '../../scripts/notion-coordination/engine.mjs';
import { OperationQueue } from '../../scripts/notion-coordination/queue.mjs';
import { loadRegistry } from '../../scripts/notion-coordination/router.mjs';
import { FixedProfileClient } from '../../scripts/notion-coordination/profiles.mjs';
import { NotionFixture, appendRoute, appendIntent, updateRoute, PAGE } from './adapters-fixture.mjs';

test('an offline feedback request is saved once in its project while the shared queue has no body', t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-engine-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const input = path.join(root, 'feedback.json');
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'fixture-request' }, intent: { operationId: 'feedback-1', kind: 'append-record', target: 'archive', record: { recordId: 'fixture-record-1', title: 'Fixture feedback', body: 'private original feedback only in project', properties: {} } } }));
  const queue = new OperationQueue(path.join(root, 'queue', 'global.sqlite'));
  t.after(() => queue.close());
  const engine = new CoordinationEngine({ registry, queue });
  const first = engine.save({ projectId: 'fitness-app', inputFile: input });
  const again = engine.save({ projectId: 'fitness-app', inputFile: input });
  assert.equal(first.operationId, again.operationId);
  assert.equal(queue.list().length, 1);
  assert.equal(queue.get('fitness-app', 'feedback-1').status, 'saved_local');
  assert.doesNotMatch(JSON.stringify(queue.list()), /private original feedback/);
  assert.equal(engine.read('fitness-app', 'feedback-1').source.author, 'fixture-user');
  assert.equal(fs.statSync(first.privateRef).mode & 0o777, 0o600);
});

function fixtureEngine(t) {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-flow-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const profile = { id: 'fixture-edward', workspaceId: '20000000-0000-4000-8000-000000000001', workspaceName: 'Fixture Edward', botId: '20000000-0000-4000-8000-000000000002', secretRef: { service: 'com.notion-coordination.fixture', account: 'fixture-edward' }, capabilities: ['read', 'insert'], apiVersion: '2026-03-11', authorizationStatus: 'verified' };
  const route = { ...appendRoute(), projectRoot: root, subprojectId: null, workspaceId: profile.workspaceId, profileId: profile.id, sourceBindings: [], authorityStatus: 'confirmed', liveRead: false, liveWrite: false };
  route.targets.archive.schemaVerified = true;
  const registry = { schemaVersion: 1, revision: 'fixture-1', profiles: [profile], routes: [route], policy: { phoneRealtimeUpload: false, sharedOAuthRebind: false, crossHost: false, defaultLiveAccess: false } };
  const provider = new NotionFixture();
  const hooks = { identities: [] };
  const queue = new OperationQueue(path.join(root, 'queue', 'global.sqlite')); t.after(() => queue.close());
  const input = path.join(root, 'input.json');
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'fixture-request' }, intent: appendIntent() }));
  const clientFactory = resolved => new FixedProfileClient({
    profile: resolved.profile,
    credentialReader: () => 'fixture-only-not-a-real-credential',
    grant: { mode: 'fixture', read: true, write: true, profileId: resolved.profile.id, workspaceId: resolved.profile.workspaceId, scopeTargets: Object.values(resolved.targets).flatMap(target => [target.id, ...Object.keys(target.allowedBlocks)]), reference: 'REQ-NGC-fixture' },
    transport: { async request({ method, path: endpoint, body }) {
      if (endpoint === '/v1/users/me') {
        hooks.identities.push(resolved.profile.id);
        return { status: 200, data: { object: 'user', type: 'bot', id: resolved.profile.botId, bot: { workspace_id: resolved.profile.workspaceId } }, headers: {} };
      }
      const result = await provider.request(method, endpoint, body);
      if (method === 'POST' && endpoint === '/v1/pages') hooks.afterAcceptedWrite?.();
      return result;
    } }
  });
  const engine = new CoordinationEngine({ registry, queue, mode: 'fixture', clientFactory });
  const saved = engine.save({ projectId: 'xfit', inputFile: input });
  return { engine, queue, provider, input, registry, hooks, saved };
}

test('the complete local interface creates a record, reads it back and repeats with zero additional writes', async t => {
  const { engine, queue, provider } = fixtureEngine(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  const result = await engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest });
  assert.equal(result.status, 'readback_verified');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'readback_verified');
  assert.equal(provider.effects.length, 1);
  assert.equal((await engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest })).status, 'readback_verified');
  assert.equal(provider.effects.length, 1);
});

test('a lost creation response requires read-only reconciliation and never repeats the accepted write', async t => {
  const { engine, queue, provider } = fixtureEngine(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  provider.failAfterCreate = true;
  const result = await engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest });
  assert.equal(result.status, 'result_unknown');
  await assert.rejects(engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest }), error => error.code === 'RECONCILE_REQUIRED');
  const verified = await engine.reconcile('xfit', 'feedback-1');
  assert.equal(verified.status, 'readback_verified');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'readback_verified');
  assert.equal(provider.effects.length, 1);
});

test('a local receipt failure after an accepted write remains unknown instead of allowing a new write', async t => {
  const { engine, queue, provider, hooks, saved } = fixtureEngine(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  hooks.afterAcceptedWrite = () => fs.chmodSync(path.dirname(saved.privateRef), 0o755);
  const result = await engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest });
  assert.equal(result.status, 'result_unknown');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'result_unknown');
  assert.equal(provider.effects.length, 1);
});

test('source edits after preview persist a conflict and do not overwrite the accepted intent', async t => {
  const { engine, queue, provider, input } = fixtureEngine(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  const changed = JSON.parse(fs.readFileSync(input, 'utf8')); changed.intent.record.body = 'new unapproved body';
  fs.writeFileSync(input, JSON.stringify(changed));
  await assert.rejects(engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest }), error => error.code === 'SOURCE_CHANGED');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'conflict');
  assert.equal(provider.effects.length, 0);
  assert.equal(engine.read('xfit', 'feedback-1').intent.record.body, '今天没有肘部不适。');
});

test('a route revision invalidates its old preview without reusing a different connection', async t => {
  const { engine, queue, provider, registry } = fixtureEngine(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  registry.revision = 'fixture-2';
  await assert.rejects(engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest }), error => error.code === 'ROUTE_CHANGED');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'conflict');
  assert.equal(provider.effects.length, 0);
});

test('a changed private payload invalidates its preview and cannot become an accepted remote write', async t => {
  const { engine, queue, provider, saved } = fixtureEngine(t);
  const preview = await engine.preview('xfit', 'feedback-1');
  const altered = JSON.parse(fs.readFileSync(saved.privateRef, 'utf8'));
  altered.intent.record.body = 'unapproved altered private payload';
  fs.writeFileSync(saved.privateRef, JSON.stringify(altered));
  await assert.rejects(engine.apply('xfit', 'feedback-1', { owner: 'fixture-session', approval: preview.previewDigest }), error => error.code === 'PAYLOAD_CHANGED');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'conflict');
  assert.equal(provider.effects.length, 0);
});

test('a blocked workspace does not stop the other project, then both profiles can alternate on one queue', async t => {
  const { engine, queue, provider, registry, hooks, input: originalInput } = fixtureEngine(t);
  const root = path.join(path.dirname(originalInput), 'football');
  fs.mkdirSync(root, { mode: 0o700 });
  const profile = { ...structuredClone(registry.profiles[0]), id: 'fixture-primeviz', workspaceId: '30000000-0000-4000-8000-000000000001', botId: '30000000-0000-4000-8000-000000000002', secretRef: { service: 'com.notion-coordination.fixture', account: 'fixture-primeviz' }, capabilities: ['read', 'update'] };
  const route = { ...updateRoute(), projectRoot: root, subprojectId: null, workspaceId: profile.workspaceId, profileId: profile.id, sourceBindings: [], authorityStatus: 'confirmed', liveRead: false, liveWrite: false };
  route.targets.summary.schemaVerified = true;
  registry.profiles.push(profile); registry.routes.push(route);
  const input = path.join(root, 'summary.json');
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'fixture-user', kind: 'project_observation', reference: 'fixture-request' }, intent: { operationId: 'summary-1', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '经过验证的本地摘要' }] } }));
  engine.save({ projectId: 'football', inputFile: input });
  const offline = new CoordinationEngine({ registry, queue });
  assert.equal((await offline.preview('xfit', 'feedback-1')).status, 'blocked_access');
  const preview = await engine.preview('football', 'summary-1');
  assert.equal((await engine.apply('football', 'summary-1', { owner: 'second-session', approval: preview.previewDigest })).status, 'readback_verified');
  assert.equal(queue.get('xfit', 'feedback-1').status, 'blocked_access');
  assert.deepEqual([...new Set(hooks.identities)], ['fixture-primeviz']);
  assert.equal(provider.effects.length, 1);
  const existing = await provider.request('GET', `/v1/pages/${PAGE}`);
  assert.equal(existing.data.properties['人工批准'].checkbox, false);
  const firstPreview = await engine.preview('xfit', 'feedback-1');
  assert.equal((await engine.apply('xfit', 'feedback-1', { owner: 'first-session', approval: firstPreview.previewDigest })).status, 'readback_verified');
  assert.deepEqual([...new Set(hooks.identities)], ['fixture-primeviz', 'fixture-edward']);
  assert.equal(provider.effects.length, 2);
  assert.equal(queue.list().filter(item => item.status === 'readback_verified').length, 2);
});

test('local feedback rejects credentials, symlinks and wider private-file permissions instead of copying them', t => {
  const { engine, queue, input, saved } = fixtureEngine(t);
  const source = JSON.parse(fs.readFileSync(input, 'utf8'));
  source.intent.operationId = 'secret-content'; source.intent.record.body = 'ntn_fixture_fake_credential_not_for_storage';
  fs.writeFileSync(input, JSON.stringify(source));
  assert.throws(() => engine.save({ projectId: 'xfit', inputFile: input }), error => error.code === 'CREDENTIAL_CONTENT_REFUSED');
  const symlink = path.join(path.dirname(input), 'linked.json'); fs.symlinkSync(input, symlink);
  assert.throws(() => engine.save({ projectId: 'xfit', inputFile: symlink }), error => error.code === 'SOURCE_SYMLINK_REFUSED');
  source.intent.operationId = 'feedback-1'; source.intent.record.body = '今天没有肘部不适。';
  fs.writeFileSync(input, JSON.stringify(source));
  fs.chmodSync(saved.privateRef, 0o644);
  assert.throws(() => engine.save({ projectId: 'xfit', inputFile: input }), error => error.code === 'PRIVATE_RECORD_PERMISSIONS');
  assert.equal(queue.list().length, 1);
});

test('offline preview reports the access gate without reading credentials or contacting Notion', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-offline-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const input = path.join(root, 'feedback.json');
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'fixture-request' }, intent: { operationId: 'feedback-2', kind: 'append-record', target: 'archive', record: { recordId: 'record-2', title: 'Fixture', body: 'Offline feedback', properties: {} } } }));
  const queue = new OperationQueue(path.join(root, 'queue', 'global.sqlite')); t.after(() => queue.close());
  const engine = new CoordinationEngine({ registry, queue, clientFactory() { assert.fail('must not request a client offline'); } });
  engine.save({ projectId: 'fitness-app', inputFile: input });
  const result = await engine.preview('fitness-app', 'feedback-2');
  assert.equal(result.status, 'blocked_access');
  assert.equal(result.remoteCalls, 0);
  assert.equal(queue.get('fitness-app', 'feedback-2').status, 'blocked_access');
  assert.equal(engine.read('fitness-app', 'feedback-2').intent.record.body, 'Offline feedback');
});

test('reading a missing operation does not create project-private directories', t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-missing-read-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const queue = new OperationQueue(path.join(root, 'queue', 'global.sqlite')); t.after(() => queue.close());
  const engine = new CoordinationEngine({ registry, queue });
  assert.throws(() => engine.read('fitness-app', 'not-saved'));
  assert.equal(fs.existsSync(path.join(root, 'artifacts')), false);
});
