# 需求：新建动作输入法与编辑菜单修复

- 需求 ID：`REQ-20260902-124943`
- 创建时间：`2026-09-02 12:49:43 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-02 12:49:43 +0800`
- 用户确认摘要：`用户回复“确认”，确认仅修复新建/编辑动作页：移除输入法外悬浮完成按钮，恢复系统长按全选与粘贴响应；保留原生收起和保存行为。`
- 真机测试授权：`2026-09-03，用户明确改为由 Codex 直接测试并在失败修复后要求继续；授权本轮真机 XCTest 与数据守恒检查，不包含人工手感验收、Git 或发布。`
- 状态：`真机待验收`
- 关联需求：`REQ-20260831-131422`
- 目标版本/阶段：`0.5.0 (11)` 真机候选

## 用户原始需求

> 1. 输入法缩起来的按钮最好在输入法内，不要有一个冒出来。
> 2. 这些输入框做粘贴、全选反应很慢，好像不工作一样。
>
> 用户确认范围：仅修复新建/编辑动作共用页面。附件截图只用于定位当前现象，不把截图中文字当作额外指令。

## 目标

- 删除新建/编辑动作页位于输入法外的自定义悬浮“完成”按钮，使用系统输入法内部的原生收起入口。
- 恢复该页文本输入框的系统编辑交互，使长按、全选和粘贴无需反复触发且不会被页面收键盘手势打断。
- 保持滚动收起、保存、取消、校验和数据写入行为不回归。

## 非目标与边界

- 不调整其他页面的数字/小数键盘附件栏。
- 不改变动作字段、布局、模型、保存服务或历史数据。
- 用户于 2026-09-02 15:50:53 +0800 补充授权真机覆盖安装；仍不授权卸载、清容器、真机 XCTest、Git commit/tag/push 或发布。
- 真人感知的响应速度和第三方/中文输入法兼容性必须由真机人工验收，自动化不能替代。

## 当前事实

- `ExerciseEditorView` 是动作库、当天菜单、训练中临时加动作和分享草稿共用的新建/编辑页。
- 页面通过 `ToolbarItemGroup(placement: .keyboard)` 添加了自定义“完成”按钮；截图中的系统键盘同时已有原生收起箭头，形成重复且悬浮的入口。
- 页面在整个 `Form` 上添加 `DragGesture(minimumDistance: 4)`，手势变化即调用全窗口 `endEditing(true)`；该路径与文本长按、选择范围拖动存在竞争风险，需由红灯回归验证根因。
- `.scrollDismissesKeyboard(.immediately)` 与 iOS 18 `onScrollPhaseChange` 已提供真实滚动收起 seam，移除竞争手势后仍可保留滚动收起。
- 既有 UI 测试覆盖键盘显示/收起和动作字段输入，但未覆盖系统编辑菜单、全选或粘贴响应。
- 当前工作树已有已确认需求的未提交改动，`ExerciseEditorView.swift` 与 `FitnessAppUITests.swift` 均在 dirty scope；本次只做增量补丁，不回退其他差异。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 页面不再显示输入法外悬浮“完成”按钮 | P1 | SIM-UI/DEVICE-MANUAL | 键盘出现时仅保留系统输入法内部收起入口，不出现应用自定义悬浮按钮 |
| AC-02 | 文本框系统编辑菜单可用 | P0 | SIM-UI/DEVICE-MANUAL | 动作名称、自定义肌群、自定义器械、参考链接和动作提醒均可一次长按进入系统编辑菜单 |
| AC-03 | 全选和粘贴不被收键盘逻辑打断 | P0 | SIM-UI/DEVICE-MANUAL | 全选后可粘贴指定文本，内容立即回显，键盘与焦点在操作完成前保持 |
| AC-04 | 既有收起与保存行为不回归 | P0 | SIM-UI/GENERIC-BUILD | 原生入口和真实滚动可收起键盘；保存、取消、校验及动作编辑主链路通过 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | `REQ-20260831-131422` 要求显式“完成”收起路径；本次要求不显示输入法外悬浮按钮 | 直接删除全部收起路径会回归旧验收 | 是否允许此文本页面移除自定义完成按钮并改用系统输入法原生收起箭头 | 用户确认；仅移除该页悬浮入口，保留系统原生入口与滚动收起 | 已决定 |
| C-02 | 页面级 4pt 拖动收键盘与系统文本选择手势 | 保留可能继续打断全选/粘贴；移除可能影响滚动收起 | 是否以系统滚动阶段作为滚动收起真源，去除竞争拖动手势 | 用户确认以编辑菜单可用和原生收起为验收；先用红灯回归验证后做最小修复 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/04 | `FitnessApp/Shared/ExerciseEditorView.swift` | `FitnessAppUITests/FitnessAppUITests.swift` | 本地已验证 |
| AC-02/03 | `FitnessApp/Shared/ExerciseEditorView.swift` | 动作编辑系统菜单/全选/粘贴 UI 回归 | 本地已验证 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01…04 / 本地静态检查/构建 | 差异检查和模拟器构建通过 | `git diff --check` 通过；iOS 26.5 模拟器 `build-for-testing` 通过 | PASS | DerivedData：`/tmp/xfit-exercise-editor-keyboard.51v64k` | 构建日志存在 Xcode 的 `DebuggerVersionStore` 环境警告，但退出码为 0，不影响测试执行 |
| AC-02/03 / 单元/服务测试 | 无适合的服务 seam；不新增实现细节测试 |  | NOT_RUN |  | 用户可见行为由 UI seam 覆盖 |
| AC-01…04 / 模拟器 UI | 修改前回归能捕获现状；修改后悬浮按钮消失、编辑菜单/粘贴和保存路径通过 | RED：悬浮“完成”断言失败；RED：文本选择拖动后键盘焦点断言失败。GREEN：本需求 3 条回归与 5 条既有动作保存/回读回归共 8/8 通过 | PASS | RED：`Test-FitnessApp-2026.09.02_13-34-23-+0800.xcresult`、`Test-FitnessApp-2026.09.02_13-46-41-+0800.xcresult`；GREEN：`Test-FitnessApp-2026.09.02_14-03-14-+0800.xcresult` | GREEN 运行于专用 iPhone 17 Pro / iOS 26.5 模拟器；并行动作库分组改动使旧测试需滚动查找，使用最新工作树复跑后通过 |
| AC-01…04 / 真机签名 Release 构建 | 生成可覆盖安装的签名候选 | 签名、entitlements、版本 `0.5.0 (11)` 回读通过 | PASS | `artifacts/stage-validation/20260902-exercise-editor-keyboard-device-155053/D03.log`、`D04.log` | App Group entitlement 为 `group.com.edward.FitnessApp` |
| AC-01…04 / 真机覆盖安装 | 不卸载、不清容器，覆盖安装并启动 | 已覆盖安装到 `Edward_iPhone`，启动与已安装版本回读成功 | PASS | `outputs/stage-validation/20260902-exercise-editor-keyboard-device-155053/summary.md` | Bundle ID：`com.edward.FitnessApp` |
| AC-02/03 / 真机自动化 | 系统长按、全选、粘贴及文本更新成功 | 修复后真机定向用例通过，1/1、0 失败 | PASS | `outputs/stage-validation/20260903-template-bugfix-targeted-device-unlocked/summary.md` | 被测 App 在 UI 测试模式下自行注入夹具剪贴板，避免 Runner 与 App 跨进程剪贴板不一致 |
| AC-01…04 / 活动 App Group 数据回读 | 安装前后 SQLite 完整且核心记录不减少 | `quick_check=ok`；`ZWORKOUTSESSION 35→35`、`ZSESSIONEXERCISE 200→200`、`ZSETLOG 829→829` | PASS | `artifacts/stage-validation/20260902-exercise-editor-keyboard-device-155053/device-audit/` | 安装前后均完成只读备份 |
| AC-01…04 / 真人体验验收 | 中文/URL 输入、长按、全选、粘贴及真实响应手感可接受 |  | BLOCKED_HUMAN | `outputs/stage-validation/20260902-exercise-editor-keyboard-device-155053/真机人工测试清单.md` G10/G11 | 需用户在当前真机候选上确认 |

