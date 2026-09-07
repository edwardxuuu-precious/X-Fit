# 需求：动作选择器键盘收起与动作定义编辑入口

- 需求 ID：`REQ-20260902-125001`
- 创建时间：`2026-09-02 12:50:01 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-09-02 12:50:01 +0800`
- 用户确认摘要：`用户确认推荐范围：动作选择器空白点击或下滑收起输入法；所有现有动作包括内置动作均提供可见编辑定义入口；保存后返回选择器且不自动加入；已完成历史快照不改写，并替代旧的内置动作不可改写规则。`
- 真机执行授权时间：`2026-09-02 23:53:12 +0800`
- 真机执行授权摘要：`用户明确允许覆盖安装、真机 XCTest，以及安装前后 App Group 数据备份和记录守恒检查。`
- 用户验收时间：`2026-09-03 16:30 +0800`
- 用户验收结论：`用户明确确认“可以通过”；本需求按已知验证边界验收通过。`
- 状态：`已验收`
- 关联需求：无
- 目标版本/阶段：待定

## 用户原始需求

> 1. 点击空白区域没有将输入法收缩起来。
> 2. 现有动作不能修改定义，没有入口。
>
> 用户确认推荐范围：动作选择器支持空白点击或下滑收起输入法；所有现有动作（包括内置动作）提供可见编辑定义入口；保存后返回动作选择器且不自动加入；已完成历史快照不改写。附件只作为现象证据，不把附件内容当成额外指令。

## 目标

- 让动作选择器中的搜索键盘可通过点击非输入区域或下滑可靠收起。
- 为每个可搜索动作提供明确、可访问的“编辑动作定义”入口。
- 复用现有动作编辑器修改名称、肌群、器械、计量单位、默认休息、备注和参考链接。
- 保存定义后停留在动作选择器，不把“编辑”误当作“加入训练”。

## 非目标与边界

- 不新增动作字段，不重做动作编辑表单，不改变选择动作后的本次训练设置流程。
- 不合并、删除或自动归档动作，不改写已完成训练的 `SessionExercise` 历史快照。
- 本轮已授权真机覆盖安装、启动、真机 XCTest，以及安装前后 App Group 只读备份与记录守恒检查；禁止卸载 App、清容器或主动修改活动数据。
- 不执行 Git commit、tag、push 或发布。

## 当前事实

