#!/usr/bin/env python3
"""Read phone data into one local simulator. Never sends a write to the phone."""
import argparse
from contextlib import closing
import datetime as dt
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = 'com.edward.FitnessApp'
GROUP = 'group.com.edward.FitnessApp'
PHONE = '00008150-001E49912122401C'
SIMULATOR = '889740E8-07E1-442F-9F8C-F6908B946D7A'


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def execute(command, log, *, check=True):
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(result.stdout + result.stderr)
    if check and result.returncode:
        raise RuntimeError(f'Command failed; see {log}')
    return result


def phone_read(arguments, destination, name):
    # This allowlist is intentionally limited to reads.
    assert arguments[:2] in (['info', 'lockState'], ['copy', 'from'])
    command = ['xcrun', 'devicectl', 'device'] + arguments
    result_file = destination / (name + '.json')
    execute(command + ['--timeout', '45', '--json-output', str(result_file)],
            destination / (name + '.log'))
    receipt = json.loads(result_file.read_text())
    if receipt.get('info', {}).get('outcome') != 'success':
        raise RuntimeError(f'Phone read did not succeed: {result_file}')
    return receipt


def capture_phone(device, folder):
    folder.mkdir(parents=True, exist_ok=False)
    lock = phone_read(['info', 'lockState', '--device', device], folder, 'phone-lock')
    if lock['result']['passcodeRequired']:
        raise RuntimeError('Unlock the phone and keep its screen on; no simulator data changed.')
    for source, target, domain, identifier in [
        ('Library/Application Support', 'phone-application-support', 'appGroupDataContainer', GROUP),
        ('Library/Preferences', 'phone-app-preferences', 'appDataContainer', BUNDLE),
    ]:
        phone_read(['copy', 'from', '--device', device, '--source', source,
                    '--destination', str(folder / target), '--domain-type', domain,
                    '--domain-identifier', identifier], folder, target + '-copy')


def store_in(folder):
    stores = list(folder.rglob('*.store'))
    if len(stores) != 1:
        raise RuntimeError(f'Expected one persistent store in {folder}; found {len(stores)}')
    return stores[0]


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def model_snapshot(store, baseline=None):
    """Compare original values including PKs; ignore Core Data version bookkeeping."""
    with closing(sqlite3.connect(store.resolve().as_uri() + '?mode=ro', uri=True)) as db:
        if db.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
            raise RuntimeError('SQLite integrity check failed')
        tables = {}
        for (table,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall():
            columns = [row[1] for row in db.execute('PRAGMA table_info(' + quote(table) + ')')]
            if 'ZID' not in columns:
                continue
            columns = [c for c in columns if c not in ('Z_ENT', 'Z_OPT')]
            if baseline is not None:
                if table not in baseline or not set(baseline[table]['columns']) <= set(columns):
                    raise RuntimeError('A source model or field is missing: ' + table)
                extra = set(columns) - set(baseline[table]['columns'])
                allowed = {'ZSCHEDULEDWORKOUT': {'ZJUMPROPEPLANJSON'},
                           'ZJUMPROPEENTRY': {'ZSCHEDULEDWORKOUTID'},
                           'ZWORKOUTSESSION': {'ZCARDIORESISTANCELEVEL'}}.get(table, set())
                if not extra <= allowed:
                    raise RuntimeError('Unexpected simulator schema change: ' + table)
                for field in extra:
                    if db.execute('SELECT count(*) FROM ' + quote(table) + ' WHERE ' + quote(field) + ' IS NOT NULL').fetchone()[0]:
                        raise RuntimeError('A new field was inferred for historical rows: ' + field)
                columns = baseline[table]['columns']
            records = {}
            for row in db.execute('SELECT ' + ','.join(map(quote, columns)) + ' FROM ' + quote(table)):
                values = [v.hex() if isinstance(v, bytes) else v for v in row]
                identity = values[columns.index('ZID')]
                if identity is None or identity in records:
                    raise RuntimeError(f'Missing/duplicate model identity in {table}')
                encoded = json.dumps(values, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
                records[identity] = hashlib.sha256(encoded.encode()).hexdigest()
            tables[table] = {'columns': columns, 'records': records}
    if baseline is not None and tables.keys() != baseline.keys():
        raise RuntimeError('Simulator model identities differ from the source schema')
    if not {'ZWORKOUTSESSION', 'ZSETLOG', 'ZSCHEDULEDWORKOUT', 'ZMEALENTRY'} <= tables.keys():
        raise RuntimeError('The phone snapshot is missing required model tables')
    return tables


def assets(folder):
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.rglob('*') if p.is_file()
            and any(part in ('MealPhotos', '_EXTERNAL_DATA') for part in p.relative_to(folder).parts)}


def portable_backup(source, destination):
    if destination.exists() or destination.resolve() == source.resolve():
        raise RuntimeError('Portable backup requires a new local destination')
    with closing(sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True)) as src:
        with closing(sqlite3.connect(destination)) as dst:
            src.backup(dst)
            result = dst.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()
            if result[0] != 0 or dst.execute('PRAGMA journal_mode=DELETE').fetchone()[0] != 'delete':
                raise RuntimeError('Could not checkpoint the new local copy')
    # A copied WAL database may leave an empty WAL and an unused shared-memory
    # file after switching journal mode. These belong only to the new copy.
    wal = destination.with_name(destination.name + '-wal')
    if wal.exists() and wal.stat().st_size:
        raise RuntimeError('New local backup still has uncheckpointed WAL data')
    wal.unlink(missing_ok=True)
    destination.with_name(destination.name + '-shm').unlink(missing_ok=True)


