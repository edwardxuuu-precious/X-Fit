# X-Fit 阶段测试摘要

- Run ID：`20261023-opengym-r2-nondevice`
- 模式：`non-device`
- 时间：`2026-10-23 14:06:35 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Xcode 工程：`/tmp/xfit-opengym-build29-r2-source/FitnessApp.xcodeproj`
- Git：`main / b2ec4ab`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| N01 | PASS | Git diff 空白与冲突标记检查 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N01.log` |
| N02 | PASS | Xcode 工程与 Scheme 可读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N02.log` |
| N03 | PASS | 器械识别后端全量测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N03.log` |
| N03B | PASS | Mac 餐食交换安全测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N03B.log` |
| N04 | PASS | Simulator App 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N04.log` |
| N05 | FAIL | Simulator 全量单元测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N05.log (exit=65)` |
| N06 | FAIL | Simulator 全量 UI 测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N06.log (exit=75)` |
| N07 | FAIL | 通用 iPhoneOS Release 无签名构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20261023-opengym-r2-nondevice/N07.log (exit=75)` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
