# X-Fit

X-Fit 是一款面向 iPhone 的中文力量训练计划与记录 App。当前版本使用 SwiftUI、SwiftData 和 Swift Charts，最低支持 iOS 17。

## 当前可用功能（0.2.0）

- 按星期创建和编辑训练模板
- 自动生成训练安排，并支持改期、跳过、恢复和临时加练
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

当前共有 10 项单元测试和 3 项 UI 测试，覆盖训练指标、日程状态、放弃训练、备份恢复单例边界，以及训练、日程、营养和设置入口。

真机人工验收入口：

- [真机人工测试清单](docs/X-Fit_真机人工测试清单.md)
- [人工测试流程说明](docs/X-Fit_人工测试流程说明.md)
- [0.2.0 实现与自动化测试报告](docs/X-Fit_0.2.0_实现与自动化测试报告.md)

## 数据边界

- `WorkoutTemplate` / `TemplateExercise`：可持续修改的周计划模板
- `ScheduledWorkout`：具体日期的训练安排
- `WorkoutSession` / `SessionExercise`：开始训练时生成的历史快照
- `SetLog`：实际完成的逐组记录
- `NutritionTarget` / `MealEntry`：每日目标和按日期保存的真实餐食
- `BodyMeasurement`：本机或主动从 Apple 健康导入的身体数据

当前权威数据保存在设备本地，并可导出 JSON/CSV。HealthKit 与本地通知按用户选择启用。iCloud、Live Activity 和 Apple Watch 尚未启用；watchOS 将在 iPhone v1.0 真机稳定后开发。
