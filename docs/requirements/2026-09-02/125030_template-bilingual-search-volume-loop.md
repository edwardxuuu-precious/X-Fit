# 需求：训练模板、双语动作搜索与容量历史闭环

- 需求 ID：`REQ-20260902-125030`
- 创建时间：`2026-09-02 12:50:30 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-02 12:50:30 +0800`
- 用户确认摘要：`用户确认按需求确认单覆盖旧规则并开发：专项训练复用可编辑模板；训练完成后仅回写关联长期模板已有动作参数，历史快照与模板结构不变。`
- 真机部署授权：`2026-09-02 16:18:34 +0800，用户明确要求部署到真机；授权覆盖安装、启动、版本回读及安装前后数据守恒检查，不包含真机 XCTest。`
- 真机测试授权：`2026-09-03 09:16:42 +0800，用户明确改为由 Codex 直接测试、不使用 Zcode；授权本轮真机 XCTest、测试前后数据守恒检查，不包含人工手感验收、Git 或发布。`
- 真机失败修复授权：`2026-09-03 15:34:34 +0800，用户确认开始修复真机全量 UI 的两条稳定失败；范围为系统粘贴菜单测试与专项模板编辑器空动作列表，不包含 Git 或发布。`
- 状态：`真机待验收`
- 关联需求：`REQ-20260830-131240`（覆盖其“当天调整不自动回写长期周模板”边界中的参数回写部分）；[`REQ-20261030-144735`](../2026-10-30/144735_active-workout-reduce-sets.md)（用户明确替代手动减组动作自动回写长期模板的部分，其他动作仍沿用本需求）；[`REQ-20261102-140102`](../2026-11-02/140102_active-workout-replace-exercise.md)（本人确认新增训练中替换的同类例外：被替换原动作不回写长期模板，其他动作保留本需求规则；实现/验证状态以新需求为准）
- 目标版本/阶段：待定

## 用户原始需求

> 训练计划按肌群多选，动作按照设备肌群，中文首字母排序，中英文要做到双向模糊搜索，就是我搜 squat 要能出来深蹲。另外制定专项训练，其实就是模板，有默认的，但是可以让我修改，我做完训练，里面的动作的数量跟重量记录要更新成为最新的，同时记录下来这个动作历史的 volume 变化，采用折线图。

> 用户确认：确认，按此覆盖旧规则并开发。

> 用户追加确认：你可以直接进行测试吧，不要用 zcode 了。

> 用户追加确认：好的，开始进行修复。

## 目标

- 今日训练继续支持肌群多选；动作候选按器械、肌群、中文名拼音首字母稳定排序。
- 动作搜索统一覆盖中英文标准名、别名与器械词，支持忽略大小写、空格、连字符的双向 substring 匹配；`squat`/`squa` 必须命中“深蹲”。
- “专项训练”复用现有 `WorkoutTemplate` / `TemplateExercise`，保留默认推/拉/腿模板并允许用户编辑，不建立第二套模板模型。
- 完成由长期模板发起的训练时，仅以实际完成的非热身组更新关联模板中已有动作的组数、每组次数与重量。
- 历史训练快照保持不可变；动作级 volume 按完成训练日持续聚合，并使用现有折线图展示。

## 非目标与边界

- 不提供拼写纠错；`sqaut` 等编辑距离搜索不在本轮范围。
- 不因一次训练自动增删模板动作、改变顺序或更新未完成动作；临时动作仍需用户在模板编辑页确认。
- 一次性当天训练（`isOneOff == true`）不回写长期模板。
- 不修改既有 `WorkoutSession`、`SessionExercise`、`SetLog` 历史事实；不因模板更新重算旧快照。
- 真机覆盖安装与 XCTest 已于后续分别获得授权；人工手感验收、Git commit、tag、push 或发布仍不在本轮范围。
- 当前工作树已有其他未提交修改；本轮仅做增量编辑，不覆盖或回退既有改动。

## 当前事实

