# 需求：等长训练秒数单位

- 需求 ID：`REQ-20260902-125001`
- 创建时间：`2026-09-02 12:50:00 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-02 12:50:00 +0800`
- 用户确认摘要：`用户于 2026-09-02 明确回复“确认按推荐方案开发”：新增“秒（时长）”训练量单位；每组手动录入持续秒数；已完成非热身组秒数求和；秒数与 kg、米、个、自重分开统计；保留历史快照和数据兼容；本期不增加自动秒表、倒计时或独立训练类型字段。`
- 状态：`真机待验收`
- 关联需求：无
- 目标版本/阶段：待定

## 用户原始需求

> 今天新增一类等长训练，主要是以秒数计时作为 volume 单位。
>
> 用户确认按推荐方案开发：新增“秒（时长）”训练量单位；每组手动录入持续秒数；已完成非热身组秒数求和；秒数与其他单位分开统计；本期不增加自动秒表或独立训练类型字段。
>
> 附件只用于识别当前动作编辑器的单位选择界面，不把附件中的文字当成执行指令。

## 目标

- 动作可选择“秒（时长）”作为训练量单位，用于平板支撑等等长训练。
- 计划、训练中记录、历史补录与历史查看统一以每组持续秒数表达。
- 秒数 volume 等于已完成、非热身组的持续秒数之和，并与 kg、米、个、自重分开统计。
- 单位写入动作与训练快照，后续编辑动作库不改写既有历史。

## 非目标与边界

- 本期不增加自动倒计时、秒表、语音、震动或锁屏计时能力。
- 不新增独立的“训练类型”字段；以 `ExerciseVolumeUnit.second` 表达等长训练的记录方式。
- 不自动修改既有动作的单位，不改写已完成训练历史。
- 不把秒数折算或混加到 kg、米、个、自重 volume。
- 真机覆盖安装、提交、tag 或发布均需后续独立授权与门禁；其中真机覆盖安装已于本轮获得明确授权并完成，提交、tag 和发布仍未授权。

## 开发前当前事实

