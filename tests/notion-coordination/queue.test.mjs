import test from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fork } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { OperationQueue, QueueError } from '../../scripts/notion-coordination/queue.mjs';

function fixture(t) {
  const directory = mkdtempSync(join(realpathSync(tmpdir()), 'notion-queue-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return { directory, dbPath: join(directory, 'queue.sqlite') };
}

function operation(directory, overrides = {}) {
  return {
    projectId: 'xfit', operationId: 'feedback-1',
    sourceRef: join(directory, 'feedback-1.json'),
    sourceDigest: 'a'.repeat(64), payloadDigest: 'b'.repeat(64),
    routeDigest: 'c'.repeat(64), targetId: 'page-1',
    profileId: 'edward-xfit', adapterId: 'append-only',
    ...overrides,
  };
}

test('saved local intent is retrievable after closing and reopening the queue', (t) => {
  const { directory, dbPath } = fixture(t);
  const input = operation(directory);
  const queue = new OperationQueue(dbPath);
  assert.equal(queue.enqueue(input).status, 'saved_local');
  queue.close();
  const restarted = new OperationQueue(dbPath);
  t.after(() => restarted.close());
  assert.deepEqual(restarted.get('xfit', 'feedback-1'), { ...input, status: 'saved_local',
    previewDigest: null, receiptRef: null, readbackDigest: null, errorCode: null });
  assert.equal(restarted.list().length, 1);
});

test('repeated intent is idempotent and operation IDs remain project scoped', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  const first = operation(directory);
  assert.deepEqual(queue.enqueue(first), queue.enqueue(first));
  queue.enqueue(operation(directory, { projectId: 'football', profileId: 'primeviz' }));
  assert.deepEqual(queue.list().map((item) => [item.projectId, item.operationId]),
    [['xfit', 'feedback-1'], ['football', 'feedback-1']]);
});

test('same scoped ID cannot replace original content or destination', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  const original = queue.enqueue(operation(directory));
  assert.throws(() => queue.enqueue(operation(directory, { payloadDigest: 'd'.repeat(64) })),
    { name: 'QueueError', code: 'ID_CONFLICT' });
  assert.throws(() => queue.enqueue(operation(directory, { targetId: 'page-other' })),
    { code: 'ID_CONFLICT' });
  assert.deepEqual(queue.get('xfit', 'feedback-1'), original);
  assert.equal(queue.list().length, 1);
});

test('preview records the exact review digest without changing the saved intent', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  queue.enqueue(operation(directory));
  const reviewed = queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
  assert.equal(reviewed.status, 'preview_ready');
  assert.equal(reviewed.previewDigest, 'd'.repeat(64));
  assert.equal(reviewed.payloadDigest, 'b'.repeat(64));
  assert.deepEqual(queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) }), reviewed);
});

test('only the earliest ready intent can claim the single writer lease', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  queue.enqueue(operation(directory, { operationId: 'unreviewed' }));
  queue.enqueue(operation(directory, { operationId: 'ready-1' }));
  queue.enqueue(operation(directory, { projectId: 'football', operationId: 'ready-2' }));
  assert.throws(() => queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'unreviewed' }),
    { code: 'NOT_READY' });
  queue.preview('xfit', 'ready-1', { previewDigest: 'd'.repeat(64) });
  queue.preview('football', 'ready-2', { previewDigest: 'e'.repeat(64) });
  assert.throws(() => queue.claim({ owner: 'worker-2', projectId: 'football', operationId: 'ready-2' }),
    { code: 'FIFO_PENDING' });
  const lease = queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'ready-1' });
  assert.equal(lease.owner, 'worker-1');
  assert.equal(lease.projectId, 'xfit');
  assert.equal(lease.operationId, 'ready-1');
  assert.match(lease.token, /^[a-f0-9-]{36}$/);
  assert.equal(queue.get('xfit', 'ready-1').status, 'executing');
  assert.throws(() => queue.claim({ owner: 'worker-2', projectId: 'football', operationId: 'ready-2' }),
    { code: 'LEASE_HELD' });
});

test('successful completion needs a receipt and readback digest before releasing the writer', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  queue.enqueue(operation(directory));
  queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
  const lease = queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'feedback-1' });
  assert.throws(() => queue.finish(lease, { status: 'readback_verified' }),
    { code: 'INVALID_ARGUMENT' });
  const completion = { status: 'readback_verified', receiptRef: join(directory, 'receipt.json'),
    readbackDigest: 'e'.repeat(64) };
  assert.equal(queue.finish(lease, completion).status, 'readback_verified');
  assert.equal(queue.get('xfit', 'feedback-1').receiptRef, completion.receiptRef);
  queue.enqueue(operation(directory, { projectId: 'football' }));
  queue.preview('football', 'feedback-1', { previewDigest: 'e'.repeat(64) });
  assert.equal(queue.claim({ owner: 'worker-2', projectId: 'football', operationId: 'feedback-1' })
    .projectId, 'football');
});

