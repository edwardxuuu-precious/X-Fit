#!/usr/bin/env python3
"""Audit downloaded SQLite backups only. Never opens originals with SQLite.
Usage: python3 audit_backup_conservation.py --output DIR label=/path/to/backup ...
Copies db+WAL+SHM into temporary workspace, verifies source hashes unchanged,
compares all ZID entities and all common business columns. No migration is
silently allowlisted: every changed business value requires explanation.
"""
import argparse,collections,hashlib,json,pathlib,shutil,sqlite3,tempfile
INTERNAL={'Z_PK','Z_ENT','Z_OPT'}
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def enc(v):
 return {'sqlite_blob_hex':v.hex()} if isinstance(v,bytes) else v
def identity(v):
 return v.hex() if isinstance(v,bytes) else str(v)
def digest(v):return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def snapshot(label,root):
 files=sorted(root.rglob('*.store')) if root.is_dir() else [root]
 if len(files)!=1:raise ValueError(f'{label}: expected exactly one .store; found {len(files)}')
 original=files[0]
 sources=[pathlib.Path(str(original)+s) for s in ('','-wal','-shm') if pathlib.Path(str(original)+s).exists()]
 before={str(p):sha(p) for p in sources}
 with tempfile.TemporaryDirectory(prefix='xfit-backup-audit-') as tmp:
  dest=pathlib.Path(tmp)/original.name
  for p in sources:shutil.copy2(p,pathlib.Path(tmp)/p.name)
  db=sqlite3.connect(dest); db.row_factory=sqlite3.Row
  integrity=[r[0] for r in db.execute('PRAGMA integrity_check')]
  entities={}; excluded=[]
  for name,sql in db.execute("SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name"):
   q='"'+name.replace('"','""')+'"'
   cols=[dict(r) for r in db.execute(f'PRAGMA table_info({q})')]
   names=[r['name'] for r in cols]
   if 'ZID' not in names:
    excluded.append(name);continue
   rows=[dict(r) for r in db.execute(f'SELECT * FROM {q}')]
   ids=[identity(r['ZID']) for r in rows if r['ZID'] is not None]
   duplicates=[i for i,c in collections.Counter(ids).items() if c>1]
   records={identity(r['ZID']):{k:enc(v) for k,v in r.items()} for r in rows if r['ZID'] is not None}
   entities[name]={'count':len(rows),'null_ids':sum(r['ZID'] is None for r in rows),'duplicate_ids':duplicates,'columns':cols,'records':records,'ids_sha256':digest(sorted(ids)),'business_sha256':digest({i:{k:v for k,v in r.items() if k not in INTERNAL} for i,r in records.items()})}
  db.close()
 after={str(p):sha(p) for p in sources}
 return {'label':label,'source':str(original.resolve()),'source_files_sha256':before,'source_files_unchanged':before==after,'integrity_check':integrity,'entities':entities,'excluded_non_ZID_tables':excluded}
