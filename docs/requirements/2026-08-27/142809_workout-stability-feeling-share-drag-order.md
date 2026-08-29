# 需求：训练交互稳定性、感受流程、资料提醒与拖动排序

- 需求 ID：`REQ-20260827-142809`
- 创建时间：`2026-08-27 14:28:09 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-08-27 14:28:09 +0800`；补充验收确认：`2026-08-28 16:56:34 +0800`
- 用户确认摘要：`用户确认四项实施范围；资料弹窗采用同一份资料仅自动提醒一次，新分享才再次提醒；并确认修复全部剩余通知相关失败，由 Agent 完成真机 Instruments 自动性能测试。`
- 状态：`真机待验收`
- 关联需求：`REQ-20260825-WORKOUT-UX`、`REQ-20260826-182544`
- 目标版本/阶段：待定

## 用户原始需求

> 1. 今天使用明显卡顿，RIR 偶发点击无反应；检查不必要代码和可能严重占用内存的实现，有证据时直接优化。
> 2. 最后一组完成后动作立即折叠，尚未来得及选择表情感受；完成小卡片应放在上方，减少反复翻找。
> 3. 临时动作资料弹窗反复出现，需要停止同一份资料的重复自动提醒。
> 4. 编排今日训练计划时，支持切换为只显示动作名称的小卡片，并通过拖动调整顺序，替代逐次点击上下箭头。
>
> 附件只作为当前弹窗和首页现象证据，不把附件中的文字当成额外指令。证据文件：`5884ccea463f0838eee368f52374c0b5.png`。

## 目标

- 建立可重复的性能、RIR 点击和核心交互反馈环，只修复有证据的卡顿或内存问题。
- 完成动作先收集表情感受或明确跳过，再折叠；完成卡片固定在未完成动作上方。
- 同一份分享草稿只自动提醒一次；新草稿继续正常提醒。
- 今日计划提供仅名称小卡片的直接拖动排序模式。

## 非目标与边界

- 不改写已完成训练历史、已完成组数值或既有动作快照。
- 不删除真实分享内容；“稍后处理”只抑制同一草稿的再次自动弹出，新分享仍可提醒。
- 不用删除源码文件数量或缩小二进制体积冒充运行时内存优化。
- 本轮不自动执行真机覆盖安装、清容器、Git commit、tag、push 或发布。
- 补充验收已授权真机覆盖安装与自动化测试；仍禁止卸载、清容器、Git commit、tag、push 或发布。
- Instruments 由 Agent 执行 CPU、内存分配、泄漏、动画卡顿与启动性能测试；真人主观流畅度仍由用户最终确认。
- 保留并精确合并当前未提交的首页、RootView、主题和 UI 测试改动。

## 当前事实