test('an active provider call keeps the writer held until the exact owner settles it', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  queue.enqueue(operation(directory));
  queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
  const lease = queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'feedback-1' });
  queue.beginCall(lease, 'write-1');
  assert.throws(() => queue.finish(lease, { status: 'result_unknown', errorCode: 'RESPONSE_LOST' }),
    { code: 'ACTIVE_CALL' });
  assert.throws(() => queue.endCall({ ...lease, owner: 'worker-2' }, 'write-1', { outcome: 'unknown' }),
    { code: 'LEASE_MISMATCH' });
  assert.throws(() => queue.beginCall(lease, 'write-1'), { code: 'CALL_ALREADY_TRACKED' });
  queue.endCall(lease, 'write-1', { outcome: 'unknown' });
  assert.equal(queue.finish(lease, { status: 'result_unknown', errorCode: 'RESPONSE_LOST' }).status,
    'result_unknown');
  assert.throws(() => queue.finish(lease, { status: 'cancelled' }), { code: 'LEASE_MISMATCH' });
});

test('a blocked project remains saved but does not hold up another workspace ready intent', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  queue.enqueue(operation(directory, { targetId: 'unresolved', profileId: 'unresolved' }));
  queue.block('xfit', 'feedback-1', { code: 'TARGET_UNBOUND' });
  queue.enqueue(operation(directory, { projectId: 'football', profileId: 'primeviz' }));
  queue.preview('football', 'feedback-1', { previewDigest: 'e'.repeat(64) });
  assert.equal(queue.get('xfit', 'feedback-1').status, 'blocked_access');
  assert.equal(queue.get('xfit', 'feedback-1').errorCode, 'TARGET_UNBOUND');
  const lease = queue.claim({ owner: 'worker-1', projectId: 'football', operationId: 'feedback-1' });
  assert.equal(lease.profileId, undefined);
  queue.finish(lease, { status: 'blocked_access', errorCode: 'ACCESS_UNAVAILABLE' });
  assert.equal(queue.get('football', 'feedback-1').status, 'blocked_access');
});

test('unknown write result cannot be previewed or claimed again and only verified readback reconciles it', (t) => {
  const { directory, dbPath } = fixture(t);
  let queue = new OperationQueue(dbPath);
  queue.enqueue(operation(directory));
  queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
  const lease = queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'feedback-1' });
  queue.beginCall(lease, 'write-1');
  queue.endCall(lease, 'write-1', { outcome: 'unknown' });
  queue.finish(lease, { status: 'result_unknown', errorCode: 'RESPONSE_LOST' });
  queue.close();
  queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  assert.equal(queue.get('xfit', 'feedback-1').status, 'result_unknown');
  assert.throws(() => queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) }),
    { code: 'INVALID_STATE' });
  assert.throws(() => queue.claim({ owner: 'worker-2', projectId: 'xfit', operationId: 'feedback-1' }),
    { code: 'NOT_READY' });
  assert.throws(() => queue.reconcile('xfit', 'feedback-1', { readbackDigest: 'e'.repeat(64) }),
    { code: 'INVALID_ARGUMENT' });
  const reconciled = queue.reconcile('xfit', 'feedback-1', {
    readbackDigest: 'e'.repeat(64), receiptRef: join(directory, 'reconciled.json') });
  assert.equal(reconciled.status, 'readback_verified');
  assert.equal(reconciled.errorCode, null);
  assert.throws(() => queue.reconcile('xfit', 'feedback-1', {
    readbackDigest: 'e'.repeat(64), receiptRef: join(directory, 'reconciled.json') }),
  { code: 'INVALID_STATE' });
});

test('an unrelated SQLite file is not adopted or changed into a queue', (t) => {
  const { dbPath } = fixture(t);
  const unrelated = new DatabaseSync(dbPath);
  unrelated.exec('CREATE TABLE unrelated (id INTEGER PRIMARY KEY); INSERT INTO unrelated VALUES(1);');
  unrelated.close();
  chmodSync(dbPath, 0o600);
  const before = readFileSync(dbPath);
  assert.throws(() => new OperationQueue(dbPath), { code: 'UNRECOGNIZED_STORAGE' });
  assert.deepEqual(readFileSync(dbPath), before);
});

