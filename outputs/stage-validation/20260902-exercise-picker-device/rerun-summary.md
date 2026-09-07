# 真机 UI 失败候选串行复跑摘要

- 时间：`2026-09-03 00:20–00:39 +0800`
- 设备：`Edward_iPhone`（iPhone 17）
- 方式：关闭并行，串行复跑首次全量真机 UI 中的 7 个失败/未完成候选。

## 结果

| 用例 | 结果 | 说明 |
|---|---|---|
| `testActionEditorSystemMenuSelectAllAndPasteUpdatesField` | FAIL | 真机 XCTest 通用剪贴板不可用，系统 Paste 菜单未出现；与首次失败一致。 |
| `testActiveWorkoutUsesExplicitRIRChoiceAndOneActionLevelSideControl` | PASS | 串行复跑通过。 |
| `testDailyBodyCheckInCreatesBothMarkerTypesAndCancellationIsSafe` | PASS | 串行复跑通过。 |
| `testDeviceTemplateWritebackAfterFinishAndPersist` | FAIL | 三次尝试均未加载出模板动作列表，命中既有持久化慢查询竞态。 |
| `testExerciseLibraryFindsChineseExerciseByEnglishAliasAndShowsEquipmentMuscleGroup` | PASS | 串行复跑通过。 |
| `testExercisePickerFiftyCycleStressPreservesMenuAndAvoidsDuplicates` | PASS | 50 轮完整通过，耗时 882.162 秒。 |
| `testHistoricalWorkoutImportIsReachableFromProfile` | PASS | 串行复跑通过。 |

本需求的真机主链路 `testExercisePickerDismissesKeyboardAndEditsBuiltInDefinitionWithoutSelecting` 已在首次全量真机 UI 中通过；串行压力测试也已通过。两项剩余失败均不属于本需求动作选择器主链路，但会继续阻断阶段级 GO。

## 证据边界

- 测试套件结束后 Xcode 出现本机密码提示；未输入密码，并在测试结果已打印后终止该进程。
- 因进程终止，`device-ui-rerun.xcresult` 未完成封装；本摘要依据本轮终端 XCTest 逐条结果。
- 复跑后再次复制活动 App Group 数据：`PRAGMA quick_check=ok`。
- 核心记录保持不变：`ZSESSIONEXERCISE=199`、`ZSETLOG=825`、`ZWORKOUTSESSION=35`。
