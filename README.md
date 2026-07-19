# FitnessApp

一款面向 iPhone 的中文力量训练计划与记录 App。当前版本使用 SwiftUI、SwiftData 和 Swift Charts，最低支持 iOS 17。

## 当前可用功能

- 按星期创建和编辑训练模板
- 自动生成未来 14 天训练安排
- 今日训练与后续计划总览
- 开始训练时生成独立快照，模板修改不会污染历史
- 逐组记录重量、次数和 RIR
- 自动带入同一动作上一次完成的重量和次数
- 组间休息计时、异常退出后继续训练
- 历史训练详情、训练容量、估算 1RM 与进阶建议
- 完全本机存储，当前不需要账号或服务器

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

当前测试覆盖训练容量、估算 1RM、进阶规则，以及“开始训练 → 完成第一组 → 启动休息计时”的界面闭环。

## 数据边界

- `WorkoutTemplate` / `TemplateExercise`：可持续修改的周计划模板
- `ScheduledWorkout`：具体日期的训练安排
- `WorkoutSession` / `SessionExercise`：开始训练时生成的历史快照
- `SetLog`：实际完成的逐组记录

当前数据只保存在设备本地。iCloud、HealthKit、通知、Live Activity 和 Apple Watch 尚未启用。
