import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { main } from '../../scripts/notion-coordinate.mjs';
import { loadRegistry } from '../../scripts/notion-coordination/router.mjs';
import { NotionFixture, appendRoute, updateRoute, appendIntent, SOURCE, PAGE, BLOCK } from './adapters-fixture.mjs';

const cli = fileURLToPath(new URL('../../scripts/notion-coordinate.mjs', import.meta.url));
async function runCLI(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, ...args], { timeout: 15_000 });
    let stdout = '', stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', code => resolve({ code, stdout, stderr, report: stdout ? JSON.parse(stdout) : null }));
  });
}
async function fixtureProject(t, registry, projectId, root) {
  fs.mkdirSync(root, { mode: 0o700 });
  const route = registry.routes.find(item => item.projectId === projectId);
  route.projectRoot = root; route.sourceBindings = [];
  route.targets = (projectId === 'fitness-app' ? appendRoute() : updateRoute()).targets;
  for (const target of Object.values(route.targets)) target.schemaVerified = true;
  const profile = registry.profiles.find(item => item.id === route.profileId);
  profile.botId = 'a1111111-1111-4111-8111-111111111111';
  profile.authorizationStatus = 'verified';
  profile.capabilities = ['read', 'insert', 'update'];
  profile.secretRef = { service: 'com.xfit.notion-access', account: profile.workspaceId };
  const provider = new NotionFixture();
  const calls = [];
  const server = http.createServer(async (request, response) => {
    const chunks = []; for await (const chunk of request) chunks.push(chunk);
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : undefined;
    calls.push({ method: request.method, path: request.url });
    try {
      let result;
      if (request.url === '/v1/users/me') result = { status: 200, data: { object: 'user', type: 'bot', id: profile.botId, bot: { workspace_id: profile.workspaceId } } };
      else if (request.url === `/v1/data_sources/${SOURCE}/query` && !body?.filter) result = { status: 200, data: { object: 'list', results: [...provider.pages.values()].map(entry => entry.page).filter(page => page.parent.data_source_id === SOURCE), has_more: false, next_cursor: null } };
      else result = await provider.request(request.method, request.url, body);
      // Serve the actual property metadata contract, not the lean adapter fixture.
      result.data = structuredClone(result.data);
      if (result.data?.object === 'data_source') {
        result.data.archived ??= false;
        result.data.in_trash ??= false;
        for (const property of Object.values(result.data.properties)) property[property.type] ??= {};
      }
      if (result.data?.object === 'page') {
        for (const [name, property] of Object.entries(result.data.properties)) property.id ??= `fixture-${encodeURIComponent(name)}`;
      }
      response.writeHead(result.status, { 'content-type': 'application/json', ...result.headers });
      response.end(JSON.stringify(result.data));
    } catch { response.destroy(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const target = Object.values(route.targets)[0];
  const access = { schemaVersion: 1, mode: 'fixture', fixtureOrigin: `http://127.0.0.1:${server.address().port}`, grant: { mode: 'fixture', reference: 'fixture-only-reviewed-source', profileId: route.profileId, workspaceId: route.workspaceId, read: true, write: false, scopeTargets: [target.id, ...Object.keys(target.allowedBlocks)] } };
  const accessFile = path.join(root, 'access.json');
  const writeAccess = () => fs.writeFileSync(accessFile, JSON.stringify(access), { mode: 0o600 });
  writeAccess();
  return { route, target, provider, calls, access, accessFile, writeAccess, root };
}
function writeInput(project, intent) {
  const inputFile = path.join(project.root, 'feedback.json');
  fs.writeFileSync(inputFile, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'fixture-request-not-a-real-grant' }, intent }));
  return inputFile;
}
function authorizeFixture(project, saved, preview) {
  project.access.executionGrant = { ...project.access.grant, write: true, projectId: saved.projectId, targetId: project.target.id, operationId: saved.intent.operationId, previewDigest: preview.previewDigest, sourceDigest: saved.metadata.sourceDigest, payloadDigest: saved.metadata.payloadDigest, routeDigest: saved.metadata.routeDigest };
  project.writeAccess();
}

test('doctor defaults to offline and reports its gate without creating a queue', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-doctor-offline-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const queue = path.join(root, 'new-queue', 'shared.sqlite');
  const report = await main(['doctor', '--project', 'fitness-app', '--queue', queue]);
  assert.equal(report.status, 'blocked_access');
  assert.equal(report.mode, 'offline');
  assert.equal(report.credentialReadPerformed, false);
  assert.equal(report.remoteCalls, 0);
  assert.equal(fs.existsSync(path.dirname(queue)), false);
});