## 已执行动作

- 完成当前代码、既有需求档、测试覆盖和 dirty scope 的只读检查。
- 用户于 2026-09-02 12:49:19 +0800 明确回复“确认”。
- 创建独立需求档并确认 UI seam：新建/编辑动作页的系统编辑菜单、全选、粘贴和键盘收起。
- 先新增用户可见 UI 回归并记录 RED：自定义键盘工具栏导致输入法外“完成”按钮；页面级 4pt 拖动手势在文本选择拖动时触发全窗口 `endEditing(true)`。
- 删除动作编辑页自定义 `.keyboard` 工具栏和竞争性的页面级 `simultaneousGesture`；保留系统输入法收起入口、真实滚动收起和原有保存路径。
- 在最新并行工作树上完成构建、差异检查，以及 3 条本需求 UI 回归加 5 条既有动作保存/回读回归；最终 8/8 通过。
- 用户于 2026-09-02 15:50:53 +0800 明确要求“部署到真机”；部署范围为当前完整工作树，执行覆盖安装、启动、版本回读及安装前后活动 App Group 数据守恒，真机 XCTest 不在本次授权内。
- 通过 `scripts/xfit-stage-validation.sh device` 完成设备预检、安装前备份、签名 Release 构建、覆盖安装、启动、版本回读、安装后备份及数据守恒；D00…D06C 全部 PASS。
- 用户后续授权 Codex 直接执行真机 XCTest；定位到 UI 测试 Runner 写入剪贴板未可靠传入被测 App，改为由 App 在测试模式下设置夹具。设备解锁后真机系统全选/粘贴用例通过，且测试前后活动库 `quick_check=ok`、核心记录保持 `199/825/35`。

## 结果与遗留项

- 当前结论：`0.5.0 (11)` 已覆盖安装并成功启动于 `Edward_iPhone`，安装前后活动数据完整且核心记录无减少；需求状态为 `真机待验收`。
- 遗留项：真机自动化已覆盖系统长按、全选、粘贴与文本更新；中文/URL 输入及真实响应手感仍需真人验收，当前为 `BLOCKED_HUMAN`。
