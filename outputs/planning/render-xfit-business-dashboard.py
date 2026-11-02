#!/usr/bin/env python3
"""Render the requested R4 planning draft; does not run tasks or access App data."""
import json
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'outputs/planning'
d = json.loads((BASE / 'xfit-business-dashboard.json').read_text())
tasks = d['tasks']
ids = {t['id'] for t in tasks}
required = 'id branch title priority status purpose scenario decision tradeoff not_now inputs output exit evaluation depends_on trigger stop_or_reopen evidence workflow owner authorization'.split()
assert len(tasks) == len(ids) == 17
for t in tasks:
    assert all(k in t and (t[k] or k == 'depends_on') for k in required), t['id']
    assert set(t['depends_on']) <= ids
    assert t['priority'] in ('P0', 'P1', 'P2')
    for e in t['evidence']:
        assert (ROOT / e).exists(), e
visiting, visited = set(), set()
def visit(k):
    assert k not in visiting, 'dependency cycle: ' + k
    if k in visited:
        return
    visiting.add(k)
    for dep in next(t for t in tasks if t['id'] == k)['depends_on']:
        visit(dep)
    visiting.remove(k)
    visited.add(k)
for k in ids:
    visit(k)
assert d['approval'] in ('pending_user_confirmation', 'confirmed')
approved = d['approval'] == 'confirmed'
assert d['facts']['local']['review_resolved'] + d['facts']['local']['review_pending'] == 348
assert 976 + 348 == d['facts']['local']['catalog_total']
counts = Counter(t['status'] for t in tasks)
def table(headers, rows):
    def cell(v):
        return str(v).replace('|', '／').replace('\n', ' ')
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join('---' for _ in headers) + ' |'] + ['| ' + ' | '.join(cell(v) for v in row) + ' |' for row in rows])
def refs(paths, local):
    return '；'.join(f'[{Path(p).name}]({ROOT / p})' if local else f'`{p}`' for p in paths)

