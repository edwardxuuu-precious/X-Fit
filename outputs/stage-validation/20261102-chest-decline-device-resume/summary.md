# X-Fit 阶段测试摘要

- Run ID：`20261102-chest-decline-device-resume`
- 模式：`device`
- 时间：`2026-11-02 21:33:57 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Xcode 工程：`/private/tmp/xfit-chest-actual-candidate-20261102/FitnessApp.xcodeproj`
- Git：`main / b2ec4ab`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/training-sync/20261102-chest-decline/stage-device-20261102-resume`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | BLOCKED_ENV | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/training-sync/20261102-chest-decline/stage-device-20261102-resume/D00.log (exit=1)` |
| D01 | NOT_RUN | 真机开发通道不可用，未读取活动 App Group | `依赖 D00` |
| D02 | NOT_RUN | 未执行安装前 SQLite 完整性与核心计数 | `依赖 D01` |
| D03 | NOT_RUN | 设备预检失败，停止后续真机步骤 | `-` |
| D04 | NOT_RUN | 签名、entitlements 与版本回读 | `依赖 D00；未安装或写入产品数据` |
| D05 | NOT_RUN | 覆盖安装、启动与版本回读 | `依赖 D00；未安装或写入产品数据` |
| D06 | NOT_RUN | 安装后活动数据与守恒 | `依赖 D00；未安装或写入产品数据` |
| D07 | NOT_RUN | 真机全量单元/UI 测试 | `依赖 D00；未安装或写入产品数据` |
| D08 | NOT_RUN | 真机测试后活动数据与守恒 | `依赖 D00；未安装或写入产品数据` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/docs/X-Fit_真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。
