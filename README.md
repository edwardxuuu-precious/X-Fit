# X-Fit

X-Fit 是一款面向 iPhone 的中文力量训练计划与记录 App。当前版本使用 SwiftUI、SwiftData 和 Swift Charts，最低支持 iOS 17。

## 当前可用功能（0.5.0）

- 按星期创建和编辑训练模板
- 自动生成训练安排，并支持改期、跳过、恢复和临时加练
- 按当天需求选择肌群，结合真实完成历史给出恢复与训练建议
- 推荐近期较少使用的动作，降低上一份同肌群菜单的重复权重
- 选择动作时显示上次组数、最佳组、RIR、容量和注意事项
- 把推荐动作编排成当天一次性菜单，不污染固定周计划
- 手动补录过去训练，或通过 CSV 批量同步并按 `session_id` 防重复
- 新建、编辑、搜索、归档和恢复自定义动作
- 为当前动作生成受控的标准中英文、canonical ID、置信度和歧义候选，并在设置中逐项人工审核
- 审核决定与原始动作名分开保存；已完成训练快照不改名，动作 UUID、PR 和上次重量不自动合并
- 同名动作的肌群、器械或计量单位冲突时，动作库、CSV 导入和设备合并会停止并要求审核
- 预留 DeepSeek 等模型的 HTTPS 代理合约；App 不保存 Provider API Key，未配置代理时只使用本地候选库
- 当天编排和训练中都可搜索完整动作库；没有结果时可原地“新建并加入”，当前菜单不会丢失
- 自定义动作可保存学习资料链接，开始训练后链接与动作要点会进入独立历史快照
- 首页可直接调整今天菜单，日程页可调整指定日期的计划或恢复已跳过日程
- Safari 和其他 App 可通过 Share Extension 把链接/文字交给 X-Fit，回到 App 后补全动作信息再保存
- 今日训练与后续计划总览
- 首页“今日训练”直接呈现当天唯一菜单，不显示无实际用途的“查看全部”入口
- 首页不重复底部“训练 / 进度 / 我的”导航；日程由“接下来”统一管理，历史同步收纳到“我的”
- 今日训练背景图会根据推、拉、腿、核心或综合训练目标自动切换，图片离线内置并保留许可来源
- 首页支持本周/本月进度切换，按日或自然周显示训练容量柱图、计划完成率、工作组、时长和同期对比
- 开始训练时生成独立快照，模板修改不会污染历史
- 逐组记录重量、次数和 RIR
- 训练中按当天状态增减未完成组、修改重量与次数；RIR 提供中文解释并允许不记录
- 自动带入同一动作上一次完成的重量和次数
- 组间休息支持固定倒计时（±30 秒、锁屏提醒）与 Freestyle 自由记录；下一组开始时保存真实间歇，漏记后可在历史按组补录
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

当前共有 132 项单元测试和 32 项 UI 测试，覆盖训练指标、周/月周期汇总、日程状态、放弃训练、备份恢复、动作 canonical 身份、术语审核、同名冲突保护、AI 代理边界、自适应推荐、肌群恢复、目标背景图、首页导航去重、当天菜单、动作原地补录、分享草稿、参考链接、历史补录与同步入口。

真机人工验收入口：

- [真机人工测试清单](docs/X-Fit_真机人工测试清单.md)
- [人工测试流程说明](docs/X-Fit_人工测试流程说明.md)
- [今日体感与动作体验高鲁棒性测试与评估](docs/X-Fit_今日体感与动作体验高鲁棒性测试与评估.md)
- [0.2.0 实现与自动化测试报告](docs/X-Fit_0.2.0_实现与自动化测试报告.md)
- [0.3.0 自适应训练与历史同步测试清单](docs/X-Fit_0.3.0_自适应训练与历史同步测试清单.md)
- [0.3.0 实现与自动化测试报告](docs/X-Fit_0.3.0_实现与自动化测试报告.md)
- [0.4.0 动作补录与当天菜单实施报告](docs/X-Fit_0.4.0_动作补录与当天菜单实施报告.md)
- [动作补录、当天菜单与分享入口高鲁棒性测试与评估](docs/X-Fit_动作补录与当天菜单高鲁棒性测试与评估.md)
- [0.5.0 动作标准化审核与 AI 代理边界](docs/X-Fit_0.5.0_动作标准化审核与AI代理边界.md)
- [训练背景图来源与许可](docs/X-Fit_训练背景图来源.md)
- [历史训练导入模板](docs/X-Fit_历史训练导入模板.csv)

## 数据边界

- `WorkoutTemplate` / `TemplateExercise`：可持续修改的周计划模板
- `ScheduledWorkout`：具体日期的训练安排
- `WorkoutSession` / `SessionExercise`：开始训练时生成的历史快照，包括当时的动作要点与参考链接
- `SetLog`：实际完成的逐组重量、次数、RIR、可选开始时间与组后休息记录
- `NutritionTarget` / `MealEntry`：每日目标和按日期保存的真实餐食
- `BodyMeasurement`：本机或主动从 Apple 健康导入的身体数据

当前权威数据保存在设备本地，并可导出 JSON/CSV。Share Extension 只通过 App Group `group.com.edward.FitnessApp` 传递一个待确认草稿，不直接写 SwiftData。HealthKit 与本地通知按用户选择启用。iCloud、Live Activity 和 Apple Watch 尚未启用；watchOS 将在 iPhone v1.0 真机稳定后开发。

主 App 与 `com.edward.FitnessApp.XFitShareExtension` 已在 development 签名中同时启用上述 App Group；`0.5.0 (10)` 已于 2026-08-21 覆盖安装到 `Edward_iPhone`，`0.5.0 (11)` 已完成高鲁棒性回归和签名构建，待设备恢复 DDI/Xcode destination 后覆盖安装。当前 Personal Team profile 到期时间为 2026-08-27；到期后需重新运行 Xcode 自动签名。Safari 分享入口和保存后的真机数据链路仍以人工测试清单的实机结果为准。