def overview():
    phone = d['facts']['phone']
    history = d['facts']['history']
    usage = d['facts']['usage']
    delivery = d.get('phone_delivery')
    local_delta = d['facts']['local'].get('current_delta')
    data_limit = ('本批安装及测试后已对照当前手机备份；' if delivery and delivery.get('status') == 'installed_data_verified' else '本批安装前另读当前手机；') + f"原图样本{history['photo_samples']}，不作有图恢复证明"
    if local_delta:
        data_limit = f"本轮本地主/共享设置原样保持；手机沿用上次交付证据。原图样本{history['photo_samples']}，不作有图恢复证明"
    full = delivery.get('non_device', {}) if delivery else {}
    if full:
        full_label = delivery['target_version'] + '完整本地复验'
        ui_value = f"{full['ui_pass']}通过/{full['ui_skip']}原跳过" if full.get('ui_status') == 'PASS' else full.get('ui_status', 'unknown')
        full_value = f"{full.get('passed_gates', 'unknown')}/{full.get('total_gates', 8)}门；单元{full.get('unit_pass', 'unknown')}通过；UI{ui_value}"
        full_limit = '首轮原失败保留；当前结果见本批统一入口证据，不能用定向6/6替代完整回归'
        if local_delta:
            full_label += '（已交付历史批）'
            full_limit = '该完整结果属于已交付手机版本；本轮后续本地资源增量仅执行相关18服务＋5独立UI，不冒充再跑全量'
    else:
        full_label, full_value, full_limit = 'Build32完整本地层（历史）', '8/8门；单元500通过；UI161通过/8原跳过', '该批历史证据，不冒充后续增量门禁'
    unit = f"单元{phone['unit_pass']}通过/{phone['unit_existing_skip']}原跳过" if phone.get('unit_pass') is not None else '本次单元' + phone.get('unit_status', 'NOT_RUN')
    o = [
        '## 当前项目dashboard · R4整体规划待确认',
        '**业务目标：**' + d['objective'],
        '**现在在做：**本轮动作核查已完成本地交付，正在把全项目目标、真实进度和下一出口整理到原固定工作台；本轮不继续无增量批量搜索，不操作手机或训练数据。',
        '**规划状态：**3个业务目标／6个工作分支／17个叶子任务，整体待本人确认。以下是承接现状，不能合成项目完成率。',
        table(['任务现状', '数量', '解释'], [(k, counts[k], {'已交付证据':'能力或方法已有证据，人工接受/效果另算','待真实输入':'已有记录可先读取，缺指定意图/恢复或自然使用样本','本地就绪':'新增目录增量未交付手机','条件候选':'保留全队列，真实需求/证据触发','待前置':'依赖完整提案及具体确认','草案就绪':'本轮规划尚待整体确认','方法可用':'复用方法已有，真实收益尚缺比较'}[k]) for k in ['已交付证据','本地就绪','草案就绪','方法可用','待真实输入','待前置','条件候选']]),
        table(['独立证据口径', '当前数字/状态', '尚缺什么'], [
            ('手机最后已证交付',f"{phone['version']}；{phone['review_pending']}待核",delivery['next_gate'] if delivery else '后续本地增量未上手机；不是实时读机'),
            ('本地动作库',f"{d['facts']['local']['catalog_total']}来源；原{d['facts']['local']['review_initial']}疑点解除{d['facts']['local']['review_resolved']}（{d['facts']['local']['review_resolved'] / d['facts']['local']['review_initial']:.2%}），剩{d['facts']['local']['review_pending']}",'976原未标疑点不等于新核实；不追求为清零而猜测'),
            ('Notes实际','10动作48/48条完整，重复新增0','RIR/热身性质/时长未知不填；R6原稿及skipped保持'),
            ('记录规模',f"{usage['sessions_total']}场={usage['sessions_completed']}完成+{usage['sessions_discarded']}丢弃；{usage['set_rows_total']}组记录={usage['set_rows_completed']}完成+{usage['set_rows_incomplete']}未完成",'完成行不是有效工作组，不据此算坚持率'),
            ('数据保护',f"最近已证{history['tables']}表{history['business_rows']}行业务字段/UUID关系、{history['non_database_files']}文件守恒",data_limit),
            (full_label,full_value,full_limit),
            ('手机自动化',unit+f"；UI实际{phone['ui_executed']}、{phone['ui']}",'原始失败保留；完整UI专项须新定位证据和明确恢复才重开'),
            ('本人验收',phone['human'],'按当前需求AC映射；旧清单Build11表头不作新分母'),
            ('业务效果','K1/K2/O1基线unknown；K3历史已证1次、R4未启动、覆盖分母unknown','真实尝试分母、可比负担、具名复盘与恢复/身体样本'),
            ('旧阶段','调整范围已收尾，必办0；历史总账7/8','不当全项目87.5%，不自动重开T7或已取消事项')
        ]),
        '**证据新鲜度：**' + d['facts']['evidence_as_of'],
        '**下一出口（待整体确认）：**先从已有已完成记录和下一条自然反馈定位A4/C2所需输入，只补影响决定的缺项；形成真实任务基线和可审阅的下一次候选。B2已可审阅，需要手机再具体授权；B3保留330队列，按已练相关与新证据批次启动。',
        '**计划不按日期排程。**P0是护栏/真实关键故障优先，不表示当前存在故障；P1是当前结果；P2是条件增强。授权、真实输入、证据门决定是否启动。'
    ]
    if approved:
        o[0] = '## 当前项目dashboard · R4已整体确认'
        o[2] = '**当前结果：**' + d['current_iteration'].get('headline', '已有训练复盘与下一次完整腿＋核心C1候选已形成，具体方案待本人确认。未写App或手机，UI/历史保持。') + ('\n\n**最近手机交付（独立批次）：**' + delivery['summary'] if delivery else '')
        o[3] = '**规划状态：**3个业务目标／6个工作分支／17个任务已整体确认；任务现状为证据分布，不合成业务效果完成率。'
        o[4] = table(['任务现状','数量','解释'], [(k, counts[k], {'已交付证据':'能力、方法或已确认方案已有交付证据，人工/应用/效果另算','本地就绪':'B2目录增量已就绪，手机交付另核授权及原门','方法可用':'复用方法已有，真实收益待比较','待真实输入':'自然真实使用/可比效果仍缺样本','待前置':'C3依当前确认、日期和设备状态恢复；见下一出口','条件候选':'保留队列，按证据/真实启用触发'}[k]) for k in ['已交付证据','本地就绪','方法可用','待真实输入','待前置','条件候选'] if counts[k]])
        o[5] = o[5].replace('K1/K2/O1基线unknown；K3历史已证1次、R4未启动、覆盖分母unknown', 'K1/K2/O1基线unknown；' + next(m['baseline'] for m in d['metrics'] if m['id']=='K3'))
        c = d['current_iteration']
        o[7] = '**首轮复盘与下一出口：**' + c['observed'] + ' ' + c['owner_feedback'] + ' ' + c['proposal'] + ' ' + c['stage_counts'] + ' 下一步：' + c['next']
        o.insert(8, '**动作库本轮相关检查：**' + c['catalog'])
    return '\n\n'.join(o)