test('two isolated project processes use the same public workflow without auth switching or duplicate writes', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-http-two-projects-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  const xfit = await fixtureProject(t, registry, 'fitness-app', path.join(root, 'fitness'));
  const football = await fixtureProject(t, registry, 'football', path.join(root, 'football'));
  const config = path.join(root, 'registry.json'); fs.writeFileSync(config, JSON.stringify(registry));
  const queue = path.join(root, 'queue', 'shared.sqlite');
  const humanBefore = JSON.stringify(football.provider.pages.get(PAGE).page.properties['人工批准']);
  for (const [project, intent] of [[xfit, appendIntent()], [football, { operationId: 'owned-1', kind: 'owned-update', target: 'summary', changes: [{ property: '工程摘要', value: '本地fixture完成' }, { blockId: BLOCK, value: '本地fixture完成' }] }]]) {
    const base = ['--registry', config, '--project', project.route.projectId, '--queue', queue];
    const online = ['--mode', 'fixture', '--access', project.accessFile];
    const recorded = await runCLI(['record', ...base, '--input', writeInput(project, intent)]);
    assert.equal(recorded.code, 0, recorded.stderr);
    assert.equal(recorded.report.remoteCalls, 0);
    const saved = JSON.parse(fs.readFileSync(recorded.report.privateRef, 'utf8'));
    const preview = await runCLI(['preview', ...base, '--operation', intent.operationId, ...online]);
    assert.equal(preview.code, 0, preview.stderr);
    assert.equal(preview.report.status, 'preview_ready');
    assert.equal(preview.report.verificationScope, 'fixture_only_not_live');
    authorizeFixture(project, saved, preview.report);
    const execute = ['apply', ...base, '--operation', intent.operationId, ...online, '--owner', `session-${project.route.projectId}`, '--approval', preview.report.previewDigest];
    const applied = await runCLI(execute);
    assert.equal(applied.code, 0, applied.stderr);
    assert.equal(applied.report.status, 'readback_verified');
    assert.equal(applied.report.verificationScope, 'fixture_only_not_live');
    const receipt = JSON.parse(fs.readFileSync(applied.report.receiptRef, 'utf8'));
    assert.equal(receipt.verificationScope, 'fixture_only_not_live');
    assert.match(receipt.readbackDigest, /^[a-f0-9]{64}$/);
    const writeCount = project.provider.effects.length;
    const requestCount = project.calls.length;
    const repeated = await runCLI(execute);
    assert.equal(repeated.code, 0, repeated.stderr);
    assert.equal(project.provider.effects.length, writeCount);
    assert.equal(repeated.report.status, 'readback_verified');
    assert.equal(project.calls.length, requestCount);
    const doctor = await runCLI(['doctor', ...base, ...online]);
    assert.equal(doctor.code, 0, doctor.stderr);
    assert.equal(doctor.report.status, 'inspection_verified');
    assert.equal(doctor.report.permissionsActivated, false);
    assert.equal(doctor.report.writes, 0);
    assert.doesNotMatch(doctor.stdout, /今天没有肘部不适|本地fixture完成|人工意见保持原样|fixture-only-local-token/);
  }
  assert.equal(xfit.provider.effects.filter(item => item.method === 'POST').length, 1);
  assert.equal(football.provider.effects.filter(item => item.method === 'PATCH').length, 2);
  assert.equal(JSON.stringify(football.provider.pages.get(PAGE).page.properties['人工批准']), humanBefore);
});

