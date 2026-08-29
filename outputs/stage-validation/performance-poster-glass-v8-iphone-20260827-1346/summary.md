# X-Fit 阶段测试摘要

- Run ID：`performance-poster-glass-v8-iphone-20260827-1346`
- 模式：`device`
- 时间：`2026-08-27 13:46:02 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / a38dcb6`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/performance-poster-glass-v8-iphone-20260827-1346`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/performance-poster-glass-v8-iphone-20260827-1346/D00.log` |
| D01 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/performance-poster-glass-v8-iphone-20260827-1346/D01.log` |
| D02 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/performance-poster-glass-v8-iphone-20260827-1346/D02.log` |
| D03 | FAIL | 真机签名 Release 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/performance-poster-glass-v8-iphone-20260827-1346/D03.log (exit=65)` |
| D04 | FAIL | 签名、entitlements 与版本回读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/performance-poster-glass-v8-iphone-20260827-1346/D04.log (exit=1)` |
| D07 | NOT_RUN | 未授权真机 XCTest | `设置 XFIT_ALLOW_DEVICE_TESTS=1` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/outputs/stage-validation/performance-poster-glass-v8-iphone-20260827-1346/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