def render(local):
    o = [overview(), '## 1. 整体目标与范围', d['user'], d['scope'], d['date_policy']]
    for g in d['goals']:
        o += [f"### {g['id']} {g['title']}", f"目的/场景效果：{g['effect']} 指标：{'、'.join(g['metrics'])}。收敛：{g['exit']}"]
    o += ['## 2. 业务指标与护栏',d['metrics_definition_note']]
    for m in d['metrics']:
        o += [f"### {m['id']} {m['name']}（{m['type']}）", f"定义：{m['formula']}\n\n基线：{m['baseline'] if m['baseline'] is not None else 'unknown，缺真实可比较分母/样本'}。目标/收敛：{m['target']}\n\n采集/负责：{m['collection']}／{m['owner']}。限制：{m['limitation']}"]
    o += ['## 3. 任务树与每项收敛合同', '以下任务状态描述目前证据，不等于R4新执行授权。每个任务引用原需求，不放宽原AC。短暂等待不需要重建背景或产生新任务ID。']
    for b in d['branches']:
        o += [f"### {b['id']}. {b['title']} → {b['goal']}", f"目的：{b['purpose']} 阶段决定：{b['decision']} 取舍：{b['tradeoff']} 阶段出口：{b['stage_exit']}"]
        bt = [t for t in tasks if t['branch'] == b['id']]
        o += [table(['任务','优先级/现状','直接前置（集合）','下一触发'],[(t['id']+' '+t['title'],t['priority']+'／'+t['status'],'、'.join(t['depends_on']) or '无',t['trigger']) for t in bt])]
        for t in bt:
            o += [f"#### {t['id']} {t['title']}",
                  f"目的/原因：{t['purpose']} 场景/预期：{t['scenario']}",
                  f"采用的decision：{t['decision']} 取舍：{t['tradeoff']} 未来可试但现在不做：{t['not_now']}",
                  f"输入：{t['inputs']} 输出：" + ('`'+t['output']+'`' if not local and t['output'].startswith(('outputs/', 'artifacts/')) else t['output']),
                  f"收敛条件：{t['exit']} 评估：{t['evaluation']}",
                  f"优先级/现状：{t['priority']}／{t['status']}。前置集合：{'、'.join(t['depends_on']) or '无'}；关系：{t['dependency_mode']}；工作流：{t['workflow']}。负责：{t['owner']}。触发：{t['trigger']}",
                  f"停止/重开：{t['stop_or_reopen']} 权限：{t['authorization']}",
                  '依据：' + refs(t['evidence'], local)]
    o += ['## 4. 依赖、优先级与阶段门', d['dependencies']]
    o += [table(['顺位','任务','采用原因'],[(p['rank'],'、'.join(p['tasks']),p['rule']) for p in d['priorities']])]
    o += [table(['阶段门（非日期）','收敛出口'],[(m['id']+' '+m['name'],m['exit']) for m in d['milestones']])]
    o += ['## 5. 可循环业务workflow与升级口径']
    for w in d['workflows']:
        o += [f"### {w['id']} {w['name']}",f"触发：{w['trigger']}。流转：{w['steps']}。退出：{w['exit']}。业务/框架优化：{w['upgrade']}"]
    f = d['feedback_contract']
    o += ['## 6. 数据、Skill、问题与经验怎样持续调用', f['event'], '最小反馈字段：'+'、'.join(f['minimum_fields'])+'。', f['ownership'],f['updates'],f['evaluation'],f['unvalidated']]
    o += [table(['复用Skill','业务调用','何时改方法'],[(s['entry'],s['use'],s['change_gate']) for s in f['skill_inventory']])]
    for l in d['lessons']:
        o += [f"### {l['id']} {l['kind']}", f"事实：{l['fact']} 可调用规则：{l['rule']} 边界：{l['boundary']}\n\n依据：{refs([l['source']],local)}"]
    o += ['## 7. 已确认决定与本轮建议的差异']
    o += [table(['ID/状态','决定','tradeoff','改判/重开'],[(x['id']+'／'+x['state'],x['choice'],x['tradeoff'],x['reopen']) for x in d['decisions']])]
    o += ['## 8. 方法依据、尚未验证的尝试与反证']
    r = d['research_contract']
    o += [f"研究问题/用途：{r['question']} 类型：{r['type']}；证据等级：{r['assurance']}。排除：{r['exclusions']}。", f"最强反证/替代解释：{r['counter_evidence']} 结论上限：{r['conclusion_ceiling']}"]
    for m in d['methods']:
        o += [f"### {m['id']} {m['name']}", f"状态：{m['status']}。本项目用法：{m['application']} 阅读范围：{m['read_scope']}。局限/利益关系：{m['limit']}\n\n来源：[{m['name']}]({m['source']})"]
    for h in d['experiments']:
        o += [f"### {h['id']} {h['state']}",f"预测：{h['hypothesis']} 最小尝试：{h['test']} 指标：{h['metrics']} 停止/回退：{h['stop']} 结论上限：{h['ceiling']}"]
    state = '当前状态：**confirmed／R4整体已确认**。' + d['current_iteration'].get('headline', '') + ' 旧R3/cycle保留。' if approved else '当前状态：**pending_user_confirmation／整体待确认**。本轮准备看板不代表17项新增执行已开始；未改App/UI/手机、训练/历史数据或全局Skill。旧R3及原cycle保持历史来源。'
    o += ['## 9. 整体确认与本轮交付边界',d['confirmation']['question'], d['confirmation']['limits'], state]
    return '\n\n'.join(o)+'\n'

