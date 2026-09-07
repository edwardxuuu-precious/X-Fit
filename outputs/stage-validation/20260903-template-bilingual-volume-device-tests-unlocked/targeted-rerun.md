# X-Fit 真机失败集独立复跑

- 设备：`Edward_iPhone`
- 版本：`0.5.0 (11)`
- 测试结果包：`/tmp/xfit-template-device-two-failures-rerun.xcresult`
- 结论：`2 FAIL / 2`

| 用例 | 结果 | 实际失败点 | 边界 |
|---|---|---|---|
| `testActionEditorSystemMenuSelectAllAndPasteUpdatesField` | FAIL | 长按并全选动作名称后，系统“粘贴/Paste”菜单未在 2 秒内出现 | 真机稳定复现；未证明输入框值无法通过其他方式修改 |
| `testDeviceTemplateWritebackAfterFinishAndPersist` | FAIL | 模板卡片显示 4 个动作，但编辑器连续三次加载为空 | 尚未进入训练完成和模板参数回写步骤；服务层回写单元测试已通过 |

## 全量中与本需求直接相关的通过项

- `testExerciseLibraryFindsChineseExerciseByEnglishAliasAndShowsEquipmentMuscleGroup`
- `testExerciseLibrarySearchesSquatAliasAndSupportsEditDeleteRestore`
- `testSpecialTemplateEditorExposesMuscleMultiselectAndExerciseReordering`
- `testStatsVolumeTrendSwitchesFromOverallToExerciseHistory`

## 数据保护

- 定向复跑后 SQLite `quick_check=ok`。
- `ZSESSIONEXERCISE=199`
- `ZSETLOG=825`
- `ZWORKOUTSESSION=35`
- 与全量测试前一致，核心记录未减少。
