# 真机安装与并发维护数据守恒复核

- 安装需求：`REQ-20260902-122243`
- 并发维护：`REQ-20260902-125003`
- 设备：`Edward_iPhone`
- 安装版本：`0.5.0 (11)`
- 复核时间：`2026-09-02 13:30 +0800`

## 结论

`D06C` 的原始计数比较跨越了另一项已授权真机维护，因此不能直接归因于覆盖安装。以 `REQ-20260902-125003` 的维护后读回作为正确基线复核，本次覆盖安装没有新增或删除任何核心训练 ID；安装后的活动数据库 `PRAGMA quick_check=ok`。

## 时间线

1. 本次安装脚本于 13:11 完成安装前备份，计数为 38 场训练、215 个动作快照、876 条组记录。
2. Release 构建期间，已确认需求 `REQ-20260902-125003` 于 13:21 执行固定 ID 测试数据清理；回执记录清理后为 35/200/829，`protectedIDsPresent=true`。
3. 本次候选包于 13:29 覆盖安装并启动，版本回读为 `0.5.0 (11)`；安装后及延迟回读均为 35/200/829。

## 核心 ID 复核

以并发维护的 `post-execute` 数据库对比本次安装后的延迟回读：

| 检查 | 差异数 |
|---|---:|
| 维护后场次 ID 在安装后缺失 | 0 |
| 安装后新增场次 ID | 0 |
| 维护后动作快照 ID 在安装后缺失 | 0 |
| 安装后新增动作快照 ID | 0 |
| 维护后组记录 ID 在安装后缺失 | 0 |
| 安装后新增组记录 ID | 0 |

## 证据

- 原始设备门禁摘要：`outputs/stage-validation/20260902-final-merged-workout-interaction-device/summary.md`
- 本次安装后延迟回读：`artifacts/stage-validation/20260902-final-merged-workout-interaction-device/device-data/post-install-recheck/`
- 并发维护执行回执：`artifacts/stage-validation/20260902-final-merged-workout-interaction-device/device-data/post-install-recheck/AuthorizedMaintenanceReceipts/REQ-20260902-125003-execute.json`
- 并发维护后数据库：`artifacts/device-data-cleanup/20260902-REQ-20260902-125003/post-execute/Application Support/default.store`
- 本次安装后数据库：`artifacts/stage-validation/20260902-final-merged-workout-interaction-device/device-data/post-install-recheck/default.store`
- App 版本回读：`artifacts/stage-validation/20260902-final-merged-workout-interaction-device/device-app-readback.json`

## 判定边界

- 保留原始 `D06C=FAIL` 记录，不改写脚本事实。
- 补充复核证明该 FAIL 由基线期间的并发授权维护导致，不是本次覆盖安装的数据回归。
- 真机 XCTest 未授权、未执行；真人触控体验仍为 `BLOCKED_HUMAN`。