(BASE/'xfit-business-task-tree-r4.md').write_text(('# X-Fit 业务目标与可收敛任务树 R4（已整体确认）' if approved else '# X-Fit 业务目标与可收敛任务树 R4（整体待确认）')+'\n\n'+render(True))
(BASE/'xfit-business-dashboard.notion.md').write_text(overview()+'\n\n详细17任务的目的/决定/取舍/未来方向/出口/指标/依赖/反馈，见原规划页的“R4整体规划”段。原R3、旧阶段与三库保留。\n\n<mention url="https://app.notion.com/p/3f74c857b83480048a2dca7863ccfc2b" />\n\n## 以下为历史阶段记录（保留，不代表当前版本）\n')
(BASE/'xfit-business-task-tree-r4.notion.md').write_text(('## R4整体规划（已确认，首轮复盘候选已形成）' if approved else '## R4整体规划草案（待本人整体确认）')+'\n\n'+render(False)+'\n\n## 以下保留原R3及已关闭阶段全文\n')
print(json.dumps({'approval':d['approval'],'leaves':len(tasks),'branches':len(d['branches']),'goals':len(d['goals']),'task_statuses':dict(counts),'dependency_cycle':False,'missing_contract_fields':0,'missing_evidence_paths':0,'outputs':['xfit-business-task-tree-r4.md','xfit-business-dashboard.notion.md','xfit-business-task-tree-r4.notion.md']},ensure_ascii=False,indent=2))

# Notion uses native tables and indented toggle children. Keep local Markdown plain.
import re
def notion_native(text):
    text = text.replace('<mention url=', '<mention-page url=').replace('**', '')
    lines = text.splitlines()
    out, i = [], 0
    while i < len(lines):
        if lines[i].startswith('| ') and i + 1 < len(lines) and re.match(r'^\|[\s|:-]+\|$', lines[i+1]):
            rows = [lines[i]]
            i += 2
            while i < len(lines) and lines[i].startswith('| '):
                rows.append(lines[i]); i += 1
            out.append('<table fit-page-width="true" header-row="true">')
            for row in rows:
                out.append('\t<tr>')
                for cell in row.strip().strip('|').split('|'):
                    out.append('\t\t<td>' + cell.strip().replace('&','&amp;').replace('<','&lt;').replace('>','&gt;') + '</td>')
                out.append('\t</tr>')
            out.append('</table>')
        else:
            out.append(lines[i]); i += 1
    text = '\n'.join(out)
    # Each task and long reference section is collapsed until requested.
    text = re.sub(r'^#### ([^\n]+)\n(.*?)(?=^#### |^### |^## |\Z)', lambda m:'<details>\n<summary>'+m[1]+'</summary>\n'+ '\n'.join('\t'+s if s else '' for s in m[2].strip().splitlines())+'\n</details>\n\n', text, flags=re.M|re.S)
    text = re.sub(r'^## ([1-9]\. [^\n]+)\n(.*?)(?=^## |\Z)', lambda m:'<details>\n<summary>'+m[1]+'</summary>\n'+ '\n'.join('\t'+s if s else '' for s in m[2].strip().splitlines())+'\n</details>\n\n', text, flags=re.M|re.S)
    # The live writer now canonicalizes legacy details/summary as toggle and
    # mention-page as mention; use that documented migration format directly.
    text = re.sub(r'(?m)^(\t*)<details>\n\1<summary>([^\n]+)</summary>\n', lambda m:m[1]+'<toggle>\n'+m[1]+m[2]+'\n\n', text)
    text = text.replace('</details>', '</toggle>').replace('<mention-page ', '<mention ')
    return text+'\n'
for name in ['xfit-business-dashboard.notion.md','xfit-business-task-tree-r4.notion.md']:
    p=BASE/name
    p.write_text(notion_native(p.read_text()))
assert len(re.findall(r'<toggle>\n\t*[A-F][1-4] ', (BASE/'xfit-business-task-tree-r4.notion.md').read_text())) == 17
