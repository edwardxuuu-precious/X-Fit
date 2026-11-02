# 需求：真机覆盖安装与数据同步验收

- 需求 ID：`REQ-20260908-111711`
- 创建时间：`2026-09-08 11:17:11 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-08 11:17:11 +0800`
- 用户确认摘要：`用户明确同意将本地已验证的训练偏好与首周编排覆盖安装到已连接的 Edward_iPhone，并完成安装前后活动数据备份、数据守恒、版本回读与真机测试；禁止卸载或清空容器。`
- 状态：`真机待验收`
- 关联需求：`REQ-20260908-062544`（训练偏好与首周编排）、`REQ-20260906-100804`（四 Tab 全界面重构）
- 目标版本/阶段：0.5.0 (11) 真机覆盖安装与数据守恒

## 用户原始需求

用户确认：“好的，可以开始安装到手机然后完成数据同步。”目标设备为当前已连接、已解锁的 `Edward_iPhone`。

## 目标

- 将本地已验证的 0.5.0 (11) 候选包签名并覆盖安装到 `Edward_iPhone`。
- 安装前、安装后和真机测试后分别备份活动 App Group 数据，执行 SQLite 完整性与核心记录计数核对。
- 启动 App 并回读设备中的 bundle、版本和安装状态；运行真机单元与 UI 自动化。
- 保留现有 App、训练历史、日程、身体记录及 UUID；确认训练偏好和首周编排可进入手机运行时。

## 非目标与边界

- 禁止卸载 App、清空容器、删除活动数据库或用模拟器数据覆盖手机数据。
- 本轮不提交 Git、不打 tag、不发布 App Store/TestFlight。
- 自动化不能代替用户对页面观感、真实输入、系统权限和训练内容的人工验收。
- 若安装前活动数据库无法备份、SQLite 检查失败、核心表不完整或设备掉线，立即停止安装。

## 当前事实

