# X-Fit 阶段测试摘要

- Run ID：`upper-r2-wireless-20261018`
- 模式：`device`
- 时间：`2026-10-18 09:34:51 +0800`
- 仓库：`/tmp/xfit-r2-build`
- Git：` / `
- Artifacts：`/tmp/xfit-r2-wireless-mks3sj3g/stage`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/tmp/xfit-r2-wireless-mks3sj3g/stage/D00.log` |
| D01 | PASS | pre-install | `/tmp/xfit-r2-wireless-mks3sj3g/stage/D01.log` |
| D02 | PASS | pre-install | `/tmp/xfit-r2-wireless-mks3sj3g/stage/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `/tmp/xfit-r2-wireless-mks3sj3g/stage/D03.log` |
| D04 | FAIL | 签名、entitlements 与版本回读 | `/tmp/xfit-r2-wireless-mks3sj3g/stage/D04.log (exit=1)` |
| D05 | NOT_RUN | 构建或签名门未通过，未安装 | `依赖 D03/D04` |
| D06 | NOT_RUN | 未安装，未执行安装后数据回读 | `依赖 D05` |
| D07 | NOT_RUN | 未授权真机 XCTest | `设置 XFIT_ALLOW_DEVICE_TESTS=1` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/outputs/test-results/20261017-upper-r2/device-install/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