- `DailyWorkoutBuilderView` 已使用 `Set<String>` 支持肌群多选；推荐动作已按器械分组，但组内仍按推荐分数排序。
- `ExerciseCatalogService.search` 已做大小写/变音符/全半角标准化 substring 搜索，并读取可选英文术语；默认动作种子没有稳定英文别名，故 `squat` 不能保证命中“深蹲”。
- `WorkoutTemplate` / `TemplateExercise` 已支持默认推、拉、腿计划和用户编辑；界面当前称为“每周模板”。
- `WorkoutService.finish` 当前只完成 session/schedule，不回写模板参数。
- `TrainingMetrics.volumeTrends` 与 `StatsView` 已按动作聚合完成的非热身组并显示折线图，本轮复用现有真源并补回归。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 今日训练肌群可多选，取消某肌群保持既有确认语义 | P0 | UNIT/SIM-UI | 可同时选择两个以上肌群；选择状态可访问且动作候选随之变化 |
| AC-02 | 动作按器械、肌群、中文名拼音首字母稳定排序 | P1 | UNIT/SIM-UI | 中文名称按拼音 A-Z；同名键使用稳定后备顺序；推荐分数不打乱目录顺序 |
| AC-03 | 中英文双向模糊搜索 | P0 | UNIT/SIM-UI | `squat`、`squa`、`深蹲` 均命中深蹲；大小写、空格和连字符差异不影响命中 |
| AC-04 | 专项训练复用现有可编辑模板 | P0 | UNIT/SIM-UI | 默认推/拉/腿可见；可修改名称、肌群、动作顺序与逐组次数/重量，不产生平行模型 |
| AC-05 | 完成长期开启的模板训练后更新已有动作参数 | P0 | SERVICE | 每个动作的完成非热身组转为模板 `plannedSets`；组数、次数、重量与本次实际值一致 |
| AC-06 | 模板自动更新边界 | P0 | SERVICE | 一次性模板、未完成动作、热身组及临时新增/删除/排序均不改变长期模板结构；保存失败不留下部分模板更新 |
| AC-07 | 历史与 volume 折线图 | P0 | UNIT/SIM-UI | 旧 session/snapshot/log 不变；同一动作两次完成训练形成两个日期点，volume 使用各自完成非热身组 |
| AC-08 | 现有训练与数据流程不回归 | P0 | UNIT/SERVICE/SIM-UI/GENERIC-BUILD | 针对性测试、全量单元/UI、模拟器构建和无签名 iPhoneOS Release 构建通过 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | `REQ-20260830-131240` 的“当天调整不自动回写长期周模板” vs 本次训练完成后更新模板参数 | 长期模板的组数、次数和重量会随完成记录变化 | 是否覆盖旧边界 | 用户确认覆盖；仅回写关联长期模板已有动作参数，结构与历史不变 | 已决定 |
| C-02 | 现有推荐按分数排序 vs 本次中文拼音首字母排序 | 动作候选展示顺序改变 | 目录顺序是否优先于推荐分数 | 用户确认按器械、肌群、中文首字母排序 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02/03/04 | `ExerciseCatalogService`、`DailyWorkoutBuilderView`、`ExercisePickerSheet`、`PlanView`、`SeedDataService` | `ExerciseCaptureRobustnessTests`、`FitnessAppUITests` | 已实现并定向通过 |
| AC-05/06 | `WorkoutService.finish` 的长期模板参数回写 | `ScheduleAndDataTests` | 已实现并定向通过 |
| AC-07 | `TrainingMetrics.volumeTrends`、`StatsView` | `TrainingMetricsTests`、`FitnessAppUITests` | 复用现有实现并回归通过 |
| AC-08 | 完整应用 | `scripts/xfit-stage-validation.sh all` | 已实现并完成分层验证 |

## 已确认测试 seams

