# 需求：低频计划调整收进管理安排并交付模拟器预览

- 需求 ID：`REQ-20261022-153912`
- 创建时间：`2026-10-22 15:39:12 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-10-22 本轮用户直接确认；消息未提供精确时刻`
- 用户确认摘要：`按已展示的管理入口预览实施：首页移除调整计划，操作收进对应计划的管理安排，其他页面风格与布局保持，完成后先展示模拟器。`
- 状态：`真机待验收`
- 关联需求：`2026-10-19/230503_home-date-training-menu.md`；`2026-10-20/222819_monthly-schedule-graphic-status.md`；`2026-10-21/103533_pyramid-history-training-experience.md`
- 目标版本/阶段：0.5.0局部实现及模拟器预览；后续用户明确确认手机体验覆盖更新，目标Build 27；不宣称完整阶段固化。

## 用户原始需求

> 这版可以，就按这个方案改到 App 里：首页去掉“调整计划”，相关操作收进对应计划的“管理安排”，其他页面风格和布局保持不变，做好后先给我看模拟器效果。

确认预览：`/Users/edward/.codex/visualizations/2026/10/22/01a16249-fb71-7083-9332-54c277814ee4/xfit-plan-management-preview.html`。

### 后续手机交付确认（2026-10-22）

> 这版可以，帮我更新到手机上，保留现有的训练数据和记录。

- 用户已确认本轮模拟器方案，并明确授权向Edward_iPhone覆盖更新。此补充沿用同一需求文件；不重新征询已给出的安装授权。
- 手机当前只读回读为0.5.0(26)，设备在线但初次检查锁屏；请本人解锁，构建准备继续。以安装前新鲜手机活动数据为基准，不向手机回传模拟器数据库。
- 使用既有统一device入口，开启覆盖安装，关闭真机fixture/XCTest；本轮为手机体验交付，完整阶段仍PARTIAL，真人功能体验留本人验收。

## 目标

- 首页不再常驻调整计划；沿用日期行进入训练菜单，经该场计划原位置的管理安排直接改期、跳过/恢复或进入已有内容编辑。
- 改期先预览及冲突校验；保存回到原日期菜单，显示结果、查看及撤销。具体UUID隔离，已开始/实际数据保护。
- 主模拟器保留真实手机持久副本并普通启动；提供真实原生截图。独立模拟器验证会产生写入的操作。
- 后续已确认手机交付：以手机当前活动数据为基准备份，覆盖安装相同功能的签名版本，回读版本和全部原记录。

## 非目标与边界

- 2026-10-23局部替代：用户明确确认过去尚未开始待练计划增加首页直接改期入口，仅该入口限制由[REQ-20261023-112357](../2026-10-23/112357_past-pending-reschedule.md)替代；本需求其他管理规则、数据保护和历史验收保持原范围。
- 不改页面视觉系统、导航、月历/记录布局；不自动顺延整周、不自动重排处方，不向手机回传模拟器数据、不修改Notion或长期偏好。
- 最初预览阶段不安装手机；后续明确授权后增加手机覆盖更新及数据回读。真机fixture/XCTest、提交/tag/发布仍不执行；本轮不是完整阶段验收，不因局部通过标GO。
- 保留原工作区既有修改。手机最近副本来自2026-10-21安装后只读快照，11:44:51为刷新批次，精确手机捕获时刻未知；不宣称实时同步。

## 开发前事实（本轮只读检查）