- `Edward_iPhone`：CoreDevice ID `DC2912E0-36B3-5555-B66D-09C1A1DD12AD`，iPhone 17，iOS 26.6.1，wired、paired、booted，Developer Mode 与 DDI 可用。
- 当前候选版本为 0.5.0 (11)，bundle 为 `com.edward.FitnessApp`，Development Team 为 `664DT5VC99`。
- 本地统一 Run `20260908-training-preferences-final2` 的 N01–N07 全部 PASS；274 项单元测试、100 项 UI 测试与通用 iPhoneOS Release 构建已完成。
- 真机 UI 测试使用内存或独立 `XFitUITesting` 测试库；带 `--ui-testing-reset-store` 时只删除该测试库，不删除生产 SwiftData 存储。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 安装前数据备份与完整性 | P0 | DEVICE-DATA | App Group 数据可复制，SwiftData `.store` 存在且 `PRAGMA quick_check=ok`；核心三表完整 |
| AC-02 | 签名候选包 | P0 | DEVICE-AUTO | 真机 Release 构建、codesign、entitlements 与版本回读通过 |
| AC-03 | 覆盖安装与启动 | P0 | DEVICE-AUTO | 对指定设备执行 install app，不调用 uninstall/清容器；安装后可启动并回读 0.5.0 (11) |
| AC-04 | 安装后数据守恒 | P0 | DEVICE-DATA | 安装后再次备份、quick_check 通过，WorkoutSession/SessionExercise/SetLog 核心数量不减少 |
| AC-05 | 真机自动化 | P1 | DEVICE-AUTO | 真机全量单元与 UI 测试完成；失败项如实分层记录，不清理生产数据掩盖失败 |
| AC-06 | 测试后数据守恒 | P0 | DEVICE-DATA | 真机测试后第三次备份与完整性检查通过，安装前到测试后核心数量不减少 |
| AC-07 | 人工体验 | P1 | DEVICE-MANUAL | 用户检查启动、历史、训练偏好、本周编排和实际操作后确认 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | `REQ-20260908-062544` 的“本轮不覆盖安装”边界 vs 用户本次明确开始手机安装 | 是否可进入真机阶段 | 是否单独开启覆盖安装与同步验收 | 用户明确开启新的真机阶段；旧需求本地范围保持不变 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/04/06 | `scripts/xfit-stage-validation.sh device` 的 D01/D02、D06、D08 | SQLite quick_check、核心计数比较 | 待执行 |
| AC-02/03/05 | 同一统一脚本 D03–D07 | 签名、安装、版本回读、真机 XCTest | 待执行 |
| AC-07 | `docs/X-Fit_真机人工测试清单.md` | 用户实际操作 | 待执行 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01~07 / 本地基线 | N01–N07 全部通过 | `20260908-training-preferences-final2` 全部 PASS | PASS | `outputs/stage-validation/20260908-training-preferences-final2/summary.md` | 当前真机包来源基线 |
| AC-01 / 安装前数据 | 活动数据可备份且 SQLite 完整 | `quick_check=ok`；SessionExercise 203、SetLog 837、WorkoutSession 36 | PASS | `artifacts/stage-validation/20260908-training-preferences-device/device-audit/pre-install/` | 数据门通过后才继续安装 |
| AC-02/03 / 签名与安装 | 签名 Release 覆盖安装并回读版本 | 0.5.0 (11) 已安装并启动 | PASS | `artifacts/stage-validation/20260908-training-preferences-device/D03.log`～`D05.log`、`device-app-readback.json` | 未卸载、未清容器 |
| AC-04/06 / 活动数据 | 安装后、测试后及全部复跑后核心计数不减少 | 三个时间点均为 203 / 837 / 36，`quick_check=ok` | PASS | `device-audit/pre-install-to-post-install.txt`、`pre-install-to-post-tests.txt`、`pre-install-to-post-retries.txt` | 最终只读备份为 `post-retries` |
| AC-05 / 真机单元测试 | 全量单元测试完成 | 274 项中 272 通过、2 条按环境跳过、0 失败 | PASS | `device-unit.xcresult` | 设备 iOS 26.6.1 |
| AC-05 / 真机 UI 测试 | 全量 UI 路径执行，失败项复核 | 统一入口首次在 Runner 启用自动化模式时超时；复跑完整 100 项为 92 通过、7 跳过、1 个 5 秒时序断言失败；该失败用例原样单独复跑通过 | PASS | `device-ui.xcresult`、`device-ui-full-retry-1126.xcresult`、`device-ui-flake-retry-1201.xcresult` | 首次失败和复跑证据均保留，不把业务失败写成全量一次通过 |
| AC-01~06 / 训练数据同步 | 偏好和首周编排已进入手机活动数据库 | 偏好 `TP-20260908-01`、编排 `CUT-4D-20260908`；4 次力量、98 个抗阻组、3 组箱跳、2 次跳绳、1 次 Zone 2 | PASS | `device-audit/post-retries/training-sync-readback.txt` | 按产品规则仅同步编排版本，不静默创建训练日程；实际导入仍需预览确认 |
| AC-07 / 真人体验 | 用户实际查看与操作 | 待执行 | BLOCKED_HUMAN |  | 自动化后仍需本人验收 |

## 已执行动作

- 完成 Context Router 项目预检并读取当前项目真源。
- 核对目标设备、连接方式、系统版本、Developer Mode、DDI、候选版本和本地验证基线。
- 核对真机 UI 测试使用独立测试数据库，不以 `--ui-testing-reset-store` 删除生产 SwiftData。
- 使用统一 `device` 入口完成安装前备份、签名构建、覆盖安装、启动回读、真机单元测试和安装前/后/测试后数据守恒。
- 对 UI Runner 初始化超时执行诊断复跑；完整 100 项执行后，对唯一失败用例原样单独复跑并通过。
- 在全部复跑后再次只读备份活动 App Group，确认核心记录数量不减少，并回读训练偏好与首周编排版本。

## 结果与遗留项

- 当前结论：0.5.0 (11) 已覆盖安装到 `Edward_iPhone`；既有训练核心记录守恒，训练偏好与首周编排已进入手机活动数据库。
- 日程边界：本周编排可在 App 内查看；根据已确认的“先预览、再导入”规则，尚未静默创建本周四次力量日程。
- 遗留项：用户在手机上检查界面、历史、训练编排，并在预览无冲突后确认导入；真人体验完成前保持 `真机待验收`。
