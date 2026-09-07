# 需求：X-Fit全界面重构：训练饮食与目标

## 2026-09-07 真机安装与测试（用户确认）

- 用户明确确认“好的 开始安装与测试”：先备份现有数据、覆盖安装、核对数据完整性并运行真机测试；保留原有记录，人工验收单列。延续同一 UI 需求的真机阶段，非新增功能。
- 当前核对：目标 Edward_iPhone 已在线；113 个源码/资源指纹与已通过本地验证的版本全部一致。工具页旧顺序不变，无新的产品规则冲突。
- 验证入口：`scripts/xfit-stage-validation.sh device`，Run ID `20260907-normal-ui-device`；显式开启覆盖安装及真机 XCTest 开关。活动 App Group 备份/完整性/计数与额外 UUID 守恒分别核对。
- 验收：AC-01 至 AC-14 对应 device UI/unit；AC-09 安装前后和测试后活动记录不减少、原 UUID 保留；AC-07/08/11 真人体验仍由用户确认。禁止卸载或清容器，不 commit/tag/push。
- 分工：Coordinator 串行执行备份、签名构建、覆盖安装、设备测试和档案更新；Worker 只读审计测试存储隔离与数据守恒范围。

### 连接手机核心体验补验（2026-09-07）

- 用户明确要求“我连接手机你来帮我测试”。使用隔离 UI 测试数据在 Edward_iPhone 补跑训练恢复、肌群选择、实吃与备餐、目标复盘、备份设置、食谱详情六条核心流程，6/6 PASS，并导出 18 张真机截图检查正常字号和主要布局。
- 测试结束后重新覆盖安装并启动 Release 0.5.0（11）。测试前后真实库均为 1,257 行，36 次训练 / 203 个会话动作 / 837 个组记录及全部原 UUID 保留；仅同一已归档动作的更新时间按已解释的启动逻辑刷新。
- 截图显示部分页面最下方操作在初始滚动位置只露出一部分，但可滚动至 Tab Bar 上方且自动操作通过；不作为技术阻断，视觉舒适度仍由用户本人判断。
- 证据：`outputs/stage-validation/20260907-human-assisted-smoke/final-verification.md` 与 `artifacts/stage-validation/20260907-human-assisted-smoke/`。状态仍为真机待验收，不能由 Agent 代签人工体验或系统权限。

### 真机执行结果（2026-09-07）

- 已使用统一入口完成真机阶段。首次 `20260907-normal-ui-device` 在 UI runner 启动时连接中断，原始失败保留；重跑 `20260907-normal-ui-device-retry` 完成 D00–D08。
- 真机单元 256 PASS、2 个仅主机 fixture 用例跳过（本地全量已覆盖）；UI 首轮 87 PASS / 4 FAIL / 7 个既有停用用例跳过。四条失败仅修测试中的空值/placeholder 表达和通知/转场有效点击，定向完整流程 4 PASS；最终有效 UI 91 PASS / 7 SKIP，未增加跳过。
- 应用源码与本地最终验证版本一致，113 个指纹中仅三个 UI 测试文件更新。无 UI、医学参数、业务数据或保存逻辑修改。
- 最终已将同一签名 Release 产物重新覆盖安装并正常启动，回读版本 0.5.0（11）；未卸载或清容器。`final-release-package.json` 保存可执行文件 SHA 与开发签名信息，Release 的开发签名允许调试，不用该 entitlement 冒充配置判据。
- 最终全实体审计七份备份完整、1257 行及全部原 UUID 保留；原36次训练/203动作/837组不变，仅一个已归档动作更新时间按原有启动逻辑刷新。修正后四条模拟器兼容补验全部 PASS。
- 全实体 UUID/字段审计及模拟器兼容补验最终结果见 `outputs/stage-validation/20260907-normal-ui-device/final-verification.md`。真机人工体验仍为 BLOCKED_HUMAN，由本人填写清单；本阶段不标 GO 或已验收。

## 2026-09-07 全量本地推进（用户确认）

