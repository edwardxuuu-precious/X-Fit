# X-Fit 阶段测试摘要

- Run ID：`20260909-weekday-import-r2-device`
- 模式：`device`
- 时间：`2026-09-09 18:53:50 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / b2ec4ab`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D00.log` |
| D01 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D01.log` |
| D02 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D03.log` |
| D04 | PASS | 签名、entitlements 与版本回读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D04.log` |
| D05 | PASS | 真机覆盖安装、启动与版本回读（不卸载、不清容器） | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D05.log` |
| D06A | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D06A.log` |
| D06B | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D06B.log` |
| D06C | PASS | 安装前后核心记录不减少 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D06C.log` |
| D07A | PASS | 真机全量单元测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D07A.log` |
| D07B | FAIL | 真机全量 UI 测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D07B.log (exit=65)` |
| D08A | PASS | post-tests | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D08A.log` |
| D08B | PASS | post-tests | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D08B.log` |
| D08C | PASS | 安装前到测试后核心记录不减少 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/D08C.log` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/outputs/stage-validation/20260909-weekday-import-r2-device/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。

## 补充诊断与最终回装

- D07B 的 `FAIL` 来自测试 Runner 在用例执行前无法开启系统 automation mode；没有产品 UI 断言被执行。一次关键导入用例原样复测仍得到相同超时，因此按环境阻塞收口，不继续重复运行。
- 补充复测证据：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/supplemental/device-ui-smoke-summary.json`。
- 已在自动化尝试后再次覆盖安装并启动签名 Release 0.5.0 (11)，未卸载或清空容器。最终版本回读、复制与审计证据位于 `artifacts/stage-validation/20260909-weekday-import-r2-device/supplemental/`。
- 最终活动数据库 `PRAGMA quick_check=ok`；WorkoutSession / SessionExercise / SetLog 为 36 / 203 / 837，与安装前一致。
- 最终活动库回读到偏好 `TP-20260908-01/02` 和编排 `CUT-4D-20260908/R2`，新旧版本共存。
- 当前总判定仍为 `PARTIAL-BLOCKED`：Release 安装、数据守恒与真机单元测试通过；真机 UI 自动化为 `BLOCKED_ENV`，人工体验为 `BLOCKED_HUMAN`。

## 本人确认导入后的回读

- 本人已在真机完成 R2 预览与确认导入。随后只读复制活动 App Group，`PRAGMA quick_check=ok`。
- ScheduledWorkout 从 23 增至 26，ProgramWorkoutLink 从 0 增至 3；新增记录均属于 R2，日程 ID、逻辑键各 3 个且互不重复。
- 新增日程为：2026-09-09 背部＋二头、2026-09-11 腿部＋核心、2026-09-13 肩部＋手臂，当前状态均为 `planned`。
- WorkoutSession / SessionExercise / SetLog 仍为 36 / 203 / 837；既有“推 · 胸肩三头”进行中会话保持不变；V1/V2 偏好与原版/R2 编排继续共存。
- 证据：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260909-weekday-import-r2-device/supplemental/post-user-import-audit/`。
- 当前只剩首页显示、再次预览已导入状态的真人确认，以及被系统 automation mode 阻塞的真机 UI 自动化层。
