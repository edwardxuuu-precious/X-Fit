# 专项模板与系统粘贴修复：真机定向复验

- 设备：`Edward_iPhone`（iPhone 17）
- 执行时间：`2026-09-03 16:00–16:02 +0800`
- 范围：修复前真机全量 UI 中稳定失败的两条用例
- 结果：`PASS`（2/2，0 失败）

## 用例结果

| 用例 | 验证结果 | 状态 |
|---|---|---|
| `testActionEditorSystemMenuSelectAllAndPasteUpdatesField` | 系统长按、全选、粘贴及文本更新成功 | PASS |
| `testDeviceTemplateWritebackAfterFinishAndPersist` | 专项模板稳定载入；完成训练后杠铃卧推 3 组回写为 44kg × 10；未完成的上斜哑铃卧推保持 16kg | PASS |

## 数据守恒

测试前后活动 App Group 数据库均为 `PRAGMA quick_check = ok`：

| 核心表 | 测试前 | 测试后 |
|---|---:|---:|
| `ZSESSIONEXERCISE` | 199 | 199 |
| `ZSETLOG` | 825 | 825 |
| `ZWORKOUTSESSION` | 35 | 35 |

## 证据

- XCTest：`artifacts/stage-validation/20260903-template-bugfix-targeted-device-unlocked/device-targeted.xcresult`
- 测试前备份：`artifacts/stage-validation/20260903-template-bugfix-targeted-device-unlocked/device-data/pre-tests/`
- 测试后备份：`artifacts/stage-validation/20260903-template-bugfix-targeted-device-unlocked/device-data/post-tests/`

## 剩余门禁

- 本轮是原失败集的真机定向复验，不等同于修复后全量真机 UI 重跑。
- 系统粘贴的真人响应手感仍需人工确认。
- 未执行 Git commit、tag、push 或发布。
