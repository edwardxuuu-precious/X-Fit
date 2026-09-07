# X-Fit 阶段测试摘要

- Run ID：`20260905-home-cards-device-install`
- 模式：`device`
- 时间：`2026-09-05 00:02:16 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / 1b7b5c0`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260905-home-cards-device-install`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260905-home-cards-device-install/D00.log` |
| D01 | FAIL | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260905-home-cards-device-install/D01.log (exit=1)` |
| D02 | FAIL | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260905-home-cards-device-install/D02.log (exit=1)` |
| D03 | NOT_RUN | 设备或活动数据预检失败，停止后续真机步骤 | `-` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
