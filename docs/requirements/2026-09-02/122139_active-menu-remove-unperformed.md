# 需求：进行中训练菜单调整与未完成动作删除

- 需求 ID：`REQ-20260902-122139`
- 创建时间：`2026-09-02 12:21:39 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-02 12:21:39 +0800`
- 用户确认摘要：`用户回复确认开发：训练页顶部增加调整今日菜单入口；允许删除零完成组动作，即使系统已自动标记开始；删除本次动作快照及未完成组，不影响更早已完成历史；任何已完成组的动作禁止整项删除；至少保留一个动作。`
- 状态：`真机待验收`
- 关联需求：无
- 目标版本/阶段：待定

## 用户原始需求

> 最上面这里可以添加调整今日训练菜单的功能，比如今天的保加利亚深蹲我就不想做了但是现在删不掉，这种没做的就不要沿用这次的记录给下次训练了。

附件只作为当前训练页现象证据，不把附件中的文字当成额外指令。

## 目标

- 在进行中训练页顶部提供明确的“调整今日菜单”入口。
- 允许删除本次尚未完成任何训练组的动作，并同步移除其未完成组占位记录。
- 删除后的动作不再作为本次菜单或本次表现来源影响下一次训练建议；更早真实完成的历史保持不变。

## 非目标与边界

- 不允许整项删除已有任意完成组的动作。
- 本次训练至少保留一个动作。
- 不改写已完成历史、既有模板历史快照或更早真实训练表现。
- 本轮不自动执行真机覆盖安装、Git commit、tag 或发布。

## 当前事实

- `ActiveWorkoutView` 顶部当前只有“临时加动作”入口，动作删除服务方法仍存在但没有可见 UI 入口。
- `WorkoutService.removeExercise` 已按“是否存在完成组”保护删除，但 `syncMenu` 还会把 `startedAt` 当成删除阻断；首个动作进入页面时会被系统自动标记开始，因此会出现 `0/4` 仍无法从菜单编辑器删除的冲突。
- `WorkoutRecommendationService` 的表现数据只读取 `isCompleted` 组；但未删除的 `SessionExercise` 仍会保留“本次菜单出现过”的身份。
- 当前工作树存在用户既有未提交修改，且与 `ActiveWorkoutView`、`WorkoutService`、测试文件重叠；本轮只在当前状态上做最小补丁，不覆盖或回退既有改动。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 进行中训练页顶部可进入“调整今日菜单” | P0 | SIM-UI/DEVICE-MANUAL | 不退出或放弃训练即可打开当前菜单编辑器 |
| AC-02 | `0` 个完成组的动作可从菜单删除 | P0 | UNIT/SERVICE/SIM-UI | 即使系统已有自动 `startedAt`，确认删除后动作卡与组占位均消失 |
| AC-03 | 有任意完成组的动作不可整项删除 | P0 | UNIT/SERVICE/SIM-UI | 删除入口禁用或保存时拒绝，完成事实不变 |
| AC-04 | 删除后训练进度分母立即减少 | P1 | UNIT/SIM-UI | 删除 4 组动作时总组数减少 4，已完成组数不变 |
| AC-05 | 被删动作不沿用本次记录到下次训练 | P0 | UNIT/SERVICE | 本次 `SessionExercise` 与未完成 `SetLog` 被移除；下一次菜单身份和表现不读取本次空记录 |
| AC-06 | 更早已完成历史与其他动作保持不变 | P0 | UNIT/SERVICE | 更早历史、当前其他动作、已完成组及顺序均不被误删 |
| AC-07 | 本次训练至少保留一个动作 | P1 | UNIT/SIM-UI | 删除最后一个动作时明确阻止 |
| AC-08 | 删除结果重启后仍保持 | P1 | SIM-UI/DEVICE-MANUAL | 退出训练页再进入时，被删动作不恢复 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 既有 `syncMenu` 将 `startedAt` 视为已开始 vs 用户要求 `0` 完成组可删除 | 首个动作会因页面自动计时被锁住，即使实际一组都没做 | 删除保护按“完成组”还是内部开始时间判断 | 用户确认按 `0` 完成组判断；自动开始时间不阻止删除 | 已决定 |
| C-02 | 删除本次空记录 vs 保护真实历史 | 若误删完成组会污染训练事实 | 是否允许部分完成动作整项删除 | 用户确认任何已完成组都禁止整项删除，更早历史不变 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/08 | `FitnessApp/Features/Workout/ActiveWorkoutView.swift`、`FitnessApp/Features/DailyPlan/DailyWorkoutBuilderView.swift` | `FitnessAppUITests/FitnessAppUITests.swift` | 本地已验证 |
| AC-02/03/04/06/07 | `FitnessApp/Services/WorkoutService.swift` | `FitnessAppTests/AdaptivePlanningTests.swift`、既有 `FitnessAppTests/ScheduleAndDataTests.swift` 回归 | 本地已验证；AC-07 运行时补测受模拟器环境阻塞 |
| AC-05 | `FitnessApp/Services/WorkoutService.swift`、`FitnessApp/Services/WorkoutRecommendationService.swift` | `FitnessAppTests/AdaptivePlanningTests.swift` | 本地已验证 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01…08 / 本地静态检查/模拟器编译 | 当前工作树可编译 | 定向测试完成应用与测试 Bundle 编译；范围内 `git diff --check` 无错误 | PASS | `/tmp/xfit-active-menu-unit2/Logs/Test/Test-FitnessApp-2026.09.02_12-39-43-+0800.xcresult` | 只证明模拟器定向编译，不替代通用 iPhoneOS Release |
| AC-02/03/04/05/06 / 单元/服务测试 | 删除边界、数据清理与历史保护通过 | 新增 2 项服务测试通过；既有进行中菜单同步回归 1 项通过 | PASS | `/tmp/xfit-active-menu-unit2/Logs/Test/Test-FitnessApp-2026.09.02_12-39-43-+0800.xcresult`、`/tmp/xfit-active-menu-unit2/Logs/Test/Test-FitnessApp-2026.09.02_12-48-16-+0800.xcresult` | 验证零完成组可删、完成组保护、旧历史与其他动作保持 |
| AC-07 / 单元/服务测试 | 最后一个动作不可删除 | 已补测试；测试启动阶段 CoreSimulator 返回 `Invalid device state` / `server died`，未进入用例执行 | BLOCKED_ENV | `testRunningWorkoutMenuKeepsAtLeastOneExercise` | 代码层已有 Builder 数量保护和 Service 空菜单保护；未把静态检查冒充运行通过 |
| AC-01/02/04/08 / 模拟器 UI | 顶部进入、删除确认、进度更新与重进持久化通过 | `0/12` 删除 3 组动作后变为 `0/9`，终止并重启后仍为 `0/9` 且动作未恢复 | PASS | `/tmp/xfit-active-menu-ui-green/Logs/Test/Test-FitnessApp-2026.09.02_12-42-16-+0800.xcresult` | `testActiveWorkoutTopMenuRemovesZeroCompletedExerciseAndPersistsAfterRelaunch` 1/1 通过 |
| AC-03/07 / 模拟器 UI | 完成组动作与最后一个动作不可整项删除 | 本轮未单独执行 UI 级保护测试 | NOT_RUN |  | Service/单元边界与 UI 禁用条件已实现；待后续完整 UI 回归覆盖 |
| AC-01…08 / 通用 iPhoneOS 构建 | 无签名 Release 构建通过 | 隔离镜像在约 16 个并发 Xcode 任务下持续编译，已生成 `.app` 目录但没有取得成功退出码；超过本轮验证窗口后中止 | BLOCKED_ENV |  | 未出现本功能编译错误，但不能记为 PASS；临时镜像与 DerivedData 已移入废纸篓 |
| AC-01…08 / 真机覆盖安装 | 需要用户另行授权后覆盖安装 | 当前完整工作树 0.5.0 (11) 已覆盖安装并成功启动，未卸载、未清容器 | PASS | `artifacts/stage-validation/20260902-exercise-library-dedup-device-1338/D05.log` | 本功能三个源文件构建前后 SHA-256 与冻结指纹一致 |
| AC-01…08 / 真机自动化 | 需要真机阶段执行 |  | NOT_RUN |  |  |
| AC-05/06/08 / 活动 App Group 数据回读 | 覆盖安装前后核心记录守恒 | 安装前后均 `quick_check=ok`；训练/动作/组记录为 35/200/829，均未减少 | PASS | `artifacts/stage-validation/20260902-exercise-library-dedup-device-1338/device-audit/` | 只证明安装与活动数据守恒，不代替本功能人工操作验收 |
| AC-01/02/03/08 / 真人体验验收 | 用户确认顶部入口和删除反馈清晰 |  | NOT_RUN |  |  |