def refresh(args):
    stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S')
    run = ROOT / 'artifacts/simulator-real-data' / stamp
    run.mkdir(parents=True, exist_ok=False)
    source = args.snapshot.resolve() if args.snapshot else run / 'phone-source'
    if args.snapshot is None:
        capture_phone(args.device, source)
    else:
        receipts = list(source.glob('*copy.json'))
        if not receipts or any(json.loads(p.read_text()).get('info', {}).get('outcome') != 'success' for p in receipts):
            raise RuntimeError('Existing snapshot has no successful phone-copy receipt')
    support = source / 'phone-application-support'
    source_store = store_in(support)
    expected = model_snapshot(source_store)
    expected_assets = assets(support)
    sim = ['xcrun', 'simctl']
    groups = execute(sim + ['get_app_container', args.simulator, BUNDLE, 'groups'], run / 'container.log').stdout
    matches = [line.split('\t', 1)[1] for line in groups.splitlines() if line.startswith(GROUP + '\t')]
    if len(matches) != 1:
        raise RuntimeError('The named simulator App Group could not be uniquely identified')
    data = Path(matches[0])
    app = Path(execute(sim + ['get_app_container', args.simulator, BUNDLE, 'app'], run / 'app.log').stdout.strip())
    if args.simulator not in data.parts or 'CoreSimulator' not in data.parts:
        raise RuntimeError('Target is not the selected CoreSimulator container')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if str(info.get('XFitCloudSyncEnabled', '')).lower() not in ('no', 'false', '0'):
        raise RuntimeError('Refusing to clone phone data into an app with cloud sync enabled')
    stopped = execute(sim + ['terminate', args.simulator, BUNDLE], run / 'terminate.log', check=False)
    if stopped.returncode and not any(t in (stopped.stdout + stopped.stderr).lower()
                                       for t in ('not running', 'no such process', 'found nothing to terminate')):
        raise RuntimeError('Could not stop the simulator app safely')
    execute(sim + ['spawn', args.simulator, 'defaults', 'export', BUNDLE, str(run / 'simulator-before-preferences.plist')],
            run / 'export-preferences.log')
    backup = run / 'simulator-before'
    shutil.copytree(data, backup)
    target = data / 'Library/Application Support'
    incoming = data / 'Library' / ('Application Support.incoming-' + stamp)
    shutil.copytree(support, incoming, ignore=shutil.ignore_patterns('*.store', '*.store-wal', '*.store-shm'))
    prepared_store = incoming / source_store.relative_to(support)
    prepared_store.parent.mkdir(parents=True, exist_ok=True)
    portable_backup(source_store, prepared_store)
    if model_snapshot(prepared_store) != expected or assets(incoming) != expected_assets:
        raise RuntimeError('Prepared simulator copy does not match the phone snapshot')
    preferences = source / 'phone-app-preferences' / (BUNDLE + '.plist')
    try:
        if target.exists():
            shutil.rmtree(target)
        incoming.rename(target)
        if preferences.exists():
            execute(sim + ['spawn', args.simulator, 'defaults', 'import', BUNDLE, str(preferences)], run / 'import-preferences.log')
        launched = execute(sim + ['launch', args.simulator, BUNDLE], run / 'normal-launch.log')
        pid = int(launched.stdout.rsplit(':', 1)[-1].strip())
        active_store = store_in(target).resolve()
        deadline = time.monotonic() + 45
        while True:
            opened = subprocess.run(['/usr/sbin/lsof', '-p', str(pid), '-Fn'], capture_output=True, text=True, timeout=10)
            if 'n' + str(active_store) in opened.stdout.splitlines():
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('The normal app process did not open the expected App Group store')
            time.sleep(0.5)
        actual = model_snapshot(active_store, expected)
        if actual != expected or assets(target) != expected_assets:
            raise RuntimeError('Running simulator data diverged from the phone snapshot')
    except Exception:
        execute(sim + ['terminate', args.simulator, BUNDLE], run / 'rollback-terminate.log', check=False)
        if target.exists():
            shutil.rmtree(target)
        previous = backup / 'Library/Application Support'
        if previous.exists():
            shutil.copytree(previous, target)
        execute(sim + ['spawn', args.simulator, 'defaults', 'import', BUNDLE, str(run / 'simulator-before-preferences.plist')],
                run / 'rollback-preferences.log')
        save(run / 'result.json', {'status': 'FAIL_ROLLED_BACK', 'phone_writes': 0, 'backup': str(backup)})
        raise
    record = {'status': 'PASS', 'captured_source': str(source), 'simulator': args.simulator,
              'phone_writes': 0, 'cloud_sync_enabled': False, 'launch_arguments': [],
              'model_tables': len(expected), 'records': sum(len(t['records']) for t in expected.values()),
              'counts': {name: len(t['records']) for name, t in expected.items()},
              'assets': len(expected_assets), 'simulator_backup': str(backup),
              'target_store': str(store_in(target)), 'preferences_copied': preferences.exists(),
              'storage_scope': 'App Group', 'active_store_verified_by_process': True,
              'freshness': 'One-way phone snapshot; explicitly refresh again after new phone records.'}
    save(run / 'result.json', record)
    # Only aggregate metadata is copied into user-facing reports.
    save(ROOT / 'outputs/simulator-real-data' / stamp / 'result.json', record)
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default=PHONE)
    parser.add_argument('--simulator', default=SIMULATOR)
    parser.add_argument('--snapshot', type=Path, help='Reuse a just-captured phone snapshot with successful copy receipts')
    refresh(parser.parse_args())