- 用户确认：2026-09-07 回复“好的 全量推进”，承接正常字号界面检查、修复与项目统一全量本地测试；正常字号紧凑排版为默认视觉验收对象。系统放大文字仍做兼容回归，不作为默认设计稿。
- 当前事实：此前 secondary-refinement 仅定向验证；当前整套源码尚未完成本轮 non-device 回归。
- 目标/验收：AC-01 至 AC-14 在当前源码重新映射和回归；正常字号主要按钮/输入可达、三条日常流程和历史守恒通过；失败保留原证据并闭环。
- 边界/冲突：延续四 Tab、医学参数未知、手动训练、UUID 与版本保护。工具页顺序保持已确认助手优先，尚不替代旧规则；不 commit/tag/push，不卸载或清数据。真机覆盖安装及真人验收单列。
- 分工：Worker 只读审计默认字号和入口；Coordinator 负责同一需求及阶段计划、修复、统一测试和收尾。共用代码和构建串行。
- 验证入口：`scripts/xfit-stage-validation.sh non-device`，Run ID `20260907-full-ui-regression`。执行结果待回写，旧 PASS 不代替当前验证。
- 实际字号调整：AppTheme 统一页面标题 title2（默认 22pt）与指标 title（默认 28pt）；目标主数字 88→36pt，并移除负字距/斜体，单位降为正文级。训练、饮食、身体体重、引导、备餐、复盘及我的共用层级；保留动态字号和原触控区域。业务模型/计算未变。
- 最终验证 Run ID 更新为 `20260907-full-ui-final`：初始 N01–N05 通过后发现 UI 测试二进制早于字号调整，主动中止初始 N06，从统一入口重跑以保证同版验证。原始中止日志保留，不计作 PASS。
- 当前结果：完整入口及必要补验已闭环，6 后端 / 258 单元 / 91 有效 UI PASS，7 既有停用用例跳过；最终 iPhoneOS Release 无签名构建 PASS。原始 6 个 UI 失败及补验中 2 个后续失败保留，不宣称首次整套零失败。
- 修复映射：审核按钮补足 44pt 完整点击标签；测试处理浮点容差、设置分段/工作组文案和固定底栏遮挡；DEBUG 非持久 UI 演示周期固定相对起点，正式周期和持久记录逻辑不变。正常字号为默认展示。
- 最新证据：`outputs/stage-validation/20260907-full-ui-final/final-verification.md/json`；实际正常字号截图 `outputs/ui-redesign/normal-type/index.html`。旧预览保留对比，本入口为当前默认字号检查稿。
- 真机在线检查：Edward_iPhone unavailable，BLOCKED_ENV；安装、真机自动化和活动库/UUID 守恒 NOT_RUN。本人实际使用 BLOCKED_HUMAN；工具顺序仍保留助手优先。未 commit/tag/push、发布、安装或清空真实数据；状态保持本地已验证，整体 PARTIAL，不标记 GO/已验收。

- 需求 ID：`REQ-20260906-100804`
- 创建时间：`2026-09-06 10:08:04 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-06 10:08:04 +0800`
- 用户确认摘要：`用户明确要求实施全UI重构方案：深色简洁、训练饮食目标我的四Tab替代旧五Tab/首页限制、列表快速记组、单主目标、肌群选择与分布；先隔离原型再全页面迁移，医学与数据保护不变，真机及人工验收单列。`
- 状态：`真机待验收`
- 关联需求：`../2026-09-05/225730_fat-loss-program.md`；`../2026-09-04/234522_requirement.md`
- 目标版本/阶段：0.5.0（11）当前工作树；真机自动验证后待本人验收

## 用户原始需求

实施已确认的全界面重构方案，以训练和目标为中心，深灰与荧光绿的简洁运动风，训练/饮食/目标/我的四Tab、当前动作展开的列表记组、一个主目标与关联指标、人体肌群选择及实际训练分布。先用隔离数据制作八个SwiftUI交互核心页面，检查视觉和操作后迁移全部页面；用户实际体验与自动测试分别验收。

## 目标

- 默认打开训练，首屏开始/继续；饮食直接记录实吃和明日备餐；目标看主目标/7日趋势/复盘；我的归集设置与数据。
- 八个核心原型复用正式组件；统一所有主次级页面的背景、层级、表单、输入、日期选择和返回路径。
- 保留已有数据、手动训练与实际记录保护，用户反馈后才标记设计已验收。

## 非目标与边界

- 不改医学建议、不自动生成营养目标或推断肌肉恢复；不重建业务数据库。
- 不清理原有脏工作树，不删除真实数据；不commit/tag/push、发布或安装真机。
- 仅原型/测试使用隔离演示数据，不能进入真实持久数据库。

## 开发前事实（2026-09-06 基线）

