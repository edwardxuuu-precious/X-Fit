# 需求：周中高集中训练计划与导入修复

- 需求 ID：`REQ-20260908-213749`
- 创建时间：`2026-09-08 21:37:49 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-08 21:37:49 +0800`
- 用户确认摘要：`用户确认周中完成约80%以上训练任务、上肢集中高强度高容量、本周修订计划及导入交互修复；重量单位原回复仍为斜杠选项，实施中保留Notes原始口径，不擅自换算。`
- 状态：`真机待验收`
- 关联需求：`docs/requirements/2026-09-08/062544_requirement.md`、`docs/requirements/2026-09-08/111711_device-install-data-sync.md`
- 目标版本/阶段：0.5.0 真机修订

## 用户原始需求

> 1. 当前预览页无法点击确认导入，也没有看到此前描述的冲突按钮，需要按现有 App 问题修复。
> 2. 读取本人 Notes 近期训练记录后重新规划本周训练；今天自行完成的训练作为实际记录保留。
> 3. 每周约 80% 训练任务尽量在周中完成，周末保留家庭时间。
> 4. 偏好集中性高强度刺激，尤其上肢需要较高集中度和训练容量。
> 5. 用户已明确回复确认上述偏好、计划与修复范围；重量口径回复仍保留“总重/单边、单只/一对、刻度/公斤”斜杠选项，因此不能推定具体单位。

## 目标

- 追加 `TP-20260908-02` 训练偏好版本，保留旧偏好与既有训练历史。
- 追加 `CUT-4D-20260908-R2` 本周编排：周二实际训练作为冲突保留，计划覆盖周三背部＋二头、周五腿部＋核心、周日肩部＋手臂及工作日有氧。
- 后续标准周结构为周一胸＋三头、周二背＋二头、周三有氧、周四腿＋核心、周五肩＋手臂；周末仅可选短有氧或休息。
- 导入预览始终显示可导入、已有训练、已导入数量；冲突日期逐日明确保留；主操作使用全宽按钮并说明不可用原因。
- 训练首页在编排已保存但日程未导入时给出明确入口。

## 非目标与边界

- 不覆盖或删除 2026-09-08 已有手动训练、已有日程、已完成组、UUID 或历史快照。
- 不把 Notes 中含糊的重量数字换算成公斤、总重、单边或单只口径；仅复用 App 内满足同动作、同器械、单位明确的历史完成组。
- 不自动在后台创建日程；仍由用户预览并点击确认导入。
- 不修改饮食、热量、蛋白质或医学参数。
- 本轮不提交 Git、打 tag 或发布。

## 当前事实

- 当前代码的确认按钮在存在冲突且未开启全局 `skipConflicts` 时禁用；开关仅在检测到冲突时显示，按钮附近没有禁用原因。
- 当前 UI 测试只断言确认按钮存在，没有断言 `isHittable`、点击后日程落库或重复导入幂等。
- 训练首页仅根据 `ScheduledWorkout` 显示本周安排；编排快照存在但日程未导入时仍显示“本周暂无安排”。
- Notes 显示用户近期单次通常录入 20 组以上，偏好部位分化；2026-09-08 已自行完成胸、肩、三头训练。
- 当前偏好真源为 `TP-20260908-01`，当前编排为 `CUT-4D-20260908`；两者必须保留。
- 手机本轮最近一次只读状态为 unavailable；真机现状须在重新连接后回读。

## 验收标准

