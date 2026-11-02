# X-Fit

X-Fit 是一款面向 iPhone 的中文力量训练计划与记录 App，使用 SwiftUI、SwiftData 和 Swift Charts，最低支持 iOS 17。

## 当前交付与入口

- 当前整体规划：[R4业务任务树（已整体确认）](outputs/planning/xfit-business-task-tree-r4.md)；固定展示沿用[原Notion工作台](https://app.notion.com/p/3f84c857b834810bb182e00e55dc82b1)。首轮[已有训练复盘](outputs/training-review/2026-10-25-r4-training-review.md)与[下一腿＋核心C1候选](outputs/training-plan/2026-10-25-next-lower-candidate.md)已形成，具体方案待确认、未写App。业务指标与本地、手机、人工、效果进度分别展示，不合成总完成率。
- 最近已证明手机交付为 **0.5.0 Build32**，证据截至2026-10-24 22:00快照；目录335待核，最新本地目录330待核，两轮增量未上手机。安装与数据守恒通过，完整真机UI `BLOCKED_ENV`、人工 `BLOCKED_HUMAN`，不是GO。见[Build32需求与证据](docs/requirements/2026-10-24/202853_build32-ui.md)、[最新本地复核](docs/requirements/2026-10-24/231501_opengym331.md)。本次没有读取实时手机。
- 下列R3/C10–13描述的是已关闭历史阶段：原五处Notion最终同步已回读、当时必办项0；Build18为该阶段设备证据。原7/8台账保留，不作为当前全项目进度或重开授权。
- 餐食原图保存/导出/恢复验收，等本人开始实际拍照并明确要求后再集中执行；真实指定周的评估与一次确认回写另由真实资料触发。
- 完整真机 UI 自动化保留未通过证据，暂不推进，只有本人明确要求恢复才继续；严格物理 P95 测试已取消。
- Notion 采用既有连接的普通协同写入，不配置新凭证、不移动旧训练档案、不实时上传手机。
- 正文入口：[项目循环手册](docs/operations/项目循环手册.md) · [当前事实索引](docs/operations/事实与内容索引.md) · [R3 正式收尾](outputs/planning/xfit-business-task-tree-r3.md#124-本阶段正式收尾调整后范围)。
- 原验收与未验项：[收尾需求 C-10–13](docs/requirements/2026-10-13/131921_remaining-business-convergence.md) · [阶段测试计划](docs/releases/0.5.0/goal-stage-closeout/阶段固化测试计划.md)。任务交付、本地通过、设备/人工验收和长期效果不互相替代。

## 文件架构与资料归属

| 目录/文件 | 保存什么 | 使用边界 |
|---|---|---|
| `FitnessApp/` | 主 App 源码、现用离线资源 | 不与历史设计候选混用 |
| `XFitShareExtension/` | 分享扩展源码 | 只传递待确认草稿 |
| `FitnessAppTests/`、`FitnessAppUITests/` | 原生单元/UI 测试 | 历史 fixture 保留，真机 UI 未通过事实不变 |
| `EquipmentRecognitionBackend/` | 可选后端源码与锁文件 | 当前无服务器；需要使用时在该目录运行 `npm ci` 重建依赖 |
| `FitnessApp.xcodeproj/`、`project.yml` | 工程与生成配置 | 保持现有编译路径，未产生新版本 |
| `docs/requirements/` | 正式需求、用户确认、实现与验收 | 同一需求持续回写，历史确认不删除 |
| `docs/training/`、`docs/fat-loss/` | 已确认偏好、训练方案与业务资料 | 实际训练仍由 App 保存，旧重量不是新处方 |
| `docs/operations/` | 当前状态、调用规则、Notion 绑定、恢复说明 | 当前状态入口，旧工具存在不等于启用 |
| `docs/releases/`、`docs/design/` | 分层验收与现有餐食设计 | 只记录各自证据层 |
| `docs/archive/` | 旧版本说明、历史入口快照和设计候选 | 保留独有正文，不作为当前任务或状态 |
| `outputs/planning/`、`outputs/training-plan/`、`outputs/notes-import/` | 正式任务树、确认计划和导入来源 | 稳定 ID 与来源保留；被测试读取的导入文件不可清掉 |
| `outputs/stage-validation/`、`outputs/test-results/` | 测试结果与历史摘要 | 原失败/跳过/未知保留，历史 PASS 不代表当前验收 |
| `artifacts/` | 必需原始证据、数据副本与恢复资料 | 只保留当前/必要载荷；旧结果包退役有摘要和明确不可恢复边界 |
| `outputs/storage-retirement/` | 精确清理记录 | 删除与归档事实，不是一套新框架 |
| `scripts/`、`tests/` | 原有工具和合同测试 | 不自动操作手机或访问真实服务 |
| `.git/` | 完整 Git 历史 | 本次未裁剪、重写或提交 |

当前只读状态可运行：

```bash
python3 scripts/xfit-project-loop.py status --cycle docs/operations/cycle-20260927.json
```

该原入口保留原 7/8 任务总账和原未验门；本阶段是否结束以 `cycle.current_phase_closeout` 与 R3 第 12.4 节为准，不能由旧 `overall=partial` 重新启动工作。

## 已有实现概览

以下沿用既有实现说明，不是所有功能均完成当前真机验收的声明：

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


## 打开与验证项目

```bash
open FitnessApp.xcodeproj
```

工程由 `project.yml` 生成；只有明确修改工程结构时才运行 `xcodegen generate`。本次只整理资料，没有修改工程或重新生成。

开发验证示例：使用项目外的临时 DerivedData，避免在项目中堆积构建缓存。

```bash
FITNESS_DERIVED_PATH=$(mktemp -d /tmp/fitnessapp-derived.XXXXXX)
xcodebuild -project FitnessApp.xcodeproj \
  -scheme FitnessApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$FITNESS_DERIVED_PATH" \
  test
```

阶段固化仍使用 `scripts/xfit-stage-validation.sh` 的统一入口，安装与设备运行另核授权。本次目录整理不重跑 App/手机测试；已有结果查[阶段计划](docs/releases/0.5.0/goal-stage-closeout/阶段固化测试计划.md)。

当前人工入口为[真机人工清单](docs/X-Fit_真机人工测试清单.md)；餐食后续按[原工作流](docs/meal-photo-workflow.md)与[R3 触发条件](outputs/planning/xfit-business-task-tree-r3.md#124-本阶段正式收尾调整后范围)。旧版本报告和测试方法在[历史资料](docs/archive/README.md)，不要求重新验收已接受的体验。

## 数据边界

- `WorkoutTemplate` / `TemplateExercise`：可修改的周计划模板。
- `ScheduledWorkout`：具体日期的训练安排。
- `WorkoutSession` / `SessionExercise`：开始训练时生成的独立历史快照，包括动作要点和参考链接。
- `SetLog`：逐组实际重量、次数、RIR、开始时间与休息等；计划组不自动算已完成组。
- `NutritionTarget` / `MealEntry`：目标与实际餐食；原照片、备注、本人估算与 AI 评估分开。
- `BodyMeasurement`：本机或主动从 Apple 健康导入的身体数据，来源日期与未知保留。

设备是实际数据真源；Share Extension 通过 App Group `group.com.edward.FitnessApp` 传递待确认草稿，不直接写 SwiftData。HealthKit 与通知按本人选择启用；不直接改手机 SQLite、不猜补缺失数据、不新增营养目标。历史签名/安装日期见归档 README，不用旧 profile 日期推断当前状态。

资料入口：[训练档案流程](docs/training/训练档案工作流.md) · [餐食工作流](docs/meal-photo-workflow.md) · [动作标准化与代理边界](docs/X-Fit_0.5.0_动作标准化审核与AI代理边界.md) · [资源许可](docs/X-Fit_训练背景图来源.md) · [历史导入模板](docs/X-Fit_历史训练导入模板.csv)。

## 存储与恢复

本次已确认以精确清理替代 Build14/Build15/local-ready 原包“全部保留”的旧规则。当前最终包、关键 UI 诊断、所有实际数据副本、测试 fixture、源码与 Git 历史保留；76 个旧测试包先提取原生摘要再退役，闲置缓存可重建。

具体结果与恢复限制见[存储说明](docs/operations/本地存储与历史测试载荷.md)、[清理需求](docs/requirements/2026-10-14/133439_project-folder-consolidation.md)与[唯一清理清单](outputs/storage-retirement/20261014-project-consolidation.json)。旧原包没有完整恢复副本；摘要不能用于原生重放。构建缓存可重新生成，后端依赖可用锁文件重建。

后续新增资料按上述用途进入原目录；当前状态正文只维护一次，其他入口用摘要和链接。不自动扩建框架或重新执行已结束任务。