- 当前RootView为五Tab；Today、FatLoss、Stats、Profile存在重复训练/目标/记录入口；AppTheme含多层渐变、光晕与浮动材质。
- 当前SwiftData与备份已有减脂、目标版本、计划餐/实吃和历史保护能力；本次以展示/导航适配复用。
- 历史验证不代替本轮验证。工作树含前序大量未提交改动，按文件所有权增量修改。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 四Tab与全部入口迁移 | P1 | SIM-UI | 训练/饮食/目标/我的，默认训练，原功能有明确入口 |
| AC-02 | 训练首屏 | P1 | SIM-UI | 日期周历、开始/继续首屏可达，无计划可安排 |
| AC-03 | 列表快速记组 | P0 | UNIT/SIM-UI | 当前动作展开，就地编辑/一键完成，多单位/历史/中断恢复保真 |
| AC-04 | 人体肌群选择与训练分布 | P1 | UNIT/SIM-UI | 正背面/多选/文字筛选一致，仅依据实际完成记录，不推断恢复 |
| AC-05 | 饮食/备餐/实吃 | P0 | SERVICE/SIM-UI | 三餐直接记录、调整同一面板、明日备餐可分享，未知保真 |
| AC-06 | 一个主目标与复盘 | P0 | SERVICE/SIM-UI | 7自然日及覆盖率、未足3日无趋势判断，医学待确认无默认预算 |
| AC-07 | 全局视觉与可达性 | P1 | SIM-UI/HUMAN | 简洁深色、20pt标准边距、44pt触区，大字体/键盘不遮主操作 |
| AC-08 | 原型和人工验收 | P1 | SIM-UI/HUMAN | 八核心页面可交互，演示数据隔离；人工未验收不得声称已验收 |
| AC-09 | 历史与备份守恒 | P0 | UNIT/DEVICE-DATA | UUID/已完成组/版本/备份保持，真实设备单独验证 |
| AC-10 | 统一完整回归 | P0 | UNIT/SIM-UI/GENERIC-BUILD | 执行统一脚本，失败/跳过和真机未执行分别报告 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 用户决定 | 状态 |
|---|---|---|---|---|
| C-01 | 20260905减脂需求五Tab/首页顺序 vs 新四Tab训练优先 | Root/首页 | 本轮明确替代旧五Tab及首页排列规则 | 已决定 |
| C-02 | 9/4首页展示限制 vs 全UI统一设计 | 首页视觉与入口 | 本轮重构替代旧视觉布局要求，历史保护保留 | 已决定 |
| C-03 | UI简化 vs 医学/数据保护 | 实吃、目标、训练 | 简化展示和路径，不变数据与医学边界 | 已决定 |

## 并行/串行边界

Coordinator负责Theme、Root、训练首页、我的、原型隔离、需求、统一构建测试与收尾。Worker分别负责训练记录/肌群、饮食目标、只读页面可达审计与测试候选。工程生成、共用文件及最终结果由Coordinator串行写入。

## 实现映射

| 范围 | 实现 |
|---|---|
| 四 Tab / 统一视觉 | `App/RootView.swift`、`Shared/AppTheme.swift`；统一深灰表面、绿色主操作、20pt 边距、44pt 操作区；移除主页面光晕及重复展示卡片 |
| 训练首页 | `Features/Today/TodayView.swift`；日期周历、开始/继续/已完成三态、当日动作、本周安排，计划/历史/跳绳/减脂训练预览导入二级入口 |
| 列表记组 | `Features/Workout/ActiveWorkoutView.swift`；当前动作展开、稳定动作顺序、就地输入、一键完成、已完成摘要及修改；单/双侧修改仅作用于未完成组 |
| 肌群图 | `Shared/MuscleSelectionView.swift`、`Services/MuscleCoverageService.swift`；正背面多选与文字筛选同步，实际完成组分布，保持疼痛坐标与含义独立 |
| 饮食与备餐 | `Features/Redesign/NutritionHomeView.swift`、`Features/FatLoss/`；三餐直接实吃、统一编辑、同日饮水、所选日次日备餐，分装/采购提前、细节展开 |
| 目标与记录 | `Features/Redesign/GoalHomeView.swift`；单主目标、近7自然日及覆盖率、腰围/训练/力量/复盘，体感与日常记录复用现有编辑器 |
| 我的与二级页面 | Profile/Settings/Plan/Schedule/History/Body/Stats/共享动作表单完成导航及视觉迁移；新增 `ProgramDataExportView.swift` 周期 CSV 导出入口 |
| 正确性修复 | `FatLossService.recordMeal` 拒绝与同日同餐旧实吃重复记账；新餐食日期以周期时区保存；完整身体记录允许仅腰围，编辑保留 UUID |
| 原型与证据 | RootView 仅 DEBUG + UI测试 + 非持久库允许 `--ui-redesign-preview` 演示；`RedesignUITests` 操作与留图，`outputs/ui-redesign/core-preview/` 查看 |

实际体重、实吃与完成状态不由导入计划代填。医学目标未确认保持未知；原型数据不会导入真实数据库。

## 分层验证

统一 non-device 入口及必要补验已完成：6 后端、248 单元通过；85 有效 UI 用例通过、7 既有停用功能跳过；模拟器与最终无签名 iPhoneOS Release 构建通过。原始首轮失败及后续补验逐项保留，见 `outputs/stage-validation/20260906-ui-redesign-local/final-verification.md` / `.json`。

真机覆盖安装、活动库回读与自动化为 NOT_RUN；真人体验为 BLOCKED_HUMAN。设计尚未标记“已验收”，阶段不标记 GO。

## 已执行动作

- 当前代码与工作树只读核对、Context Router预检完成，按明确实施请求创建同一份需求档案。
- 先实现并操作八个核心 SwiftUI 页面，修复父容器遮蔽控件、实吃保存不可见、肌群入口手势拦截，再迁移二级页面。
- 执行统一 non-device 回归，保留原始失败记录，并为发现的问题补充针对性回归；结果见阶段验证文件。

## 结果与遗留项

全界面迁移与本地验证完成。核心预览：`outputs/ui-redesign/core-preview/index.html`；最终验证索引见上。真机及真人体验仍待后续授权/反馈，医学份量与个性化营养目标仍待确认。未 commit/tag/push 或覆盖安装。

