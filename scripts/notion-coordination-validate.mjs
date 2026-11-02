#!/usr/bin/env node
/** Finite local-only verification. Localhost fixtures only; no live credentials/requests. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { loadRegistry, resolveRoute } from './notion-coordination/router.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const output = path.join(root, 'outputs/test-results/NGC-R1-local/validation.json');
const protectedSources = {
  'docs/operations/cycle-20260927.json': '668e343282110327dda2520ab895eba3911994e5ec299b1b36383517e7dd2521',
  'docs/training/notion-sync-state.json': '3e0ffc57baece708e5c07e95268c8e194324addb88ccf34bc73d0aaed4254415',
  'docs/training/archive-records.json': '53cea09760547f0dcd32979238a7c427e441dde0f03abab26e70b81e5d97ec7e',
  'scripts/xfit-project-loop.py': 'c581f6d705ee122b395f3e3bac76e2d8875d2980a01c7462ab0082fa1584c598',
  'scripts/xfit-training-archive.py': '39d8dbb4c52f035317e43a5aea3b864519dcc3304696118fee15fbb8d86abe5b',
  'scripts/xfit-notion-access.py': 'af73812c3d71abf464dc9f2f4c2c20ac6878e9ce260b472061d1a2db050703e7'
};
const reuseRoot = '/Users/edward/.codex/worktrees/notion-workspace-routing/体育组队';
const reuseSources = {
  'scripts/notion-sync.js': '0fba96171fc8fb0bbd7f15e993bb81d559fa676ce2947bf6a8fce0307d68bf6a',
  'tests/notion-sync.test.js': '33f41c333fa3c784d5a905b1121e43a43eb160b9eeb0ea16eb27408586de44eb'
};
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const fileHash = file => hash(fs.readFileSync(file));
const report = { schemaVersion: 1, requirementId: 'REQ-20261007-102225', incrementRequirementId: 'REQ-20261007-194550', scope: 'local_and_external_fixtures_only_not_live_notion_or_app_release', observedAt: new Date().toISOString(), runtime: process.version, steps: [], sourceVersions: [], verificationLayers: { L0: 'NOT_RUN', L1: 'NOT_RUN', L2: 'NOT_RUN', L3: 'BLOCKED_ENV', L4: 'NOT_RUN', L5: 'NOT_RUN' }, excludedActions: { productionCredentialReads: 0, realNotionRequests: 0, sharedAuthenticationChanges: 0, phoneActions: 0, globalInstallation: 0 }, productionGates: { fixedProfileOwnerAuthorization: 'UNVERIFIED', exactBotAndOwnedScope: 'UNVERIFIED', specificOnlineIntentGrant: 'NOT_RUN', humanAdoption: 'NOT_RUN', noImplicitActivation: true } };
const steps = report.steps;

function guard(base, sources) {
  return Object.entries(sources).map(([file, expected]) => {
    let actual = null;
    try { actual = fileHash(path.join(base, file)); } catch { /* Missing stays null. */ }
    return { sourceRef: path.join(base, file), expected, actual, status: actual === expected ? 'PASS' : 'FAIL' };
  });
}
function run(name, executable, args, cwd = root, kind = 'node') {
  const child = spawnSync(executable, args, { cwd, encoding: 'utf8', timeout: 60_000, maxBuffer: 4_000_000 });
  const text = `${child.stdout ?? ''}\n${child.stderr ?? ''}`;
  const result = { name, command: [executable, ...args], cwd, status: child.status === 0 ? 'PASS' : 'FAIL', exitCode: child.status, outputSha256: hash(text) };
  if (child.error) result.error = 'LOCAL_PROCESS_FAILED';
  if (kind === 'node') {
    for (const [key, field] of [['tests', 'tests'], ['pass', 'passed'], ['fail', 'failed'], ['cancelled', 'cancelled'], ['skipped', 'skipped']]) {
      const found = text.match(new RegExp(`^# ${key} (\\d+)$`, 'm'));
      if (found) result[field] = Number(found[1]);
    }
    if (args.includes('--test') && (!result.tests || result.passed !== result.tests || result.failed !== 0 || result.cancelled !== 0 || result.skipped !== 0)) result.status = 'FAIL';
  } else if (kind === 'python') {
    const found = text.match(/Ran (\d+) tests/);
    result.tests = found ? Number(found[1]) : 0;
    result.passed = result.status === 'PASS' && /\nOK\s*$/.test(text) ? result.tests : 0;
    if (!result.tests || result.passed !== result.tests || /skipped=/.test(text)) result.status = 'FAIL';
  }
  steps.push(result);
  process.stdout.write(`${result.name}: ${result.status}${result.tests ? ` (${result.passed}/${result.tests})` : ''}\n`);
  return result;
}
function structure() {
  const registry = loadRegistry(path.join(root, 'docs/operations/notion-coordination/registry.json'));
  const routes = registry.routes.map(route => {
    const resolved = resolveRoute(registry, { projectId: route.projectId });
    if (resolved.remoteCalls !== 0 || route.liveRead || route.liveWrite) throw new Error('LIVE_GATE_UNEXPECTED');
    return { projectId: route.projectId, workspaceId: route.workspaceId, accessStatus: resolved.accessStatus, gateReasons: resolved.gateReasons };
  });
  const plan = JSON.parse(fs.readFileSync(path.join(root, 'outputs/planning/notion-global-coordination-r1.tasks.json'), 'utf8'));
  const byId = new Map(plan.tasks.map(task => [task.id, task]));
  if (plan.tasks.length !== 11 || byId.size !== 11 || !plan.convergence.task_set_frozen || plan.scheduling_basis !== 'dependencies_evidence_and_authorization_not_calendar') throw new Error('TASK_SCOPE_CHANGED');
  const visiting = new Set(), visited = new Set();
  function visit(id) {
    if (visiting.has(id) || !byId.has(id)) throw new Error('INVALID_DEPENDENCY');
    if (visited.has(id)) return;
    visiting.add(id);
    const task = byId.get(id);
    if (!task.exit || !['done', 'pending', 'blocked'].includes(task.status)) throw new Error('TASK_WITHOUT_EXIT');
    task.depends_on.forEach(visit); visiting.delete(id); visited.add(id);
  }
  plan.tasks.forEach(task => visit(task.id));
  const ready = plan.tasks.filter(task => task.status === 'pending' && task.gates.length === 0 && task.depends_on.every(id => byId.get(id).status === 'done')).map(task => task.id);
  const dependencyEdges = plan.tasks.reduce((count, task) => count + task.depends_on.length, 0);
  if (dependencyEdges !== 15) throw new Error('TASK_SCOPE_CHANGED');
  const texts = ['docs/requirements/2026-10-07/102225_notion-global-coordination.md', 'docs/requirements/2026-10-07/194550_notion-coordination-connection.md', 'docs/operations/notion-coordination/README.md', 'outputs/planning/notion-global-coordination-r1.md'];
  let localLinks = 0;
  for (const file of texts) {
    const content = fs.readFileSync(path.join(root, file), 'utf8');
    for (const match of content.matchAll(/\]\((<[^>]+>|[^)]+)\)/g)) {
      const target = match[1].replace(/^<|>$/g, '');
      if (/^[a-z]+:\/\//i.test(target) || target.startsWith('#')) continue;
      const local = target.split('#')[0].replace(/:\d+$/, '');
      const resolved = path.resolve(root, path.dirname(file), local);
      // The current report is published at the end of this same invocation.
      if (!local || !fs.existsSync(resolved) && resolved !== output) throw new Error('MISSING_LOCAL_LINK');
      localLinks++;
    }
  }
  return { name: 'contract_registry_dependency_graph_and_links', status: 'PASS', taskCount: 11, dependencyEdges, acyclic: true, ready, localLinks, routes };
}
function publish(value) {
  let cursor = root;
  for (const segment of ['outputs', 'test-results', 'NGC-R1-local']) {
    cursor = path.join(cursor, segment);
    try { fs.mkdirSync(cursor); } catch (error) { if (error.code !== 'EEXIST') throw error; }
    const stat = fs.lstatSync(cursor);
    if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error('UNSAFE_REPORT_DIRECTORY');
  }
  if (fs.existsSync(output) && (!fs.lstatSync(output).isFile() || fs.lstatSync(output).isSymbolicLink())) throw new Error('UNSAFE_REPORT_FILE');
  const temporary = `${output}.pending.${crypto.randomUUID()}`;
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  fs.renameSync(temporary, output);
}

