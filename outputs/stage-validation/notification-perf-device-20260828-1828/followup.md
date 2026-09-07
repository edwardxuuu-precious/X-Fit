# X-Fit 真机自动化与性能续测

> 2026-09-05 存储清理：本页引用的旧 `.trace`、`.xcresult` 和部分测试媒体已按用户要求删除；轻量统计、摘要和真实设备数据保留。本页结论仅为当时记录，本轮未重新测试。逐项清单见 [清理记录](../20260905-storage-cleanup/summary.md)。

- Run ID：`notification-perf-device-20260828-1828`
- 设备：iPhone 17 / iOS 26.6
- 安装方式：签名 Release 覆盖安装；未卸载、未清容器
- 自动化结论：PASS（真人主观体验仍为 `BLOCKED_HUMAN`）

## 真机测试收口

- 真机单元测试：154/154 PASS。
- 真机全量 UI 首轮复跑：56/57 PASS；请求涉及的通知、RIR、感受、分享草稿与拖动排序均 PASS。
- 唯一失败项 `testExercisePickerFiftyCycleStressPreservesMenuAndAvoidsDuplicates` 的根因是 XCTest 在“新建动作”关闭动画结束前点击底层选择器，并非产品数据或业务逻辑失败。
- 修正测试等待条件后，模拟器 50/50 PASS；真机最终 50/50 PASS，用时 859.593 秒。期间出现两次真实系统通知横幅抢占，均自动恢复；最终新增第 5 个动作及去重断言 PASS。
- 真机最终证据：`artifacts/stage-validation/notification-perf-device-20260828-1828/device-stress-race-fixed-v7.xcresult`。

## Instruments

| 模板 | 状态 | 结果 | 证据 |
|---|---|---|---|
| App Launch | PASS | 冷启动至 `Foreground - Active` 约 480.47 ms；其中进程创建 321.23 ms，首帧渲染 57.82 ms | `instruments/app-launch.trace`、`instruments/app-launch-lifecycle.xml` |
| Allocations | PASS | X-Fit 本体连续采样 120.982 秒；结束时 Heap + Anonymous VM 常驻约 91.0 MiB，其中 Heap 约 80.0 MiB | `instruments/stress-app-allocations.trace`、`instruments/stress-app-allocations-statistics.xml` |
| Leaks | PASS | 独立采样 31.050 秒，导出的 Leaks 明细为 0 条 | `instruments/app-leaks.trace`、`instruments/app-leaks-detail.xml` |
| Time Profiler | PASS | 拖动排序真机测试同时通过；3.239 秒记录 346 个 1ms CPU 样本，没有单一 App 热点占主导 | `instruments/drag-time-profiler-v2.trace`、`instruments/drag-time-profiler-detail.xml` |
| Animation Hitches | PASS | 拖动排序真机测试同时通过；0 个渲染 hitch、0 个 250ms 以上 hang；记录 1 次 52.46ms potential interaction delay | `instruments/drag-animation-hitches.trace`、`instruments/drag-animation-hitches-detail.xml`、`instruments/drag-animation-potential-hangs.xml` |

边界：这些数据支持“本轮未检测到严重泄漏或持续卡顿热点”，但不能替代真人对长时间真实训练流程的主观流畅度确认。

## 最终活动数据回读

- SQLite `quick_check=ok`。
- `ZSESSIONEXERCISE=137`。
- `ZSETLOG=581`。
- `ZWORKOUTSESSION=20`。
- 与安装前、安装后和测试后基线一致，覆盖安装、真机测试及 Instruments 后核心记录未减少。
- 证据：`artifacts/stage-validation/notification-perf-device-20260828-1828/device-audit/final-post-profile/`。

## 阶段状态

- 自动化层：PASS。
- 活动数据守恒：PASS。
- 真人主观流畅度与视觉体验：`BLOCKED_HUMAN`，由用户按 `真机人工测试清单.md` 确认。
- 未执行 Git commit、tag、push 或发布。
