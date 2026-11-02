# X-Fit 阶段测试摘要

- Run ID：`upper-r2-wireless-final-20261018`
- 模式：`device`
- 时间：`2026-10-18 09:39:56 +0800`
- 仓库：`/tmp/xfit-r2-build`
- Git：` / `
- Artifacts：`/tmp/xfit-r2-wireless-mks3sj3g/stage-final`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D00.log` |
| D01 | PASS | pre-install | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D01.log` |
| D02 | PASS | pre-install | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D03.log` |
| D04 | PASS | 签名、entitlements 与版本回读 | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D04.log` |
| D05 | FAIL | 真机覆盖安装、启动与版本回读（不卸载、不清容器） | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D05.log (exit=1)` |
| D06A | PASS | post-install | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D06A.log` |
| D06B | PASS | post-install | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D06B.log` |
| D06C | PASS | 安装前后核心记录不减少 | `/tmp/xfit-r2-wireless-mks3sj3g/stage-final/D06C.log` |
| D07 | NOT_RUN | 未授权真机 XCTest | `设置 XFIT_ALLOW_DEVICE_TESTS=1` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/outputs/test-results/20261017-upper-r2/device-install-final/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
