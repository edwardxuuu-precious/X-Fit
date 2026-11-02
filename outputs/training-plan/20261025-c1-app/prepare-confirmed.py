import datetime as dt, hashlib, json, pathlib, sys, uuid
ROOT = pathlib.Path('/Users/edward/Documents/Fitness App')
OUT = ROOT/'outputs/training-plan/20261025-c1-app'
OUT.mkdir(parents=True,exist_ok=True)
c = json.load(open(ROOT/'outputs/training-plan/2026-10-25-next-lower-candidate.json'))
old = json.load(open(ROOT/'outputs/training-review/2026-10-17-lower-body-evidence.json'))
catalog = {e['catalogExerciseID']:e for e in old['target']['exercises']}
intent = uuid.uuid5(uuid.NAMESPACE_URL,'xfit:owner-confirmed:20261025:C1-main-plus-clean')
def sets_for(key, weights, lower, upper, rir, rest, sides, cue, technical=False):
    return [{'id':str(uuid.uuid5(intent,key+':'+str(i+1))), 'weight':w,'reps':lower[i],
        'weightSide':sides[0], 'repsSide':sides[1], 'actualDefaultPolicyRaw':'blank',
        'prescription':{'label':('技术组' if technical else '工作组')+str(i+1),
            'repsLower':lower[i],'repsUpper':upper[i],
            **({'rirLower':rir[i][0],'rirUpper':rir[i][1]} if rir[i] else {}),
            'restLowerSeconds':rest[0],'restUpperSeconds':rest[1], 'effortCue':cue}}
        for i,w in enumerate(weights)]
entries=[]
t=c['optionalTechnical'];r=catalog[t['personalExerciseID']]
entries.append({'catalogExerciseID':t['personalExerciseID'],'catalogName':r['name'],'equipment':r['equipment'],
 'volumeUnit':r['volumeUnitRaw'],'displayName':'地面杠铃高翻','loadGuidance':t['unit'],
 'notes':'热身：'+t['warmup']+'\n休息：'+t['rest']+'\n'+t['anchor']+'\n'+t['adjustment']+'\n'+t['order']+'\n已由本人明确选择加入；属于4个技术组，不计腿部4动作或常规肌肥大工作组。',
 'planPattern':'fixed','plannedSets':sets_for('clean',[20]*4,[3]*4,[3]*4,[None]*4,(120,180),('single','bilateral'),t['adjustment'],True)})
specs=[
 ([105,110,115,115],[12,10,8,8],[12,12,10,10],[(2,3),(1,2),(1,2),(1,2)],(150,180),('single','unknown'),'pyramidUp'),
 ([30]*3,[8]*3,[10]*3,[(2,2),(2,2),(1,2)],(90,120),('single','single'),'fixed'),
 ([25,30,30],[12,10,10],[15,12,12],[(2,2),(1,2),(0,1)],(90,120),('unknown','unknown'),'pyramidUp'),
 ([50,55,55],[12,10,10],[12,12,12],[(2,2),(1,2),(0,1)],(90,120),('unknown','unknown'),'pyramidUp'),
 ([0]*3,[6]*3,[10]*3,[None]*3,(45,60),('unknown','single'),'fixed')]
for e,s in zip(c['entries'],specs):
    r=catalog[e['personalExerciseID']]
    cue=e['adjustment']+' '+e['confidence']
    entries.append({'catalogExerciseID':e['personalExerciseID'],'catalogName':r['name'],
        'equipment':r['equipment'],'volumeUnit':r['volumeUnitRaw'],'displayName':e['name'],
        'loadGuidance':e['unit'], 'notes':'热身：'+e['warmup']+'\n休息：'+e['rest']+'\n历史：'+e['anchor']+'\n组型：'+e['pattern']+'\n当日：'+e['adjustment']+'\n'+e['confidence'],
        'planPattern':s[6],'plannedSets':sets_for(e['id'],*s[:6],cue)})
    for planned, original in zip(entries[-1]['plannedSets'], e['sets']):
        planned['prescription']['effortCue'] = '原C1努力/质量限定：'+original['rir']+'。'+planned['prescription']['effortCue']
