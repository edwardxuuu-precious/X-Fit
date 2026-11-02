# X-Fit 阶段测试摘要

- Run ID：`20260914-lower-body-notes-nondevice-r2`
- 模式：`non-device`
- 时间：`2026-09-14 09:51:06 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / b2ec4ab`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| N01 | PASS | Git diff 空白与冲突标记检查 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2/N01.log` |
| N02 | PASS | Xcode 工程与 Scheme 可读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2/N02.log` |
| N03 | PASS | 器械识别后端全量测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2/N03.log` |
| N04 | PASS | Simulator App 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2/N04.log` |
| N05 | PASS | Simulator 全量单元测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2/N05.log` |
| N06 | FAIL | Simulator 全量 UI 测试 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2/N06.log (exit=65)` |
| N07 | PASS | 通用 iPhoneOS Release 无签名构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260914-lower-body-notes-nondevice-r2/N07.log` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
