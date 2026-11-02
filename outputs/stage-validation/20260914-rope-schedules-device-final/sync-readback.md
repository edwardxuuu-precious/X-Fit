# 周二、周六跳绳日程无线补充回读

- 设备：`Edward_iPhone`（物理设备）
- 连接：`transportType=localNetwork`、`tunnelState=connected`、`ddiServicesAvailable=true`
- 安装方式：签名 Release 无线覆盖安装；未卸载 App，未清除容器
- 安装版本：`0.5.0 (11)`
- 运行状态：首次自动启动因设备锁屏被拒；解锁后的重试于 `2026-09-14 15:19:58 +0800` 成功
- 数据库完整性：安装前、安装后均为 `PRAGMA quick_check=ok`

## 补充写入与幂等

| 执行 | 新增日程 | 日程总数 | 结果 |
|---|---:|---:|---|
| 首次无线补充 | 2 | 29 → 31 | `ROPE_TUE_LB3`、`ROPE_SAT_LB3` 各新增 1 条 |
| 第二次重复执行 | 0 | 31 → 31 | 幂等通过，无重复日程 |

- 首次回执：`artifacts/stage-validation/20260914-rope-wireless-sync/receipt-first.json`
- 重复回执：`artifacts/stage-validation/20260914-rope-wireless-sync/receipt-repeat.json`

## 最终活动库

| 实体 | 数量 |
|---|---:|
| WorkoutSession | 40 |
| SessionExercise | 233 |
| SetLog | 962 |
| BodyMeasurement | 12 |
| MealEntry | 23 |
| JumpRopeEntry | 1 |
| ScheduledWorkout | 31 |
| ProgramWorkoutLink | 8 |
| TrainingPreferenceRevision | 3 |
| TrainingProgramRevision | 3 |

- 日程状态：`completed=8`、`planned=5`、`skipped=18`。
- 安装前后上述 10 类实体的既有 UUID 缺失数均为 0。
- 本次只补正式日程；既有训练、组记录、体重、餐食和实际跳绳记录数量未变化。

## 当前 5 条 planned 日程

| 日期 | 日程 | 编排代码 |
|---|---|---|
| 2026-09-14 | 下肢前链＋足踝 · 高消耗 | `LOWER_FRONT_LB3` |
| 2026-09-15 | 跳绳间歇 · 技术与燃脂 | `ROPE_TUE_LB3` |
| 2026-09-16 | 下肢后链＋足踝 · 高消耗 | `LOWER_POSTERIOR_LB3` |
| 2026-09-18 | 下肢前后链整合＋足踝 | `LOWER_INTEGRATED_LB3` |
| 2026-09-19 | 跳绳混合间歇 · 燃脂 | `ROPE_SAT_LB3` |

- `ROPE_TUE_LB3` 与 `ROPE_SAT_LB3` 在 `ProgramWorkoutLink` 中均恰好 1 条。
- 9 月 13 日餐食按确认边界仍未同步。

## 自动化证据边界

- 本轮统一 `non-device` 的 N01～N05、N07 通过；N06 全量 103 条 UI 场景保留 3 条原始失败证据。
- 三条失败均已隔离处理并复跑：系统菜单粘贴通过；跳绳导入/今日页/日程页流程通过；旧导入导出流程在文案期望更新后通过。
- 隔离结果：`/tmp/xfit-rope-isolated-reruns.xcresult`、`/tmp/xfit-rope-cycle-rerun.xcresult`。
- 统一 device 流程的 D00～D04、D06A～D06C 通过；D05 覆盖安装成功，原流程仅因锁屏导致启动子步骤失败，解锁后的独立启动重试和安装版本回读均通过。
- 真机 XCTest 未获单独授权，状态为 `NOT_RUN`；真人页面检查仍为 `BLOCKED_HUMAN`。
