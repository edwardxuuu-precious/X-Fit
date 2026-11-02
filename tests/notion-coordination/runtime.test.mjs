import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadRegistry, resolveRoute } from '../../scripts/notion-coordination/router.mjs';

function setup(t) {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-runtime-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const route = resolveRoute(registry, { projectId: 'fitness-app' });
  return { root, route };
}

test('runtime refuses mismatched access modes before creating a client or reading a credential', async t => {
  const { root, route } = setup(t);
  const accessFile = path.join(root, 'access.json');
  fs.writeFileSync(accessFile, JSON.stringify({ schemaVersion: 1, mode: 'live', grant: { mode: 'live' } }), { mode: 0o600 });
  const { createRuntime } = await import('../../scripts/notion-coordination/runtime.mjs');
  assert.throws(() => createRuntime({ route, mode: 'fixture', accessFile, command: 'doctor' }), { code: 'ACCESS_MODE_MISMATCH' });
  assert.equal(fs.existsSync(path.join(root, 'artifacts')), false);
});

test('a runtime access file must be project-local, private, regular and contain no credential', async t => {
  const { root, route } = setup(t);
  const { createRuntime } = await import('../../scripts/notion-coordination/runtime.mjs');
  const accessFile = path.join(root, 'access.json');
  const payload = { schemaVersion: 1, mode: 'fixture', grant: { mode: 'fixture' } };
  fs.writeFileSync(accessFile, JSON.stringify(payload), { mode: 0o644 });
  assert.throws(() => createRuntime({ route, mode: 'fixture', accessFile }), { code: 'ACCESS_NOT_PRIVATE' });
  fs.chmodSync(accessFile, 0o600);
  fs.symlinkSync(accessFile, path.join(root, 'link.json'));
  assert.throws(() => createRuntime({ route, mode: 'fixture', accessFile: path.join(root, 'link.json') }), { code: 'SOURCE_SYMLINK_REFUSED' });
  assert.throws(() => createRuntime({ route, mode: 'fixture', accessFile: path.join(root, '..', 'outside.json') }), { code: 'SOURCE_OUTSIDE_PROJECT' });
  fs.writeFileSync(accessFile, JSON.stringify({ ...payload, token: 'fixture-secret-never-output' }));
  assert.throws(() => createRuntime({ route, mode: 'fixture', accessFile }), error => {
    assert.equal(error.code, 'CREDENTIAL_CONTENT_REFUSED');
    assert.doesNotMatch(error.message, /fixture-secret/);
    return true;
  });
  fs.writeFileSync(accessFile, JSON.stringify({ ...payload, executable: '/bin/echo' }));
  assert.throws(() => createRuntime({ route, mode: 'fixture', accessFile }), { code: 'ACCESS_INVALID' });
  assert.equal(fs.existsSync(path.join(root, 'artifacts')), false);
});

test('runtime constructs only a narrow read client and rejects unverified live flags before credentials', async t => {
  const { root, route } = setup(t);
  route.profile.botId = 'a1111111-1111-4111-8111-111111111111';
  route.profile.authorizationStatus = 'verified';
  route.gateReasons = [];
  const grant = { mode: 'fixture', reference: 'fixture-local-only', profileId: route.profileId, workspaceId: route.workspaceId, read: true, write: true, scopeTargets: [route.target.id] };
  const accessFile = path.join(root, 'access.json');
  fs.writeFileSync(accessFile, JSON.stringify({ schemaVersion: 1, mode: 'fixture', fixtureOrigin: 'http://127.0.0.1:12345', grant }), { mode: 0o600 });
  const { createRuntime } = await import('../../scripts/notion-coordination/runtime.mjs');
  const runtime = createRuntime({ route, mode: 'fixture', accessFile, command: 'doctor' });
  assert.equal(typeof runtime.clientFactory, 'function');
  assert.equal(runtime.authorization.write, false);
  assert.equal(runtime.productionCredentialReadPerformed, false);
  for (const mutation of [
    value => { value.grant.scopeTargets.push('b2222222-2222-4222-8222-222222222222'); },
    value => { value.grant.mode = 'live'; },
    value => { value.fixtureOrigin = 'https://api.notion.com'; }
  ]) {
    const value = { schemaVersion: 1, mode: 'fixture', fixtureOrigin: 'http://127.0.0.1:12345', grant: structuredClone(grant) };
    mutation(value); fs.writeFileSync(accessFile, JSON.stringify(value));
    assert.throws(() => createRuntime({ route, mode: 'fixture', accessFile, command: 'doctor' }));
  }
  fs.writeFileSync(accessFile, JSON.stringify({ schemaVersion: 1, mode: 'live', grant: { ...grant, mode: 'live' } }));
  assert.throws(() => createRuntime({ route, mode: 'live', accessFile, command: 'doctor' }), { code: 'LIVE_READ_NOT_GRANTED' });
});