最后修复：完整身体数据编辑采用携带原记录的单一弹窗状态，保证冷启动首次打开仍编辑原 UUID；新增回归验证取消、腰围独立新增、修改和重启读回。

## 页面清单与导航映射

同一服务与记录由各入口复用；导航返回使用原 NavigationStack。下表按当前源码盘点所有 Feature View；共用选择器随调用页返回。

| 文件 | 页面 / 组件 | 新入口 |
|---|---|---|
| `FitnessApp/Features/Body/BodyMeasurementsView.swift` | `BodyMeasurementsView`、`BodyWeightTrendCard`、`QuickBodyWeightEntryView`、`BodyMeasurementEditorView` | 目标 / 我的 → 身体数据 |
| `FitnessApp/Features/DailyPlan/DailyWorkoutBuilderView.swift` | `DailyWorkoutBuilderView` | 训练 → 调整 / 安排今天 / 训练计划与动作库 |
| `FitnessApp/Features/FatLoss/FatLossComponents.swift` | `FatLossProgressLink`、`FatLossMetric`、`FatLossNote`、`FatLossNavigationRow` | 目标 → 周期 / 健康 / 复盘；饮食 → 餐单 / 食谱 / 备餐 |
| `FitnessApp/Features/FatLoss/FatLossIntroductionView.swift` | `FatLossIntroductionView` | 目标 → 周期 / 健康 / 复盘；饮食 → 餐单 / 食谱 / 备餐 |
| `FitnessApp/Features/FatLoss/FatLossMealsView.swift` | `FatLossMealsView`、`FatLossRecipeSourcesView`、`FatLossMenuPreview`、`FatLossRecipeView`、`FatLossPrepView`、`FatLossMealDetailView` | 目标 → 周期 / 健康 / 复盘；饮食 → 餐单 / 食谱 / 备餐 |
| `FitnessApp/Features/FatLoss/FatLossRecordViews.swift` | `FatLossDailyEditor`、`FatLossTargetsView`、`FatLossTargetEditor`、`FatLossHealthEditor`、`FatLossReviewView` | 目标 → 周期 / 健康 / 复盘；饮食 → 餐单 / 食谱 / 备餐 |
| `FitnessApp/Features/FatLoss/FatLossTrainingView.swift` | `FatLossTrainingView` | 目标 → 周期 / 健康 / 复盘；饮食 → 餐单 / 食谱 / 备餐 |
| `FitnessApp/Features/FatLoss/FatLossViews.swift` | `FatLossHomeSummary`、`FatLossQuickRecordLinks`、`FatLossDashboardView`、`FatLossTimelineView`、`FatLossDayDetailView` | 目标 → 周期 / 健康 / 复盘；饮食 → 餐单 / 食谱 / 备餐 |
| `FitnessApp/Features/History/HistoricalWorkoutEntryView.swift` | `HistoricalWorkoutEntryView`、`HistoricalExerciseEditor` | 训练 → 训练历史；我的 → 导入历史训练 |
| `FitnessApp/Features/History/HistoricalWorkoutImportView.swift` | `HistoricalWorkoutImportView` | 训练 → 训练历史；我的 → 导入历史训练 |
| `FitnessApp/Features/History/HistoryView.swift` | `HistoryView`、`WorkoutDetailView`、`HistoricalWorkoutEditView`、`HistoricalWorkoutEditExerciseCard` | 训练 → 训练历史；我的 → 导入历史训练 |
| `FitnessApp/Features/Nutrition/NutritionView.swift` | `NutritionPreviewCard`、`NutritionView`、`MealEditorView`、`NutritionTargetEditorView` | 饮食 → 饮食记录 / 加餐 |
| `FitnessApp/Features/Plan/PlanView.swift` | `PlanView`、`TrainingSetupView`、`TemplateEditorView`、`LegacyExerciseEditorView`、`DraftExerciseEditor` | 训练 → 训练计划与动作库 → 编排 / 模板 / 动作库 |
| `FitnessApp/Features/Profile/ProfileView.swift` | `ProfileView`、`ToolsView`、`AgentToolConfirmationSheet`、`WaterQuickEntrySheet`、`JumpRopeQuickEntrySheet`、`SedentaryQuickEntrySheet` | 我的 → 更多记录工具；饮食 → 饮水；训练 → 跳绳 |
| `FitnessApp/Features/Redesign/GoalHomeView.swift` | `GoalHomeView` | 饮食 / 目标一级入口 |
| `FitnessApp/Features/Redesign/NutritionHomeView.swift` | `NutritionHomeView` | 饮食 / 目标一级入口 |
| `FitnessApp/Features/Schedule/ScheduleView.swift` | `ScheduleView`、`AddScheduledWorkoutView`、`RescheduleWorkoutView` | 训练 → 训练日程 / 本周安排 |
| `FitnessApp/Features/Settings/AppSettingsView.swift` | `AppSettingsView` | 我的 → 个人设置与权限 / 备份与恢复 |
| `FitnessApp/Features/Settings/ExerciseTerminologyReviewView.swift` | `ExerciseTerminologyReviewView`、`ExerciseTerminologyDetailView` | 我的 → 个人设置与权限 / 备份与恢复 |
| `FitnessApp/Features/Stats/StatsView.swift` | `StatsView` | 目标 → 力量与训练趋势（无周期也可进入） |
| `FitnessApp/Features/Today/TodayView.swift` | `TodayView`、`DailyBodyCheckInEditor`、`BodyMapDiagram` | 训练首页 → 今日安排 / 日程 / 记录跳绳 |
| `FitnessApp/Features/Workout/ActiveWorkoutView.swift` | `ActiveWorkoutView`、`LegacyWorkoutExercisePickerSheet`、`SetLogRow` | 训练 → 开始 / 继续 |

