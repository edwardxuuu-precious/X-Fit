# X-Fit 真机复验补充

- Run ID：`20260830-daily-planner-device-rerun`
- 设备：`Edward_iPhone` / iPhone 17 / iOS 26.6
- 结论：自动化真机层通过；真人体验仍为 `BLOCKED_HUMAN`

## 自动化结果

- 真机签名 Release 构建、覆盖安装、启动与版本回读通过。
- 真机全量单元测试：157 项通过，0 失败。
- 真机全量 UI 首轮：59 项中 56 项通过；2 项被 SpringBoard 通知横幅遮挡，1 项为真机滚动时序超时。
- 3 个失败用例集中复验：3 项通过，0 失败；证据为 `artifacts/stage-validation/20260830-daily-planner-device-rerun/device-ui-failed-retry.xcresult`。
- 综合首轮与集中复验，59 项真机 UI 均已有通过证据，未确认产品失败。

## 最终安装与数据守恒

- 最终重新覆盖安装并启动 Release `0.5.0 (11)`；未卸载、未清容器。
- 最终活动数据库 `PRAGMA quick_check`：`ok`。
- 安装前、全量测试后、失败项复验后及最终 Release 安装后，核心记录均未减少：
  - `ZWORKOUTSESSION`：20 → 20
  - `ZSESSIONEXERCISE`：137 → 137
  - `ZSETLOG`：581 → 581
- 最终证据：`artifacts/stage-validation/20260830-daily-planner-device-rerun/device-audit/final-release/`。

## 剩余门禁

- 真人主观体验与系统权限清单尚未由用户确认，不能以自动化结果替代。
