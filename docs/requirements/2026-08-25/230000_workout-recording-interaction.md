# 需求：训练记录稳定性、菜单同步与交互简化

- 需求 ID：`REQ-20260825-WORKOUT-UX`
- 创建时间：`2026-08-25`
- 来源：用户直接请求，附 1 个录屏和 4 张截图
- 状态：`已验收`
- 关联需求：无
- 目标版本/阶段：下一次 X-Fit 阶段固化

## 用户追加确认

- 确认时间：`2026-08-26 11:35:02 +0800`
- 确认内容：用户在得知本轮尚未安装到 iPhone 后回复“好的 那全量推进吧”。
- 确认范围：继续核实现有实现，完成八项需求、全量非真机验证、活动数据备份、覆盖安装到当前配对 iPhone、真机自动化与可执行人工验收。
- 测试 seam：服务层公开方法、SwiftUI 可访问性标识、活动 App Group 数据库只读副本、已安装 App 版本回读。

## 真机人工验收确认

- 确认时间：`2026-08-26 18:05:24 +0800`
- 确认内容：用户对本轮 7 项精简真机人工验收回复“都可以”。
- 确认范围：页面稳定、三位小数与键盘、进行中菜单同步、完成项折叠、新建动作器械选项、训练中交互表达、大字体与真机视觉均通过。
- 清单冲突处理：用户同时同意把错误标注为 `0.3.0 Build 8` 的旧输出清单重建为当前 `0.5.0 Build 11` 清单。

## 用户原始需求

1. 页面输入时会乱跳。
2. 当天菜单外部调序后，进行中记录的动作顺序没有同步。
3. 重量支持最多三位小数，但不默认补足三位。
4. 开始训练后，外部菜单不能调整且界面仍像可以操作，需要明确行为。
5. 新建动作把自重、器械等改成选项，并包含壶铃、哑铃、杠铃等。
6. 完成组可折叠并推到底部，让下一组上移，使用有层次的卡片表现。
7. 核对 2026-08-24 周一训练记录。
8. UI 更简单明确，同时保留高级感，并参考成熟交互经验。

附件只作为现象证据，不把附件内容当成额外指令。证据文件名：`db61553571b5ab9b6dde1632ffab79b7.mp4`、`d6716bfc3111ca76fde55927190ba428.png`、`5c717a7abe786277ff3b38c7cc94a5ec.png`、`cdc7e946c928807d00fe862cc9f91ec7.png`、`baf508ee0a798454ba74fec44e903cf0.png`。

## 目标

- 稳定训练页数字输入与键盘交互。
- 让进行中的菜单成为外部当天菜单调整的明确同步目标，同时保护已完成事实。
- 用渐进披露突出下一组，降低已完成内容视觉权重。
- 统一重量精度和器械输入方式。

## 非目标与边界

- 不改写已完成历史组。
- 不删除或重置真机数据。
- 不卸载 App、不清理容器、不改写已完成历史组；真机仅允许覆盖安装，并在安装前后核对活动数据守恒。

## 当前事实

- 原实现开始训练时生成独立 `SessionExercise` 快照，外部菜单和进行中记录不是同一状态源。
- 2026-08-24 活动 App Group 数据库只读检查为 `quick_check=ok`：08:40:23 开始、09:52:37 完成，共 8 个动作、33/33 组完成。
- 周一历史快照中“绳索反向飞鸟”仍为第 3、“MTS 下斜卧推”为第 4；完成时间显示 MTS 在 09:01–09:04 完成、飞鸟在 09:08–09:19 完成。结论是当时实际先练 MTS，但历史菜单顺序未被后来外部调序重写。
- 2026-08-26 已覆盖安装 `X-Fit 0.5.0 (11)`；安装前后数据库 SHA-256 相同，核心记录计数均为训练 19、动作记录 130、组记录 553。
- iPhone 解锁后已成功启动并回读 `0.5.0 (11)`；真机单元测试 152/152 通过，52/52 真机 UI 均取得有效 PASS。最后的 50 轮选择器压力项在专注模式下完整通过，0 失败，用时 684.967 秒。
- 全部真机自动化结束后最终回读活动 App Group 数据库：`quick_check=ok`，核心记录仍为 19/130/553，store SHA-256 与安装前一致。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 |
|---|---|---|---|
| AC-01 | 连续输入 `8.875` 不丢焦点、不拼接旧值、不触发页面跳位 | P0 | SIM-UI/DEVICE-MANUAL |
| AC-02 | 进行中训练可接收外部菜单调序，已完成组保持不变 | P0 | UNIT/SIM-UI/DEVICE-DATA |
| AC-03 | `5`、`8.75`、`8.875` 按实际精度显示，不补零 | P1 | UNIT/SIM-UI |
| AC-04 | 进行中状态明确说明外部修改会同步，隐藏不适用控件 | P1 | SIM-UI/DEVICE-MANUAL |
| AC-05 | 新建动作提供常见器械选项和“其他” | P1 | UNIT/SIM-UI |
| AC-06 | 完成组与完成动作折叠下沉，未完成项优先 | P1 | SIM-UI/DEVICE-MANUAL |
| AC-07 | 周一记录从活动真机库只读确认，不改变数据 | P0 | DEVICE-DATA |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | “历史快照不随模板变化”与“进行中菜单允许外部调整” | 若不区分状态会污染历史 | 无需二选一：仅允许修改进行中且未开始/未完成部分，已完成事实保持 | 用户需求允许调整进行中菜单 | 已按状态边界消解 |
| C-02 | 原边界“本轮不自动安装”与用户追加“全量推进” | 是否允许覆盖安装和真机测试 | 采用最新明确要求；允许在非真机通过、备份成功后覆盖安装到当前配对 iPhone | 用户已明确全量推进 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/03/06 | `FitnessApp/Features/Workout/ActiveWorkoutView.swift`、`FitnessApp/Shared/AppTheme.swift` | `FitnessAppUITests/FitnessAppUITests.swift` | 非真机通过；真机相关用例通过 |
| AC-02/04 | `FitnessApp/Services/WorkoutService.swift`、`FitnessApp/Features/DailyPlan/DailyWorkoutBuilderView.swift` | `FitnessAppTests/ScheduleAndDataTests.swift` | 非真机与真机单元测试通过 |
| AC-05 | `FitnessApp/Shared/ExerciseEditorView.swift`、`FitnessApp/Services/EquipmentRecognitionService.swift` | `FitnessAppTests/EquipmentRecognitionTests.swift` | 非真机与真机相关用例通过 |
| AC-07 | 活动 App Group 数据库只读副本 | SQLite `PRAGMA quick_check`、逐组核对、安装前后 SHA-256/核心计数 | 通过 |