## 已执行动作

- 完成只读代码、历史需求边界与当前脏工作树核对。
- 用户确认目标、非目标、删除保护和分层验收标准；已创建本需求档案并进入开发。
- 在进行中训练页顶部增加“调整今日菜单”入口，并复用当日菜单编辑器。
- 将进行中菜单删除保护统一为“存在完成组才阻止”；自动 `startedAt` 不再锁住零完成组动作。
- 菜单编辑器对已有完成组和最后一个动作禁用删除；删除零完成组动作时清理本次快照与未完成组，不改写更早完成历史。
- 补充服务层历史保护/完成组保护/最后动作保护测试，以及模拟器 UI 删除与重启持久化测试。
- 定向服务测试 2/2、既有回归 1/1、模拟器 UI 1/1 通过；范围内 `git diff --check` 通过。
- 通用 iPhoneOS Release 构建与 AC-07 运行时补测因并发 Xcode/CoreSimulator 环境阻塞，按 `BLOCKED_ENV` 记录；该时点尚未执行真机安装，且本轮始终未发布。
- 复用同一设备上串行完成的当前工作树签名构建：本功能文件指纹匹配，0.5.0 (11) 已覆盖安装、成功启动并完成安装前后 App Group 数据守恒回读。

## 结果与遗留项

- 当前结论：功能实现、核心模拟器/服务行为、签名覆盖安装、启动和活动数据守恒已通过；状态进入 `真机待验收`。
- 遗留项：用户在设备上确认顶部入口、删除零完成组动作、进度分母变化及重新进入后不恢复；真机 XCTest、通用 iPhoneOS Release 和 AC-07 运行时测试仍未取得本轮完整通过结论。