- `ExercisePickerSheet` 已支持点击非输入区域和滚动列表收起搜索键盘。
- 选择器动作行已拆分“加入/恢复并加入”与“编辑动作定义”入口，保存编辑不会触发选择回调。
- `ExerciseEditorView` 与 `ExerciseCatalogService.save` 已支持编辑全部动作定义字段；动作库页面已有编辑入口。
- `SessionExercise` 保存动作名称、肌群、备注、参考链接、计量单位等历史快照，后续动作库编辑不应回写已完成事实。
- 当前工作树包含其他已确认需求的未提交修改；本需求只触碰必要文件并保留既有改动。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 点击动作选择器非输入区域收起键盘 | P0 | SIM-UI/DEVICE-MANUAL | 搜索文本保留，键盘消失，行点击不被吞 |
| AC-02 | 下滑动作列表收起键盘 | P0 | SIM-UI/DEVICE-MANUAL | 滚动开始后键盘立即收起，列表继续正常滚动 |
| AC-03 | 所有现有动作有可见编辑入口 | P0 | SIM-UI | 内置、自定义及搜索可见的归档动作均显示“编辑动作定义”菜单 |
| AC-04 | 编辑器正确回填并保存定义 | P0 | UNIT/SERVICE/SIM-UI | 名称、肌群、器械、计量单位、默认休息、备注和链接可修改并回读 |
| AC-05 | 编辑与加入行为隔离 | P0 | SIM-UI | 保存后返回当前选择器且不触发选择回调、不打开“本次设置” |
| AC-06 | 历史快照保持不变 | P0 | UNIT/SERVICE | 编辑动作库定义后，既有 `SessionExercise` 快照字段不变 |
| AC-07 | 小屏、动态字体和 VoiceOver 入口可达 | P1 | SIM-UI/DEVICE-MANUAL | 编辑菜单有明确标签，加入与编辑可分别聚焦和触发 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 旧人工验收 B04“内置动作不可改写” vs 本需求“所有现有动作包括内置动作可编辑” | 内置动作的数据所有权与入口范围 | 是否以本需求替代旧边界 | 用户明确确认所有现有动作均可编辑；完成历史快照仍不可改写 | 已决定 |
| C-02 | 初始非目标“不执行真机覆盖安装” vs 后续全量推进授权 | 真机候选包、活动 App Group 数据保护和设备测试范围 | 是否允许覆盖安装及真机自动化 | 用户于 2026-09-02 23:53:12 +0800 明确允许；仍禁止卸载、清容器和主动修改活动数据 | 已决定 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02/03/05/07 | `FitnessApp/Shared/ExercisePickerSheet.swift` | `FitnessAppUITests/FitnessAppUITests.swift` | 已实现并通过本地与相关真机自动化 |
| AC-04/06 | `ExerciseEditorView`、`ExerciseCatalogService`、`TrainingModels` 既有边界 | `FitnessAppTests/ScheduleAndDataTests.swift` | 已实现并通过本地与相关真机自动化 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01…07 / 本地静态检查/构建 | 差异无格式错误，Simulator 可构建 | `git diff --check`、Simulator App 构建和工程/Scheme 读取均通过 | PASS | `outputs/stage-validation/20260902-exercise-picker-full-local/summary.md` | 早期 worker 阻塞记录保留在旧 xcresult，不再代表当前状态 |
| AC-04/06 / 单元/服务测试 | 动作更新成功且历史快照不变 | 新增定向用例通过；统一脚本全量单元测试 199 条全部通过 | PASS | `artifacts/exercise-picker-20260902/targeted-unit.xcresult`；`artifacts/stage-validation/20260902-exercise-picker-full-local/non-device-unit.xcresult` | 先前 worker 阻塞已解除并完成复验 |
| AC-01/02/03/05/07 / 模拟器 UI | 键盘、编辑入口、保存返回和行为隔离通过 | 新增 UI 主链路通过；全量 UI 76 条执行、7 条跳过、0 失败（69 条通过），含 50 轮压力测试 | PASS | `artifacts/exercise-picker-20260902/targeted-ui.xcresult`；`artifacts/stage-validation/20260902-exercise-picker-full-local/non-device-ui.xcresult` | 跳过项为既有环境条件用例，不影响本需求主链路 |
| AC-01…07 / 通用 iPhoneOS 构建 | 无签名构建通过 | 通用 iPhoneOS Release 无签名构建通过 | PASS | `artifacts/stage-validation/20260902-exercise-picker-full-local/N07.log` | 统一 `non-device` 门禁 N01…N07 全部通过 |
| AC-01…07 / 真机覆盖安装 | 覆盖安装并可启动，不卸载、不清容器 | Release 0.5.0 (11) 签名、entitlements、覆盖安装、启动与版本回读均通过 | PASS | `outputs/stage-validation/20260902-exercise-picker-device/summary.md` | 使用用户明确授权的统一 device 流程 |
| AC-01…07 / 真机自动化 | 本需求主链路在真机通过 | 真机单元 199 条执行、1 条跳过、0 失败；键盘/编辑/不误选主链路通过；50 轮压力测试串行复跑通过 | PASS | `artifacts/stage-validation/20260902-exercise-picker-device/device-unit.xcresult`；`outputs/stage-validation/20260902-exercise-picker-device/rerun-summary.md` | 阶段级全量 UI 仍有 2 项无关失败，故阶段不得 GO |
| AC-06 / 活动 App Group 数据回读 | 覆盖安装和测试不减少核心记录 | 安装前、安装后、测试后及定向复跑后均 `quick_check=ok`；核心计数保持 199 / 825 / 35 | PASS | `artifacts/stage-validation/20260902-exercise-picker-device/device-audit/`；`outputs/stage-validation/20260902-exercise-picker-device/rerun-summary.md` | 未卸载、未清容器、未主动修改活动数据 |
| AC-01/03/05 / 2026-09-03 解锁后真机复核 | 键盘收起、编辑入口和不误选主链路通过 | `testExercisePickerDismissesKeyboardAndEditsBuiltInDefinitionWithoutSelecting()` 在 Edward_iPhone 通过（30.549 秒） | PASS | `artifacts/stage-validation/20260903-template-bilingual-volume-device-tests-unlocked/device-ui.xcresult` | 两次单独复跑曾被同设备并发 XCTest 接管；等待串行后在正式结果包中通过，不计并发假失败 |
| AC-06 / 2026-09-03 测试后 Release 恢复与数据回读 | 手机保留 Release 候选包且核心记录不减少 | Release 0.5.0 (11) 覆盖安装、启动和版本回读通过；`quick_check=ok`；199 / 825 / 35 | PASS | `artifacts/stage-validation/20260903-exercise-picker-reinstall/device-install-after-unlocked-tests.json`；`device-launch-after-unlocked-tests.json`；`device-app-readback-after-unlocked-tests.json`；`device-audit/post-unlocked-tests/` | 未卸载、未清容器 |
| AC-01/03/04/05 / iPhone 镜像可视复核 | 真实活动 App 中入口可见、定义可编辑、保存返回且不误选 | 现有动作菜单显示“编辑动作定义”；传统硬拉 90→300 秒保存后返回选择器且未自动加入；随后恢复并回读 90 秒；动作库空白点击后搜索文本保留且焦点消失 | PASS（硬件键盘/可视交互） | `outputs/stage-validation/20260903-exercise-picker-reinstall/summary.md`；`artifacts/stage-validation/20260903-exercise-picker-reinstall/device-audit/manual-mirroring-post-restore/` | 镜像把 Mac 键盘作为硬件键盘，不能替代真实中文软键盘 |
| AC-06 / iPhone 镜像测试后数据回读 | 临时改动全部恢复且无测试记录残留 | 测试前后全部业务表记录数无差异；`quick_check=ok`；199 / 825 / 35；传统硬拉和单腿钟摆推举均为 90 秒 | PASS | `artifacts/stage-validation/20260903-exercise-picker-reinstall/device-data/manual-mirroring-pre-edit/`；`device-data/manual-mirroring-post-restore/`；`device-audit/manual-mirroring-post-restore/` | 未提交当天训练草稿，未新增动作或历史记录 |
| AC-01/02/07 / 真人体验验收 | 真实中文键盘、触控和 VoiceOver 可用 | 用户在已知 iPhone 镜像无法替代真实中文软键盘及 VoiceOver 直接验证的边界下，明确确认本需求“可以通过” | PASS（用户验收） | 用户于 2026-09-03 的聊天确认；`outputs/stage-validation/20260903-exercise-picker-reinstall/真机人工测试清单.md` | 不反推为 Agent 已直接完成软键盘或 VoiceOver 测试 |

