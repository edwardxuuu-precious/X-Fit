#!/usr/bin/env node
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadRegistry, resolveRoute, validateRegistry, RouteError } from './notion-coordination/router.mjs';
import { OperationQueue } from './notion-coordination/queue.mjs';
import { CoordinationEngine, inspectFeedbackInput, readSavedIntent } from './notion-coordination/engine.mjs';
import { createRuntime } from './notion-coordination/runtime.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const defaultRegistry = path.join(root, 'docs/operations/notion-coordination/registry.json');
const defaultQueue = path.join(os.homedir(), '.codex/coordination/notion-projects.sqlite');
const usage = { commands: ['status', 'resolve', 'record', 'preview', 'doctor', 'apply', 'reconcile'], examples: ['node scripts/notion-coordinate.mjs status', 'node scripts/notion-coordinate.mjs resolve --project fitness-app', 'node scripts/notion-coordinate.mjs record --project fitness-app --input <project-local-json>', 'node scripts/notion-coordinate.mjs doctor --project fitness-app', 'node scripts/notion-coordinate.mjs preview --project fitness-app --operation <stable-id>', 'node scripts/notion-coordinate.mjs apply --project <id> --operation <stable-id> --mode <fixture-or-live> --access <project-private-json> --owner <session-id> --approval <exact-preview-digest>', 'node scripts/notion-coordinate.mjs reconcile --project <id> --operation <same-id> --mode <fixture-or-live> --access <project-private-json>'], defaultMode: 'offline', onlineAccess: 'disabled_by_default_requires_fixed_authorization', credentials: 'never_cli_arguments', queue: 'host_local_cooperative_metadata_only', verification: 'local_software_does_not_prove_live_access_or_human_acceptance' };
const flags = {
  status: ['--registry', '--queue'],
  resolve: ['--registry', '--project', '--root', '--subproject', '--target'],
  record: ['--registry', '--project', '--input', '--queue'],
  doctor: ['--registry', '--project', '--target', '--queue', '--mode', '--access'],
  preview: ['--registry', '--project', '--operation', '--queue', '--mode', '--access'],
  apply: ['--registry', '--project', '--operation', '--queue', '--mode', '--access', '--owner', '--approval'],
  reconcile: ['--registry', '--project', '--operation', '--queue', '--mode', '--access']
};

