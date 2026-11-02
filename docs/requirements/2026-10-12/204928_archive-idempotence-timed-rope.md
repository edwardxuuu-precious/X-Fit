# 需求：归档启动幂等与计时跳绳未知次数

- 需求 ID：`REQ-20261012-204928`
- 创建时间：`2026-10-12 20:49:28 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：本轮回复“好的 你可以推进”；精确消息时间未提供。上述创建时间只为归档时间。
- 用户确认摘要：`本人对上轮具名两项规则回复“好的 你可以推进”：归档内容不变不刷新更新时间；计时跳绳次数可未知。仅最小修复及原分层验证，不改已确认R1或历史实际。`
- 状态：`本地已验证`
- 关联需求：REQ-20261010-160518、REQ-20261012-151220；原合同及必测门保留。
- 目标版本/阶段：0.5.0(17)新候选，完成本地验证后才集中无线验收。

## 用户原始需求

> 好的 你可以推进。

对应上轮已展示的两项具名规则：归档内容未变化不刷新更新时间；计时跳绳只记时长时，次数保持未知，不补零、不推算。

## 目标

- 重复普通启动不改变已归档深蹲的时间戳、UUID或内容。
- 跳绳可仅保存真实时长，未知次数在记录、摘要和备份恢复中保持未知；完成所选日程，不影响别的日程。

## 非目标与边界

- 不改R1确认包、排期、重量、容量和历史实际；不结束原进行中训练，不重新导入。
- 不猜修未复现的SQLite锁；原完整FAIL保留。旧备份兼容、全部原断言/预算/跳过项保留，手机/真人/效果独立验收。
- 不切共享Notion认证、不搬旧库、不扩大权限、不上传手机实时数据。

## 当前事实

- consolidateConfirmedSquatDuplicate无条件写归档重复项updatedAt；原手机证据只该字段变化。
- JumpRopeEntry.count及快填入口强制计数；R1跳绳代码不符合旧ROPE_路由。通用秒数录入可保存，但不是明确可选次数的跳绳入口。
- 新SDK原完整单元为383 PASS/1 FAIL；原类24项及完整前序139项均未复现，原因unknown；本修复不把它包装为已修复。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 归档内容不变的重复启动幂等 | P0 | SERVICE/DEVICE-DATA | 原UUID、内容、updatedAt不变；初次必要归档仍完成 |
| AC-02 | 计时跳绳个数可未知 | P0 | SERVICE/SIM-UI | 时长可保存、count为nil、所选日程完成；空白全无及非法输入拒绝 |
| AC-03 | 确认计划跳绳入口可达 | P1 | SERVICE/SIM-UI | 无需ROPE_命名前缀也能按关联的准确器械识别跳绳；单车不误判 |
| AC-04 | 摘要、备份及旧数据兼容 | P0 | SERVICE/旧磁盘迁移 | 未知不是0；有次数旧记录/旧备份保持原值，重复恢复新增0 |
| AC-05 | 同候选完整验证、集中手机验收 | P0 | 原统一non-device/device/真人 | 原必测不减、失败不抹；覆盖安装及数据守恒独立通过 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 原跳绳必填次数与仅有时长真实记录 | count模型/入口/备份/摘要 | 是否允许未知 | 本轮确认具名可选次数规则；已知旧次数不改 | 已确认 |
| C-02 | 原归档首次更新时间与重复启动漂移 | 启动归并 | 是否仅内容变化更新时间 | 本轮确认；保留首次归并及历史名称快照 | 已确认 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01 | FitnessApp/Services/ExerciseCatalogService.swift | ScheduleAndDataTests.testStrictSquatConsolidationIsIdempotentRemovesPlanCollisionAndRemapsLogs | 服务RED→GREEN；仅不重复触碰已归档项 |
| AC-02/04 | Models/WellnessModels.swift；Services/DataExportService.swift；Services/FatLossService.swift；Models/FatLossModels.swift；Services/WellnessAgentService.swift | FatLossBackupTests：仅时长恢复、所选日程、旧备份；WellnessAgentTests：未知不补零 | 模型、备份v16及摘要保持nil；旧迁移根因仍unknown |
| AC-02 | FitnessApp/Features/Profile/ProfileView.swift | RedesignUITests.testDurationOnlyJumpRopeCanSaveWithoutAnInventedCount；原取消用例 | 实际2 PASS；记录工具回读次数未知/600秒/900秒 |
| AC-03 | Features/FatLoss/FatLossTrainingView.swift；Features/Today/TodayView.swift；Features/Schedule/ScheduleView.swift | ConfirmedTrainingPlanTests.testConfirmedRopeRouteUsesExactCatalogIdentityRatherThanCodeOrTitle | 真实路由RED→GREEN；整类19 PASS/0 FAIL；不改确认包 |
| AC-05 | 原统一scripts/xfit-stage-validation.sh；原阶段固化测试计划 | 同候选完整non-device；最后集中device/人工 | 完整层尚未执行；原FAIL保留 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01 / SERVICE | 重复归并不改已归档的updatedAt | 原实现1 FAIL；最小修复后1 PASS/0 FAIL | PASS | artifacts/stage-validation/goal-archive-timed-rope-20261012/archive-{red,green}.xcresult | 原重映射、重复菜单与历史断言保留 |
| AC-02/04 / SERVICE | 未知计数、真实时长、仅所选任务、备份重复零 | 缺count实际解码RED；备份GREEN；相关单元33 PASS/0 FAIL | PASS | 同目录rope-backup-{red,green}及rope-ui-related-green.xcresult | 定向证据不替代全量迁移/单元 |
| AC-04 / 日汇总/CSV | 旧时长+未知次数仍有记录；无条目日仍未记录；导出不补0 | 日汇总真实RED；最小修复后整类43 PASS/0 FAIL/0 SKIP | PASS | 同目录rope-legacy-summary-{red,green}.xcresult | 初次新测试误把原CSV带引号空格判为非空，纠正为实际带引号空单元格；不改导出格式或原断言 |
| AC-02 / SIM-UI | 不填次数可保存；真实页面回读；取消可达 | 最新2 PASS/0 FAIL/0 SKIP | PASS | 同目录rope-ui-navigation-green.xcresult及附件manifest | 新用例漏开记录工具的前批FAIL保留；截图/AX定位后仅补真实导航，不改产品数据 |
| AC-03 / SERVICE | 非旧前缀R1按准确动作身份路由 | 真实RED 1 FAIL/3断言；最小修复后整类19 PASS/0 FAIL/0 SKIP | PASS | 同目录rope-route-{red-compiled,green}.xcresult | 两真实页面共用准确ID/跳绳器械/秒单位；旧无ID保留前缀。初次编译失败不计行为RED |
| AC-05 / 完整NON-DEVICE | 同候选原完整范围/预算/跳过项 | 新候选完整统一入口自然终态 N01–N07 PASS；N05 389 PASS/0 FAIL/0 SKIP；N06 118项中111执行通过、7个原跳过、0 FAIL；N07 Release无签名构建PASS | PASS | `outputs/stage-validation/goal-archive-timed-rope-local-fixed-20261013/summary.md`及对应`artifacts/` | 原Build16 SQLite5迁移失败原因仍unknown并保留；本次结果不声称修复旧根因 |
| AC-05 / 真机覆盖安装 | 新候选覆盖、不卸载或清容器 | 无线覆盖安装Build17 0.5.0(17)，启动与版本读回PASS；不卸载、不清容器 | PASS | `artifacts/stage-validation/goal-archive-timed-rope-wireless-retry-20261013/{D05.log,device-app-readback.json}` | 当前手机为该候选；非发布/商店分发 |
| AC-05 / 真机自动化 | 原真机必测全部运行 | 全量真机单元389 PASS、5个既有跳过、0 FAIL；真机UI在两次启动尝试中均约31秒后IDE断开，实际UI用例0，XCTest runner exit74 | BLOCKED_ENV | `artifacts/stage-validation/goal-archive-timed-rope-wireless-20261013/device-ui.xcresult`及`goal-archive-timed-rope-wireless-retry-20261013/device-ui.xcresult` | 设备在线且解锁；第二次仍同阶段失败。停止相同条件盲重试；根因unknown，须先有新的Xcode/设备Runner诊断证据 |
| AC-05 / 解锁后受控复验 | 新鲜在线/解锁条件下完整真机必测 | Run `goal-unlocked-device-recheck-20261013`：D00–D06C PASS；Build17(0.5.0/17)覆盖安装；真机单元392项中387 PASS、5既有SKIP、0 FAIL；D07B仍于Runner启动后约31秒IDE disconnection/exit74、0个UI场景；D07C–D08C恢复与九表/UUID守恒PASS | BLOCKED_ENV | `outputs/stage-validation/goal-unlocked-device-recheck-20261013/summary.md`及`artifacts/stage-validation/goal-unlocked-device-recheck-20261013/device-ui.xcresult` | 解锁、无线在线、destination可用均未改变Runner断连；锁屏/目标不可见不足以解释本次失败。根因仍unknown；无新Xcode/Runner/DTX证据或运行时版本变化前停止同条件重试 |
| AC-05 / Xcode进程活跃条件复验 | 区分IDE进程未启动假设 | Run `goal-xcode-host-ui-device-recheck-20261013`：Build17覆盖安装，D00–D06C/D07C–D08C通过；真机单元387 PASS/5既有SKIP/0 FAIL；D07B日志明确`DTXConnection` peer拒绝`XCTestManager_IDEInterface`，Runner exit74，UI场景0 | BLOCKED_ENV | `outputs/stage-validation/goal-xcode-host-ui-device-recheck-20261013/summary.md`及`artifacts/stage-validation/goal-xcode-host-ui-device-recheck-20261013/D07B.log`、`device-ui.xcresult` | Xcode 27.0进程已运行，但GUI仍显示Welcome，未证明IDE项目测试会话建立；活跃进程本身未解决失败。筛选8分钟本机统一日志无匹配事件。停止同条件重试；需真实IDE会话/Runner日志、可定位host-testmanager/DTX证据或版本变化后重开 |
| AC-01/04/05 / 活动数据 | 原字段、UUID及照片守恒 | 两个无线批次安装后及测试后SQLite quick_check=ok；九张核心表计数及原ID均不变，0条核心记录减少。MealPhotos目录在安装前快照中不存在，未以空目录声称照片恢复已验证 | PASS（核心数据库） | 两批`artifacts/stage-validation/goal-archive-timed-rope-wireless-*/device-audit/`及`device-audit/pre-install-to-post-tests.txt` | 照片备份恢复仍须有真实照片样本验证；不代表未列入核心审计的行为均已验收 |
| AC-05 / 真人与效果 | 新入口接受、实际餐食/强度反馈独立 | 此轮没有新增真人操作验收；用户此前已接受的触屏手感、中文输入法、拍照与庆祝四项继续有效；客观P95/主线程trace仍未取得 | BLOCKED_HUMAN / NOT_RUN | `docs/X-Fit_真机人工测试清单.md`第K节；两批输出下的清单 | 不重复询问已接受体验；真实餐食周评估须等自然记录出现 |

## 已执行动作

- 当前代码、原需求、真实设备证据及原完整FAIL/有限反证已核对；归档本轮具名确认。
- 归档公开边界RED后仅增加未归档条件；原UUID、引用及历史断言保留，GREEN实际通过。
- 未知计数贯穿模型/验证/备份v16/摘要/可选Agent上下文；快填次数可留空，不按时长估算。
- 新UI原mandatory count RED保留；关联33单元通过。首轮UI漏进记录工具后，用截图/AX补齐真实路径，两项UI通过；未放宽原断言或预算。
- R1路由先真实复现漏认和错误前缀误认；最小修复后整类19项通过，确切单车/未知ID不误认、旧无ID兼容。
- 旧式时长+未知次数日汇总真实显示“未记录”而断言失败；仅调整记录存在性判定，旧时长仍不改成有效/含休息时长。整类43项通过，空白下一天与CSV未知空格控制保留。
- 由project.yml将本地候选区分为Build17并用原Xcodegen机械生成；169源、原R1正文/确认包、原只读迁移fixture及main/HEAD已绑定，未操作手机。
- 统一non-device完整入口现已自然终态N01–N07全PASS；其原完整测试预算、断言及7个既有UI跳过项均保留。首轮`N06`全量118项=111执行通过+7跳过、0失败；`N05`为389 PASS/0 FAIL/0 SKIP。
- 经用户授权按无线方式执行两次统一device入口。两次D00–D06、D07A、D07C、D08A–C均PASS；Build17覆盖安装后恢复普通签名Release并启动。核心表行数、原ID及MealPhotos字节经安装后/测试后检查无减少，SQLite quick_check均为ok。
- 两次真机全量UI自动化均在runner报告“Running tests”约31秒后出现IDE channel断开/runner exit74，均为0个实际UI用例；第二次设备已在线且解锁。属可复现环境/runner阻塞，具体根因unknown；已有两个同阶段失败后停止重跑，需先取得新的Xcode或设备Runner诊断证据。
- 用户再次确认解锁后，基于新鲜设备在线/destination可用证据按统一device入口只复验一次。D00–D06C、D07A（387 PASS/5既有SKIP/0 FAIL）、D07C–D08C通过且核心数据守恒；D07B仍于Runner启动后约31秒IDE disconnection/exit74、UI场景0。症状未因解锁或destination可用而改变，进一步排除锁屏/目标不可见解释；上游IDE/XCTest/无线DTX根因仍unknown。此次复验及停止条件见本需求新增验证行与阶段计划，不再同条件重跑。
- 为验证宿主Xcode进程假设，启动Xcode 27.0并向其打开工程路径后，以统一device入口再做一次受控批次：D00–D06C/D07C–D08C和数据守恒通过，D07A 387 PASS/5既有SKIP/0 FAIL；D07B明确记录`DTXConnection` peer拒绝`XCTestManager_IDEInterface`、Runner exit74、UI场景0。Xcode GUI仍显示Welcome，未证明IDE内测试会话建立；筛选8分钟本机统一日志无匹配信号。根因仍unknown，停止同条件重试。完整结果见本需求新验证行和阶段计划。

## 结果与遗留项

- 当前结论：两条确认规则、R1精确入口及未知计数旧时长摘要通过定向与完整本地验证；候选Build17已无线覆盖手机且安装/测试后数据守恒。真机全量单元通过，但解锁和Xcode进程活跃条件下的受控UI尝试均被runner exit74阻断；因此本需求仍非全阶段验收/GO。
- 下一步：不以相同条件再跑UI；先取得能解释runner拒绝XCTest通道的新证据，再修复对应环境/配置或问题并重跑原必测。客观输入trace、尚未逐项完成的真人边界、真实餐食周闭环仍各自独立。
