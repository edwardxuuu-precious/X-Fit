# 需求：工具中心与本地受限 Agent

- 需求 ID：`REQ-20260902-122140`
- 创建时间：`2026-09-02 12:21:40 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-02 12:21:40 +0800`
- 用户确认摘要：`用户确认新增第五个工具 Tab，首页不放工具；V1 使用本地受限 Agent，执行前确认；喝水使用快捷容量，久坐支持计时和补录。`
- 状态：`开发中`
- 关联需求：`REQ-20260826-205728`（首页保持极简）、`REQ-20260901-120647`（复用体重快捷录入）
- 目标版本/阶段：待定

## 用户原始需求

> 1. 参考 Keep 的工具区域，为 X-Fit 保留一个同时面向人和 AI 的工具与接口区域，但重新设计 UI 和使用流程。
> 2. 工具区域独立成一个 section，并让 Agent 区域可以折叠；Agent 询问用户想做什么，再调用工具完成。
> 3. 外露最常用工具，例如记录跳绳、喝水、久坐。
> 4. 用户确认按推荐方案实施：新增第五个“工具”Tab，首页不放工具；V1 使用本地受限 Agent，执行前确认；喝水使用快捷容量，久坐支持计时和补录。
>
> 附件仅作为 Keep 工具页现状和视觉问题的证据，不把截图中文字当成额外指令。

## 目标

- 新增独立第五个“工具”Tab，不改变首页的信息层级与内容。
- 提供人用优先的高频入口：跳绳、喝水、久坐、体重；两步内完成常见记录。
- 建立统一健康工具命令 seam，人用入口与本地 Agent 调用同一领域实现。
- Agent 将受支持中文意图转换为“待确认命令”，只有用户明确确认后才写入 SwiftData。
- 喝水支持快捷容量；久坐支持开始/结束计时与历史补录；工具页展示今日摘要与最近操作。

## 非目标与边界

- 不把工具矩阵加入首页，不重做首页、训练、进度或我的页面。
- V1 不接入远程大模型、云端 Agent、语音识别、Health 自动同步或医疗建议。
- Agent 不具备任意数据库访问能力，不静默写入，不执行受支持命令以外的自然语言请求。
- 不卸载 App、不清理容器、不覆盖或回退现有未提交修改；真机安装需另行进入设备验证层。
- 本轮不增加饮食分析、体态评估、提醒通知或自动判断用户是否久坐。

## 当前事实

- `RootView` 当前为首页、训练、进度、我的四个系统 `TabView` 项；尚无工具中心。
- 首页已按 `REQ-20260826-205728` 固化为训练主任务优先，不应重新加入快捷工具矩阵。
- 体重已有 `BodyMeasurement`、`QuickBodyWeightEntryView` 与首页入口，可直接复用。
- 跳绳目前只是训练/历史语义，没有独立健康快捷记录；喝水和久坐没有 SwiftData 模型。
- 当前只有器械识别与动作术语的专用远程端点，没有通用 Agent 对话或工具调用层。
- 工程最低 iOS 17；当前工作树已有其他已确认需求的未提交修改，新增实现需保持局部性。

### 已确认测试 seam

