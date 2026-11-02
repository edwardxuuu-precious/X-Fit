# X-Fit 阶段测试摘要

- Run ID：`goal-unlocked-device-recheck-20261013`
- 模式：`device`
- 时间：`2026-10-13 10:45:58 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / b2ec4ab`
- Artifacts：`artifacts/stage-validation/goal-unlocked-device-recheck-20261013`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D00.log` |
| D01 | PASS | pre-install | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D01.log` |
| D02 | PASS | pre-install | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D03.log` |
| D04 | PASS | 签名、entitlements 与版本回读 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D04.log` |
| D05 | PASS | 真机覆盖安装、启动与版本回读（不卸载、不清容器） | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D05.log` |
| D06A | PASS | post-install | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D06A.log` |
| D06B | PASS | post-install | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D06B.log` |
| D06C | PASS | 安装前后核心记录不减少 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D06C.log` |
| D07A | PASS | 真机全量单元测试 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D07A.log` |
| D07B | FAIL | 真机全量 UI 测试 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D07B.log (exit=65)` |
| D07C | PASS | 真机测试后恢复本次签名 Release 并启动回读 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D07C.log` |
| D08A | PASS | post-tests | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D08A.log` |
| D08B | PASS | post-tests | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D08B.log` |
| D08C | PASS | 安装前到测试后核心记录不减少 | `artifacts/stage-validation/goal-unlocked-device-recheck-20261013/D08C.log` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `outputs/stage-validation/goal-unlocked-device-recheck-20261013/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
