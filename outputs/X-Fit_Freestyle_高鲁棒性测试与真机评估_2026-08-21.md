# X-Fit Freestyle Training 高鲁棒性测试与真机评估

- 日期：2026-08-21
- 候选版本：0.5.0（Build 10）
- 真机：Edward_iPhone / iPhone 17 / iOS 26.6
- 发布结论：**Go**
- 结论依据：模拟器与真机完整回归均为 112/112 通过，核心真机链路 7/7 通过，设备包构建、签名、覆盖安装、启动和权威数据库回读全部通过；未发现 P0/P1 未解决项。

## 1. 已完成修复

1. 自由训练以持久化开始/结束时间为真源，前后台与强杀重启后按真实墙钟时间恢复。
2. 同时存在多个活动间歇时自动收敛为最新一条；放弃时清除全部临时状态，不虚构漏点时间。
3. 最后一组不产生孤儿间歇；撤销完成组会同步清除该组已记录与临时间歇。
4. 系统时间回拨时结束时间不会早于开始时间，权威秒数保持非负。
5. 历史补录采用严格整数解析，拒绝负数、字母混入、全角数字、浮点数与超过 86,400 秒的值；非法输入保留原文并显示错误。
6. 服务层、CSV 与 JSON 备份导入统一校验间歇范围和起止时间一致性。
7. 固定倒计时通知以同一标识原子替换，消除异步取消覆盖新通知的竞态；自由训练不调度固定倒计时通知。
8. App 进入后台时不再由暂停的 TimelineView 提前结束倒计时；系统通知按真实触发时间送达。
9. UI 自动化持久化恢复使用独立 `XFitUITesting` 数据库，不清除或写入正式训练库。

## 2. 放行门禁与评估体系

| 维度 | 权重 | Go 判据 | 本轮结果 |
|---|---:|---|---:|
| 数据正确性与不丢失 | 30 | 不虚构时间；升级、补录和导入后数据一致 | 30/30 |
| 状态机唯一性与幂等 | 20 | 最多一个活动间歇；重复/乱序操作无重复记录 | 20/20 |
| 中断与恢复 | 20 | Home、后台、终止与重启后按真实时间恢复 | 20/20 |
| 真机计时与通知 | 15 | 固定通知恰好一次；自由训练固定通知为 0 | 15/15 |
| 补录输入与可用性 | 10 | 非法值明确拒绝；有效值保存、重开和展示一致 | 10/10 |
| 备份、JSON、CSV 兼容 | 5 | 新字段往返不丢失；旧数据仍可读 | 5/5 |
| **总分** | **100** | **至少 95，且 P0 全过** | **100/100** |

硬门结果：P0 全部通过，P1 通过率 100%，无数据丢失、重复通知或双活动间歇。

## 3. 自动化与真机证据

### 完整回归

| 环境 | 结果 | 失败 | 跳过 | 结果包 |
|---|---:|---:|---:|---|
| Edward_iPhone / iOS 26.6 | 112/112 | 0 | 0 | `/tmp/XFit-Freestyle-Go-PhysicalDevice-Full-Final-20260821.xcresult` |
| iPhone 17 Pro Simulator / iOS 26.5 | 112/112 | 0 | 0 | `/tmp/XFit-Freestyle-Go-Simulator-Full-Final-20260821.xcresult` |

每套均包含逻辑/集成测试 89 条与 UI 测试 23 条。

### 真机核心链路

- 7/7 通过，结果包：`/tmp/XFit-Freestyle-Go-PhysicalDevice-Core-Final-20260821.xcresult`。
- 覆盖：固定通知一次、自由训练无固定通知、放弃后补录、下一组自动结束间歇、后台真实计时、终止后持久化恢复、非法输入拒绝及有效补录持久化。
- 固定通知专项在 App 终止后等待触发，再重启读取系统 delivered notifications：数量为 1，重复数量为 0。结果包：`/tmp/XFit-Freestyle-Go-PhysicalDevice-TerminatedDeliveredReadback-20260821.xcresult`。
- 自由训练专项：固定倒计时通知数量为 0。

说明：SpringBoard 在该设备上不向 XCUITest 暴露锁屏通知标题，因此不把通知标题可见性冒充自动化证据；本轮采用系统 pending/delivered 状态、通知权限状态和真机终止后回读作为可重复断言。

## 4. 构建、安装与启动

| 检查项 | 结果 |
|---|---|
| arm64 设备构建 | `BUILD SUCCEEDED` |
| 签名 | `codesign --verify --deep --strict` 通过 |
| 测试载荷隔离 | App 包内无 `.xctest` / XCTest framework |
| 能力校验 | 未包含个人团队不支持的 Time Sensitive Notifications entitlement |
| 覆盖安装 | 成功，bundle ID `com.edward.FitnessApp` |
| 正常启动 | 成功，CoreDevice 返回 launched |

安装采用覆盖安装，没有卸载 App、没有清空容器。

## 5. 正式数据保护与迁移回读

### 安装前保底备份

`/Users/edward/Documents/X-Fit_Device_Backups/20260821T123310+0800_freestyle_final_go`

### 安装后权威库备份

`/Users/edward/Documents/X-Fit_Device_Backups/20260821T133140+0800_freestyle_appgroup_audit`

当前 App 的权威 SwiftData 库位于 `group.com.edward.FitnessApp` App Group 容器；旧应用容器中的 `default.store` 仍保留，未被删除。权威库在 App 正常终止后复制，以便 SQLite 一致性回读。

| 检查项 | 安装后结果 |
|---|---:|
| SQLite `integrity_check` | ok |
| sessions | 15 |
| session exercises | 101 |
| set logs | 442 |
| completed sets | 431 |
| historical volume | 140493.75 |
| exercises | 56 |
| schedules | 15 |

数据连续性核对：旧库中的 15 个 session、101 个 session exercise、442 个 set log、55 个 exercise 和 8 个 schedule 均可在权威库按 ID 找到；已完成组数量与历史训练量完全一致。旧历史记录没有被补写 `startedAt`、间歇起止或间歇秒数，也没有被强制改写 rest mode。

新增 schema 回读通过：

- `ZSETLOG`：`ZSTARTEDAT`、`ZRESTSTARTEDAT`、`ZRESTENDEDAT`、`ZRESTDURATIONSECONDS`
- `ZWORKOUTSESSION`：`ZRESTMODERAW`

## 6. 最终结论

本候选版本满足完整 Go 门禁，已在 Edward_iPhone 上覆盖安装并正常启动，可以进入实际使用。后续训练可选择固定倒计时或 Freestyle；漏记间歇时可在历史记录中补录，既有训练量和历史数据保持不变。
