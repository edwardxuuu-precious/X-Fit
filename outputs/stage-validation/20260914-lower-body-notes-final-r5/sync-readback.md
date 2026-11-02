# 下肢专项周与 Notes 增量真机同步回读

- 设备：`Edward_iPhone`（无线隧道）
- App：`X-Fit 0.5.0 (11)`
- 结果：同步、幂等复跑、正式包覆盖安装与数据守恒通过；真人页面验收待用户完成。

## 执行结果

- Xcode 已登录 `Jiarui Xu / edwardxjr@gmail.com`；App 与 Share Extension 的开发描述文件由 Xcode 自动生成。
- 维护构建与最终构建均通过无线方式覆盖安装；全程未卸载 App、未清容器。
- 首次维护构建安装后，iOS 要求用户信任开发者；用户完成信任后启动通过。
- 一次文件复制参数把完整目标路径误写成 `Documents`；反向读取确认该文件 SHA-256 与原同步包一致，且活动 SwiftData 位于独立 App Group、未被修改。下一次覆盖安装重建标准 Documents 目录；首次同步启动因包不存在而返回错误回执，新增和撤销均为 0。
- 按正确完整路径 `Documents/confirmed-notes-increment-v2.json` 重新复制后，设备回读 SHA-256 为 `da64ceab6e582a6ee48c64bb08ce70553faddb29fd9467b31b0a549aaf446f4f`，与源文件一致。

## 首次有效同步

| 项目 | 结果 |
|---|---:|
| 新增训练 | 2 |
| 新增动作快照 | 15 |
| 新增组记录 | 63 |
| 新增体重 | 9 |
| 新增餐食 | 16 |
| 新增跳绳 | 1 |
| 新建动作 | 13 |
| 作废旧餐食 | 2 |
| 撤销旧未完成计划 | 16 |
| 新增力量日程 | 3 |

- 新日程：9 月 14 日“下肢前链＋足踝 · 高消耗”、9 月 16 日“下肢后链＋足踝 · 高消耗”、9 月 18 日“下肢前后链整合＋足踝”。
- 跳绳：9 月 10 日 1600 个；未编造缺失时长。
- 9 月 11 日与 9 月 12 日训练已按 `confirmed-notes:notes-20260910-20260912-v2` 导入。
- 9 月 13 日餐食计数为 0，符合本轮暂不同步决定。
- 回执：`../20260914-lower-body-notes-maintenance-r4/first-sync-receipt-success.json`。

## 第二次幂等同步

- 新增训练、动作、组、体重、餐食、跳绳、日程和偏好/编排版本均为 0。
- 跳过既有训练 2、体重 9、餐食 16、跳绳 1；2 条旧餐报告为已作废。
- 第一次和第二次同步后的 10 类实体数量及 ID 集合完全一致。
- 回执：`../20260914-lower-body-notes-maintenance-r4/second-sync-receipt.json`。

## 最终正式包回读

| 实体 | 数量 | ID 唯一数 |
|---|---:|---:|
| WorkoutSession | 40 | 40 |
| SessionExercise | 233 | 233 |
| SetLog | 962 | 962 |
| BodyMeasurement | 12 | 12 |
| MealEntry（物理记录） | 23 | 23 |
| MealEntry（有效） | 21 | 21 |
| JumpRopeEntry | 1 | 1 |
| ScheduledWorkout | 29 | 29 |
| TrainingPreferenceRevision | 3 | 3 |
| TrainingProgramRevision | 3 | 3 |
| ProgramWorkoutLink | 6 | 6 |

- 日程状态：completed 8、planned 3、skipped 18；其中 16 条由本轮确认决定撤销。
- 两条旧冲突餐食保留物理记录并设为作废；其余 21 条有效。
- 最终数据库 `PRAGMA quick_check=ok`。
- 第二次同步后与最终包覆盖安装后，以上 10 类实体数量和 ID 集合全部一致。
- 一次性 `confirmed-weekly-sync` 启动入口与回执类型已从正式源码移除；Swift 解析、`git diff --check` 与最终签名 Release 构建通过。
- 最终 device 门禁 D00～D06C 通过；D07 真机 XCTest 未执行，D09 真人体验保持 `BLOCKED_HUMAN`。

## 证据

- 维护构建与同步：`artifacts/stage-validation/20260914-lower-body-notes-maintenance-r4/`
- 最终正式包：`artifacts/stage-validation/20260914-lower-body-notes-final-r5/`
- 最终阶段摘要：`outputs/stage-validation/20260914-lower-body-notes-final-r5/summary.md`
