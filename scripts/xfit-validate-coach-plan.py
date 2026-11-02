#!/usr/bin/env python3
"""Read-only review of normal coach proposals against the project's confirmed personal constraints.

This validates structure and stated time assumptions, never acceptance, physiology or permission to import.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parent.parent

def validate(plan, preferences):
    errors=[];sessions=[]
    if plan.get('preferenceVersion')!=preferences['version']:
        errors.append('候选未绑定当前整课偏好版本')
    if not plan.get('sessions'):
        errors.append('缺少候选场次')
    for session in plan.get('sessions',[]):
        key=session.get('key','unknown');items=session.get('exercises',[])
        issues=[]
        formal=[e for e in items if e.get('category') in ('resistance','core','technical')]
        if len(formal)!=len(items): issues.append('正式菜单混入热身/未知分类，不能凑动作数')
        if not preferences['formalExercisesMin']<=len(formal)<=preferences['formalExercisesMax']:
            issues.append(f"正式动作{len(formal)}，应为{preferences['formalExercisesMin']}—{preferences['formalExercisesMax']}")
        ids=[e.get('catalogExerciseID') for e in formal]
        if not all(ids):issues.append('存在尚未登记/绑定的精确动作身份，不能生成手机导入包')
        known_ids=[i for i in ids if i]
        if len(known_ids)!=len(set(known_ids)):issues.append('重复动作凑数')
        primary=[e for e in formal if e.get('category')=='resistance' and e.get('primaryTarget') is True]
        if len(primary)<preferences['primaryResistanceExercisesMin']:issues.append('目标主肌群抗阻动作不足')
        roles={e.get('loadRole') for e in formal if e.get('category')=='resistance'}
        if not set(preferences['requiredResistanceLoadRoles'])<=roles:issues.append('常规抗阻缺少重/中/轻任务')
        overhead=session.get('generalWarmupSeconds');buffer=session.get('bufferSeconds')
        if not isinstance(overhead,(int,float)) or not math.isfinite(overhead) or overhead<0 or not isinstance(buffer,(int,float)) or not math.isfinite(buffer) or buffer<=0:
            issues.append('缺少一般热身或正数缓冲预算');overhead=0;buffer=0
        seconds=overhead+buffer;counts={'resistance':0,'core':0,'technical':0};timings=[]
        for e in formal:
            name=e.get('displayName','unknown');sets=e.get('plannedSets',[])
            minimum=preferences['prioritySetsMin'] if e.get('priority') else preferences['regularSetsMin']
            if e['category']!='technical' and len(sets)<minimum:issues.append(name+'工作组不足')
            if not sets:issues.append(name+'没有逐组计划')
            if not e.get('task') or not e.get('evidenceNote') or not e.get('loadGuidance'):issues.append(name+'缺少任务/负重依据/计量说明')
            timing=e.get('timeEstimate',{});required=('setSeconds','warmupSeconds','transitionSeconds')
            if not all(isinstance(timing.get(k),(int,float)) and math.isfinite(timing[k]) and timing[k]>=0 for k in required) or timing.get('setSeconds',0)<=0:
                issues.append(name+'缺少完整执行/热身/换器械估时');continue
            if any(s.get('repsSide')=='single' for s in sets) and timing.get('includesBothSides') is not True:
                issues.append(name+'单侧估时未包含双侧与换侧')
            pauses=[]
            for s in sets:
                p=s.get('prescription',{})
                if not all(k in p for k in ('repsLower','repsUpper','restLowerSeconds','restUpperSeconds')):
                    issues.append(name+'缺少逐组范围或休息');continue
                if not 1<=p['repsLower']<=p['repsUpper'] or not 0<=p['restLowerSeconds']<=p['restUpperSeconds']:
                    issues.append(name+'逐组目标无效')
                if e.get('volumeUnit')=='second' and timing['setSeconds']<p['repsUpper']:
                    issues.append(name+'计时组执行估时短于目标')
                pauses.append(p['restUpperSeconds'])
            duration=len(sets)*timing['setSeconds']+sum(pauses[:-1])+timing['warmupSeconds']+timing['transitionSeconds']
            seconds+=duration;counts[e['category']]+=len(sets)
            timings.append({'exercise':name,'estimatedSeconds':duration})
        if seconds>preferences['sessionMinutesMax']*60:issues.append(f"估时{seconds/60:.1f}分钟超过{preferences['sessionMinutesMax']}分钟")
        sessions.append({'key':key,'formalExercises':len(formal),'primaryExercises':len(primary),'plannedGroups':counts,
            'estimatedMinutes':round(seconds/60,2),'timeBasis':'计划休息上限+显式每组执行/专项热身/换器械+一般热身+缓冲；未验证实际速度/等待',
            'timings':timings,'status':'FAIL' if issues else 'PASS_STRUCTURE_ONLY','issues':issues})
        errors.extend(key+'：'+s for s in issues)
    return {'status':'FAIL' if errors else 'PASS_STRUCTURE_ONLY','preferenceVersion':preferences['version'],
        'phoneWriteAuthorized':False,'humanAcceptance':'NOT_RUN','sessions':sessions,'errors':errors}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('plan',type=Path)
    ap.add_argument('--preferences',type=Path,default=ROOT/'docs/training/用户训练偏好.md')
    ap.add_argument('--json-output',type=Path);args=ap.parse_args()
    text=args.preferences.read_text()
    block=re.findall(r'<!-- xfit-coach-session-constraints -->\s*```json\s*([\s\S]*?)\s*```',text)
    if len(block)!=1:raise ValueError('偏好文件须有且只有一个整课机器校验块')
    result=validate(json.loads(args.plan.read_text()),json.loads(block[0]))
    if args.json_output:
        args.json_output.parent.mkdir(parents=True,exist_ok=True)
        args.json_output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2));return 1 if result['errors'] else 0

if __name__=='__main__':
    try:sys.exit(main())
    except (ValueError,KeyError,TypeError,OSError) as e:raise SystemExit(str(e))