共用页面：`ExercisePickerSheet` 由当天编排、训练、模板、补录调用；`ExerciseEditorView` 由动作库、选择器、外部分享调用；`ExerciseSetupSheet` 由选择器与器械识别调用；`EquipmentRecognitionSheet` 沿原拍照入口；`MuscleSelectionView` 由动作选择器进入，`MuscleCoverageView` 由目标实际训练分布进入。

新增页面：`FitnessApp/Features/Redesign/ProgramDataExportView.swift` → 我的 / 导出减脂周期。目标图表默认近7自然日；更长历史通过身体数据及完整周期详情查看。


## 视觉精修补充（2026-09-06 17:21 +0800）

- 用户确认：对三屏运动杂志风方向稿答复「可以」，同意继续重构；沿用同一需求文件。
- 当前事实：四 Tab 和记录流程已有本地验证；用户明确指出视觉死板，原设计仍未通过人工验收。
- 范围：炭黑/暖白/黄绿色、凝练数字、训练摄影、三餐示意图、开放式列表；精修训练首页、记组、饮食、目标、肌群和共享组件。
- 非目标：不更改训练计算、医学目标、记录与版本语义；不写真实数据，不安装真机，不发布。
- 冲突检查：本次细化已确认视觉风格，不改四 Tab、20pt 边距、44pt 触区及历史保护规则；照片与排版不引入医学或份量判断。
- 补充验收 AC-11：实际 SwiftUI 页面呈现已确认稿的摄影/数字/层级，三餐主次操作明确，普通和大字体记录可达；设计稿不代替运行截图。
- 验证：本轮重新执行项目统一 non-device 入口；实际模拟器截图、自动回归、真机 NOT_RUN、人工 BLOCKED_HUMAN 分别记录。前轮结果仅代表前轮代码。
- 分工：Coordinator 负责共享主题、训练首页、素材、需求和统一验证；Worker 分别修改饮食/目标、记组/肌群，互不覆盖文件。
- 工具边界：Coordinator 的 Context Router 预检接口启动时不可调用；续行时恢复，已完成主任务预检（pfr_eKT_Zv5P8bP8，fast_skip、无知识命中），最终使用该回执收尾。

### 精修实现映射

- `AppTheme.swift` 与 AccentColor：统一炭黑、暖白、荧光绿，收敛圆角和字体层级。
- `TodayView.swift`：训练摄影封面、真实组数、开始/继续操作、开放式动作清单。
- `ActiveWorkoutView.swift`：展开当前动作、完整组数无障碍标签、已完成动作整行展开、44pt 收起入口。
- `NutritionHomeView.swift`：三餐示意图、单一重点操作、日期面板、混合营养未知状态、多条实吃编辑归位。
- `GoalHomeView.swift`：主目标大数字、实际七日趋势和覆盖率、整行复盘入口。
- `MuscleSelectionView.swift`：正背肌群曲线图、绘制区域命中优先、图文同步、训练分布可滚动。
- 图片来源见 `outputs/ui-redesign/editorial-preview/asset-provenance.md`；实际截图预览见同目录 `index.html`。

### 精修回归修复

- 修复开放式行去掉背景后空白区域点不到的问题，覆盖训练动作、周复盘、备餐及次要按钮。
- 保留视觉拆分的组数/动作数，同时恢复完整无障碍标签；饮食已记录餐数改为稳定 ID/value。
- 换菜测试实际滚动原生长菜单；训练结束测试先把按钮中心滚入屏内，避免在屏外坐标点击。
- 周复盘截图用例新增导航栏断言，确保截图对应真实复盘页。

### 精修最终状态（2026-09-06 18:22 +0800）

本地已验证。统一全量与必要补测汇总：6 后端 / 248 单元 / 86 有效 UI 通过，7 既有跳过；最终模拟器测试构建与无签名 iPhoneOS Release 构建通过。原始失败与补测日志完整保留。

权威验证索引：`outputs/stage-validation/20260906-editorial/final-verification.md` 及同名 JSON；实际截图预览：`outputs/ui-redesign/editorial-preview/index.html`，替代上方 core-preview 作为本轮最新视觉入口，旧预览保留比较。

AC-08/11 本人视觉与操作反馈仍待确认；真机安装、自动化及活动库守恒 NOT_RUN。未 commit/tag/push 或修改真实 App 数据。浏览器工具拦截本地文件自动打开，未绕过；可从交付链接查看本地预览。