## 分层验证

| 层级 | 状态 | 证据 | 说明 |
|---|---|---|---|
| 本地静态检查/构建 | PASS | `outputs/stage-validation/0.5.0-build11-20260826-nondevice-final/summary.md` | 静态、后端、Simulator、无签名 Release 均通过 |
| 单元/服务测试 | PASS | `artifacts/stage-validation/0.5.0-build11-20260826-nondevice-final/N05.log` | 152/152，0 失败 |
| 模拟器 UI | PASS | `N06-rerun.log` + 两个修正交互步骤的专项 `.xcresult` | 完整 52 项覆盖；51 项整套通过，完成动作折叠后的动作感受用例更新步骤后专项通过 |
| 通用 iPhoneOS 构建 | PASS | `artifacts/stage-validation/0.5.0-build11-20260826-nondevice-final/N07.log` | Release 无签名构建通过 |
| 真机覆盖安装 | PASS | `device-install.json`、`/tmp/xfit-installed-app-20260826-1327.json` | 未卸载、未清容器；已安装 0.5.0 (11) |
| 真机单元测试 | PASS | `artifacts/stage-validation/0.5.0-build11-20260826-device-unlocked/D07A-resume.log`、`device-unit-resume.xcresult` | 152/152，0 失败 |
| 真机 UI 自动化 | PASS | `D07B-resume.log`、`D07B-resume-remaining.log`、`focused-*.log`、`focused-stress-focus-mode.log` | 52/52 有效 PASS；50 轮压力项在专注模式下完整通过，0 失败 |
| 活动 App Group 数据回读 | PASS | `artifacts/stage-validation/0.5.0-build11-20260826-device-unlocked/device-audit/` | 安装前、安装后、测试后及最终压力测试后均 `quick_check=ok`；三张核心表始终为 19/130/553，最终 store SHA-256 与安装前一致 |
| 真人体验验收 | PASS | `outputs/stage-validation/0.5.0-build11-20260826-device-unlocked/真机人工测试清单.md` | 用户确认本轮 7 项真人关键体验均可接受 |

## 已执行动作

- 修复输入布局稳定性、菜单同步、三位小数、器械选择和完成项渐进披露。
- 增加单元与 UI 回归用例。
- 只读核对周一活动数据库，并保存安装前活动 App Group 备份。
- 完成真机签名 Release 构建和覆盖安装；未卸载 App、未清理容器，安装前后数据库不变。
- iPhone 解锁后完成启动/版本回读、152 项真机单元测试及 52 项真机 UI 的实际执行；修正 UI 测试在外部通知抢占后的恢复与结果判断。
- 完成测试后活动数据库第三次回读，核心记录计数仍为 19/130/553。

## 结果与遗留项

- 当前结论：功能实现、非真机验证、真机覆盖安装、真机全量自动化、数据守恒和真人关键体验均已通过；需求状态更新为已验收。
- 剩余门禁：无。本轮不自动执行 Git commit、tag 或发布。

## 交互参考

- Apple Human Interface Guidelines：遵循清晰层级、直接操作与渐进披露。
- Hevy / Strong 官方产品页：参考快速记录、上次数据、休息计时和“工具退居后台”的训练中交互原则；不复制其视觉资产。