- 首页存在直达编排器的独立调整行；TrainingDateMenuView管理安排原本跳转日程单条，再长按操作。
- 通用改期会改变当前日期；单日/整周确认导入都对排期日期做完整性校验，兼容合法改期必须一并验证。
- 现有编排器保存可能处理同日多个力量计划；本次编辑必须收窄到选定UUID。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 首页移除独立调整行，其余视觉/入口保持 | P1 | SIM-UI/原生截图 | 日期行、开始、原周历/导航可达 |
| AC-02 | 对应计划管理安排直接打开操作菜单 | P1 | SIM-UI | 正确标题/UUID；日期、跳过/恢复、已有编辑入口可达 |
| AC-03 | 改期冲突预览、取消与保存 | P0 | SERVICE/SIM-UI | 撞期不静默合并；仅目标计划变化；原日期菜单保留 |
| AC-04 | 跳过、恢复及撤销 | P0 | SERVICE/SIM-UI | 状态真实，撤销不覆盖后续开始/修改；失败回滚 |
| AC-05 | 已确认导入与单场编辑兼容 | P0 | UNIT/SERVICE | 原始确认来源/旧实际保留；合法改期仍回读/幂等，非法漂移拒绝；同日其他场不变 |
| AC-06 | 已开始/实际训练保护 | P0 | SERVICE/SIM-UI | 日期/跳过禁止；实际日期、完成组与历史不变 |
| AC-07 | 主预览覆盖、普通启动与真实数据守恒 | P0 | SIM-INSTALL/SIM-DATA/截图 | 不卸载清容器、不写fixture；旧业务逐字段保留，云同步关闭 |
| AC-08 | 已确认候选包覆盖到手机并普通启动 | P0 | PACKAGE/DEVICE-INSTALL/RUNTIME | 签名与App Group保持；0.5.0(26)→(27)，无测试参数，安装/版本/进程独立回读 |
| AC-09 | 手机当前全部训练数据与记录保留 | P0 | DEVICE-DATA | 安装前新鲜备份、quick_check；全部原字段/UUID/关系/快照及资源不变，不卸载/不清空 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 原首页调整行与本次低频入口方案 | 入口位置 | 是否移除首页行 | 用户明确要求本次移除并收进管理安排 | 已确认本轮范围；保留旧需求验收历史 |
| C-02 | 原日期完整性封印与合法手动改期 | 回读/重复导入 | 不涉及新处方取舍 | 保留原确认包与seal，合法调整追加来源链；回读倒放验证原内容 | 已实现；来源、防重、备份回归PASS |
| C-03 | 原同日编排保存与本次对应计划操作 | 同日其他场保护 | 不涉及新业务取舍 | 按已确认单场语义限定UUID，复制本场模板 | 已实现；同日其他场和历史隔离PASS |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02 | EditorialHomeViews.swift；TrainingDateMenuView.swift | TrainingDateMenuUITests；主预览10/23原生核对 | PASS |
| AC-03/04/06 | ScheduleService.swift；ScheduleView.swift共享改期表单 | 来源/管理服务回归及UI操作 | PASS；已开始保护由服务测试验证 |
| AC-05 | ConfirmedDailyTrainingPlanService.swift；ConfirmedTrainingPlanService.swift；DailyPlanService.swift；DailyWorkoutBuilderView.swift | ConfirmedTrainingPlanTests | PASS |
| AC-07 | artifacts/plan-management/20261022-153912/preview_delivery.py；原App Group副本 | 签名/权限、逐字段/原图比较、原生截图 | PASS |
| AC-08 | 既有xfit-stage-validation.sh device；隔离Build 27工程 | 双包签名、profile、覆盖安装及独立版本/进程回读 | PASS；手机0.5.0(27)运行 |
| AC-09 | artifacts/stage-validation/20261022-plan-management-phone/verify_delivery.py | 本轮新鲜pre/post备份逐字段与全部非数据库文件核对 | PASS；25表2399条原业务记录及4份非数据库文件完全一致 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01/02 / 主预览原生核对 | 首页删除独立调整行，原日期/周历/导航保留；管理入口位置保持 | 10/23肩＋三头首页和计划菜单已查看；对应UUID直接打开操作弹层 | PASS | outputs/test-results/20261022-plan-management/main-home.png；main-date-menu.png；main-management.png | 主预览实际数据，非fixture |
| AC-03至06 / UNIT与SERVICE | 合法改期、封印/防重、单场编辑、实际保护、失败回滚与冲突正确 | 40项确认计划测试＋4项既有改期/跳过/跨时区回归，共44项通过 | PASS | outputs/test-results/20261022-plan-management/unit-final-summary.json；unit-r3.log | 服务在此后未修改；后续只统一新增UI的日期显示语言 |
| AC-02至04 / 独立模拟器UI | 默认和最大字号完整执行取消/编辑取消/跳过/撤销/恢复/改期预览取消/改期保存/查看/撤销 | 2条完整流程全部通过；同一UUID及1200次原目标保留 | PASS | outputs/test-results/20261022-plan-management/ui-final-summary.json；ui-r3.log；ui-final-attachments/manifest.json | 最终UI源码；测试数据仅独立模拟器 |
| AC-07 / SIM-INSTALL与SIM-DATA | 主预览覆盖、普通启动、业务字段和原图不变 | App/分享扩展App Group权限及签名通过；25表2399条业务记录逐字段、ID、关系和资源一致；56次训练/1343组/60安排保留，云同步关闭 | PASS | outputs/test-results/20261022-plan-management/delivery.json；post-preview-data.json | 无卸载/清容器；无测试启动参数；手机读写0 |
| AC-03/07 / 主预览只读演示 | 能到达确认页，取消后不改真实安排 | 10/23肩＋三头预览改至10/24，取消后仍在10/23；主预览最后停首页 | PASS | outputs/test-results/20261022-plan-management/main-date-preview.png；post-preview-data.json | 确认页未保存；实际写入流程由独立模拟器覆盖 |
| 预览阶段手机/本人验收（历史） | 独立验收 | 当时未执行；后续安装见下方 | NOT_RUN | 本文件及validation.json | 该行保留原模拟器交付边界 |
| AC-08 / PACKAGE/DEVICE-INSTALL/RUNTIME | 已确认源、双包权限和签名一致，覆盖更新并普通启动 | 127项已确认输入一致，仅隔离工程Build 25→27；手机26→27，启动PID10253独立回读成功，无测试参数 | PASS | outputs/stage-validation/20261022-plan-management-phone/installed-package-verification.json；runtime-verification.json | 不卸载、不清容器；主App/扩展profile均有效且包含原手机 |
| AC-09 / DEVICE-DATA | 新鲜手机副本完整备份，所有原字段及资源保留 | quick_check通过；25表2399→2399，56场/1343组/341动作快照/60安排全部业务字段、PK/UUID/关系/JSON/空值一致；4份非数据库文件哈希一致 | PASS | outputs/stage-validation/20261022-plan-management-phone/data-conservation.json；delivery.json | 新增/改写/丢失业务记录0；不直接写手机SQLite；模拟器数据库未上传 |
| 真机fixture/XCTest与真人体验 | 分别验证 | 本批未运行真机fixture；本人实际功能体验待验收 | NOT_RUN / BLOCKED_HUMAN | docs/releases/0.5.0/2026-10-22-plan-management-phone/阶段固化测试计划.md | 手机交付PASS；完整阶段PARTIAL，不标GO |