test('a lost HTTP create response is recovered only by reading the same operation, not by resending', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-http-unknown-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  const project = await fixtureProject(t, registry, 'fitness-app', path.join(root, 'fitness'));
  const config = path.join(root, 'registry.json'); fs.writeFileSync(config, JSON.stringify(registry));
  const queue = path.join(root, 'queue', 'shared.sqlite');
  const base = ['--registry', config, '--project', project.route.projectId, '--queue', queue];
  const online = ['--mode', 'fixture', '--access', project.accessFile];
  const intent = appendIntent();
  const record = await runCLI(['record', ...base, '--input', writeInput(project, intent)]);
  assert.equal(record.code, 0, record.stderr);
  const saved = JSON.parse(fs.readFileSync(record.report.privateRef, 'utf8'));
  const preview = await runCLI(['preview', ...base, '--operation', intent.operationId, ...online]);
  assert.equal(preview.code, 0, preview.stderr);
  authorizeFixture(project, saved, preview.report);
  const execute = ['apply', ...base, '--operation', intent.operationId, ...online, '--owner', 'local-session', '--approval', preview.report.previewDigest];
  // A forged grant must fail before even opening an unrelated new queue.
  const validGrant = structuredClone(project.access.executionGrant);
  project.access.executionGrant.operationId = 'wrong-operation'; project.writeAccess();
  const callsBeforeInvalid = project.calls.length;
  const invalidQueue = path.join(root, 'invalid-queue', 'never.sqlite');
  const invalid = await runCLI(execute.map(value => value === queue ? invalidQueue : value));
  assert.equal(invalid.code, 2);
  assert.equal(JSON.parse(invalid.stderr).error, 'EXECUTION_GRANT_MISMATCH');
  assert.equal(fs.existsSync(path.dirname(invalidQueue)), false);
  assert.equal(project.calls.length, callsBeforeInvalid);
  project.access.executionGrant = validGrant; project.writeAccess();
  project.provider.failAfterCreate = true;
  const unknown = await runCLI(execute);
  assert.equal(unknown.code, 2, unknown.stderr);
  assert.equal(unknown.report.status, 'result_unknown');
  assert.equal(project.provider.effects.filter(item => item.method === 'POST').length, 1);
  const requestsAfterUnknown = project.calls.length;
  const noResend = await runCLI(execute);
  assert.equal(noResend.code, 2);
  assert.equal(JSON.parse(noResend.stderr).error, 'RECONCILE_REQUIRED');
  assert.equal(project.calls.length, requestsAfterUnknown);
  // Grant retains write capability, but the reconcile entry forcibly demotes it.
  project.access.grant.write = true; project.writeAccess();
  const recovered = await runCLI(['reconcile', ...base, '--operation', intent.operationId, ...online]);
  assert.equal(recovered.code, 0, recovered.stderr);
  assert.equal(recovered.report.status, 'readback_verified');
  const recoveryCalls = project.calls.slice(requestsAfterUnknown);
  assert.ok(recoveryCalls.length > 0);
  assert.ok(recoveryCalls.every(call => call.method === 'GET' || call.method === 'POST' && /\/data_sources\/[^/]+\/query$/.test(call.path)));
  assert.equal(project.provider.effects.filter(item => item.method === 'POST').length, 1);
});

test('public connection modes and access-file errors leave the queue, feedback and provider untouched', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-cli-access-reject-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  const project = await fixtureProject(t, registry, 'fitness-app', path.join(root, 'fitness'));
  const config = path.join(root, 'registry.json'); fs.writeFileSync(config, JSON.stringify(registry));
  const queue = path.join(root, 'queue', 'never.sqlite');
  const args = ['doctor', '--registry', config, '--project', 'fitness-app', '--queue', queue, '--mode', 'fixture', '--access', project.accessFile];
  const original = structuredClone(project.access);
  for (const [mutate, expected] of [
    [value => { value.mode = 'live'; }, 'ACCESS_MODE_MISMATCH'],
    [value => { value.grant.mode = 'live'; }, 'ACCESS_MODE_MISMATCH'],
    [value => { value.token = 'credential-must-never-appear'; }, 'CREDENTIAL_CONTENT_REFUSED'],
    [value => { value.fixtureOrigin = 'https://api.notion.com'; }, 'HTTP_CONFIG_INVALID']
  ]) {
    const mutated = structuredClone(original); mutate(mutated);
    fs.writeFileSync(project.accessFile, JSON.stringify(mutated));
    const rejected = await runCLI(args);
    assert.equal(rejected.code, 2);
    assert.equal(JSON.parse(rejected.stderr).error, expected, rejected.stderr);
    assert.doesNotMatch(rejected.stderr, /credential-must-never-appear/);
    assert.equal(project.calls.length, 0);
    assert.equal(fs.existsSync(path.dirname(queue)), false);
    assert.equal(fs.existsSync(path.join(project.root, 'artifacts')), false);
  }
});

test('invalid requests fail before creating either a queue or an outbox', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-reject-without-write-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const config = path.join(root, 'registry.json');
  fs.writeFileSync(config, JSON.stringify(registry));
  const queue = path.join(root, 'private-queue', 'shared.sqlite');
  const base = ['--registry', config, '--queue', queue];
  const input = path.join(root, 'feedback.json');
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'user', kind: 'user_feedback', reference: 'fixture-request' }, intent: { operationId: 'safe', kind: 'append-record', target: 'not-registered', record: { recordId: 'safe', title: 'Local', properties: {} } } }));
  for (const args of [
    ['record', ...base, '--project', 'unknown', '--input', input],
    ['record', ...base, '--project', 'fitness-app'],
    ['record', ...base, '--project', 'fitness-app', '--input', input],
    ['preview', ...base, '--project', 'fitness-app', '--operation', 'absent']
  ]) {
    await assert.rejects(main(args));
    assert.equal(fs.existsSync(path.dirname(queue)), false, args.join(' '));
    assert.equal(fs.existsSync(path.join(root, 'artifacts')), false, args.join(' '));
  }
});