- 搜索与排序：通过 `ExerciseCatalogService` 的公开查询/目录接口验证返回动作及稳定顺序，不测试私有标准化函数。
- 模板回写：通过 `WorkoutService.finish` 完成真实 SwiftData 测试容器中的训练，再从 `WorkoutTemplate`/`TemplateExercise` 公共模型读取结果；不 mock 内部服务。
- 交互：通过动作选择页、模板编辑页和进度页公开可访问性节点验证肌群多选、双语搜索、默认模板编辑入口和折线图。
- 历史保护：比较调用前后既有 session/snapshot/log 公共字段及记录数，不读取或修改真实设备数据库。

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01…08 / 本地静态检查/构建 | 差异无格式错误，Debug 模拟器构建通过 | `git diff --check` 与 N01/N02/N04 通过 | PASS | `outputs/stage-validation/20260902-template-bilingual-volume/summary.md` | 最终 App/UI target 后续也重新编译成功 |
| AC-02/03/05/06/07 / 单元/服务测试 | 公共 seam 的目标测试及全量单元通过 | 8 个目标单元/服务/volume 测试通过；N05 全量单元通过 | PASS | `/tmp/xfit-template-core-units-current-final.xcresult`、N05 log | 初始 RED 运行被模拟器首次迁移/worker materialize 阻断；测试先于实现落盘，后续 GREEN 已执行 |
| AC-01/03/04/07 / 模拟器 UI | 多选、搜索、模板入口与折线图通过 | 专项模板目标肌群多选/动作排序入口、英文搜深蹲并显示分组、专项模板入口、按动作 volume 折线图 4 项通过 | PASS | `/tmp/xfit-template-editor-ui-final-green.xcresult`、`/tmp/xfit-template-core-ui-current-final.xcresult` | 全量 N06 另有既有场景失败，见遗留项 |
| AC-08 / 全量模拟器 UI | 全量 UI 通过 | 最终 N06 为 70 PASS、7 SKIP、0 FAIL | PASS | `artifacts/stage-validation/20260903-final-deployment-final/N06.log` | 默认动作选择器压力循环为 5 轮 |
| AC-08 / 通用 iPhoneOS 构建 | 无签名 Release 构建通过 | N07 通过 | PASS | `outputs/stage-validation/20260902-template-bilingual-volume/summary.md` |  |
| AC-01…08 / 真机覆盖安装 | 覆盖安装且不卸载、不清容器 | Edward_iPhone 已完成签名 Release 覆盖安装、启动及版本回读，版本 `0.5.0 (11)` | PASS | `outputs/stage-validation/20260902-template-bilingual-volume-device/summary.md` | D00、D03–D05 PASS |
| AC-01…08 / 真机全量单元测试 | 在 Edward_iPhone 执行全量单元 XCTest | 执行 199 条，1 条跳过、0 失败 | PASS | `outputs/stage-validation/20260903-template-bilingual-volume-device-tests-unlocked/summary.md`、D07A log |  |
| AC-01…08 / 真机全量 UI 测试 | 在 Edward_iPhone 执行全量 UI XCTest | 最终完整执行 77 条；66 通过、7 条件跳过、4 条受系统通知/外部 App 抢焦点影响失败，4 条随后均定向复跑通过；`squat` 搜索、模板 44kg × 10 回写和默认 5 轮压力项均通过 | PASS | `outputs/stage-validation/20260903-final-deployment-final/final-device-ui-closeout.md` | 没有遗留产品断言失败 |
| AC-04/05/06 / 失败修复定向回归 | 模板编辑稳定加载并完成参数回写；系统粘贴测试不依赖测试进程跨进程剪贴板 | 模拟器 UI 2/2 PASS；模板回写服务单元 2/2 PASS | PASS | `/tmp/xfit-bugfix-template-paste-sim-green5.xcresult`、`/tmp/xfit-template-bugfix-unit.xcresult` | 模板编辑改用 item 驱动弹窗并按模板 ID 显式加载；UI 测试剪贴板由 App 自身在测试模式注入 |
| AC-04/05/06 / 修复后真机定向回归 | 同两条失败在 Edward_iPhone 通过 | 设备解锁并保持常亮后重跑 2/2 PASS：系统全选/粘贴成功；模板完成训练后 3 组回写为 44kg × 10，未完成动作保持 16kg | PASS | `outputs/stage-validation/20260903-template-bugfix-targeted-device-unlocked/summary.md`、`artifacts/stage-validation/20260903-template-bugfix-targeted-device-unlocked/device-targeted.xcresult` | 测试前后活动库均 `quick_check=ok`、`199/825/35` |
| AC-07 / 活动 App Group 数据回读 | 安装及测试前后数据库完整且核心记录不减少 | `quick_check=ok`；安装前到全量及定向复跑后均为 `ZSESSIONEXERCISE 199`、`ZSETLOG 825`、`ZWORKOUTSESSION 35` | PASS | `artifacts/stage-validation/20260903-template-bilingual-volume-device-tests-unlocked/device-audit/` | D01、D02、D06A–D06C、D08A–D08C PASS；定向复跑后再次只读核验 |
| AC-01…07 / 真人体验验收 | 用户在后续真机包确认排序、搜索和模板更新体验 |  | NOT_RUN |  |  |