## 已执行动作

- 核对当前代码、相关需求及主/测试模拟器；记录用户确认；独立Worker只读检查服务边界与覆盖入口，Coordinator串行归档、合并与构建/模拟器写入。
- 完成首页入口移除、原管理按钮弹层、改期预览/冲突、跳过/恢复/撤销及定向编辑；保留原页面视觉组件，新增日期文案沿用App中文locale。
- Worker分别实现管理/来源服务与独立UI回归；Coordinator合并、构建、串行执行测试并覆盖主预览。已确认原始Documents目录构建卡在文件协调读取，改用/tmp隔离输入构建并逐文件核对127项App输入。
- 首轮改期日期锚点失败已修复，seal精确断言保留；实际记录fixture的startedAt已校正；系统日期弹层使用实际可访问关闭区。相关失败日志保留，最终回归通过。
- 主预览覆盖前完整备份App、Group和sandbox，覆盖与预览取消后两次字段/资源回读通过；原生截图已检查。未操作手机、Notion、提交、tag或发布。
- 用户后续明确确认手机更新后，冻结相同127项输入，仅隔离工程提升Build至27；双包签名、App Group、profile和云同步关闭检查通过。
- 安装前锁屏检查曾停止一次，未备份/安装/写入数据；用户再次解锁后，统一device入口D00–D06C全部通过，手机覆盖更新及无参数普通启动完成。
- 安装前新鲜手机副本与安装后副本逐字段/资源/非数据库文件比较通过；原2399条业务记录完全保持。手机XCTest未运行，人工体验未代填；未提交、tag或发布。

## 结果与遗留项

- 当前结论：手机交付PASS，状态真机待验收；0.5.0(27)已覆盖安装到Edward_iPhone并普通启动，全部原手机数据保留。交付真源为 `outputs/stage-validation/20261022-plan-management-phone/delivery.json`；原模拟器证据继续保留。入口为首页日期行→对应计划→管理安排。
- 已知限制：两条UI用例在跳绳目标输入时各有一条SwiftUI `Invalid frame dimension`运行时警告，操作断言与截图检查通过，具体来源未定位；不据此声称全App无警告或完成全阶段验收。
- 剩余验证：本批未执行真机fixture/XCTest及全量阶段固化；实际功能手感和系统权限体验由本人验收，不把安装/数据守恒替代人工体验。主模拟器继续保留原只读手机副本，未用它覆盖手机。