try {
  report.protectedBefore = guard(root, protectedSources);
  report.reuseBefore = guard(reuseRoot, reuseSources);
  try { steps.push(structure()); }
  catch { steps.push({ name: 'contract_registry_dependency_graph_and_links', status: 'FAIL' }); }
  const modules = ['scripts/notion-coordinate.mjs', 'scripts/notion-coordination-validate.mjs', ...fs.readdirSync(path.join(root, 'scripts/notion-coordination')).filter(file => file.endsWith('.mjs')).map(file => `scripts/notion-coordination/${file}`), ...fs.readdirSync(path.join(root, 'tests/notion-coordination')).filter(file => file.endsWith('.mjs')).map(file => `tests/notion-coordination/${file}`)];
  const tests = modules.filter(file => file.startsWith('tests/') && file.endsWith('.test.mjs'));
  const documents = ['docs/operations/notion-coordination/registry.json', 'docs/operations/notion-coordination/README.md', 'docs/requirements/2026-10-07/102225_notion-global-coordination.md', 'docs/requirements/2026-10-07/194550_notion-coordination-connection.md', 'outputs/planning/notion-global-coordination-r1.tasks.json', 'outputs/planning/notion-global-coordination-r1.md'];
  const whitespaceFailures = [...modules, ...documents].filter(file => {
    const content = fs.readFileSync(path.join(root, file), 'utf8');
    return !content.endsWith('\n') || content.split('\n').some(line => /[\t ]+$/.test(line) || /^(?:<<<<<<< |=======|>>>>>>> )/.test(line));
  });
  steps.push({ name: 'owned_new_file_whitespace_and_conflict_markers', status: whitespaceFailures.length ? 'FAIL' : 'PASS', files: modules.length + documents.length, failures: whitespaceFailures });
  for (const file of modules) run(`syntax:${file}`, process.execPath, ['--check', file]);
  const regression = run('new_global_local_contract', process.execPath, ['--test', '--test-reporter=tap', ...tests]);
  // Three finite additional cold-start batches, not an unattended retry loop.
  const repetitions = Array.from({ length: 3 }, (_, i) => run(`public_cli_concurrency_probe_${i + 1}`, process.execPath, ['--test', '--test-reporter=tap', '--test-name-pattern=concurrent', 'tests/notion-coordination/cli.test.mjs']));
  const legacyXfit = run('existing_xfit_tool_regression', 'python3', ['-B', '-m', 'unittest', 'discover', '-s', 'scripts/tests', '-p', 'test_*.py'], root, 'python');
  if (report.reuseBefore.every(item => item.status === 'PASS')) run('existing_fixed_sync_fixture_regression', process.execPath, ['--test', '--test-reporter=tap', 'tests/notion-sync.test.js'], reuseRoot);
  else steps.push({ name: 'existing_fixed_sync_fixture_regression', status: 'BLOCKED_ENV', reason: 'REUSE_SOURCE_CHANGED' });
  report.protectedAfter = guard(root, protectedSources);
  report.reuseAfter = guard(reuseRoot, reuseSources);
  report.protectedConservation = [...report.protectedBefore, ...report.protectedAfter].every(item => item.status === 'PASS') ? 'PASS' : 'FAIL';
  report.reuseConservation = [...report.reuseBefore, ...report.reuseAfter].every(item => item.status === 'PASS') ? 'PASS' : 'FAIL';
  const versioned = [...modules, ...documents];
  report.sourceVersions = versioned.map(file => ({ sourceRef: path.join(root, file), sha256: fileHash(path.join(root, file)) }));
  report.verificationLayers.L0 = steps.filter(step => step.name.startsWith('syntax:') || ['contract_registry_dependency_graph_and_links', 'owned_new_file_whitespace_and_conflict_markers'].includes(step.name)).every(step => step.status === 'PASS') ? 'PASS' : 'FAIL';
  report.verificationLayers.L1 = regression.status === 'PASS' && legacyXfit.status === 'PASS' && steps.find(step => step.name === 'existing_fixed_sync_fixture_regression')?.status === 'PASS' ? 'PASS' : 'FAIL';
  report.verificationLayers.L2 = regression.status === 'PASS' && repetitions.every(step => step.status === 'PASS') ? 'PASS' : 'FAIL';
  report.status = steps.every(step => step.status === 'PASS') && report.protectedConservation === 'PASS' && report.reuseConservation === 'PASS' ? 'PASS' : 'FAIL';
  const groups = {
    'I-01': ['cli.test.mjs', 'connection-cli.test.mjs', 'runtime.test.mjs'],
    'I-02': ['transport.test.mjs', 'profiles.test.mjs', 'runtime.test.mjs'],
    'I-03': ['doctor.test.mjs', 'connection-cli.test.mjs'],
    'I-04': ['execution.test.mjs', 'engine.test.mjs', 'runtime.test.mjs', 'connection-cli.test.mjs'],
    'I-05': ['connection-cli.test.mjs', 'queue.test.mjs', 'engine.test.mjs'],
    'I-06': ['execution.test.mjs', 'engine.test.mjs', 'connection-cli.test.mjs'],
    'I-07': ['connection-cli.test.mjs', 'cli.test.mjs'],
    'I-08': ['all_owned_tests_and_legacy_regressions']
  };
  report.incrementAcceptance = Object.entries(groups).map(([id, testGroups]) => ({ id, status: report.status === 'PASS' && testGroups.every(group => group === 'all_owned_tests_and_legacy_regressions' || tests.some(file => path.basename(file) === group)) ? 'PASS' : 'FAIL', testGroups, scope: 'local_only_not_live_or_human_acceptance' }));
} catch {
  report.status = 'FAIL'; report.error = 'LOCAL_VALIDATION_FAILED';
}
publish(report);
process.stdout.write(`overall: ${report.status}; evidence: ${output}\n`);
if (report.status !== 'PASS') process.exitCode = 1;