def compare(a,b):
 result={'before':a['label'],'after':b['label'],'new_tables':sorted(set(b['entities'])-set(a['entities'])),'missing_tables':sorted(set(a['entities'])-set(b['entities'])),'tables':{}}
 for t,x in a['entities'].items():
  if t not in b['entities']:continue
  y=b['entities'][t]; xr=x['records'];yr=y['records']; common=set(xr)&set(yr)
  xc={c['name'] for c in x['columns']};yc={c['name'] for c in y['columns']};shared=sorted((xc&yc)-INTERNAL)
  changes=[]; internal_changed=0
  for i in sorted(common):
   diff={c:{'before':xr[i][c],'after':yr[i][c]} for c in shared if xr[i][c]!=yr[i][c]}
   if diff:changes.append({'id':i,'fields':diff})
   if any(xr[i].get(c)!=yr[i].get(c) for c in INTERNAL):internal_changed+=1
  # All UUID-valued reference columns are compared per record above; summarize
  # their full multisets too. Current schema uses explicit BLOB IDs, no FK PKs.
  uuidcols=sorted(c for c in shared if c.endswith('ID') and any(isinstance(r.get(c),dict) and 'sqlite_blob_hex' in r[c] for r in list(xr.values())+list(yr.values())))
  uuid_refs={c:{'before_sha256':digest(sorted(json.dumps(r[c],sort_keys=True) for r in xr.values())),'after_sha256':digest(sorted(json.dumps(r[c],sort_keys=True) for r in yr.values()))} for c in uuidcols}
  result['tables'][t]={'before_count':x['count'],'after_count':y['count'],'removed_ids':sorted(set(xr)-set(yr)),'added_ids':sorted(set(yr)-set(xr)),'common_ids':len(common),'common_business_columns':shared,'added_columns':sorted(yc-xc),'removed_columns':sorted(xc-yc),'business_changed_records':changes,'internal_metadata_changed_records':internal_changed,'uuid_column_multisets':uuid_refs}
 result['removed_ids_count']=sum(len(v['removed_ids']) for v in result['tables'].values())
 result['added_ids_count']=sum(len(v['added_ids']) for v in result['tables'].values())
 result['business_changed_records_count']=sum(len(v['business_changed_records']) for v in result['tables'].values())
 badids=any(e['null_ids'] or e['duplicate_ids'] for s in (a,b) for e in s['entities'].values())
 if not all(s['source_files_unchanged'] and s['integrity_check']==['ok'] for s in (a,b)) or badids:
  result['status']='FAIL_INTEGRITY_OR_IDENTITY'
 elif result['missing_tables'] or result['removed_ids_count'] or result['business_changed_records_count'] or any(v['removed_columns'] for v in result['tables'].values()):
  result['status']='REQUIRES_CHANGE_REVIEW'
 else:result['status']='PASS_COMMON_HISTORY_PRESERVED'
 result['interpretation']='Schema additions are reported separately. A business change is not proof of corruption or an approved migration; source-based attribution is required. Empty new tables contain no historical records to compare.'
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('backups',nargs='+');args=p.parse_args()
 out=pathlib.Path(args.output);out.mkdir(parents=True,exist_ok=True)
 shots=[snapshot(label,pathlib.Path(path)) for label,path in (v.split('=',1) for v in args.backups)]
 for s in shots:(out/(s['label']+'-snapshot.json')).write_text(json.dumps(s,ensure_ascii=False,indent=2))
 pairs=[(i,i+1) for i in range(len(shots)-1)]
 if len(shots)>2:pairs.append((0,len(shots)-1))
 comparisons=[compare(shots[i],shots[j]) for i,j in pairs]
 report={'scope':'downloaded backup copies only; no device access','script_sha256':sha(pathlib.Path(__file__)),'snapshots':[{'label':s['label'],'source':s['source'],'integrity_check':s['integrity_check'],'source_files_unchanged':s['source_files_unchanged'],'entity_count':len(s['entities']),'total_rows':sum(e['count'] for e in s['entities'].values())} for s in shots],'comparisons':comparisons}
 (out/'conservation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 lines=['# 下载备份数据守恒审计','','仅打开含 WAL/SHM 的临时工作副本；原始备份哈希前后校验。全部含 ZID 的实体均纳入，内部 Z_PK/Z_ENT/Z_OPT 单列；新增表/列不冒充旧字段比较。','']
 for s in report['snapshots']:lines.append(f"- {s['label']}：{s['entity_count']} 个实体，{s['total_rows']} 行；完整性 {s['integrity_check']}；原始文件未变 {s['source_files_unchanged']}。")
 for c in comparisons:
  lines+=['',f"## {c['before']} → {c['after']}",'',f"状态：`{c['status']}`；原 UUID 缺失 {c['removed_ids_count']}，新增 {c['added_ids_count']}，共同记录业务变化 {c['business_changed_records_count']}。",'', '| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |','|---|---:|---:|---:|---:|---:|---:|']
  for t,v in c['tables'].items():lines.append(f"| {t} | {v['before_count']} | {v['after_count']} | {len(v['removed_ids'])} | {len(v['added_ids'])} | {len(v['business_changed_records'])} | {len(v['added_columns'])} |")
  lines+=['', '新增实体：'+(', '.join(c['new_tables']) or '无')+'。','缺失实体：'+(', '.join(c['missing_tables']) or '无')+'。']
 lines+=['','字段变化需要对照当前迁移代码与授权逐项解释，不自动认定为正常迁移或损坏。此结果只证明这些下载时间点；不替代最后 Release 回读或人工验收。']
 (out/'conservation.md').write_text('\n'.join(lines)+'\n')
 print(json.dumps({'snapshots':report['snapshots'],'comparisons':[{k:c[k] for k in ('before','after','status','removed_ids_count','added_ids_count','business_changed_records_count')} for c in comparisons]},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
