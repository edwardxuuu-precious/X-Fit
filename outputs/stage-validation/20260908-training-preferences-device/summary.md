# X-Fit 阶段测试摘要

- Run ID：`20260908-training-preferences-device`
- 模式：`device`
- 时间：`2026-09-08 11:23:44 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / b2ec4ab`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D00.log` |
| D01 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D01.log` |
| D02 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D03.log` |
| D04 | PASS | 签名、entitlements 与版本回读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D04.log` |
| D05 | PASS | 真机覆盖安装、启动与版本回读（不卸载、不清容器） | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D05.log` |
| D06A | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D06A.log` |
| D06B | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D06B.log` |
| D06C | PASS | 安装前后核心记录不减少 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D06C.log` |
| D07A | PASS | 真机全量单元测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D07A.log` |
| D07B | FAIL | 真机全量 UI 测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D07B.log (exit=65)` |
| D08A | PASS | post-tests | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D08A.log` |
| D08B | PASS | post-tests | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D08B.log` |
| D08C | PASS | 安装前到测试后核心记录不减少 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260908-training-preferences-device/D08C.log` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/outputs/stage-validation/20260908-training-preferences-device/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。

## D07B 补充复跑与最终数据回读

- 统一入口 D07B 首次未进入测试用例：XCTest Runner 启用系统自动化模式超时，原始 `FAIL` 保留。
- 随后单用例 smoke 通过；完整 UI 复跑执行 100 项，92 通过、7 条按环境跳过，1 条训练保存后的 5 秒刷新断言失败。
- 唯一失败用例 `testActiveWorkoutTopMenuRemovesZeroCompletedExerciseAndPersistsAfterRelaunch` 原样单独复跑通过；对应证据为 `device-ui-flake-retry-1201.xcresult`。
- 全部复跑后再次备份活动 App Group：`quick_check=ok`，SessionExercise / SetLog / WorkoutSession 为 203 / 837 / 36，与安装前一致。
- 手机活动数据库已存在训练偏好 `TP-20260908-01` 与编排 `CUT-4D-20260908`。编排含 4 次力量、98 个抗阻组、3 组箱跳、2 次跳绳及 1 次 Zone 2。
- 编排数据已同步；训练日程继续遵守“先预览、再确认导入”，没有静默覆盖已有日程。
- 真人体验与训练日程预览确认仍为 `BLOCKED_HUMAN`，阶段不标记为 `GO`。