2026-10-27本人明确确认以[首页当天训练清理](../2026-10-27/200712_home-current-training-cleanup.md)替代AC-07的首页旧周导入提示要求。必要导入保留于训练管理；其余编排、导入保真及历史数据要求继续有效。

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 偏好追加版本 | P0 | UNIT/SERVICE | 新增 `TP-20260908-02`，旧版仍可回看；新约束包含周中优先和上肢高集中高容量 |
| AC-02 | 编排追加版本 | P0 | UNIT/SERVICE | 新增 `CUT-4D-20260908-R2`，关联新偏好；旧编排和历史不覆盖 |
| AC-03 | 本周结构 | P0 | UNIT/SERVICE | 周二实际训练被保留；从 9 月 8 日预览时可导入其余 3 个力量日，不生成重复周二日程 |
| AC-04 | 导入摘要与逐日状态 | P0 | SIM-UI | 预览始终显示可导入、已有训练和已导入数量；每个冲突日明确显示保留现有训练 |
| AC-05 | 主按钮可用 | P0 | UNIT/SIM-UI | 存在冲突但仍有候选日时，全宽按钮显示“导入其余 N 天”且可点击；无候选时显示原因 |
| AC-06 | 导入保真与幂等 | P0 | UNIT/SERVICE/SIM-UI | 导入只创建无冲突日期；重复操作不新增日程或模板；预览变更仍要求重新预览 |
| AC-07 | 首页待导入提示 | P1 | SIM-UI | 编排已存在但本周无日程时，首页显示“安排本周训练”入口，不再只显示暂无安排 |
| AC-08 | 重量语义保真 | P0 | UNIT/SERVICE | 未明确单位的 Notes 数字不作为自动填重；已有 App 历史仍按同 UUID、器械、公斤及单/双侧规则读取 |
| AC-09 | 数据与设备验证 | P0 | GENERIC-BUILD/DEVICE-DATA/DEVICE-MANUAL | 覆盖安装前后核心历史数量不减少；真机可完成预览、确认和首页回看 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 旧版周二胸＋三头计划 vs. 2026-09-08 手动胸肩三头实际训练 | 重复安排和冲突 | 是否覆盖当天实际训练 | 保留实际训练，新版仅导入其余日期 | 已确认 |
| C-02 | 旧版周末腿日/肩臂日 vs. 周中完成约 80% | 周末时间 | 是否调整长期周结构 | 下周起四次力量均放工作日；本周保留周日短课过渡 | 已确认 |
| C-03 | Notes 数字重量 vs. 未明确总重/单边等口径 | 自动填重准确性 | 是否推定单位 | 不推定、不换算，只使用 App 内单位明确历史 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01~03 | `TrainingPreferenceModels.swift`、`FatLossCatalog.swift`、偏好文档 | `FatLossCatalogTests`、`FatLossServiceTests` | 已完成；追加 V2 偏好与 R2 编排，旧版保留 |
| AC-04~06 | `FatLossTrainingView.swift`、`FatLossModels.swift`、`FatLossService.swift` | `FatLossServiceTests`、`RedesignUITests` | 已完成；摘要、冲突保留、全宽按钮、原子预览状态与幂等导入通过 |
| AC-07 | `TodayView.swift` | `RedesignUITests.testTrainingHomeShowsPendingWeekImportEntry` | 已完成；首页待导入入口通过 |
| AC-08 | `FatLossService.swift`、训练偏好文档 | `FatLossServiceTests.testLoadPreviewUsesCompletedCompatibleHistoryAndPreservesWeightSide` | 已完成；单位明确的 App 历史可读，Notes 含糊数字不换算 |
| AC-09 | 阶段验证脚本与真机清单 | `scripts/xfit-stage-validation.sh` | 覆盖安装、版本回读、真机单元测试和活动库守恒已完成；UI Runner 环境阻塞，真人待验收 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01~08 / 本地静态检查/构建 | 编译通过 | N01/N02/N04 均通过 | PASS | `outputs/stage-validation/20260908-weekday-import-r2-nondevice/summary.md` | `git diff --check`、工程读取与模拟器构建 |
| AC-01~08 / 单元/服务测试 | 新增回归和原有全量测试通过 | 276/276 通过，0 失败 | PASS | `artifacts/stage-validation/20260908-weekday-import-r2-nondevice/N05.log` | 另有训练/备份定向 58/58 通过 |
| AC-04~07 / 模拟器 UI | 可点击导入并能回看本周安排 | 关键导入与首页入口实际点击通过；全量 101 项中 94 通过、7 个环境条件项跳过、0 失败 | PASS | `artifacts/stage-validation/20260908-weekday-import-r2-nondevice/N06.log` | 原始禁用按钮 RED 已复现；修复后同用例通过 |
| AC-01~09 / 通用 iPhoneOS 构建 | 无签名 Release 构建通过 | 构建通过 | PASS | `artifacts/stage-validation/20260908-weekday-import-r2-nondevice/N07.log` |  |
| AC-09 / 真机覆盖安装 | 安装成功且不卸载/不清容器 | 实时 tunnel 与 DDI 通过；已覆盖安装并启动 0.5.0 (11) | PASS | `outputs/stage-validation/20260909-weekday-import-r2-device/summary.md` | 安装前先完成活动 App Group 备份；最终又覆盖恢复签名 Release 包 |
| AC-04~07,09 / 真机单元自动化 | 全量单元回归通过 | 276 项执行，2 条因宿主资料不可用跳过，0 失败 | PASS | `artifacts/stage-validation/20260909-weekday-import-r2-device/D07A.log` |  |
| AC-04~07,09 / 真机 UI 自动化 | 导入流程通过 | 完整入口及一次关键单项复测均在用例执行前超时：`Timed out while enabling automation mode` | BLOCKED_ENV | `artifacts/stage-validation/20260909-weekday-import-r2-device/D07B.log`、`artifacts/stage-validation/20260909-weekday-import-r2-device/supplemental/device-ui-smoke-summary.json` | 产品断言执行数为 0；不据此判定产品失败，也不继续无边界重试 |
| AC-01~03,06,09 / 活动 App Group 数据回读 | 新旧版本共存且历史数量不减少 | `quick_check=ok`；训练 36 次、动作 203 个、组记录 837 条，安装前后、测试后及最终 Release 回装后一致；V1/V2 偏好与原版/R2 编排共存 | PASS | `artifacts/stage-validation/20260909-weekday-import-r2-device/device-audit/`、`artifacts/stage-validation/20260909-weekday-import-r2-device/supplemental/final-audit/` | 回读到 `TP-20260908-01/02` 与 `CUT-4D-20260908/R2` |
| AC-04~06,09 / 真人导入与活动库回读 | 用户在真机完成预览和确认导入；活动库只新增目标日程 | 用户确认已导入；回读新增 9 月 9/11/13 三条唯一 R2 日程和 3 条唯一关联，核心历史数量不变 | PASS | `artifacts/stage-validation/20260909-weekday-import-r2-device/supplemental/post-user-import-audit/` | 导入前后 ScheduledWorkout 23→26、ProgramWorkoutLink 0→3；无重复 R2 逻辑记录 |
| AC-07,09 / 真人首页与重复预览体验 | 首页显示三天安排；再次预览不可重复导入 | 尚未收到本人对首页显示和再次预览状态的明确反馈 | BLOCKED_HUMAN | `outputs/stage-validation/20260909-weekday-import-r2-device/真机人工测试清单.md` | 活动库当前无重复记录，但不能替代界面人工确认 |