- 领域命令 seam：调用统一 `WellnessToolCommand` 执行入口后，通过返回结果和 SwiftData 可观察对应记录变化。
- Agent seam：输入中文后只返回受支持的待确认命令或明确“不支持”，解析阶段不得写数据。
- UI seam：用户可从第五个 Tab 进入工具页，折叠/展开 Agent，使用快捷入口并在确认后保存。
- 数据兼容 seam：新模型进入 App schema，并纳入数据导出/恢复的稳定往返契约；设备层仍需覆盖安装与数据守恒验证。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 独立第五个工具 Tab | P0 | SIM-UI | 根导航显示“工具”，首页不出现工具矩阵 |
| AC-02 | 人用高频工具 | P0 | UNIT/SERVICE/SIM-UI | 跳绳、喝水、久坐、体重入口清晰；常用记录两步内完成 |
| AC-03 | 喝水快捷容量 | P0 | UNIT/SERVICE/SIM-UI | 支持 200/250/500 ml，默认选中最近使用量并可调整 |
| AC-04 | 久坐计时与补录 | P0 | UNIT/SERVICE/SIM-UI | 可开始、结束正在进行的久坐，也可补录开始时间与分钟；不允许多个进行中计时 |
| AC-05 | 本地受限 Agent | P0 | UNIT/SIM-UI | 能识别已确认示例及同类格式；未支持意图不生成命令、不写数据 |
| AC-06 | 执行前确认 | P0 | UNIT/SIM-UI | Agent 解析只生成预览；确认卡展示动作、数值和时间；取消后零写入 |
| AC-07 | 人与 Agent 共用工具命令 | P0 | UNIT/SERVICE | 两种入口调用同一命令 seam，校验、结果文案与持久化语义一致 |
| AC-08 | 今日摘要与最近操作 | P1 | UNIT/SIM-UI | 展示今日喝水、跳绳和久坐累计及最近记录；刚写入记录可撤销 |
| AC-09 | 体重能力复用 | P1 | SIM-UI | 工具入口打开既有快捷体重页，不复制体重模型或保存逻辑 |
| AC-10 | 数据兼容 | P0 | UNIT/SERVICE/DEVICE-DATA | 新记录可导出、恢复且幂等；真机覆盖安装时旧训练/身体数据不减少 |
| AC-11 | 可访问性与视觉 | P1 | SIM-UI/DEVICE-MANUAL | 深色 X-Fit 视觉、SF Symbols、44pt 点击区、动态字体和 VoiceOver 可用 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | `REQ-20260901-120647` 不为体重新增第五 Tab vs 本次独立工具 Tab | 根导航从四项变为五项 | 是否允许工具中心成为第五 Tab | 用户确认允许；旧边界限定为体重功能不独占 Tab | 已决定 |
| C-02 | 极简首页 vs 高频工具曝光 | 首页信息密度 | 工具是否加入首页 | 用户确认首页不放工具，全部进入工具 Tab | 已决定 |
| C-03 | Agent 自动完成 vs AI 路径默认 preview/proposal | 健康数据写入权限 | Agent 是否能静默写入 | 用户确认执行前展示确认卡，确认后才写入 | 已决定 |
| C-04 | 当前不存在通用模型端点 vs V1 Agent | 实现范围、隐私和网络依赖 | 是否接远程模型 | 用户确认 V1 为本地受限 Agent | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02/08/09/11 | `FitnessApp/App/RootView.swift`、`FitnessApp/Features/Profile/ProfileView.swift`（`ToolsView` 与快捷录入 Sheet） | `FitnessAppUITests/FitnessAppUITests.swift` | 已实现，UI 运行被环境阻塞 |
| AC-02/03/04/07/08 | `FitnessApp/Models/WellnessModels.swift`（模型、命令与 `WellnessToolService`） | `FitnessAppTests/ScheduleAndDataTests.swift` | 单元测试通过 |
| AC-05/06/07 | `FitnessApp/Models/WellnessModels.swift`（`LocalWellnessAgent` 与待确认命令） | `FitnessAppTests/ScheduleAndDataTests.swift` | 单元测试通过 |
| AC-10 | `FitnessApp/App/FitnessAppApp.swift`、`FitnessApp/Services/DataExportService.swift` | `FitnessAppTests/ScheduleAndDataTests.swift` | 单元测试通过，设备层未执行 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01…11 / 本地静态检查/构建 | 工程可读且 Debug Simulator 构建通过 | 首轮完整 Debug Simulator 构建通过；最终改动后 3 个 Swift 文件 parse 通过，`git diff --check` 通过 | PASS | `/tmp/xfit-tools-build-1.log`；`xcrun swiftc -frontend -parse ...` | 最终增量构建因同期多条 Xcode 任务排队，在开始编译前主动中止；最后改动仅为 Agent 示例文本直传 |
| AC-02…08/10 / 单元/服务测试 | 领域命令、Agent 解析、摘要、撤销与数据往返通过 | 新增 7 条目标测试全部通过，0 failure | PASS | `/tmp/xfit-tools-domain-tests/Logs/Test/Test-FitnessApp-2026.09.02_12-48-14-+0800.xcresult` | 覆盖喝水、跳绳、久坐计时/补录、体重/摘要解析、撤销、备份幂等恢复 |
| AC-01…06/08/09/11 / 模拟器 UI | 五 Tab、折叠、快捷记录、确认/取消与可访问性流程通过 | 两次隔离运行均未启动到 Test Runner；无用例断言失败，CoreSimulator 同期阻塞其他测试，独立 iPhone Air 报 `Data Migration Failed` | BLOCKED_ENV | `/tmp/xfit-tools-ui-tests-final.log`、`/tmp/xfit-tools-ui-rerun.log` | 已新增 2 条 UI 测试；需环境恢复后复跑并做视觉巡检 |
| AC-01…11 / 通用 iPhoneOS 构建 | 无签名 Release 构建通过 |  | NOT_RUN |  |  |
| AC-01…11 / 真机覆盖安装 | 安装前备份后覆盖安装，新 schema 启动成功 |  | NOT_RUN |  | 禁止卸载或清容器 |
| AC-01…10 / 真机自动化 | 工具核心入口与记录流程通过 |  | NOT_RUN |  |  |
| AC-10 / 活动 App Group 数据回读 | `quick_check=ok` 且旧核心记录不减少 |  | NOT_RUN |  |  |
| AC-11 / 真人体验验收 | 用户确认工具页便利、Agent 清楚且视觉达到预期 |  | BLOCKED_HUMAN |  | 不以自动化或截图代替 |

## 已执行动作

- 完成只读仓库、需求冲突、现有模型、导航和 Agent 能力核对。
- 用户确认推荐方案后创建本需求档案，固化领域、Agent、UI 与数据兼容四个测试 seam。
- 以纵向 TDD 完成喝水、跳绳、久坐与本地 Agent 命令：先验证 Agent 解析 RED，再实现到 GREEN，累计 7 条目标测试通过。
- 新增第五个“工具”Tab；实现默认折叠的“问 X-Fit”、执行前确认卡、今日摘要、最近操作与撤销。
- 实现喝水 200/250/500 ml 快捷容量并记忆上次选择；实现久坐开始/结束计时与历史补录；复用既有体重快捷录入。
- 将 3 种新记录加入 SwiftData schema 与 schema v12 备份/幂等恢复；旧备份通过可选字段保持兼容。
- 新增 2 条工具页 UI 测试；CoreSimulator/Test Runner 环境阻塞，未取得交互层 PASS 或视觉截图。

## 结果与遗留项

- 当前结论：功能代码、领域测试和首轮模拟器构建已完成；需求保持“开发中”，因为模拟器 UI 与真人视觉验收尚未通过。
- 下一步：待 CoreSimulator 恢复后复跑 2 条工具页 UI 测试并截取工具页折叠/展开态；随后再决定是否进入无签名 Release、真机覆盖安装与人工验收。