- `ActiveWorkoutView` 当前在最后一组完成后立即把整个动作替换成折叠卡；表情选择器只存在于重新展开后的完整卡片。
- 当前动作排序把未完成动作放在完成动作之前，因此完成卡片会移动到列表下方。
- `SetLogRow` 的 RIR 通过行内按钮打开 `confirmationDialog`；单次模拟器路径通过，但没有覆盖滚动、键盘与反复弹层切换后的压力场景。
- `RootView` 的“稍后处理”只清空页面状态，不清除或标记已提醒的草稿；场景重新激活会再次读取相同草稿。
- `DailyWorkoutBuilderView` 当前用完整配置卡展示已选动作，只支持上下箭头逐格排序。
- 生产路径未发现 200ms 常驻轮询；该循环受 UI 测试专用开关保护。性能候选包括大范围 `@Query` 后内存过滤、视图重算和视觉材质，但必须测量后才能定因。
- 开发前专项模拟器测试 3/3 通过：单次 RIR 路径、动作感受持久化、稍后处理后重新弹出；后两项验证了当前行为与新需求的差异。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | RIR 在滚动、键盘和弹层切换后的重复交互中保持可点击 | P0 | SIM-UI | 压力场景无点击失效，选择值可立即回读 |
| AC-02 | 完成最后一组后先显示 5 个表情与明确跳过入口 | P0 | SIM-UI | 未选择或跳过前不自动折叠；选择结果持久化 |
| AC-03 | 完成动作折叠后排列在未完成动作上方 | P1 | SIM-UI | 计划顺序稳定，下一个未完成动作可直接到达 |
| AC-04 | 同一份草稿选择“稍后处理”后不再自动弹出 | P0 | UNIT/SIM-UI | 切后台、回前台和重启后均不重复；新 ID 草稿仍提醒 |
| AC-05 | 今日计划支持仅名称小卡片的拖动排序模式 | P0 | UNIT/SIM-UI | 拖动后顺序即时更新并可保存；进行中训练只同步未完成内容 |
| AC-06 | 性能优化以基线和对比证据为准 | P1 | UNIT/SIM-UI/PERF | 无泄漏或随操作轮次持续增长；删除或改写的热点有前后证据 |
| AC-07 | 既有训练、分享和数据边界不回归 | P0 | UNIT/SIM-UI/GENERIC-BUILD | 相关测试、通用构建通过，历史数据模型未被重写 |
| AC-08 | 剩余通知相关真机 UI 失败全部收敛 | P0 | DEVICE-UI | 后台通知准备、通知抢占恢复、分享草稿隔离与取消恢复均稳定通过；不读取或清除生产草稿来伪造通过 |
| AC-09 | Agent 完成真机自动性能测量 | P1 | DEVICE-PERF | Time Profiler、Allocations、Leaks、Animation Hitches、App Launch 均生成可回读证据；无确认泄漏或操作轮次持续增长 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | `REQ-20260826-182544` 规定“稍后处理保留草稿并可再次弹出” vs 本次“不再重复自动提醒” | 分享草稿提醒生命周期改变 | 是否以本次规则替代旧规则 | 用户明确确认推荐方案：同一草稿只自动提醒一次，新分享再提醒 | 已决定 |
| C-02 | `REQ-20260825-WORKOUT-UX` 规定完成动作折叠下沉 vs 本次要求完成卡片置于上方且先收集感受 | 训练页排序和完成时机改变 | 是否以本次规则替代旧交互 | 用户确认本次需求确认单 | 已决定 |
| C-03 | 当前 Performance Poster 首页改动尚未提交且涉及 `RootView`/UI 测试 | 同文件编辑可能覆盖既有修改 | 如何保护当前工作树 | 在当前精确代码块上合并，只修改分享草稿和新增测试范围 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02/03 | `FitnessApp/Features/Workout/ActiveWorkoutView.swift` | `FitnessAppUITests/FitnessAppUITests.swift` | 本地已验证 |
| AC-04 | `FitnessApp/App/RootView.swift`、`FitnessApp/Services/ExerciseShareDraftInbox.swift` | `FitnessAppTests/ExerciseCaptureRobustnessTests.swift`、`FitnessAppUITests/FitnessAppUITests.swift` | 本地已验证 |
| AC-05 | `FitnessApp/Features/DailyPlan/DailyWorkoutBuilderView.swift` | `FitnessAppUITests/FitnessAppUITests.swift`、既有菜单顺序服务测试 | 本地已验证 |
| AC-06/07 | `FitnessApp/Features/Workout/ActiveWorkoutView.swift` | 静态热点审计、全量单元测试、专项 UI、通用构建 | 本地已验证；真机性能待验收 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01…07 / 本地静态检查/构建 | 代码可编译且无格式错误 | `git diff --check` 无输出 | PASS | 当前工作树 | 保留了用户原有未提交改动 |
| AC-04/05/07 / 单元/服务测试 | 草稿生命周期、排序和数据边界通过 | 154/154 通过 | PASS | `/tmp/xfit-full-unit-20260827/Logs/Test/Test-FitnessApp-2026.08.27_15-15-02-+0800.xcresult` | 最终 CPU 优化后重跑；新增同草稿抑制、新草稿恢复提醒测试 |
| AC-01…05/07 / 模拟器 UI | 四项用户流程均通过并可重复 | RIR、感受后折叠、资料抑制、名称卡拖动 4/4 通过 | PASS | `/tmp/xfit-share-red.ZtSeI8/Logs/Test/Test-FitnessApp-2026.08.27_15-09-23-+0800.xcresult` | 新行为测试先 RED，最终 GREEN |
| AC-06 / 静态性能审计 | 识别可确认热点，只保留安全优化 | 生产路径无常驻 200ms 轮询；动作排序由比较器反复扫描组记录改为单次分组；未发现可确认的严重泄漏或应删除资源 | PASS | 源码审计、最终 4/4 UI 联测 | 不用资源文件大小冒充运行时内存结论 |
| AC-06 / Instruments 内存曲线 | 前后基线可比较，无随操作轮次持续增长 | 未执行真机 Instruments | NOT_RUN |  | 不宣称真机内存结论 |
| AC-07 / 通用 iPhoneOS 构建 | Release 无签名构建通过 | `BUILD SUCCEEDED` | PASS | `/tmp/xfit-release-20260827/Build/Products/Release-iphoneos/FitnessApp.app` | 不等同真机安装 |
| AC-01…07 / 真机覆盖安装 | 安装前后数据守恒 | X-Fit 0.5.0 (11) 覆盖安装并启动成功；未卸载或清容器 | PASS | `outputs/stage-validation/iphone-device-20260827-1620/summary.md`、`artifacts/stage-validation/iphone-device-20260827-1620/device-launch-unlocked.json` | 首次自动启动因手机锁屏失败；解锁后重试通过 |
| AC-01…05 / 真机专项 UI | 本次四项交互通过 | RIR、名称卡拖动、同草稿抑制/新草稿提醒、感受后折叠 4/4 通过 | PASS | `artifacts/stage-validation/iphone-device-20260827-1620/device-ui-core-4.xcresult` | iPhone 17 / iOS 26.6；Automation Mode 已启用 |
| AC-01…06 / 真机全量自动化 | 全量回归通过 | 单元测试 154/154 PASS；UI 57 项中 53 PASS、4 FAIL。分享取消聚焦复跑 PASS；核心四项均 PASS；后台通知用例在进入通知断言前因找不到“开始训练”失败；50 轮选择器压力在第 39 轮通知抢占后无法返回 | FAIL | `artifacts/stage-validation/iphone-device-20260827-1620/device-unit-resume.xcresult`、`outputs/stage-validation/iphone-device-20260827-1620/device-ui-followup.md` | 全量不冒充全绿；通知准备态和抢占返回路径待跟进 |
| AC-07 / 活动 App Group 数据回读 | 核心记录不减少 | 安装前、安装后、单元测试后、UI 测试后均为 137 个训练动作、581 条组记录、20 次训练；`quick_check=ok` | PASS | `artifacts/stage-validation/iphone-device-20260827-1620/device-data/` | 覆盖安装与全部已执行测试后数据守恒 |
| AC-01…06 / 真人体验验收 | 用户确认流畅度和交互 |  | NOT_RUN |  | 自动化不可替代 |
| AC-08 / 通知相关真机 UI 回归 | 四个既有失败场景全部稳定通过 | 待修复后执行 | NOT_RUN |  | 用户于 2026-08-28 确认继续修复全部失败 |
| AC-09 / 真机 Instruments | CPU、内存、泄漏、卡顿、启动均有自动证据 | 待执行 | NOT_RUN |  | 覆盖安装且保留活动 App Group 数据 |
| AC-01…08 / 2026-08-28 完整非真机回归 | 修复后全量回归通过 | 静态、后端、模拟器构建、154 条单元测试、57 条 UI 测试、Release 构建全部通过 | PASS | `outputs/stage-validation/notification-perf-non-device-20260828-1724/summary.md` | 通知倒计时、分享取消/隔离、50 轮压力均包含在全量绿灯中 |
| AC-08/09 / 2026-08-28 真机续测 | 覆盖安装后完成全量 UI 与 Instruments | 安装前 App Group 备份及 SQLite 校验 PASS；签名构建因 Xcode 无登录账号且旧免费描述文件已过期而停止，未安装、未测试 | BLOCKED_ENV | `outputs/stage-validation/notification-perf-device-20260828-1757/followup.md` | 需用户在 Xcode Accounts 登录 Personal Team 后续签 |
| AC-01…09 / 2026-08-28 真机覆盖安装与自动化 | 覆盖安装、全量单元/UI、性能采样且数据守恒 | 覆盖安装及 154/154 单元 PASS；全量 UI 56/57 PASS，唯一失败为 50 轮测试的弹窗关闭动画竞态；Allocations 已正确附加 X-Fit 本体采样 120 秒；App Group 在安装后及测试后仍为 137/581/20 且 `quick_check=ok` | FAIL | `outputs/stage-validation/notification-perf-device-20260828-1828/summary.md`、`artifacts/stage-validation/notification-perf-device-20260828-1828/device-ui-retry.xcresult`、`artifacts/stage-validation/notification-perf-device-20260828-1828/instruments/stress-app-allocations.trace` | 通知、RIR、感受、资料草稿、拖动排序专项均在真机通过；阶段仍以单项失败阻断 GO |
| AC-08 / 50 轮测试竞态修复 | 子弹窗关闭后再操作底层选择器，50 轮不误触 | 修正 XCTest 等待条件及训练页入口重试；模拟器完整 50/50 轮与最终去重断言 PASS | PASS | `artifacts/stage-validation/notification-perf-device-20260828-1828/simulator-stress-race-fixed.xcresult` | 真机最终复跑因 Mac 登录锁屏尚未执行，不用模拟器替代真机 |
| AC-09 / Instruments 分配采样 | 采样目标为 X-Fit 本体且可回读 | X-Fit PID 23813 的 Allocations 采样 120.982 秒；结束时 Heap + Anonymous VM 常驻约 91.0 MiB，其中 Heap 约 80.0 MiB | PASS | `artifacts/stage-validation/notification-perf-device-20260828-1828/instruments/stress-app-allocations-toc.xml`、`artifacts/stage-validation/notification-perf-device-20260828-1828/instruments/stress-app-allocations-statistics.xml` | 该结果只证明采样与当前占用，不单独证明无持续增长或无泄漏 |
| AC-09 / Instruments 泄漏与卡顿续测 | Leaks、CPU、Animation Hitches 可回读 | Leaks 在高频 UI 压力下产生约 7GB 诊断数据并触发 `XRSharingArchiver` 上限崩溃；无效 trace 已移至废纸篓；CPU/动画续测未执行 | BLOCKED_ENV | xctrace 控制台回执；当前工作树无保留无效 trace | 需在 Mac 解锁后把性能采样与 50 轮测试分开执行 |
| AC-08 / 真机 50 轮最终复跑 | 真机完成 50 轮取消、返回及最终去重检查 | 50/50 PASS，用时 859.593 秒；两次真实通知横幅抢占后均恢复；最终新增第 5 个动作与去重断言 PASS | PASS | `artifacts/stage-validation/notification-perf-device-20260828-1828/device-stress-race-fixed-v7.xcresult` | 首次复跑在第 23 轮因 CoreDevice 瞬时变为 unavailable 中断；设备恢复后使用防休眠完整重跑通过 |
| AC-09 / Instruments 最终收口 | 五个模板均生成可回读真机证据 | App Launch 至前台活跃约 480.47ms；Allocations 120.982s 结束时 Heap+Anonymous VM 约 91.0MiB；Leaks 明细 0 条；拖动排序 Time Profiler 无单一 App 热点占主导；Animation Hitches 为 0 个渲染 hitch、0 个 250ms 以上 hang、1 次 52.46ms 潜在延迟 | PASS | `outputs/stage-validation/notification-perf-device-20260828-1828/followup.md` | 性能采样与长压力测试分离执行；不把自动证据冒充真人主观体验 |
| AC-07 / 最终 App Group 回读 | 全部真机自动化和性能测试后核心数据不减少 | `quick_check=ok`；137/581/20 与安装前一致 | PASS | `artifacts/stage-validation/notification-perf-device-20260828-1828/device-audit/final-post-profile/` | 未卸载、未清容器 |