## 已执行动作

- 完成用户确认前只读检查并提交需求确认单。
- 用户明确确认覆盖旧规则；创建本需求档案并记录公共测试 seams。
- 扩展动作搜索：读取时补全术语目录中的中英文名/别名，统一忽略大小写、空格、连字符和下划线，并按中文拼音键稳定排序。
- 每日推荐、动作库和专项模板添加菜单按“器械 → 肌群 → 中文拼音”分组/排序；保留今日训练肌群多选。
- 将“每周模板”产品表达调整为“专项模板”；模板继续复用现有模型，编辑器支持目标肌群多选、动作拖动排序及逐组次数和重量。
- 完成长期模板训练时，用本次实际完成的非热身组回写模板已有动作 `plannedSets`；一次性模板、未完成动作与临时加练不回写，保存失败执行 rollback。
- 复核并保留现有动作级 volume 聚合与折线图，不建立平行历史口径。
- 开发阶段执行目标测试、完整 `non-device` 门禁及失败集复跑；当时未执行真机、Git 或发布动作，后续真机覆盖安装见下一条。
- 用户后续授权真机部署；按 `scripts/xfit-stage-validation.sh device` 完成活动数据安装前备份、签名 Release 构建、覆盖安装、启动/版本回读、安装后备份及核心记录守恒检查，全程未卸载或清容器。
- 用户于 2026-09-03 授权 Codex 直接执行真机测试；本轮签名构建及覆盖安装成功，但设备锁屏使系统拒绝启动 App，安全脚本因此未进入 XCTest。安装前后 `quick_check=ok`，核心记录仍为 `199/825/35`。
- 用户解锁设备后复跑正式真机门：D00–D07A、D08A–D08C PASS，D07B FAIL。真机全量单元执行 199 条、0 失败；UI 执行 77 条、7 跳过、2 失败。`squat` 搜索深蹲、专项模板肌群多选/动作排序入口及动作 volume 折线图用例均通过。
- 两条 UI 失败独立复跑均可重现：系统“全选”后 2 秒内未出现“粘贴”菜单；模板卡片已有 4 个动作，但编辑器三次加载为空，未走到训练完成后的参数回写步骤。复跑后活动库 `quick_check=ok`，核心记录仍为 `199/825/35`。
- 用户授权修复后确认根因：模板编辑同时写入可选模板和布尔弹窗状态，SwiftUI 偶发用旧的 `nil` 打开“新建模板”编辑器；真机粘贴失败则是 UI 测试 Runner 写入的剪贴板未可靠传入被测 App 进程。
- 模板编辑改为 `.sheet(item:)` 由模板对象直接驱动，并在编辑器中按模板 ID 显式读取动作；测试模式下由 App 自身按环境变量设置剪贴板。同步修正 UI 测试滚动助手，按钮只有处于可见区域且可点击时才算找到。
- 修复后模拟器 UI 两条用例 2/2 通过，覆盖系统全选/粘贴、完成训练、44kg × 10 三组回写、未完成动作保持 16kg；模板回写边界服务测试 2/2 通过。修复后真机定向运行因设备再次锁屏而未形成有效结果。
- 用户再次解锁设备并保持常亮后，修复后真机定向 UI 2/2 通过：系统全选/粘贴完整完成；长期模板完成训练后杠铃卧推 3 组均回写 44kg × 10，上斜哑铃卧推仍为 16kg。测试前后活动库 `quick_check=ok`，核心记录保持 `199/825/35`。
- 最终阶段全量 N01…N07 通过；真机完整 UI 77 项已执行，受系统通知抢焦点影响的 4 项均在同轮定向复跑中通过。测试后再次覆盖恢复精确签名 Release 0.5.0 (11)，活动库仍为 `quick_check=ok`、`199/825/35`。

## 结果与遗留项

- 当前结论：核心需求、完整 N06、真机单元和真机 UI 均已完成自动化验证；0.5.0 (11) 已最终覆盖部署。
- 自动化失败已清零，但 7 条条件跳过仍保持独立记录，不冒充执行通过。
- 需求状态保持 `真机待验收`；用户仍需人工确认中英文搜索、模板编辑/回写和 Volume 折线图的实际体验，确认后才可标记 `已验收` 与阶段最终 `GO`。