## 已执行动作

- 已读取训练偏好真源、Notes 近期训练摘要及导入相关代码。
- 已定位条件开关、禁用按钮、首页待导入提示和 UI 测试覆盖缺口。
- 已归档用户确认范围并进入开发。
- 已追加 `TP-20260908-02` 与 `CUT-4D-20260908-R2`，保留首版偏好、编排和历史记录。
- 已把导入预览改为单一不可变展示状态，消除预览数据与 Sheet 展示分离造成的首帧空摘要；冲突日固定保留，主按钮可导入其余日期。
- 已在训练首页增加待导入入口，并补充导入点击、首页入口、幂等与历史保真回归。
- 已完成统一 `non-device` 门禁，N01–N07 全部通过。
- 已在真机在线后执行统一 `device` 门禁，完成安装前备份、签名 Release 覆盖安装、版本回读、全量真机单元测试和三次活动库守恒检查。
- 已对真机 UI Runner 初始化超时做一次关键用例原样复测；同一系统环节仍超时后停止重试，并重新覆盖安装签名 Release 0.5.0 (11)。
- 已从手机活动数据库回读 `TP-20260908-02` 与 `CUT-4D-20260908-R2`，同时确认旧版本及 36 / 203 / 837 条核心训练记录均保留。
- 本人已在真机完成 R2 预览与确认导入；导入后只读回读确认新增 3 条日程及 3 条唯一 R2 关联，日期和课程分别为 9 月 9 日背部＋二头、9 月 11 日腿部＋核心、9 月 13 日肩部＋手臂。

## 结果与遗留项

- 当前结论：R2 已完成本地完整回归、真机覆盖安装、活动数据库回读和真机单元回归，状态进入 `真机待验收`。
- 当前自动化限制：真机 UI Runner 连续两次均未能开启系统 automation mode，产品 UI 用例没有开始执行；模拟器全量 UI 已通过，真机点击体验仍由本人完成，不能由构建或单元测试替代。
- 下一步：本人仅需确认训练首页已显示周三/周五/周日三条安排，并再次打开预览确认显示已导入且不能重复创建；活动数据库当前已确认没有重复 R2 记录。
- 验证脚本已要求 D00 同时确认实时 tunnel 与 DDI；本轮两者均通过。最终手机上运行的是签名 Release 0.5.0 (11)，未卸载或清空容器。