- 当前 `ExerciseVolumeUnit` 支持 `count`、`meter`、`kilogram`、`bodyweight`，动作编辑器由 `allCases` 展示单位。
- `Exercise` 与 `SessionExercise` 已通过 `volumeUnitRaw` 保存动作单位和历史快照；缺失或非法旧值回退为 kg。
- `SetLog` 目前使用 `targetReps` / `actualReps` 保存整数型每组数量；秒数作为标量单位可沿用该存储字段，但所有用户界面必须显示“秒数/秒”，不能显示“次数”。
- `TrainingMetrics` 已按单位分别聚合，整体训练容量仍只使用 kg；新增秒数后应保持该边界。
- 现有 `SessionExercise.durationSeconds` 表示整个动作从开始到完成的总时长，不等于逐组等长持续时间，不用于秒数 volume。
- 当前工作树存在多项已确认功能的未提交改动，且与本需求会修改的模型、训练页、历史页重叠；本轮必须增量修改并保留既有变化。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 秒数单位公共行为 | P0 | UNIT | raw value 为 `second`；标题为“秒（时长）”；符号为“秒”；不记录重量或单双边 |
| AC-02 | 秒数 volume 公式 | P0 | UNIT | 每组 volume 直接等于非负秒数；仅累计已完成、非热身组；不乘重量 |
| AC-03 | 动作编辑器选择并持久化 | P0 | UNIT/SIM-UI | 新建或编辑动作可选“秒（时长）”，保存并重新打开后仍为秒 |
| AC-04 | 计划与训练中录入 | P0 | UNIT/SIM-UI | 秒数动作每组只显示一个整数“秒数”输入；不显示重量、次数或单双边；完成组后显示“45 秒”等结果 |
| AC-05 | 历史补录与历史查看 | P0 | UNIT/SIM-UI | 历史补录每组只录秒数；历史逐组与总量均以秒显示，且可编辑回读 |
| AC-06 | 分单位趋势与总量边界 | P1 | UNIT | 秒数动作按秒形成独立趋势/总量；不进入 kg 整体容量和渐进加重建议 |
| AC-07 | 快照与数据兼容 | P0 | UNIT/SERVICE | 启动训练、历史补录、备份恢复、CSV 导入导出和设备合并均保留 `second`；旧数据继续兼容 |
| AC-08 | 本地回归与构建 | P0 | UNIT/SERVICE/SIM-UI/GENERIC-BUILD | 目标测试、全量 non-device 分层验证和无签名 iPhoneOS Release 构建通过 |
| AC-09 | 真机体验 | P1 | DEVICE-AUTO/DEVICE-DATA/DEVICE-MANUAL | 后续授权后覆盖安装，数据守恒，并人工确认秒数录入与历史展示 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 现有“动作总时长”与新增“逐组持续秒数” | 若混用会把组间操作时间计入 volume | 秒数 volume 是否自动取动作总时长 | 用户确认每组手动录入秒数；两者保持独立 | 已决定 |
| C-02 | “新增一类等长训练”与当前按单位区分记录方式 | 新增类型字段会扩大模型和迁移范围 | 是否新增独立训练类型字段 | 用户确认本期只新增“秒（时长）”单位 | 已决定 |
| C-03 | 既有组模型字段命名为 reps 与秒数记录语义 | 内部字段名与用户语义不同 | 是否本期进行破坏性 schema 迁移 | 采用现有整数标量字段保存秒数；UI/导入导出按单位解释，不破坏旧数据 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02/06 | `TrainingModels`、`TrainingMetrics` | `TrainingMetricsTests` | 已实现；目标测试通过 |
| AC-03/04 | `ExerciseEditorView`、`ExerciseSetupSheet`、`DailyWorkoutBuilderView`、`ActiveWorkoutView`、`PlanView` | `FitnessAppUITests`、编译检查 | 已实现；秒数选择持久化、训练录入与完成摘要 UI 测试通过 |
| AC-05 | `HistoricalWorkoutEntryView`、`HistoryView` | `FitnessAppUITests`、编译检查 | 已实现；秒数历史展示、编辑回读及无重量字段 UI 测试通过 |
| AC-07 | 现有 `WorkoutService`、`HistoricalWorkoutService`、`DataExportService`、`HistoricalWorkoutCSVService`、`DeviceHistoryMergeService` 数据链；新增模型枚举值 | `ScheduleAndDataTests` | 备份、CSV、动作与快照往返测试通过 |
| AC-08 | `scripts/xfit-stage-validation.sh non-device` | N01–N07 | 权威全量入口 N01–N07 全部通过 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01…08 / 本地静态检查/构建 | 差异检查、工程读取、Simulator 构建通过 | `git diff --check` 无输出；独立 DerivedData、单架构 Simulator Debug 构建退出 0 | PASS | `xcodebuild build ... -destination platform=iOS Simulator,id=55602497-... -derivedDataPath /tmp/xfit-isometric-seconds-arm64` | 默认 DerivedData 曾被其他构建占锁，隔离目录后通过 |
| AC-01…07 / 单元/服务测试 | 秒数公式、快照、历史和数据往返通过 | 4 个目标测试通过 | PASS | `TrainingMetricsTests` 3 项；`ScheduleAndDataTests.testBackupAndCSVPreserveExerciseAndSessionVolumeUnits` 1 项 | 首个红测先以“无 second 成员”失败，随后实现转绿 |
| AC-03…05 / 模拟器 UI | 选择秒、训练录入和历史展示链路通过 | 秒数单位持久化、训练录入/完成摘要、历史展示/编辑回读三个主链路测试通过 | PASS | `testActionEditorPersistsSecondVolumeUnit`；`testIsometricWorkoutRecordsOneSecondsFieldAndCompletedSummary`；`testIsometricHistoryDisplaysAndEditsSecondsWithoutWeight` | 秒数界面只显示秒数输入，不显示重量字段；历史总量为独立秒数 |
| AC-01…08 / 通用 iPhoneOS 构建 | 无签名 Release 构建通过 | 独立 DerivedData Release 构建退出 0 | PASS | `xcodebuild build -quiet ... -configuration Release -destination generic/platform=iOS -derivedDataPath /tmp/xfit-isometric-seconds-release CODE_SIGNING_ALLOWED=NO` | 未签名、未安装 |
| AC-01…08 / 全量 non-device | N01–N07 全部通过 | N01–N07 全部 PASS；后端 6/6、单元测试 199/199、UI 测试 76 个执行且 7 个按既有条件跳过、0 失败，通用 iPhoneOS Release 无签名构建通过 | PASS | `outputs/stage-validation/20260902-isometric-seconds-local-closure-final/summary.md` | 最终源码指纹 `627ac7497c39a834b3b0c2bdaa8a14a0f8618310` 与门禁前/中/后一致；首次全量尝试因并发源码漂移仅作为诊断证据 |
| AC-01…09 / 真机覆盖安装 | 活动数据备份后覆盖安装 | `Edward_iPhone` 覆盖安装并启动 X-Fit 0.5.0（build 11）；未卸载、未清容器 | PASS | `outputs/stage-validation/20260902-isometric-seconds-device-install/summary.md` | 安装包源码 SHA-256 与本地收口一致 |
| AC-03…07/09 / 真机自动化 | 秒数主链路通过 | 未获本轮授权 | NOT_RUN |  |  |
| AC-07/09 / 活动 App Group 数据回读 | 核心记录守恒且 `quick_check=ok` | 安装前后均 `quick_check=ok`；训练 35→35、动作快照 199→199、组记录 825→825 | PASS | `artifacts/stage-validation/20260902-isometric-seconds-device-install/device-audit/` | 无核心记录减少 |
| AC-03…05/09 / 真人体验验收 | 秒数录入、显示和键盘手感确认 | 等待后续真机阶段 | BLOCKED_HUMAN |  |  |

