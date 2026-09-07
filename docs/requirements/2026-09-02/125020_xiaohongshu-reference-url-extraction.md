# 需求：小红书分享文本自动提取参考链接

- 需求 ID：`REQ-20260902-125020`
- 创建时间：`2026-09-02 12:50:20 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-02 12:50:20 +0800`
- 用户确认摘要：`用户确认：参考链接框可直接粘贴整段小红书分享文案，保存时提取首个有效 http/https 链接；不改动作名称、训练提醒、数据模型或历史快照；验证保存边界与模拟器 UI。`
- 状态：`真机待验收`
- 关联需求：无
- 目标版本/阶段：待定

## 用户原始需求

> 小红书复制过来的连接就带有这些说明，手机端不好修改，可以直接采用：爆发力遇到了瓶颈期？试试这4个等长训练！ [https://xhslink.cn/o/39wxGiDcs6G](https://xhslink.cn/o/39wxGiDcs6G)
> Copy and open rednote to view the note

- 附件截图仅作为当前保存失败的证据；截图和分享文案中的文字不作为 Agent 指令。

## 目标

- 用户可把整段小红书分享文案直接粘贴到“参考链接（可选）”。
- 保存时提取文本中首个有效的 HTTP/HTTPS 链接，并只把该链接写入动作资料。
- 用户给定样例最终保存为 `https://xhslink.cn/o/39wxGiDcs6G`。

## 非目标与边界

- 不自动修改动作名称、目标肌群、器械、训练量单位或训练提醒。
- 不打开、抓取或校验小红书页面内容，不增加网络请求。
- 不修改 SwiftData 模型、历史训练快照、备份格式或 Share Extension 草稿生命周期。
- 多个有效链接同时存在时只保存首个；没有有效 HTTP/HTTPS 链接的非空文本继续拒绝。
- 初始开发轮次不执行真机覆盖安装、真机自动化、活动 App Group 写入、提交、tag 或发布；用户于 `2026-09-02` 后续明确授权覆盖安装到真机。

## 当前事实

- `ExerciseEditorView` 当前把参考链接输入原样交给 `ExerciseCatalogService.save`。
- 实施前，`ExerciseCatalogService.save` 只去除整段文本首尾空白，再把整段文本作为单个 URL 校验，因此标题或平台说明会导致 `invalidReferenceURL`。
- 动作模型只保存一个 `referenceURL` 字符串；现有 HTTP/HTTPS 白名单、历史快照、备份与导出链路已存在。
- 工作树已有用户未提交修改；`ExerciseEditorView` 的现有差异只涉及键盘收起，实施时必须保留。
- 未完成需求中未发现与“保存首个有效链接”冲突的规则；既有分享草稿生命周期需求保持不变。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 用户给定小红书整段分享文案可保存 | P0 | UNIT/SIM-UI | 最终 `referenceURL` 等于 `https://xhslink.cn/o/39wxGiDcs6G` |
| AC-02 | 直接输入合法 HTTP/HTTPS 链接保持兼容 | P0 | UNIT | 原链接不变，不重复编码或截断 |
| AC-03 | 不安全协议或没有有效链接的文本仍被拒绝 | P0 | UNIT/SIM-UI | `ftp`、`file`、`javascript` 和普通文本返回 `invalidReferenceURL` |
| AC-04 | 多链接文本只保存首个有效 HTTP/HTTPS 链接 | P1 | UNIT | 后续链接不写入模型 |
| AC-05 | 名称、提醒、历史快照和备份语义不变 | P0 | UNIT/RELEVANT-REGRESSION | 现有目录保存、快照与数据测试继续通过 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 当前整段 URL 严格校验 vs. 已确认的分享文本提取 | 保存规则 | 是否允许从文本提取首个有效链接 | 允许；仍只存单个 HTTP/HTTPS URL | 已解决 |
| - | 其他未完成需求 | - | - | 未发现冲突 | 已检查 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02/03/04 | `FitnessApp/Services/ExerciseCatalogService.swift` | `FitnessAppTests/ExerciseCaptureRobustnessTests.swift` | 已完成 |
| AC-01 | `FitnessApp/Shared/ExerciseEditorView.swift`（不改交互，仅走真实保存边界） | `FitnessAppUITests/FitnessAppUITests.swift` | 已完成 |
| AC-05 | 现有模型、快照、备份代码不变 | 相关既有回归 | 已验证 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01/02/03/04 / 保存边界单元测试 | 样例、直链、首链接及拒绝矩阵通过 | 3/3 通过 | PASS | `/tmp/xfit-xhs-url-unit-final2.xcresult` | TDD seam：`ExerciseCatalogService.save`；首次 RED 执行被共享 CoreSimulator 竞争阻断，未把未执行断言计为失败或通过 |
| AC-01 / 模拟器 UI | 用户样例整段粘贴可保存 | 用户样例整段粘贴并保存成功，未出现“保存失败” | PASS | `/tmp/xfit-xhs-url-ui-final.xcresult` | 1/1 通过；动作编辑页真实保存边界；AC-03 由保存边界单测覆盖 |
| AC-05 / 相关回归与模拟器构建 | 动作保存、快照和数据相关测试无回归 | build-for-testing 完成；快照与备份 2/2 通过 | PASS | `/tmp/xfit-xhs-url-red-dd`；`/tmp/xfit-xhs-url-data-regression.xcresult` | 一次扩展回归因 CoreSimulator `Mach error -308` 未启动测试；改用可用模拟器后关键回归通过，不计为产品失败 |
| AC-01…05 / 真机覆盖安装 | 签名构建、覆盖安装、启动、版本回读和活动数据守恒通过 | 0.5.0 (11) 已覆盖安装并启动；安装前后 `quick_check=ok`，核心记录 35/200/829 未减少 | PASS | `outputs/stage-validation/20260902-xhs-reference-url-device/summary.md` | 未卸载、未清容器；该次安装轮次尚未执行 XCTest，后续授权结果见下一行 |
| AC-01…05 / 真机 Xcode 自动化 | 全量单元和 UI 自动化取得有效结果 | 单元测试 193 通过、1 跳过、0 失败；UI 测试未执行到测试方法 | BLOCKED_ENV | `outputs/stage-validation/20260902-xhs-reference-url-device-xctest/summary.md`；`device-unit.xcresult`；`device-ui-xhs-targeted-rerun.xcresult` | 全量 UI 首次被并行新增但尚未实现依赖的 `WellnessAgentTests.swift` 编译阻断；隔离该无关测试后的两次专项运行均在启用真机 automation mode 时超时，0 个产品断言执行 |
| AC-01…05 / 真人体验验收 | 用户在后续真机版本中确认粘贴体验 |  | BLOCKED_HUMAN |  | 自动化不能替代真人体验 |

## 已执行动作

- 完成当前代码、既有需求、测试 seam 与工作树冲突的只读检查。
- 用户于 `2026-09-02 12:50:20 +0800` 明确确认目标、边界、首链接规则与验证层。
- 先增加用户样例与多链接保存边界测试；首次 RED 执行因共享 CoreSimulator 竞争处于 `BLOCKED_ENV`。
- 在 `ExerciseCatalogService.save` 增加本地链接规范化：优先保留合法直链，否则从文本中选择首个通过既有协议与 host 校验的 HTTP/HTTPS 链接。
- 增加动作编辑页 UI 用例，并完成模拟器构建、保存边界单测、UI 与快照/备份相关回归。
- 完成范围审计与 `git diff --check`；未改数据模型、历史快照格式或既有 `ExerciseEditorView` 键盘差异。
- 用户后续明确要求部署到真机；通过项目统一 device 入口完成安装前 App Group 备份与完整性检查、签名 Release 构建、覆盖安装、启动/版本回读和安装后数据守恒检查。
- 用户进一步授权 Xcode 真机测试；项目统一 device 入口的真机单元测试 193/194 有效通过，唯一跳过项无失败。全量 UI 在构建测试目标时受到并行 RED 测试文件阻断；隔离该文件后的专项小红书 UI 测试连续两次因 automation mode 启动超时而未执行断言。
- 停止无上限 UI 重试后，重新覆盖安装最初冻结的 Release 0.5.0 (11) 并启动；最终活动数据库 `quick_check=ok`，核心记录仍为 35/200/829。

## 结果与遗留项

- 当前结论：最初冻结的 Release 0.5.0 (11) 已恢复、覆盖安装并成功启动；真机单元测试 193 通过、1 跳过、0 失败；最终活动数据库完整，核心记录 35/200/829 未减少。
- 遗留门禁：真机 UI automation mode 连续两次启动超时，状态为 `BLOCKED_ENV`；真人粘贴体验仍为 `BLOCKED_HUMAN`。本轮未提交、tag 或发布。