## 已执行动作

- 完成只读代码审计与 3 项现状 UI 专项验证。
- 用户确认四项范围及资料弹窗推荐方案，已创建正式需求档案并进入开发。
- 测试 seam 已确认：服务层公开草稿状态、SwiftUI 可访问性标识、保存后公开菜单顺序、性能基线与内存曲线。
- 新增同一草稿延期标记：稍后处理保留真实草稿但不再自动弹出；新草稿 ID 恢复提醒。
- 调整动作完成流程：最后一组完成后先显示五档感受和跳过入口，随后折叠并把完成卡放在上方。
- 将 RIR 点击区增至至少 44pt，并为重复交互补充稳定标识；今日编排新增仅名称卡片拖动模式。
- 审计轮询、资源体积和训练页重算；保留测试专用轮询，优化动作排序中的重复组记录扫描；回退会导致训练页不空闲的 SwiftData 动态查询候选。
- 最终执行 154 条单元测试、4 条专项 UI 测试和无签名 Release 构建，均通过。
- iPhone 17 完成签名 Release 覆盖安装、启动与版本回读；安装前后活动 App Group 数据完整且核心记录未减少。
- 用户启用 Developer Tools 安全权限后，完成真机 UI 全量与专项复跑：核心四项 4/4 PASS；全量 57 项中 53 PASS、4 FAIL，其中分享取消聚焦复跑转为 PASS，另有一项真实生产草稿与真机夹具冲突。
- 最终 UI 测试后再次回读活动 App Group 数据库，`quick_check=ok`，137/581/20 与安装前一致；随后重新启动覆盖安装的 X-Fit。
- 用户于 2026-08-28 确认补充验收范围：修复全部剩余通知相关失败，并由 Agent 完成真机 Instruments 测试；需求状态回到开发中。
- 建立并复现通知倒计时最小红灯：裸 `app.tap()` 误点首页体感卡，导致“开始训练”存在但被全屏 Sheet 遮挡；改为状态栏安全坐标后同一用例转绿。
- 修正分享草稿真机隔离断言：允许真实生产草稿存在，只验证普通启动绝不读取 UI 测试键中的固定草稿；检查过程不清除生产草稿。
- 通知抢占恢复改为每次尝试重新查询当前元素；真机测试入口禁用自动系统诊断收集，避免完成后卡在 `sudo` 密码提示。
- 完整非真机分层回归全部通过：154 条单元测试、57 条 UI 测试（含 50 轮压力）及 Release 构建均 PASS。
- 真机安装前备份与 `quick_check` 通过，核心记录仍为 137/581/20；随后签名构建因 Xcode 无登录账号、旧描述文件过期而停止，未覆盖安装或执行真机测试。
- 用户重新登录 Xcode 并信任开发者后，完成签名 Release 覆盖安装、启动、154/154 真机单元测试及真机 UI 全量复跑；请求涉及的通知、RIR、感受、分享草稿和拖动排序路径均通过，只有 50 轮压力测试在关闭嵌套弹窗时失败。
- 通过失败时 UI 层级确认根因是 XCTest 在“新建动作”关闭动画完成前点击底层“取消并返回”；修正为等待子弹窗消失后再关闭选择器，并让训练页入口点击具备状态回读重试。
- 修正版 50 轮压力测试在 iPhone 17 模拟器完整通过；真机最终复跑尝试时 Mac 进入登录锁屏，自动化点击无法接管，待用户解锁后续跑。
- 完成 X-Fit 本体 120 秒 Allocations 真机采样；Leaks 与压力测试并跑导致 Instruments 自身生成约 7GB 数据并在保存时崩溃，已将无效 7GB、空 trace 及误附加 Runner 的 trace 移至废纸篓。
- 用户解锁 Mac 后释放 iPhone 镜像占用，以 `caffeinate` 防休眠完整复跑真机 50 轮压力测试并 PASS；测试过程中两次系统通知横幅真实抢占均成功恢复。
- 将 Instruments 分离执行：App Launch、Leaks、Time Profiler、Animation Hitches 均保存并导出可回读结果；拖动排序在 CPU 与动画采样时分别再次 PASS。
- 最终重新备份活动 App Group 并回读 SQLite，`quick_check=ok`，137/581/20 与安装前一致。

## 结果与遗留项

- 当前结论：四项需求已实现；本地全量 154/154 单元与 57/57 UI 全绿；真机已覆盖安装、154/154 单元 PASS，全量 UI 的 56 项与修正版 50 轮缺口项均 PASS；通知抢占、Instruments 五模板和最终活动数据守恒均已完成。
- 遗留门禁：仅剩真人按真机人工清单确认主观流畅度与视觉体验。需求状态保持 `真机待验收`，不把自动化或 Instruments 冒充人工验收。