export async function main(argv) {
  const [command, ...args] = argv;
  if (!command || command === 'help') return usage;
  if (!usage.commands.includes(command)) throw new RouteError('COMMAND_NOT_ENABLED');
  const options = {};
  while (args.length) {
    const flag = args.shift();
    if (!flags[command].includes(flag) || !args.length || Object.hasOwn(options, flag)) throw new RouteError('INVALID_ARGUMENT');
    const value = args.shift();
    if (value.startsWith('--')) throw new RouteError('INVALID_ARGUMENT');
    options[flag] = value;
  }
  const mode = options['--mode'] ?? 'offline';
  if (!['offline', 'fixture', 'live'].includes(mode)) throw new RouteError('INVALID_MODE');
  if (mode === 'offline' && options['--access']) throw new RouteError('ACCESS_FORBIDDEN_IN_OFFLINE');
  const registry = loadRegistry(options['--registry'] ?? defaultRegistry);
  if (command === 'resolve') return resolveRoute(registry, {
    ...(options['--project'] ? { projectId: options['--project'] } : {}),
    ...(options['--root'] ? { projectRoot: path.resolve(options['--root']) } : {}),
    ...(options['--subproject'] ? { subprojectId: options['--subproject'] } : {}),
    ...(options['--target'] ? { target: options['--target'] } : {})
  });
  if (command === 'status') {
    const report = { ...validateRegistry(registry), implementation: 'explicit_access_software_default_offline', defaultMode: 'offline', defaultLiveAccess: false, softwareAccessCommandsAvailable: true, liveAccessEnabled: false, liveAccessEnabledMeaning: 'this_status_invocation_not_profile_authorization', credentialReadPerformed: false, queueCoverage: 'adopted_calls_on_this_host_only', routes: registry.routes.map(route => {
      const resolved = resolveRoute(registry, { projectId: route.projectId });
      return { projectId: route.projectId, workspaceId: route.workspaceId, profileId: route.profileId, liveRead: route.liveRead, liveWrite: route.liveWrite, accessStatus: resolved.accessStatus, gateReasons: resolved.gateReasons };
    }) };
    if (options['--queue']) {
      const queue = new OperationQueue(path.resolve(options['--queue']));
      try { report.operations = queue.list(); } finally { queue.close(); }
    }
    return report;
  }
  if (!options['--project']) throw new RouteError('PROJECT_REQUIRED');
  if (command === 'doctor') {
    const route = resolveRoute(registry, { projectId: options['--project'], ...(options['--target'] ? { target: options['--target'] } : {}) });
    if (mode === 'offline') return { status: 'blocked_access', mode, projectId: route.projectId, target: route.targetAlias, gateReasons: [...new Set([...route.gateReasons, 'EXPLICIT_ACCESS_REQUIRED'])], credentialReadPerformed: false, remoteCalls: 0, permissionsActivated: false, writes: 0 };
    const runtime = createRuntime({ route, mode, accessFile: options['--access'], command });
    const { inspectConnection } = await import('./notion-coordination/doctor.mjs');
    const report = await inspectConnection({ route, client: runtime.clientFactory(route, { readOnly: true }) });
    return { ...report, mode, httpRequests: runtime.remoteCalls, productionCredentialReadPerformed: runtime.productionCredentialReadPerformed, remoteCalls: mode === 'live' ? runtime.remoteCalls : 0, verificationScope: mode === 'fixture' ? 'fixture_only_not_live' : 'fixed_profile_read_only_observation_not_write_grant' };
  }
  // Validate all inputs and access gates before opening a mutable queue/outbox.
  let route, saved, runtime = null;
  if (command === 'record') {
    if (!options['--input']) throw new RouteError('INPUT_REQUIRED');
    ({ route } = inspectFeedbackInput(registry, { projectId: options['--project'], inputFile: options['--input'] }));
  } else {
    if (!options['--operation']) throw new RouteError('OPERATION_REQUIRED');
    saved = readSavedIntent(registry, { projectId: options['--project'], operationId: options['--operation'] });
    route = resolveRoute(registry, { projectId: options['--project'], target: saved.intent.target });
    if (command === 'apply' && (!options['--owner'] || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(options['--owner']))) throw new RouteError('OWNER_REQUIRED');
    if (command === 'apply' && !/^[a-f0-9]{64}$/.test(options['--approval'] ?? '')) throw new RouteError('PREVIEW_APPROVAL_REQUIRED');
    if (mode === 'offline' && command !== 'preview') throw new RouteError('LIVE_ACCESS_NOT_ENABLED');
    if (mode !== 'offline') runtime = createRuntime({ route, mode, accessFile: options['--access'], command, saved, approval: options['--approval'] });
  }
  const queueFile = path.resolve(options['--queue'] ?? defaultQueue);
  if (command !== 'record' && !fs.existsSync(queueFile)) throw new RouteError('QUEUE_UNAVAILABLE');
  const queue = new OperationQueue(queueFile);
  try {
    const engine = new CoordinationEngine({ registry, queue, mode, ...(runtime ? { clientFactory: runtime.clientFactory, authorization: runtime.authorization } : {}) });
    if (command === 'record') {
      return engine.save({ projectId: options['--project'], inputFile: options['--input'] });
    }
    if (command === 'apply') return await engine.apply(options['--project'], options['--operation'], { owner: options['--owner'], approval: options['--approval'], authorization: runtime.executionGrant });
    if (command === 'reconcile') return await engine.reconcile(options['--project'], options['--operation']);
    return await engine.preview(options['--project'], options['--operation']);
  } finally { queue.close(); }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(report => {
    process.stdout.write(JSON.stringify(report, null, 2) + '\n');
    if (['blocked_access', 'conflict', 'result_unknown'].includes(report.status)) process.exitCode = 2;
  }).catch(error => {
    const code = typeof error.code === 'string' && /^[A-Z][A-Z0-9_]{0,95}$/.test(error.code) ? error.code : 'LOCAL_INPUT_ERROR';
    process.stderr.write(JSON.stringify({ status: 'blocked', error: code }) + '\n');
    process.exitCode = 2;
  });
}
