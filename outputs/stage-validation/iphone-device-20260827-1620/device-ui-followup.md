# X-Fit 真机 UI 补充验证

- 设备：Edward_iPhone（iPhone 17，iOS 26.6）
- App：X-Fit 0.5.0 (11)
- 安装方式：覆盖安装；未卸载、未清容器

## 核心需求复跑

结果：4/4 PASS。

- RIR 明确选择与点击：PASS
- 今日计划名称小卡拖动排序：PASS
- 同一分享草稿稍后处理后不再自动提醒、新 ID 恢复提醒：PASS
- 最后一组完成后先收集动作感受再折叠并持久化：PASS

证据：`artifacts/stage-validation/iphone-device-20260827-1620/device-ui-core-4.xcresult`

## 全量 UI 回归

首次完整执行 57 项：53 PASS、4 FAIL。测试本身已执行结束；失败诊断收集阶段调用 `devicectl diagnose` 时触发管理员密码提示，因此该次 `device-ui-resume-2.xcresult` 未完整封包，不能作为可读取的最终结果包。

失败项及复核：

1. `testCountdownRestDeliversOneBackgroundNotification`：聚焦复跑仍 FAIL，但失败发生在准备阶段找不到“开始训练”，尚未进入通知排程、后台等待或送达断言；当前只能判为测试前置状态/导航问题，不能据此判定通知功能失败。
2. `testExercisePickerFiftyCycleStressPreservesMenuAndAvoidsDuplicates`：前 38 轮通过，第 39 轮被系统通知抢占后自动化无法返回计划，FAIL；这是当前仍需跟进的通知抢占交互边界。
3. `testShareDraftEditorCancellationKeepsDraftAvailable`：聚焦复跑 PASS，判定为全量运行中的偶发自动化时序。
4. `testUITestShareDraftDoesNotLeakIntoProductionStartup`：真机存在真实生产分享草稿，且用例按数据保护规则不会在真机清空生产草稿；这是夹具与真机真实状态冲突，不判为 UI 测试草稿泄漏。

短失败复跑结果：1 PASS、1 FAIL。证据：`artifacts/stage-validation/iphone-device-20260827-1620/device-ui-short-failure-rerun.xcresult`。

## 用户数据守恒

最终 UI 测试后 App Group 数据库 `PRAGMA quick_check=ok`，核心记录与安装前一致：

- `ZSESSIONEXERCISE = 137`
- `ZSETLOG = 581`
- `ZWORKOUTSESSION = 20`

证据：`artifacts/stage-validation/iphone-device-20260827-1620/device-data/post-ui-final/default.store`

## 当前边界

- 本次四项用户需求的真机专项自动化均已通过。
- 全量 UI 套件不是全绿；通知测试前置状态与通知抢占后的返回路径仍需后续修复/加固。
- Instruments 内存曲线与真人流畅度验收仍未执行，不能宣称真机性能已经完全验收。
