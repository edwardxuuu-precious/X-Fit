# X-Fit Notes 真机写入结果

- 执行日期：2026-08-31；最终回读：2026-09-01
- 设备：`00008150-001E49912122401C`
- App：`com.edward.FitnessApp`，`0.5.0 (11)`
- 写入方式：活动 App Group 备份后覆盖安装；未卸载、未清容器

## Notes 导入

| 检查 | 结果 | 状态 |
|---|---:|---|
| CSV SHA-256 | `cd57038052b0ce43a8cd2514cef8ee29218af39331a4d72f5b8e777b4aefdbdc` | PASS |
| 首次导入 | 13 场、53 个动作快照、204 组；新建 26 个动作 | PASS |
| 第二次导入 | 新增 0 场、0 组；跳过 13 场 | PASS |
| 8 月 22 日 | 保留 App 原有 1 场，没有 Notes 重复记录 | PASS |
| 导入后核心计数 | 35 场、200 个动作快照、822 组 | PASS |
| SQLite | `PRAGMA quick_check=ok` | PASS |
| 进行中训练 | 1 场；6 个动作、25 组保持存在 | PASS |

首次与第二次回执：

- `artifacts/stage-validation/20260831-training-record-optimization-notes-import/unlocked-first-receipt.json`
- `artifacts/stage-validation/20260831-training-record-optimization-notes-import/unlocked-second-receipt.json`

## 目录与自重迁移

- 已回读确认传统硬拉、哑铃侧边蹲、地雷杆转体、地雷杆泽奇蹲均为 `kilogram`，肌群和器械已按确认结果修正。
- 既有自重历史快照继续使用 84 kg；首次 Notes 导入产生的 4 个自重快照最初因本地 `BodyMeasurement` 为空且本轮 Health 查询未返回值而暂为“暂无体重”，未写成 0 kg。
- 已实现并通过测试的最终回退规则：本地体重与 Health 均不可用时，使用最近已有的非空自重快照。`final5` 的 N01–N07 全部 PASS。
- 最终修正版已覆盖安装；2026-09-01 设备解锁后成功启动并回读，全部 12 个自重快照均为 84 kg，缺失数为 0。
- 最终回读 `PRAGMA quick_check=ok`；核心计数保持 35 场、200 个动作快照、822 组；进行中训练保持 6 个动作、25 组。

## 2026-09-02 最终 Release 回读

- 真实训练已结束；Release `0.5.0 (11)` 再次覆盖安装、启动和手机端版本回读通过。
- 五组已确认同义动作均完成收口：每组 1 个活跃主动作、1 个归档别名，未来计划引用归档别名数为 0；已完成历史快照不改名。
- 安装后 App Group `PRAGMA quick_check=ok`；安装前 35/200/822 条核心记录的 ID 缺失数均为 0。

## 尚未完成的门禁

- 真人确认键盘收起、编排卡片层级和动作总时长。