assert len(entries)==6 and sum(len(e['plannedSets']) for e in entries)==20
assert len({s['id'] for e in entries for s in e['plannedSets']})==20
draft={'intentID':str(intent),'candidate':'NEXT-LOWER-20261025-C1','confirmedSelection':'C1主方案＋高翻4技术组','dateStatus':'pending_owner_reply','exercises':entries}
(OUT/'prepared-exercises.json').write_text(json.dumps(draft,ensure_ascii=False,indent=2)+'\n')
if len(sys.argv)==1:
    print('Prepared 6 exact personal exercise references / 20 unique planned sets; date pending; no App request.')
    raise SystemExit
day=dt.date.fromisoformat(sys.argv[1]);today=dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).date();assert day>=today
confirmation='REQ-20261025-104305；本人明确采用C1主方案、高翻也加上、安排下一次并同步App且保留历史；训练日期本人另明确为'+day.isoformat()+'。只追加本日，不续排、不替代旧日程。'
guidance='C1确认版：高翻在前，随后四腿动作与核心，6动作20计划组位置，其中4技术＋13常规下肢＋3核心；热身另计。计划数字不等于实际完成，真实重量/次数/RIR由本人训练时填写。\n'+c['generalWarmup']+'\n'+c['generalStop']+'\n'+c['feedingException']+'\n'+c['progression']+'\n原90分钟边界保留：按约80–90分钟预算准备，必要休息不压缩；器械等待/热身延长导致到达上限则如实保留未完成，不强凑。110/115/55只在当次首组余力和质量支持且存在相应档位时采用；不把新增档视为已跨课达标。\n单哑铃扶架沿本人熟悉做法，不改同/对侧身份。机器数字沿原机显示，不换算别机或添加未知杆重/空载阻力。'
lines=['# C1主方案＋高翻：已确认单日训练','训练日：'+day.isoformat()+'；时区Asia/Shanghai。','偏好TP-20261021-06；方法METHOD-20261023-09；力量档案STR-20261025-07；默认场景CONTEXT-PREF-20261025-01。',confirmation,guidance]
for i,e in enumerate(entries):
    lines += ['## '+str(i+1)+'. '+e['displayName'],e['loadGuidance'],e['notes']]
    for s in e['plannedSets']:
        p=s['prescription'];rr=str(p.get('rirLower','技术/质量'))+'–'+str(p.get('rirUpper','技术/质量'))
        load = '自重' if e['volumeUnit']=='count' else str(s['weight'])
        lines.append(p['label']+'：'+load+' × '+str(p['repsLower'])+'–'+str(p['repsUpper'])+'；RIR/质量 '+rr+'；休息'+str(p['restLowerSeconds'])+'–'+str(p['restUpperSeconds'])+'秒。'+p['effortCue'])
source='\n\n'.join(lines)+'\n'
packet={'version':1,'id':str(intent),'localDay':day.isoformat(),'timeZoneIdentifier':'Asia/Shanghai',
 'title':'腿＋核心 · C1＋高翻','preferenceRevisionCode':'TP-20261021-06',
 'confirmedAt':dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).replace(microsecond=0).isoformat(),
 'confirmationReference':confirmation,'sourceMarkdown':source,'sourceSHA256':hashlib.sha256(source.encode()).hexdigest(),
 'guidance':guidance,'exercises':entries}
target=OUT/(day.isoformat()+'.json')
if target.exists():
    previous=json.load(open(target));packet['confirmedAt']=previous['confirmedAt']
    assert previous==packet,'Prepared identity already bound to different content; stop'
else:
    target.write_text(json.dumps(packet,ensure_ascii=False,indent=2)+'\n')
(ROOT/'outputs/training-plan/2026-10-25-c1-clean-confirmed.md').write_text(source)
manifest={'status':'CONFIRMED_PREPARED_NOT_APPLIED','id':packet['id'],'localDay':packet['localDay'],
 'source':str(target.relative_to(ROOT)),'transportSHA256':hashlib.sha256(target.read_bytes()).hexdigest(),
 'sourceSHA256':packet['sourceSHA256'],'exercises':6,'plannedSetPositions':20,'technicalSets':4,'legWorkSets':13,'coreSets':3,
 'actualSessionsCreated':0,'deviceWritten':False,'requiresFreshPhonePreview':True}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print(json.dumps(manifest,ensure_ascii=False))