test('a SQLite journal symlink is rejected before opening persistent storage', (t) => {
  const { directory, dbPath } = fixture(t);
  symlinkSync(join(directory, 'unrelated-private-file'), `${dbPath}-journal`);
  assert.throws(() => new OperationQueue(dbPath), { code: 'UNSAFE_PATH' });
});

function claimWorker(t, dbPath, owner) {
  const child = fork(fileURLToPath(new URL('./queue-worker.mjs', import.meta.url)),
    [dbPath, owner, 'xfit', 'feedback-1'], { execArgv: [], stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });
  t.after(() => { if (child.exitCode === null) child.kill(); });
  let readyResolve, readyReject, resultResolve, resultReject;
  let readySeen = false, resultSeen = false;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  const result = new Promise((resolve, reject) => { resultResolve = resolve; resultReject = reject; });
  // A startup failure can finish the test before it awaits the separate result promise.
  result.catch(() => {});
  child.on('message', (message) => {
    if (message.type === 'ready') { readySeen = true; readyResolve(); }
    if (message.type === 'result') { resultSeen = true; resultResolve(message); }
    if (message.type === 'failure') {
      readyReject(new QueueError(message.code)); resultSeen = true; resultResolve(message);
    }
  });
  child.on('error', (error) => { readyReject(error); resultReject(error); });
  child.on('exit', () => {
    if (!readySeen) readyReject(new QueueError('WORKER_EXITED'));
    if (readySeen && !resultSeen) resultReject(new QueueError('WORKER_EXITED'));
  });
  return { child, ready, result };
}

test('two independent processes cannot obtain the same writer and restart never steals a crashed lease',
  { timeout: 5000 }, async (t) => {
    const { directory, dbPath } = fixture(t);
    const queue = new OperationQueue(dbPath);
    queue.enqueue(operation(directory));
    queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
    queue.close();
    const workers = [claimWorker(t, dbPath, 'worker-1'), claimWorker(t, dbPath, 'worker-2')];
    await Promise.all(workers.map((worker) => worker.ready));
    workers.forEach((worker) => worker.child.send('claim'));
    const results = await Promise.all(workers.map((worker) => worker.result));
    assert.equal(results.filter((result) => result.lease).length, 1);
    assert.deepEqual(results.filter((result) => result.code).map((result) => result.code), ['LEASE_HELD']);
    const restarted = new OperationQueue(dbPath);
    t.after(() => restarted.close());
    assert.equal(restarted.get('xfit', 'feedback-1').status, 'executing');
    assert.throws(() => restarted.claim({ owner: 'worker-3', projectId: 'xfit', operationId: 'feedback-1' }),
      { code: 'LEASE_HELD' });
    assert.throws(() => restarted.claim({ owner: 'worker-3', projectId: 'xfit',
      operationId: 'feedback-1', force: true }), { code: 'INVALID_ARGUMENT' });
    assert.equal(restarted.finish(results.find((result) => result.lease).lease,
      { status: 'cancelled' }).status, 'cancelled');
  });

test('unsafe error text and non-metadata fields are rejected without being retained or reflected', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  const privateText = 'secret_abc123';
  assert.throws(() => queue.enqueue(operation(directory, { token: privateText })), (error) => {
    assert.ok(error instanceof QueueError);
    assert.equal(error.code, 'INVALID_ARGUMENT');
    assert.ok(!error.message.includes(privateText));
    return true;
  });
  queue.enqueue(operation(directory));
  assert.throws(() => queue.block('xfit', 'feedback-1', { code: privateText }),
    { code: 'INVALID_ARGUMENT' });
  assert.equal(queue.get('xfit', 'feedback-1').errorCode, null);
});

test('queue storage uses a private directory without changing broader ancestor permissions', (t) => {
  const { directory, dbPath } = fixture(t);
  chmodSync(directory, 0o755);
  const privateDb = join(directory, 'private', 'queue.sqlite');
  const queue = new OperationQueue(privateDb);
  queue.close();
  assert.equal(statSync(join(directory, 'private')).mode & 0o777, 0o700);
  assert.equal(statSync(privateDb).mode & 0o777, 0o600);
  assert.equal(statSync(directory).mode & 0o777, 0o755);
  assert.throws(() => new OperationQueue(dbPath), { code: 'UNSAFE_PERMISSIONS' });
  assert.equal(statSync(directory).mode & 0o777, 0o755);
});

