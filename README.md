# X-Fit

X-Fit 是一款面向 iPhone 的中文力量训练计划与记录 App。当前版本使用 SwiftUI、SwiftData 和 Swift Charts，最低支持 iOS 17。

## 当前可用功能（0.3.0）

- 按星期创建和编辑训练模板
- 自动生成训练安排，并支持改期、跳过、恢复和临时加练
- 按当天需求选择肌群，结合真实完成历史给出恢复与训练建议
- 推荐近期较少使用的动作，降低上一份同肌群菜单的重复权重
- 选择动作时显示上次组数、最佳组、RIR、容量和注意事项
- 把推荐动作编排成当天一次性菜单，不污染固定周计划
- 手动补录过去训练，或通过 CSV 批量同步并按 `session_id` 防重复
- 新建、编辑、搜索、归档和恢复自定义动作
- 今日训练与后续计划总览
- 开始训练时生成独立快照，模板修改不会污染历史
- 逐组记录重量、次数和 RIR
- 自动带入同一动作上一次完成的重量和次数
- 训练备注、组间休息计时、锁屏提醒、异常退出后继续训练
- 历史训练详情、训练容量、估算 1RM 与进阶建议
- 按日期记录餐食、热量、三大营养素和每日目标
- 记录体重、体脂、围度和体重趋势
- 可选写入 Apple 健康的传统力量训练，并主动读取体重/体脂
- 完整 JSON 备份/非覆盖恢复，以及逐组训练 CSV 导出
- 本机离线存储，不需要账号或服务器

## 打开项目

```bash
open FitnessApp.xcodeproj
```

项目文件由 `project.yml` 生成。修改项目结构后运行：

```bash
xcodegen generate
```

## 自动化验证

仓库位于 File Provider 管理目录时，建议把 DerivedData 放到 `/tmp`，避免测试包继承 Finder 扩展属性：

```bash
FITNESS_DERIVED_PATH=$(mktemp -d /tmp/fitnessapp-derived.XXXXXX)
xcodebuild -project FitnessApp.xcodeproj \
  -scheme FitnessApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$FITNESS_DERIVED_PATH" \
  test
```

当前共有 18 项单元测试和 6 项 UI 测试，覆盖训练指标、日程状态、放弃训练、备份恢复、自适应推荐、肌群恢复、当天菜单、历史补录与同步入口。

真机人工验收入口：

- [真机人工测试清单](docs/X-Fit_真机人工测试清单.md)
- [人工测试流程说明](docs/X-Fit_人工测试流程说明.md)
- [0.2.0 实现与自动化测试报告](docs/X-Fit_0.2.0_实现与自动化测试报告.md)
- [0.3.0 自适应训练与历史同步测试清单](docs/X-Fit_0.3.0_自适应训练与历史同步测试清单.md)
- [0.3.0 实现与自动化测试报告](docs/X-Fit_0.3.0_实现与自动化测试报告.md)
- [历史训练导入模板](docs/X-Fit_历史训练导入模板.csv)

## 数据边界

- `WorkoutTemplate` / `TemplateExercise`：可持续修改的周计划模板
- `ScheduledWorkout`：具体日期的训练安排
- `WorkoutSession` / `SessionExercise`：开始训练时生成的历史快照
- `SetLog`：实际完成的逐组记录
- `NutritionTarget` / `MealEntry`：每日目标和按日期保存的真实餐食
- `BodyMeasurement`：本机或主动从 Apple 健康导入的身体数据

当前权威数据保存在设备本地，并可导出 JSON/CSV。HealthKit 与本地通知按用户选择启用。iCloud、Live Activity 和 Apple Watch 尚未启用；watchOS 将在 iPhone v1.0 真机稳定后开发。