## 肌群图参考图二修订

- 用户明确要求：肌群图按本轮提供图二重画，属于本需求视觉验收补充；原稿尚未获本人验收。
- 目标：运动员比例、解剖式肌肉分束、深灰肌肉及绿色填充/亮色边线，正背一致。
- 边界：只调整图形和相关选择样式；保留肌群 ID、中文选择、左右语义和实际训练计数，不改疼痛图或服务/记录。
- 冲突：无新的数据或导航冲突；图二用于视觉方向，现有八类肌群语义保持。
- 验收：运行截图核对人体比例、轮廓/分束和选中效果；原正背选择、文字同步及大字体可达用例针对性回归。非固化/发布，不重复全量阶段回归，不安装真机。

### 肌群重画结果

- 原始矢量人体固定 300×600 比例、340pt 展示；胸肩、腹斜肌、股四头/腘绳肌和小腿分束重画，选择框使用描边胶囊。
- 可见路径与点击命中复用；前后、身体自身左右、肌群 ID 和实际统计不变。
- 8 个 MuscleCoverage 单元通过；最终 2 个肌群 UI 用例通过，覆盖正背图文多选/清除/回读及大字体分布可达；模拟器构建通过。此轮为局部修订，不声称重新完成全量阶段或 iPhoneOS Release 验证。
- 27 个 App/模型/服务文件与前轮最终版本指纹一致；证据及源指纹见 `outputs/ui-redesign/anatomy-preview/verification.json`。
- 实际截图见 `outputs/ui-redesign/anatomy-preview/index.html`；整套 editorial-preview 已链接新版图，旧截图保留对比。
- 用户审美与真人操作验收仍待确认，真机 NOT_RUN。未安装/发布或修改真实记录。

## 日常操作优化（用户回复“好的”确认前三项）

- 范围：训练记组状态及顶部层级、目标页当前7日均重/变化/覆盖率、明日备餐分组与分享清单。饮食当前餐次高亮和全体二级页面重做不在本轮。
- 当前事实：未完成组显示绿色勾；目标体重大字优先于当前均重；采购清单混入水和常备调料。
- 冲突检查：延续既有图形风格与四Tab、目标历史/医学未知/计划实际分离；本轮仅调整展示优先级和导出文本，不变更训练计时规则、营养建议或数据库。
- AC-12：未完成组为空心圈、完成后实心勾/摘要，一次点击完成且能撤销恢复；头部压缩后主要输入首屏可达。
- AC-13：当前7自然日均重优先，目标体重为参照；近7日与前7日均≥3有效天才比较，缺记录显示不足，不以自述起点冒充实测进展。
- AC-14：需要购买、常备需核对、烹调用水分开，已知克重按每餐取一份汇总，未知不凑完整总量，医学份量未确认显式标注；分享文字显示菜式、份数和午晚分装。
- 验证：针对性单元与UI回归及实际截图；不是新一轮固化/发布，真机和本人验收继续单列。
- 并行：worker 分别负责目标页和备餐展示/文本；Coordinator 负责训练、共享档案、交叉审查及串行运行构建测试。

### 日常操作优化结果

- AC-12：空心圈待完成、实心勾已完成及AX状态；顶部压缩，完成/撤销/重做/Tab恢复通过，三位小数及计时类动作单位记录通过。
- AC-13：当前7日均重成为主数字，覆盖率、变化阈值及记录按钮集中；前7日不足不比较。纯函数4项与目标首屏/大字体可达UI通过。
- AC-14：备餐开放式列表，个人份量待确认/需要购买/常备需核对/烹调用水分组；ShareLink文本先菜式、1人每餐1份和餐盒，再采购与步骤。6项纯展示测试及实吃→分享→复盘通过。
- 最终模拟器构建及46单元/13 UI通过，证据 `outputs/ui-redesign/daily-usability/verification.json`。首次编译的MainActor隔离错误修复，原始日志保留。
- 6个App/模型文件指纹未改；FatLossService仅prepText转交新展示helper，购物合计及持久化规则不变。
- 实际对比预览 `outputs/ui-redesign/daily-usability/index.html`；editorial-preview入口已引用本轮三页，旧PNG保留比较。本人审美/操作尚未验收，真机NOT_RUN。
- 组间休息已按此前需求移除，本轮未恢复；更正此前建议中“保留现有计时”的不准确表述。
- 本轮为局部优化，未重新运行完整阶段脚本或iPhoneOS Release，不能把旧全量结果视为本轮结果。未commit/tag/push、发布或安装真机。

## 备餐视觉反馈补充（2026-09-06）