test('opening a queue waits for a short existing SQLite writer instead of failing at startup',
  { timeout: 5000 }, async (t) => {
    const { directory, dbPath } = fixture(t);
    const queue = new OperationQueue(dbPath);
    queue.enqueue(operation(directory));
    queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
    queue.close();
    const externalWriter = new DatabaseSync(dbPath);
    externalWriter.exec('BEGIN EXCLUSIVE');
    let locked = true;
    const release = setTimeout(() => { externalWriter.exec('ROLLBACK'); locked = false; }, 200);
    t.after(() => {
      clearTimeout(release);
      if (locked) externalWriter.exec('ROLLBACK');
      externalWriter.close();
    });
    const worker = claimWorker(t, dbPath, 'worker-1');
    await worker.ready;
    worker.child.send('claim');
    assert.equal((await worker.result).lease.owner, 'worker-1');
  });

test('preview drift is an explicit persistent conflict and never changes prior content', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  queue.enqueue(operation(directory));
  queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
  const conflicted = queue.block('xfit', 'feedback-1', { code: 'SOURCE_CHANGED', status: 'conflict' });
  assert.equal(conflicted.status, 'conflict');
  assert.equal(conflicted.sourceDigest, 'a'.repeat(64));
  assert.equal(conflicted.errorCode, 'SOURCE_CHANGED');
  assert.throws(() => queue.preview('xfit', 'feedback-1', { previewDigest: 'e'.repeat(64) }),
    { code: 'INVALID_STATE' });
  assert.throws(() => queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'feedback-1' }),
    { code: 'NOT_READY' });
  assert.equal(queue.enqueue(operation(directory)).status, 'conflict');
});

test('even the exact owner cannot start parallel provider calls in one batch', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  queue.enqueue(operation(directory));
  queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
  const lease = queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'feedback-1' });
  queue.beginCall(lease, 'read-1');
  assert.throws(() => queue.beginCall(lease, 'write-1'), { code: 'ACTIVE_CALL' });
  queue.endCall(lease, 'read-1', { outcome: 'success' });
  assert.equal(queue.beginCall(lease, 'write-1').status, 'active');
  queue.endCall(lease, 'write-1', { outcome: 'unknown' });
  queue.finish(lease, { status: 'result_unknown', errorCode: 'RESPONSE_LOST' });
});

test('malformed metadata and an explicitly invalid optional state never become saved intent', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  for (const invalid of [
    { projectId: '../other' }, { sourceRef: 'https://example.invalid/private' },
    { sourceRef: join(directory, 'note.json') + '?private=value' },
    { sourceRef: 'relative/note.json' }, { sourceDigest: 'not-a-sha' },
  ]) assert.throws(() => queue.enqueue(operation(directory, invalid)), { code: 'INVALID_ARGUMENT' });
  assert.equal(queue.list().length, 0);
  queue.enqueue(operation(directory));
  assert.throws(() => queue.block('xfit', 'feedback-1', { code: 'TARGET_UNBOUND', status: null }),
    { code: 'INVALID_ARGUMENT' });
  assert.equal(queue.get('xfit', 'feedback-1').status, 'saved_local');
});

test('restart retains an active call and does not accept forged lease tokens', (t) => {
  const { directory, dbPath } = fixture(t);
  let queue = new OperationQueue(dbPath);
  queue.enqueue(operation(directory));
  queue.preview('xfit', 'feedback-1', { previewDigest: 'd'.repeat(64) });
  const lease = queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: 'feedback-1' });
  queue.beginCall(lease, 'write-1');
  queue.close();
  queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  assert.throws(() => queue.finish(lease, { status: 'cancelled' }), { code: 'ACTIVE_CALL' });
  assert.throws(() => queue.endCall({ ...lease, token: 'forged-token' }, 'write-1', { outcome: 'unknown' }),
    { code: 'LEASE_MISMATCH' });
  queue.endCall(lease, 'write-1', { outcome: 'unknown' });
  assert.deepEqual(queue.endCall(lease, 'write-1', { outcome: 'unknown' }),
    { callId: 'write-1', status: 'settled', outcome: 'unknown' });
  assert.throws(() => queue.endCall(lease, 'write-1', { outcome: 'success' }),
    { code: 'CALL_OUTCOME_CONFLICT' });
  assert.equal(queue.finish(lease, { status: 'result_unknown', errorCode: 'RESPONSE_LOST' }).status,
    'result_unknown');
});