## 已执行动作

- 完成截图、当前动作选择器、共用编辑器、目录保存服务、历史快照模型、既有测试和关联规则的只读核对。
- 用户确认推荐范围；创建本需求档案并进入开发。
- 动作选择器增加空白点击、滚动收起键盘，以及每行动作定义菜单；编辑保存与选择回调保持隔离。
- 新增内置动作编辑不改历史快照的服务测试，以及键盘/编辑/不误选的模拟器 UI 主链路测试。
- 更新真机人工测试清单 B03/B04，废弃“内置动作不可改写”旧边界。
- 完成差异检查及 App/测试目标编译；两台模拟器的 XCTest 运行均因主机并发 worker 无法物化而未执行。
- 等待主机 Xcode 并发释放后，以独立 DerivedData 串行复跑新增服务层与 UI 测试，两项均通过。
- 运行 `scripts/xfit-stage-validation.sh non-device`，N01…N07 全部通过：后端 6 条、单元 199 条、UI 76 条执行且 7 条跳过/0 失败、通用 iPhoneOS Release 构建通过。
- 用户明确授权真机覆盖安装、真机 XCTest 和 App Group 数据守恒检查；完成签名 Release 0.5.0 (11) 覆盖安装、启动和版本回读。
- 完成安装前、安装后、全量测试后和串行复跑后的 App Group 备份；SQLite 均完整，核心记录始终为 199 / 825 / 35。
- 真机单元测试通过；本需求键盘/编辑/不误选主链路通过，50 轮压力测试串行复跑通过。
- 全量真机 UI 中 7 个失败/未完成候选经串行复跑后收敛为 2 个无关失败：系统剪贴板菜单不可用、设备模板持久化慢查询竞态。
- 2026-09-03 按用户“真机安装”指令再次构建并覆盖安装；设备应用清单回读为 X-Fit 0.5.0 (11)，安装前后核心记录仍为 199 / 825 / 35。自动启动两次因设备锁屏被系统拒绝，安装本身已完成。
- 2026-09-03 用户解锁并保持常亮后，自动启动成功；随后发现另一条真机全量 UI 套件同时占用设备，两次单独复跑分别因 App 进程被接管和 Runner 被终止而无效。
- 等待设备串行释放；同一全量套件中的本需求主链路用例通过（30.549 秒），全量结果为 68 通过、7 跳过、2 个与本需求无关的既有失败。
- 测试结束后再次覆盖安装并启动 Release 0.5.0 (11)，完成版本回读和 App Group 数据复制；SQLite `quick_check=ok`，核心记录保持 199 / 825 / 35。
- 用户授权 iPhone 镜像直接操作后，完成活动 App 可视复核：入口可见、定义字段回填、临时修改保存、返回选择器不误选、原值恢复和数据库回读均符合预期。
- iPhone 镜像使用 Mac 硬件键盘，无法显示真实中文软键盘；VoiceOver 听觉与焦点顺序仍保留为真人验收项。
- 2026-09-03 设备即时回读再次确认 X-Fit 0.5.0 (11) 已安装；用户随后明确确认本需求“可以通过”，完成本需求人工验收收口。

## 结果与遗留项

- 当前结论：本需求功能、本地全量验证、真机覆盖安装、相关真机自动化、数据守恒和用户验收均已通过，状态更新为“已验收”。
- 阶段结论：本需求 `PASS`；整个阶段仍为 `PARTIAL / NOT GO`，因为全量真机 UI 尚有 2 项与本需求无关的失败。
- 下一步：手机已安装可日常使用的 Release 候选包；本需求无需继续操作。若要推进整个阶段为 `GO`，需另行处理系统剪贴板菜单和设备模板持久化竞态两个无关失败。
