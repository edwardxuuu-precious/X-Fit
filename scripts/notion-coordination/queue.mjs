import { DatabaseSync } from 'node:sqlite';
import { constants, closeSync, lstatSync, mkdirSync, openSync } from 'node:fs';
import { dirname, isAbsolute, join, parse, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';

export class QueueError extends Error {
  constructor(code) {
    const safeCode = typeof code === 'string' && /^[A-Z][A-Z0-9_]{0,95}$/.test(code) ? code : 'QUEUE_ERROR';
    super(`Operation queue rejected the request (${safeCode}).`);
    this.name = 'QueueError';
    this.code = safeCode;
  }
}

const METADATA = ['projectId', 'operationId', 'sourceRef', 'sourceDigest', 'payloadDigest',
  'routeDigest', 'targetId', 'profileId', 'adapterId'];
const COLUMNS = ['project_id', 'operation_id', 'source_ref', 'source_digest', 'payload_digest',
  'route_digest', 'target_id', 'profile_id', 'adapter_id'];
const APPLICATION_ID = 0x4e474351;

function identifier(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(value)) {
    throw new QueueError('INVALID_ARGUMENT');
  }
  return value;
}

function digest(value) {
  if (typeof value !== 'string' || !/^[a-f0-9]{64}$/.test(value)) throw new QueueError('INVALID_ARGUMENT');
  return value;
}

function errorCode(value) {
  if (typeof value !== 'string' || !/^[A-Z][A-Z0-9_]{0,95}$/.test(value)) {
    throw new QueueError('INVALID_ARGUMENT');
  }
  return value;
}

function localReference(value) {
  if (typeof value !== 'string' || value.length > 2048 || /[\x00-\x1f\x7f?#]/.test(value)
      || !isAbsolute(value) || resolve(value) !== value || value === parse(value).root) {
    throw new QueueError('INVALID_ARGUMENT');
  }
  return value;
}

function exactObject(value, required, optional = []) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)
      || ![Object.prototype, null].includes(Object.getPrototypeOf(value))
      || Object.keys(value).some((key) => ![...required, ...optional].includes(key))
      || required.some((key) => !Object.hasOwn(value, key))) throw new QueueError('INVALID_ARGUMENT');
}