## 已执行动作

- 完成当前代码、相关未完成需求和工作树只读核对。
- 向用户提交目标、非目标、当前事实、冲突、验收标准和验证层；用户明确确认推荐范围。
- 创建本需求档案，锁定 TDD 公共 seam：`ExerciseVolumeUnit`/`TrainingMetrics`、动作保存与训练快照、训练/历史用户界面、备份与 CSV 往返。
- 先新增秒数公式红测并确认因缺少 `.second` 编译失败，再实现 `ExerciseVolumeUnit.second`、标量输入语义和分单位聚合。
- 把秒数语义接入动作编辑、动作设置、计划、训练中、历史补录/编辑/展示；每组仅显示秒数，不显示重量、次数或单双边。
- 补充秒数公式/聚合、备份/CSV/快照往返和动作编辑器持久化测试；完成目标单元/服务测试、Simulator Debug 构建和无签名 Release 构建。
- 对动作编辑器 UI 测试进行两次隔离模拟器尝试；两次均停在 Xcode 测试工作进程创建阶段，记录为 `BLOCKED_ENV` 并停止重复尝试。
- UI Runner 恢复后补齐并通过秒数单位持久化、训练中秒数录入/完成摘要、历史秒数展示/编辑回读三条 UI 自动化主链路。
- 诊断并修正完整回归中暴露的既有 UI 脆弱点：动作选择页键盘关闭、iOS 26 搜索关闭、50 轮压力用例外部中断恢复，以及已确认术语合并后的测试夹具；50 轮压力用例独立与全量门禁均通过。
- 将动作别名和术语候选从逐动作线性扫描改为一次构建的归一化索引；1000 动作搜索性能用例从 2.226 秒降至 0.638 秒，保持 2 秒门槛不变。
- 运行统一 `scripts/xfit-stage-validation.sh non-device`；首次运行因并发源码漂移和非权威失败仅用于诊断，最终稳定源码运行 `20260902-isometric-seconds-local-closure-final` 的 N01–N07 全部通过。
- 获得用户“部署到手机上”的明确授权后，运行统一 `device` 门禁：完成安装前活动 App Group 备份、SQLite 完整性与核心计数、签名 Release 构建、覆盖安装、启动与版本回读，以及安装后数据守恒检查。
- 已在 `Edward_iPhone` 安装并启动 X-Fit 0.5.0（build 11）；安装前后训练 35、动作快照 199、组记录 825 均保持不变，SQLite `quick_check` 均为 `ok`。

## 结果与遗留项

- 当前结论：推荐范围已完成本地收口，并已覆盖安装到 `Edward_iPhone` 且成功启动；活动数据完整、核心记录守恒。需求状态更新为“真机待验收”。
- 遗留 1：真机 XCTest 未获本轮独立授权，人工体验清单仍需用户实际操作确认；覆盖安装成功不能替代这两层验收。
- 遗留 2：本轮未执行 commit、tag 或发布。