- 用户否定 daily-usability 备餐与采购两张截图；本次继续已确认全 UI 重构与日常操作优化范围，重做备餐展示层。
- 当前事实：菜单为无图文字列表，采购默认展开原配方说明，首屏层级和操作重点不清楚。
- 目标：菜单采用餐食示意图与分装卡；菜单/采购直接切换；采购按名称和合计量扫描，库存、原配方和保存说明按需展开。
- 边界：不改食谱、医学份量、采购计算、分享内容及模型；未知份量继续明确提示。与 AC-05/07/14 无语义冲突。
- 验收：两餐/每餐一份清楚；切换采购和待确认详情可达；库存与水不混入直接采购；大字体、分享与返回可用。视觉验收仍由用户实际反馈。
- 验证层：本轮定向单元/UI 回归与模拟器实图；不代替完整阶段脚本、真机与真人验收。

### 本次备餐反馈的实现与验证

- `FatLossMealsView.FatLossPrepView`：菜单/采购切换；两餐图文卡、每餐一份；首屏待确认入口与份量详情；采购名称/数量对齐，原配方、库存和水按需展开；固定底部分享。
- `RedesignUITests`：验证切换、首屏待确认、详情返回、分享与库存展开。大字体参数修正为 `UICTContentSizeCategoryAccessibilityXXXL`，新增实际标题高度断言。旧 daily-usability 大字体截图使用无效参数，不作为最大辅助字号证据。
- 最终定向验证：6 单元、3 UI 通过；`/tmp/xfit-prep-refinement-final.xcresult`。日志、模拟器实图和哈希见 `outputs/ui-redesign/prep-refinement/verification.json`。HTML 本地资源链接检查通过。
- 保护核对：PrepPresentation、FatLossService、FatLossModels、ActiveWorkoutView、GoalHomeView 相较本轮前哈希不变；没有修改业务计算或真实数据。
- 预览：`outputs/ui-redesign/prep-refinement/index.html`；daily-usability 和 editorial-preview 指向新版备餐图，旧图保留。
- 局部本地验证完成；整阶段回归、真机与用户实际体验仍单列，未标记已验收或 GO。

## 继续统一其他页面（用户确认“好的，继续推进”）

- 授权范围：延续已确认的全界面重构；采用用户认可的图文、紧凑清单和细节展开方向，继续整理其他页面。仍回写同一需求。
- 当前事实：食谱详情默认展示整批原配方长列表；周复盘均重/执行/反馈为同级文字；我的两个设置入口指向同页。首轮集中完成食谱详情、每周复盘、我的与设置的视觉/入口精修。
- 非目标：不变医学参数、训练计算、目标/食谱版本、保存与备份协议；不提交、发布或安装真机。与已确认四 Tab 及历史保护规则无冲突。
- 验收：食谱明确原配方份数、材料/步骤与个人待确认区别；复盘关键数字优先、草稿与保存动作清楚；设置入口明确，所有原操作保留。普通/辅助字号可达，实际截图与保存路径定向验证，人工验收仍单列。
- 分工：Coordinator负责食谱、复盘、共享需求与构建验证；Worker负责独立的我的/设置页面检查与视觉实现。共享写入、构建与收口串行。
- 同轮继续覆盖审计中其余三个入口：训练管理/模板以紧凑摘要进入原编辑器；训练历史压缩列表并保留详情、补录/导入；记录工具把快速记录前置，保留助手展开偏好与写入确认。对应原 AC-01/03/07，不更改业务语义。
- 工具页顺序冲突待用户决定：`../2026-09-02/144115_agent-v2.md` AC-06/C-04 明确助手对话优先、首屏输入；快速记录前置会改变该已确认顺序。已单独询问用户，决定前不改顺序或默认展开偏好；可继续独立的颜色/留白精修与其他页面。

### 其他页面统一的实际结果

- 食谱详情：图文头部、原配方份数、食材/做法切换；整批用量、个人份量待确认和制作/保存/来源详情分层，照片明确示意。复用原 RecipeDraft。
- 每周复盘：均重/覆盖率/训练/实吃优先；备注与下一步草稿、底部保存、历史展开。保存快照、版本和目标/菜单单独确认沿用原服务。
- 我的/设置：紧凑分组；备份直达同一 AppSettingsView 数据模式；偏好/数据切换，原权限、导入预检/确认和备份 handlers 保留。
- 训练管理/模板/历史：下一次训练前置，三个管理入口合并；模板压缩为动作/组数摘要；历史为日期与训练摘要行。原查询、手动安排、详情及编辑器不变。
- 工具页：只统一助手图标与快捷入口配色；顺序冲突仍待用户决定，未替代旧规则。
- 验证：36 单元、11 个独立 UI 用例按最新结果全部 PASS。复盘和历史测试的多行字段点击定位各失败一次，修正测试定位后分别补跑通过，原 FAIL 保留；没有为通过测试修改业务处理。详见 `outputs/ui-redesign/secondary-refinement/verification.json`。
- 实际模拟器截图/前后对比：`outputs/ui-redesign/secondary-refinement/index.html`；普通字号、大字体、键盘、备份生成、复盘/历史保存回看已定向验证。5 个保护基线文件哈希不变。
- 本轮仅已实施范围本地验证；工具顺序待决定，完整阶段脚本/真机/本人体验仍独立，不标记 GO 或已验收。