function safeDatabasePath(value) {
  localReference(value);
  const root = parse(value).root;
  let current = root;
  const segments = dirname(value).slice(root.length).split('/').filter(Boolean);
  for (const segment of segments) {
    current = join(current, segment);
    let stat;
    try { stat = lstatSync(current); } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      try { mkdirSync(current, { mode: 0o700 }); }
      catch (createError) { if (createError.code !== 'EEXIST') throw createError; }
      stat = lstatSync(current);
    }
    if (stat.isSymbolicLink() || !stat.isDirectory()) throw new QueueError('UNSAFE_PATH');
  }
  if ((lstatSync(dirname(value)).mode & 0o077) !== 0) throw new QueueError('UNSAFE_PERMISSIONS');
  for (const suffix of ['-journal', '-wal', '-shm']) {
    try {
      const sidecar = lstatSync(`${value}${suffix}`);
      if (sidecar.isSymbolicLink() || !sidecar.isFile() || sidecar.nlink !== 1) {
        throw new QueueError('UNSAFE_PATH');
      }
      if ((sidecar.mode & 0o077) !== 0) throw new QueueError('UNSAFE_PERMISSIONS');
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  let stat;
  try {
    stat = lstatSync(value);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    try {
      const file = openSync(value, constants.O_RDWR | constants.O_CREAT | constants.O_EXCL
        | constants.O_NOFOLLOW, 0o600);
      closeSync(file);
    } catch (createError) { if (createError.code !== 'EEXIST') throw createError; }
    stat = lstatSync(value);
  }
  if (stat.isSymbolicLink() || !stat.isFile() || stat.nlink !== 1) throw new QueueError('UNSAFE_PATH');
  if ((stat.mode & 0o077) !== 0) throw new QueueError('UNSAFE_PERMISSIONS');
}

function operationRow(row) {
  if (!row) return null;
  const result = Object.fromEntries(METADATA.map((key, index) => [key, row[COLUMNS[index]]]));
  return { ...result, status: row.status, previewDigest: row.preview_digest,
    receiptRef: row.receipt_ref, readbackDigest: row.readback_digest, errorCode: row.error_code };
}

export class OperationQueue {
  #database;
  #closed = false;

  constructor(dbPath) {
    try {
      safeDatabasePath(dbPath);
      this.#database = new DatabaseSync(dbPath);
      // Apply the bounded provider wait before the first schema/identity read.
      // Two processes may open while the other is finishing a SQLite write.
      this.#database.exec(`PRAGMA busy_timeout=1000; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;`);
      // A cold-start contender must observe identity, version, and schema from
      // the same locked snapshot. Publishing these in separate transactions can
      // expose application_id=0 with user_version=1 (or the reverse).
      this.#transaction(() => {
        const applicationId = this.#database.prepare('PRAGMA application_id').get().application_id;
        const storageVersion = this.#database.prepare('PRAGMA user_version').get().user_version;
        const tables = this.#database.prepare(`SELECT name FROM sqlite_master
          WHERE type='table' AND name NOT LIKE 'sqlite_%'`).all();
        if (applicationId !== APPLICATION_ID && (applicationId !== 0 || tables.length !== 0)) {
          throw new QueueError('UNRECOGNIZED_STORAGE');
        }
        if ((applicationId === APPLICATION_ID && storageVersion !== 1)
            || (applicationId === 0 && storageVersion !== 0)) {
          throw new QueueError('UNSUPPORTED_STORAGE_VERSION');
        }
        if (this.#database.prepare('PRAGMA journal_mode').get().journal_mode !== 'delete') {
          throw new QueueError('UNSUPPORTED_STORAGE_MODE');
        }
        if (applicationId === APPLICATION_ID) {
          const names = new Set(tables.map((table) => table.name));
          if (names.size !== 3 || !['operations', 'lease', 'calls'].every((name) => names.has(name))) {
            throw new QueueError('QUEUE_SCHEMA_INVALID');
          }
          return;
        }
        this.#database.exec(`CREATE TABLE operations (
          sequence INTEGER PRIMARY KEY AUTOINCREMENT,
          project_id TEXT NOT NULL, operation_id TEXT NOT NULL,
          source_ref TEXT NOT NULL, source_digest TEXT NOT NULL, payload_digest TEXT NOT NULL,
          route_digest TEXT NOT NULL, target_id TEXT NOT NULL, profile_id TEXT NOT NULL,
          adapter_id TEXT NOT NULL, status TEXT NOT NULL,
          preview_digest TEXT, receipt_ref TEXT, readback_digest TEXT, error_code TEXT,
          UNIQUE(project_id, operation_id)
        );
        CREATE TABLE lease (
          singleton INTEGER PRIMARY KEY CHECK(singleton=1), token TEXT NOT NULL,
          owner TEXT NOT NULL, project_id TEXT NOT NULL, operation_id TEXT NOT NULL,
          FOREIGN KEY(project_id,operation_id) REFERENCES operations(project_id,operation_id)
        );
        CREATE TABLE calls (
          lease_token TEXT NOT NULL, call_id TEXT NOT NULL,
          active INTEGER NOT NULL CHECK(active IN(0,1)), outcome TEXT,
          PRIMARY KEY(lease_token,call_id)
        );
        PRAGMA application_id=${APPLICATION_ID}; PRAGMA user_version=1;`);
      });
    } catch (error) {
      this.#database?.close();
      if (error instanceof QueueError) throw error;
      throw new QueueError('QUEUE_STORAGE_FAILED');
    }
  }

  #transaction(action) {
    if (this.#closed) throw new QueueError('QUEUE_CLOSED');
    let begun = false;
    try {
      this.#database.exec('BEGIN IMMEDIATE');
      begun = true;
      const result = action();
      this.#database.exec('COMMIT');
      return result;
    } catch (error) {
      if (begun) { try { this.#database.exec('ROLLBACK'); } catch {} }
      if (error instanceof QueueError) throw error;
      throw new QueueError('QUEUE_STORAGE_FAILED');
    }
  }

  #row(projectId, operationId) {
    identifier(projectId); identifier(operationId);
    return this.#database.prepare('SELECT * FROM operations WHERE project_id=? AND operation_id=?')
      .get(projectId, operationId);
  }

  #assertLease(lease) {
    exactObject(lease, ['token', 'owner', 'projectId', 'operationId']);
    for (const value of Object.values(lease)) identifier(value);
    const stored = this.#database.prepare('SELECT * FROM lease WHERE singleton=1').get();
    if (!stored || stored.token !== lease.token || stored.owner !== lease.owner
        || stored.project_id !== lease.projectId || stored.operation_id !== lease.operationId) {
      throw new QueueError('LEASE_MISMATCH');
    }
  }

  enqueue(input) {
    exactObject(input, METADATA);
    const values = METADATA.map((key) => key.endsWith('Digest') ? digest(input[key])
      : key === 'sourceRef' ? localReference(input[key]) : identifier(input[key]));
    return this.#transaction(() => {
      const existing = this.#row(input.projectId, input.operationId);
      if (existing) {
        if (COLUMNS.some((column, index) => existing[column] !== values[index])) {
          throw new QueueError('ID_CONFLICT');
        }
        return operationRow(existing);
      }
      this.#database.prepare(`INSERT INTO operations (${COLUMNS.join(',')},status)
        VALUES (?,?,?,?,?,?,?,?,?,'saved_local')`).run(...values);
      return operationRow(this.#row(input.projectId, input.operationId));
    });
  }

  get(projectId, operationId) {
    return this.#transaction(() => operationRow(this.#row(projectId, operationId)));
  }

  list() {
    return this.#transaction(() => this.#database.prepare('SELECT * FROM operations ORDER BY sequence')
      .all().map(operationRow));
  }

  preview(projectId, operationId, input) {
    exactObject(input, ['previewDigest']);
    digest(input.previewDigest);
    return this.#transaction(() => {
      const existing = this.#row(projectId, operationId);
      if (!existing) throw new QueueError('OPERATION_NOT_FOUND');
      if (!['saved_local', 'preview_ready', 'blocked_access'].includes(existing.status)) {
        throw new QueueError('INVALID_STATE');
      }
      if (existing.status === 'preview_ready' && existing.preview_digest !== input.previewDigest) {
        throw new QueueError('PREVIEW_CONFLICT');
      }
      this.#database.prepare(`UPDATE operations SET status='preview_ready', preview_digest=?,
        error_code=NULL WHERE project_id=? AND operation_id=?`)
        .run(input.previewDigest, projectId, operationId);
      return operationRow(this.#row(projectId, operationId));
    });
  }

  block(projectId, operationId, input) {
    exactObject(input, ['code'], ['status']); errorCode(input.code);
    const status = Object.hasOwn(input, 'status') ? input.status : 'blocked_access';
    if (!['blocked_access', 'conflict'].includes(status)) throw new QueueError('INVALID_ARGUMENT');
    return this.#transaction(() => {
      const existing = this.#row(projectId, operationId);
      if (!existing) throw new QueueError('OPERATION_NOT_FOUND');
      if (!['saved_local', 'preview_ready', 'blocked_access'].includes(existing.status)) {
        throw new QueueError('INVALID_STATE');
      }
      this.#database.prepare(`UPDATE operations SET status=?,error_code=?
        WHERE project_id=? AND operation_id=?`).run(status, input.code, projectId, operationId);
      return operationRow(this.#row(projectId, operationId));
    });
  }

  claim(input) {
    exactObject(input, ['owner', 'projectId', 'operationId']);
    identifier(input.owner); identifier(input.projectId); identifier(input.operationId);
    return this.#transaction(() => {
      if (this.#database.prepare('SELECT 1 FROM lease').get()) throw new QueueError('LEASE_HELD');
      const current = this.#row(input.projectId, input.operationId);
      if (!current) throw new QueueError('OPERATION_NOT_FOUND');
      if (current.status !== 'preview_ready') throw new QueueError('NOT_READY');
      const first = this.#database.prepare(`SELECT sequence FROM operations
        WHERE status='preview_ready' ORDER BY sequence LIMIT 1`).get();
      if (first.sequence !== current.sequence) throw new QueueError('FIFO_PENDING');
      const token = randomUUID();
      this.#database.prepare(`INSERT INTO lease(singleton,token,owner,project_id,operation_id)
        VALUES(1,?,?,?,?)`).run(token, input.owner, input.projectId, input.operationId);
      this.#database.prepare(`UPDATE operations SET status='executing'
        WHERE project_id=? AND operation_id=?`).run(input.projectId, input.operationId);
      return { token, owner: input.owner, projectId: input.projectId, operationId: input.operationId };
    });
  }

  finish(lease, input) {
    exactObject(input, ['status'], ['receiptRef', 'readbackDigest', 'errorCode']);
    if (!['readback_verified', 'blocked_access', 'conflict', 'result_unknown', 'cancelled']
      .includes(input.status)) throw new QueueError('INVALID_ARGUMENT');
    if (input.status === 'readback_verified') {
      localReference(input.receiptRef); digest(input.readbackDigest);
      if (Object.hasOwn(input, 'errorCode')) throw new QueueError('INVALID_ARGUMENT');
    } else {
      if (Object.hasOwn(input, 'receiptRef') || Object.hasOwn(input, 'readbackDigest')) {
        throw new QueueError('INVALID_ARGUMENT');
      }
      if (input.status !== 'cancelled' || Object.hasOwn(input, 'errorCode')) errorCode(input.errorCode);
    }
    return this.#transaction(() => {
      this.#assertLease(lease);
      if (this.#database.prepare('SELECT 1 FROM calls WHERE lease_token=? AND active=1 LIMIT 1')
        .get(lease.token)) throw new QueueError('ACTIVE_CALL');
      this.#database.prepare(`UPDATE operations SET status=?, receipt_ref=?, readback_digest=?,
        error_code=? WHERE project_id=? AND operation_id=?`).run(input.status,
        input.receiptRef ?? null, input.readbackDigest ?? null, input.errorCode ?? null,
        lease.projectId, lease.operationId);
      this.#database.prepare('DELETE FROM lease WHERE singleton=1').run();
      this.#database.prepare('DELETE FROM calls WHERE lease_token=?').run(lease.token);
      return operationRow(this.#row(lease.projectId, lease.operationId));
    });
  }

  beginCall(lease, callId) {
    identifier(callId);
    return this.#transaction(() => {
      this.#assertLease(lease);
      if (this.#database.prepare('SELECT 1 FROM calls WHERE lease_token=? AND call_id=?')
        .get(lease.token, callId)) throw new QueueError('CALL_ALREADY_TRACKED');
      if (this.#database.prepare('SELECT 1 FROM calls WHERE lease_token=? AND active=1 LIMIT 1')
        .get(lease.token)) throw new QueueError('ACTIVE_CALL');
      this.#database.prepare('INSERT INTO calls(lease_token,call_id,active) VALUES(?,?,1)')
        .run(lease.token, callId);
      return { callId, status: 'active' };
    });
  }

  endCall(lease, callId, input) {
    identifier(callId); exactObject(input, ['outcome']);
    if (!['success', 'failed', 'unknown'].includes(input.outcome)) throw new QueueError('INVALID_ARGUMENT');
    return this.#transaction(() => {
      this.#assertLease(lease);
      const call = this.#database.prepare('SELECT * FROM calls WHERE lease_token=? AND call_id=?')
        .get(lease.token, callId);
      if (!call) throw new QueueError('CALL_NOT_FOUND');
      if (!call.active && call.outcome !== input.outcome) throw new QueueError('CALL_OUTCOME_CONFLICT');
      this.#database.prepare('UPDATE calls SET active=0,outcome=? WHERE lease_token=? AND call_id=?')
        .run(input.outcome, lease.token, callId);
      return { callId, status: 'settled', outcome: input.outcome };
    });
  }

  // Caller must independently verify the expected and protected remote values first.
  // This acknowledges readback only; it never performs or retries a remote write.
  reconcile(projectId, operationId, input) {
    exactObject(input, ['readbackDigest', 'receiptRef']);
    digest(input.readbackDigest); localReference(input.receiptRef);
    return this.#transaction(() => {
      const existing = this.#row(projectId, operationId);
      if (!existing) throw new QueueError('OPERATION_NOT_FOUND');
      if (existing.status !== 'result_unknown') throw new QueueError('INVALID_STATE');
      this.#database.prepare(`UPDATE operations SET status='readback_verified',readback_digest=?,
        receipt_ref=?,error_code=NULL WHERE project_id=? AND operation_id=?`)
        .run(input.readbackDigest, input.receiptRef, projectId, operationId);
      return operationRow(this.#row(projectId, operationId));
    });
  }

  close() {
    if (!this.#closed) { this.#database.close(); this.#closed = true; }
  }
}
