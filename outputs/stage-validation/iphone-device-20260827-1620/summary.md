# X-Fit 阶段测试摘要

- Run ID：`iphone-device-20260827-1620`
- 模式：`device`
- 时间：`2026-08-27 16:19:02 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / a38dcb6`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D00.log` |
| D01 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D01.log` |
| D02 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D03.log` |
| D04 | PASS | 签名、entitlements 与版本回读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D04.log` |
| D05 | PASS | 真机覆盖安装、启动与版本回读（不卸载、不清容器） | 首次因锁屏失败；解锁后覆盖安装并回读 X-Fit 0.5.0 (11)，见 `device-launch-unlocked.json` |
| D06A | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D06A.log` |
| D06B | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D06B.log` |
| D06C | PASS | 安装前后核心记录不减少 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/iphone-device-20260827-1620/D06C.log` |
| D07 | PASS | 真机单元测试 | 154/154 PASS，`device-unit-resume.xcresult` |
| D08A | PASS | 本次四项核心真机 UI | 4/4 PASS，`device-ui-core-4.xcresult` |
| D08B | FAIL | 真机全量 UI 回归 | 57 项中 53 PASS、4 FAIL；复核结论见 `device-ui-followup.md` |
| D08C | PASS | 测试后活动 App Group 数据守恒 | `quick_check=ok`；137/581/20，与安装前一致 |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/outputs/stage-validation/iphone-device-20260827-1620/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
