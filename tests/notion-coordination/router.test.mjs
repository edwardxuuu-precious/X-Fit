import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadRegistry, resolveRoute, validateRegistry } from '../../scripts/notion-coordination/router.mjs';

test('X-Fit routes to Edward and football to PrimeViz without selecting shared OAuth', () => {
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  const xfit = resolveRoute(registry, { projectId: 'fitness-app', target: 'archive' });
  const football = resolveRoute(registry, { projectId: 'football', target: 'features' });
  assert.equal(xfit.workspaceId, 'c63f367d-6f39-41c0-9a28-e4ad2ce10251');
  assert.equal(football.workspaceId, '84ec1ddd-3200-8110-ae91-000338974a99');
  assert.equal(xfit.remoteCalls + football.remoteCalls, 0);
  assert.equal(xfit.accessStatus, 'blocked_access');
  assert.equal(football.accessStatus, 'blocked_access');
  assert.ok(xfit.gateReasons.includes('BOT_UNVERIFIED'));
  assert.equal(validateRegistry(registry).routes, 6);
});

test('a changed source binding invalidates the previous route version', t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-route-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, 'binding.json');
  fs.writeFileSync(source, '{"revision":1}');
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root;
  registry.routes[0].sourceBindings = [source];
  const first = resolveRoute(registry, { projectId: 'fitness-app' });
  fs.writeFileSync(source, '{"revision":2}');
  const second = resolveRoute(registry, { projectId: 'fitness-app' });
  assert.notEqual(first.routeDigest, second.routeDigest);
});

test('a shared Bene root requires an explicit business project instead of guessing a destination', t => {
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-shared-root-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  registry.routes.filter(route => route.projectRoot === '/Users/edward/Desktop/Benemarketing')
    .forEach(route => { route.projectRoot = root; });
  assert.throws(() => resolveRoute(registry, { projectRoot: root }), error => error.code === 'PROJECT_AMBIGUOUS');
  assert.equal(resolveRoute(registry, { projectRoot: root, subprojectId: 'glimmer-ad-strategy-v1' }).projectId, 'glimmer-ad-strategy');
});

test('unknown project and target cannot resolve by title, directory prefix, or another workspace fallback', () => {
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  assert.throws(() => resolveRoute(registry, { projectId: 'not-registered' }), error => error.code === 'PROJECT_NOT_REGISTERED');
  assert.throws(() => resolveRoute(registry, { projectId: 'fitness-app', target: 'new-private-parent' }), error => error.code === 'TARGET_NOT_REGISTERED');
  const unknown = resolveRoute(registry, { projectId: 'greendeagle' });
  assert.equal(unknown.workspaceId, null);
  assert.ok(unknown.gateReasons.includes('WORKSPACE_UNBOUND'));
  assert.ok(unknown.gateReasons.includes('AUTHORITY_UNCONFIRMED'));
});

test('invalid registry identity, unsafe credential reference and human-owned field overlap fail closed', () => {
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  const duplicate = structuredClone(registry); duplicate.routes.push(structuredClone(duplicate.routes[0]));
  assert.throws(() => validateRegistry(duplicate), error => error.code === 'DUPLICATE_PROJECT');
  const mismatch = structuredClone(registry); mismatch.routes[0].profileId = mismatch.profiles[1].id;
  assert.throws(() => validateRegistry(mismatch), error => error.code === 'PROFILE_WORKSPACE_MISMATCH');
  const unsafe = structuredClone(registry); unsafe.profiles[0].secretRef.service = 'another-project-secret';
  assert.throws(() => validateRegistry(unsafe), error => error.code === 'INVALID_SECRET_REFERENCE');
  const human = structuredClone(registry); human.routes[0].targets.archive.allowedProperties['我的备注'] = 'rich_text';
  assert.throws(() => validateRegistry(human), error => error.code === 'HUMAN_FIELD_OWNERSHIP_CONFLICT');
});

test('policy cannot silently introduce phone upload or OAuth rebinding', () => {
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.policy.sharedOAuthRebind = true;
  assert.throws(() => validateRegistry(registry), error => error.code === 'UNAPPROVED_POLICY');
});
