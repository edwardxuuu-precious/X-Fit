import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { loadRegistry } from '../../scripts/notion-coordination/router.mjs';
import { OperationQueue } from '../../scripts/notion-coordination/queue.mjs';

const cli = fileURLToPath(new URL('../../scripts/notion-coordinate.mjs', import.meta.url));
test('the public CLI resolves both workspace routes without enabling online calls', () => {
  for (const [project, workspace] of [['fitness-app', 'c63f367d-6f39-41c0-9a28-e4ad2ce10251'], ['football', '84ec1ddd-3200-8110-ae91-000338974a99']]) {
    const result = spawnSync(process.execPath, [cli, 'resolve', '--project', project], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.equal(report.workspaceId, workspace);
    assert.equal(report.remoteCalls, 0);
    assert.equal(report.accessStatus, 'blocked_access');
  }
});

test('the public CLI rejects auth switching, secrets, live writes and ambiguous project selection', () => {
  for (const args of [['apply', '--project', 'fitness-app'], ['resolve', '--project', 'fitness-app', '--token', 'fixture-only'], ['resolve', '--project', 'fitness-app', '--live'], ['resolve', '--root', '/Users/edward/Desktop/Benemarketing']]) {
    const result = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    assert.equal(result.status, 2);
    assert.equal(JSON.parse(result.stderr).status, 'blocked');
    assert.doesNotMatch(result.stderr, /fixture-only/);
    assert.equal(result.stdout, '');
  }
  const report = spawnSync(process.execPath, [cli, 'status'], { encoding: 'utf8' });
  assert.equal(report.status, 0, report.stderr);
  assert.equal(JSON.parse(report.stdout).credentialReadPerformed, false);
  assert.equal(JSON.parse(report.stdout).liveAccessEnabled, false);
  assert.equal(JSON.parse(report.stdout).routes.length, 6);
});

test('a local-only CLI roundtrip preserves feedback and repeat count while reporting its exact access gate', t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-cli-offline-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const config = path.join(root, 'registry.json'); fs.writeFileSync(config, JSON.stringify(registry));
  const queue = path.join(root, 'private-queue', 'global.sqlite');
  const input = path.join(root, 'feedback.json');
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'fixture-request' }, intent: { operationId: 'offline', kind: 'append-record', target: 'archive', record: { recordId: 'offline-record', title: 'Fixture only', body: 'private feedback stays local', properties: {} } } }));
  const base = ['--registry', config, '--project', 'fitness-app', '--queue', queue];
  const first = spawnSync(process.execPath, [cli, 'record', ...base, '--input', input], { encoding: 'utf8' });
  const again = spawnSync(process.execPath, [cli, 'record', ...base, '--input', input], { encoding: 'utf8' });
  assert.equal(first.status, 0, first.stderr); assert.equal(again.status, 0, again.stderr);
  assert.equal(JSON.parse(first.stdout).privateRef, JSON.parse(again.stdout).privateRef);
  const preview = spawnSync(process.execPath, [cli, 'preview', ...base, '--operation', 'offline'], { encoding: 'utf8' });
  assert.equal(preview.status, 2, preview.stderr);
  assert.equal(JSON.parse(preview.stdout).status, 'blocked_access');
  assert.equal(JSON.parse(preview.stdout).remoteCalls, 0);
  const status = spawnSync(process.execPath, [cli, 'status', '--registry', config, '--queue', queue], { encoding: 'utf8' });
  const operations = JSON.parse(status.stdout).operations;
  assert.equal(operations.length, 1); assert.equal(operations[0].status, 'blocked_access');
  assert.doesNotMatch(JSON.stringify(operations), /private feedback stays local/);
  assert.equal(JSON.parse(fs.readFileSync(JSON.parse(first.stdout).privateRef, 'utf8')).intent.record.body, 'private feedback stays local');
});

test('concurrent cold-start callers retain all distinct local requests in the same queue', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-cli-cold-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const config = path.join(root, 'registry.json'); fs.writeFileSync(config, JSON.stringify(registry));
  const queue = path.join(root, 'private-queue', 'global.sqlite');
  const inputs = Array.from({ length: 4 }, (_, index) => {
    const file = path.join(root, `feedback-${index}.json`);
    fs.writeFileSync(file, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'fixture-request' }, intent: { operationId: `cold-${index}`, kind: 'append-record', target: 'archive', record: { recordId: `cold-record-${index}`, title: 'Fixture only', body: `private-${index}`, properties: {} } } }));
    return file;
  });
  const results = await Promise.all(inputs.map(file => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, 'record', '--registry', config, '--project', 'fitness-app', '--input', file, '--queue', queue]);
    let stdout = '', stderr = ''; child.stdout.on('data', value => { stdout += value; }); child.stderr.on('data', value => { stderr += value; });
    child.on('error', reject); child.on('close', status => resolve({ status, stdout, stderr }));
  })));
  assert.deepEqual(results.map(result => result.status), [0, 0, 0, 0], JSON.stringify(results));
  const status = spawnSync(process.execPath, [cli, 'status', '--registry', config, '--queue', queue], { encoding: 'utf8' });
  assert.equal(status.status, 0, status.stderr);
  assert.equal(JSON.parse(status.stdout).operations.length, 4);
});

test('concurrent identical submissions publish one complete private record and one queue intent', async t => {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'ngc-cli-idempotent-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const registry = loadRegistry(new URL('../../docs/operations/notion-coordination/registry.json', import.meta.url));
  registry.routes[0].projectRoot = root; registry.routes[0].sourceBindings = [];
  const config = path.join(root, 'registry.json'); fs.writeFileSync(config, JSON.stringify(registry));
  const queue = path.join(root, 'private-queue', 'global.sqlite');
  // Open via the public queue seam first to isolate private-record publication.
  new OperationQueue(queue).close();
  const input = path.join(root, 'feedback.json');
  const body = 'private-fixture-'.repeat(12000);
  fs.writeFileSync(input, JSON.stringify({ source: { author: 'fixture-user', kind: 'user_feedback', reference: 'fixture-request' }, intent: { operationId: 'identical', kind: 'append-record', target: 'archive', record: { recordId: 'identical-record', title: 'Fixture only', body, properties: {} } } }));
  const results = await Promise.all(Array.from({ length: 8 }, () => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, 'record', '--registry', config, '--project', 'fitness-app', '--input', input, '--queue', queue]);
    let stdout = '', stderr = ''; child.stdout.on('data', value => { stdout += value; }); child.stderr.on('data', value => { stderr += value; });
    child.on('error', reject); child.on('close', status => resolve({ status, stdout, stderr }));
  })));
  assert.deepEqual(results.map(result => result.status), Array(8).fill(0), JSON.stringify(results));
  const outputs = results.map(result => JSON.parse(result.stdout));
  assert.equal(new Set(outputs.map(result => result.privateRef)).size, 1);
  const stored = JSON.parse(fs.readFileSync(outputs[0].privateRef, 'utf8'));
  assert.equal(stored.intent.record.body, body);
  assert.equal(fs.readdirSync(path.dirname(outputs[0].privateRef)).length, 1);
  const observer = new OperationQueue(queue); t.after(() => observer.close());
  assert.equal(observer.list().length, 1);
});
