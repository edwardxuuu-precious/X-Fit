# X-Fit 真机自动化恢复与最终数据回读

- 设备：Edward_iPhone（iPhone 17，iOS 26.6）
- 候选包：0.5.0 (11)
- 安装方式：覆盖安装；未卸载、未清容器
- 最终结论：真机自动化有效通过；Release 0.5.0 (11) 已重新覆盖安装并留在设备；活动数据完整且安装前旧记录全部保留

## 自动化结果

- 真机全量单元测试：171 项执行，170 项通过，1 项按环境能力跳过，0 失败。
- 真机 UI 首次门禁被残留自动化服务阻断，未产生产品测试结果；清理残留服务后恢复。
- 恢复后的完整 UI 套件执行 61 项：52 项直接通过，7 项因组间休息功能已确认移除而跳过，2 项暴露测试手势坐标/等待方式问题。
- 修正测试后，训练页三位小数与滑动收键盘、器械拍照识别两项真机定向复跑 2/2 通过。
- 因而当前 54 个有效 UI 用例均有真机 PASS 证据；7 个跳过项均对应已废弃的组间休息功能。
- 首页体重主链路真机通过：渐进展开、键盘“完成”、可见内容区滑动、点击非输入区、84.2 kg 保存与首页回显。

## 数据回读

- 自动化复验结束时的 App Group 只读备份：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-data/post-final-rerun/`
- SQLite：`PRAGMA quick_check=ok`
- 安装前与自动化复验后核心计数：
  - `ZWORKOUTSESSION`：35 → 35
  - `ZSESSIONEXERCISE`：200 → 200
  - `ZSETLOG`：822 → 822
- 比较证据：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-audit/pre-install-to-post-final-rerun.tsv`

## 最终 Release 留机门禁

- 2026-09-02 在设备重新连接后，重新核验候选签名并覆盖安装 Release `0.5.0 (11)`；启动成功，手机端版本回读为 `0.5.0 / 11`。
- 安装后 App Group 只读备份：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-data/post-final-release/`
- SQLite：`PRAGMA quick_check=ok`。
- 相对安装前基线，核心计数为训练 `35 → 38`、动作 `200 → 215`、组 `822 → 876`，三个实体的 `missing_old_ids` 均为 `0`，没有旧记录丢失。
- 新增量已核对为两次 2026-09-01 的已放弃测试训练，以及一条 2026-09-02 09:23–10:37 的已完成训练；保留现场数据，未做删除或修复。
- 活动训练已结束，启动迁移已完成五组同义动作收口：每组只保留 1 个活跃主动作、归档 1 个别名，未来计划对归档别名的引用均为 0；已完成历史快照未改名。
- 安装、启动、版本和数据比较证据分别为 `final-release-install.json`、`final-release-launch.json`、`final-release-readback.json` 与 `device-audit/pre-install-to-post-final-release.tsv`。

## 证据

- 完整真机 UI：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-ui-final-rerun.xcresult`
- 两项恢复复跑：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-ui-two-failures-rerun.xcresult`
- 体重与键盘定向链路：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-ui-visible-drag-smoke.xcresult`
- 最终 non-device：`outputs/stage-validation/20260901-weight-entry-keyboard-final3/summary.md`
- 最终 Release 数据差异说明：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-audit/post-final-release/new-session-breakdown.tsv`
- 五组同义动作回读：`artifacts/stage-validation/20260901-weight-entry-keyboard-device-final/device-audit/post-final-release/confirmed-alias-groups.tsv`

## 剩余门禁

- 真人确认首页体重入口、趋势层级、真实中文/数字键盘手感、动作卡层级和动作总时长。
