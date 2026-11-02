import { OperationQueue } from '../../scripts/notion-coordination/queue.mjs';
import { dirname, join } from 'node:path';

const [dbPath, owner, projectId, operationId, mode = 'claim'] = process.argv.slice(2);
let queue;
if (mode === 'cold-enqueue') {
  process.send({ type: 'waiting' });
  process.once('message', (message) => {
    if (message !== 'start') { process.exitCode = 1; process.disconnect(); return; }
    try {
      queue = new OperationQueue(dbPath);
      const saved = queue.enqueue({ projectId, operationId,
        sourceRef: join(dirname(dbPath), `${operationId}.json`), sourceDigest: 'a'.repeat(64),
        payloadDigest: 'b'.repeat(64), routeDigest: 'c'.repeat(64), targetId: 'page-1',
        profileId: 'edward-xfit', adapterId: 'append-only' });
      process.send({ type: 'result', status: saved.status });
    } catch (error) { process.send({ type: 'result', code: error.code ?? 'WORKER_FAILED' }); }
    finally { queue?.close(); process.disconnect(); }
  });
} else {
try {
  queue = new OperationQueue(dbPath);
  process.send({ type: 'ready' });
  process.once('message', (message) => {
    if (message !== 'claim') { queue.close(); process.exitCode = 1; process.disconnect(); return; }
    try {
      const lease = queue.claim({ owner, projectId, operationId });
      process.send({ type: 'result', lease });
    } catch (error) {
      process.send({ type: 'result', code: error.code ?? 'WORKER_FAILED' });
    } finally {
      queue.close();
      process.disconnect();
    }
  });
} catch (error) {
  queue?.close();
  process.send({ type: 'failure', code: error.code ?? 'WORKER_FAILED' }, () => process.disconnect());
  process.exitCode = 1;
}
}