## 目标首页视觉精修（2026-09-07 用户确认）

- 用户确认目标首页当前视觉粗糙、不够精美；本轮人工视觉验收未通过，阶段继续保持 `BLOCKED_HUMAN`。
- 用户确认先完成优秀参考研究并由本人选择方向；方向确认前不修改 `GoalHomeView` 或共享正式组件。
- 目标：用紧凑的周期信息、七日均重主视觉、目标参照、记录覆盖率、精修趋势图、体重记录与周复盘操作，形成完整的目标仪表盘；普通字号为默认，主数字不回到夸张大字。
- 非目标：不修改体重统计、少于三个有效称重日不判断趋势、医学参数未知、目标历史、训练统计、记录与备份语义；不导入或改写真实数据。
- 当前事实：当前页由独立标题、数字、整宽荧光绿按钮、默认折线图及菜单行顺序堆叠；功能与真机自动路径已通过，但本人视觉反馈未通过。
- 冲突检查：延续四 Tab、炭黑/暖白/荧光绿和一个主目标规则；用户已明确排除大字体方向。与数据及医学规则无冲突。
- 验收：首屏能回答当前均重、目标、记录可信度和本周动作；图表具有统一视觉语言；记录体重和周复盘操作清楚；普通字号、辅助字号和键盘状态可达；模拟器与真机截图分别复核，最终视觉仍由本人确认。
- 验证层：参考方向确认 → SwiftUI 实现 → 定向单元/UI 与模拟器实图 → 覆盖安装真机 → 本人视觉验收。任何前层通过均不替代本人验收。

### 目标首页视觉精修实现与本地验证

- 用户查看参考方向后回复「很好」；本轮采用推荐的 A「目标轨迹」，把周期、七日均重、目标参照、覆盖率、趋势解释和两个主要操作合为单一主卡。
- `GoalHomeView.swift` 已改为主目标卡加四个关联指标：训练执行、腰围、步数/睡眠和今日体感；肌群分布、医学状态与历史资料降为二级入口。普通字号继续作为默认。
- 业务保护保持：前后两个七日窗口均不少于 3 个有效称重日才比较；不使用自述起点替代实测趋势；医学参数未知时不显示剩余额度或旧的 2400 kcal / 160 g 默认值。
- 首次模拟器实图发现趋势面积填充越过图表区域；已将面积图改为明确的上下界并裁切到图表容器，复跑实图确认不再污染下方指标。
- 本地验证：Simulator Debug 构建通过；`GoalProgressPresentationTests` 4/4 通过；目标首页/周复盘/肌群路径与辅助字号 2/2 通过；四 Tab、体重输入和医学未知状态 2/2 通过。证据见 `outputs/ui-redesign/goal-refinement/verification.json`。
- 当前阶段：本地已验证；设备在本轮检查时为 `unavailable`，因此覆盖安装、设备数据守恒与真机截图尚未执行；本人对最终运行页的视觉和实际操作仍待确认，不能标记 `已验收` 或 `GO`。

### 目标首页真机覆盖安装第一次执行

- 用户确认手机已连接并解锁后，统一 `device` 入口完成设备预检、安装前活动 App Group 备份、SQLite 完整性、签名 Release 构建与覆盖安装；版本为 `0.5.0 (11)`，未卸载或清容器。
- 安装后活动库再次通过完整性检查；核心记录安装前后保持 `ZSESSIONEXERCISE 203`、`ZSETLOG 837`、`ZWORKOUTSESSION 36`，没有减少。
- 长时间签名构建后手机已自动锁定，安装后的自动启动被 iOS 以 `Locked` 拒绝；立即重试仍为锁定状态。脚本据此停止，真机 XCTest 未运行，不将覆盖安装成功冒充完整设备阶段通过。
- 权威证据：`outputs/stage-validation/20260907-goal-refinement-device/summary.md`。恢复条件：手机再次解锁并保持亮屏，重新执行设备启动、版本回读和真机测试，随后再比较测试后的活动库。

### 目标首页真机测试第二次执行

- 手机再次解锁后，已安装版本启动成功并回读为 `0.5.0 (11)`；统一 `device` 入口再次完成覆盖安装、启动、安装前后活动库检查和 258 项真机单元测试，单元测试 256 通过、2 跳过、0 失败。
- 真机 UI Runner 连续两次在“启用自动化模式”阶段等待 60 秒后超时，尚未进入任何 UI 测试用例；单个目标页 smoke 复跑结果相同。当前不能将其归因为目标页产品失败。
- 设备当时保持解锁，Developer Mode 已开启；CoreDevice DDI 回读为 `contentIsCompatible=true`。下一步需在手机开发者设置确认“启用 UI 自动化”，随后只补跑缺失的真机 UI 层。
- 测试后 SQLite 完整性通过，安装前至测试后核心记录仍为 `ZSESSIONEXERCISE 203`、`ZSETLOG 837`、`ZWORKOUTSESSION 36`。权威汇总：`outputs/stage-validation/20260907-goal-refinement-device-retry/summary.md`。