test('database and ancestor symlinks are refused and public file permissions are not silently changed', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  queue.close();
  symlinkSync(dbPath, join(directory, 'linked.sqlite'));
  assert.throws(() => new OperationQueue(join(directory, 'linked.sqlite')), { code: 'UNSAFE_PATH' });
  symlinkSync(directory, join(directory, 'linked-directory'));
  assert.throws(() => new OperationQueue(join(directory, 'linked-directory', 'another.sqlite')),
    { code: 'UNSAFE_PATH' });
  chmodSync(dbPath, 0o644);
  assert.throws(() => new OperationQueue(dbPath), { code: 'UNSAFE_PERMISSIONS' });
  assert.equal(statSync(dbPath).mode & 0o777, 0o644);
});

test('verified receipt and cancelled or conflicted records cannot be reopened for writes', (t) => {
  const { directory, dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  t.after(() => queue.close());
  for (const status of ['readback_verified', 'cancelled', 'conflict']) {
    const input = operation(directory, { operationId: `terminal-${status}` });
    queue.enqueue(input);
    queue.preview('xfit', input.operationId, { previewDigest: 'd'.repeat(64) });
    const lease = queue.claim({ owner: 'worker-1', projectId: 'xfit', operationId: input.operationId });
    const completion = status === 'readback_verified'
      ? { status, receiptRef: join(directory, 'verified.json'), readbackDigest: 'e'.repeat(64) }
      : status === 'conflict' ? { status, errorCode: 'READBACK_MISMATCH' } : { status };
    const saved = queue.finish(lease, completion);
    assert.throws(() => queue.preview('xfit', input.operationId, { previewDigest: 'e'.repeat(64) }),
      { code: 'INVALID_STATE' });
    assert.throws(() => queue.block('xfit', input.operationId, { code: 'TARGET_UNBOUND' }),
      { code: 'INVALID_STATE' });
    assert.throws(() => queue.claim({ owner: 'worker-2', projectId: 'xfit', operationId: input.operationId }),
      { code: 'NOT_READY' });
    assert.deepEqual(queue.enqueue(input), saved);
  }
});

test('a newer storage version is rejected rather than silently downgraded', (t) => {
  const { dbPath } = fixture(t);
  const queue = new OperationQueue(dbPath);
  queue.close();
  const futureStorage = new DatabaseSync(dbPath);
  futureStorage.exec('PRAGMA user_version=2');
  futureStorage.close();
  const before = readFileSync(dbPath);
  assert.throws(() => new OperationQueue(dbPath), { code: 'UNSUPPORTED_STORAGE_VERSION' });
  assert.deepEqual(readFileSync(dbPath), before);
});

function coldWorker(t, dbPath, index) {
  const child = fork(fileURLToPath(new URL('./queue-worker.mjs', import.meta.url)),
    [dbPath, `worker-${index}`, 'xfit', `cold-${index}`, 'cold-enqueue'],
    { execArgv: [], stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });
  t.after(() => { if (child.exitCode === null) child.kill(); });
  let waitingResolve, waitingReject, resultResolve, resultReject;
  let waitingSeen = false, resultSeen = false;
  const waiting = new Promise((resolve, reject) => { waitingResolve = resolve; waitingReject = reject; });
  const result = new Promise((resolve, reject) => { resultResolve = resolve; resultReject = reject; });
  result.catch(() => {});
  child.on('message', (message) => {
    if (message.type === 'waiting') { waitingSeen = true; waitingResolve(); }
    if (message.type === 'result') { resultSeen = true; resultResolve(message); }
  });
  child.on('error', (error) => { waitingReject(error); resultReject(error); });
  child.on('exit', () => {
    if (!waitingSeen) waitingReject(new QueueError('WORKER_EXITED'));
    if (waitingSeen && !resultSeen) resultReject(new QueueError('WORKER_EXITED'));
  });
  return { child, waiting, result };
}

test('four independent cold-start processes atomically initialize missing storage and retain every intent',
  { timeout: 6000 }, async (t) => {
    const { directory } = fixture(t);
    for (let round = 0; round < 3; round += 1) {
      const dbPath = join(directory, `round-${round}`, 'private', 'queue.sqlite');
      const workers = Array.from({ length: 4 }, (_, index) => coldWorker(t, dbPath, index));
      await Promise.all(workers.map((worker) => worker.waiting));
      workers.forEach((worker) => worker.child.send('start'));
      const results = await Promise.all(workers.map((worker) => worker.result));
      assert.deepEqual(results.map((result) => result.status),
        ['saved_local', 'saved_local', 'saved_local', 'saved_local'], JSON.stringify(results));
      const restarted = new OperationQueue(dbPath);
      assert.deepEqual(restarted.list().map((item) => item.operationId).sort(),
        ['cold-0', 'cold-1', 'cold-2', 'cold-3']);
      restarted.close();
    }
  });
