# Notes 历史训练导入保留来源日期与未知开始时间

- 需求 ID：`REQ-20261013-090344`
- 创建时间：`2026-10-13 09:03:44 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-10-13 +0800`
- 用户确认摘要：`确认按原名与未知字段补录 2026-10-12 Apple Notes 训练。`
- 状态：`真机待验收`
- 关联需求：`docs/requirements/2026-10-10/160518_confirmed-training-import.md`
- 目标版本/阶段：当前 X-Fit 数据正确性修复

## 用户原始需求

> 训练反馈我如果有记录就都记录了；可以查看本地 Notes 的训练计划和体重数据进行补充；请继续推进。
>
> 对 10/12 训练的确认：`按原名与未知字段补录`。

## 目标

- 将 Notes 的 10/12 训练保存在 App，动作原名、重量、次数、未知侧别/RIR/时长均如实呈现。
- 对仅有日期的历史训练，保存来源当地日期及时区；没有具体开始时间时不把午夜默认值伪装为已知时间。
- 对同一确认包重试，仅补足缺失的来源日期/时间已知性元数据；不新增重复训练、不覆盖已由本人编辑的时间/组次，也不改变计划日程。
- 导入回执应报告训练/动作/组数量，避免仅显示体重和餐食的误导信息。

## 非目标与边界

- 不改写 Notes，不猜动作身份、肌群/器械、RIR、训练时长或实际开始时间。
- 初始确认中暂不更改 10/12 已计划的胸三头和跳绳状态；该边界已被用户在后续明确补充的决定取代：两项均未完成，应以 Notes 中实际完成的腿部训练为准。仅可通过 App 支持的操作将这两项记为跳过，不直接改数据库。
- 不直接修改 App Group SQLite；通过 App 自有导入通道修复与回读。
- 本次不改变自重动作采用最近历史体重快照的既有算法；若显示该值，明确其来源日期，不能称为当日称重。

## 当前事实

- Notes「Oct 12」包含 9 个动作、28 组；开始时间、时长、RIR及多个动作分类/侧别未知。
- 已批准包通过 App 导入：1 场、9 个动作、28 组；同日原排期仍 planned。
- 发现导入器未冻结 `trainingLocalDay` / `trainingTimeZoneIdentifier`，且把日期型训练的午夜默认标作已知开始时间。
- 自重动作记录显示 87.4 kg，来源是最近一次先前测量（2026-09-23），不是 10/12 当日测量。
- 日期/时区修复已通过同一批准包的幂等重试写回 App：新增训练/动作/组均为 0，修复日期元数据 1 条，跳过重复训练 1 场；设备活动数据库回读同一 session UUID、9 动作、28 组、`2026-10-12`、`Asia/Shanghai`、`isStartTimeKnown=false`。10/12胸三头和跳绳排期仍为 `planned`。
- 用户最新确认：10/12 未完成胸三头和跳绳；应按 Notes 的实际训练记录反映状态。此决定取代本需求最初“不更改排期状态”的边界。随后通过 iPhone 镜像在 App 排期菜单中分别选择“跳过训练”，返回首页回读两项均显示“已跳过”；跳过原因留空，避免把对话解释写成用户在 App 中填写的原因。
- 真机覆盖安装、活动数据备份与 SQLite `quick_check`、真机全量单测均通过；真机全量 UI runner 两次均在用例启动前因 XCTest DTX 通道断开退出 code 74，未执行 UI 场景。安装前/测试后核心表计数及 UUID 未减少。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 日期型 Notes 导入写入当地日期/来源时区并保持未知开始时间 | P0 | UNIT/SERVICE/DEVICE-DATA | `2026-10-12`、`Asia/Shanghai`、开始时间未知；绝对日期不随设备时区切换 |
| AC-02 | 对已导入且仅缺来源元数据的同包重试 | P0 | UNIT/SERVICE/DEVICE-DATA | 同一 session ID；新增 session/action/set 为 0；元数据修复；已编辑的非午夜时间、组次及排期不被覆盖 |
| AC-03 | App 写入与数据回读 | P0 | DEVICE-DATA | 1 场、9 动作、28 组；原名/数值/unknown side 一致；胸三头与跳绳按用户确认记为 skipped；其他核心数据不减少 |
| AC-04 | 体重快照来源说明 | P1 | SERVICE/DEVICE-DATA | 87.4 kg 明确为最近已记录快照（9/23），不显示为 10/12 新测体重 |
| AC-05 | 导入回执内容完整 | P1 | UNIT/DEVICE-DATA | 回执含训练、动作、组新增/跳过计数 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| - | 未发现；开始时间未知按用户确认的未知字段边界处理 | 不推断午夜为训练开始时间 | - | 保留未知 | 已决定 |
| D-02 | 原确认“不更改10/12已计划胸三头与跳绳” vs 用户最新确认“两项未完成，应按照 Notes 实际训练记录” | 将两项排期从 planned 改为 skipped；保留 Notes 已导入的腿部训练事实，不把不同训练互相冒充 | 是否由 Notes 判定当天两项排期未完成 | 用户确认：没有完成，应按 Notes 记录；此项明确取代原来的排期状态不变边界 | 已决定并已回读 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| AC-01/02 | `FitnessApp/Services/HistoricalWorkoutService.swift` | 日期型新增、同包修复、保留本人编辑时间 3 项通过；全量单元重跑 392/392 通过 | PASS |
| AC-03 | Notes 包经 App 导入；排期跳过使用 App 内置操作 | 1场/9动作/28组、原名与侧别未知、同一 session ID；胸三头与跳绳分别通过“跳过训练”更新，返回首页均显示“已跳过” | PASS |
| AC-04 | `SessionExercise.bodyWeightSnapshotSourceDate`；训练/历史补录、备份/设备合并与训练/详情页来源说明 | 来源日期解析/备份回环本地PASS；Build18手机10/12详情实际显示9/23来源，旧数据守恒 | PASS；本地＋具名手机来源标签 |
| AC-05 | `FitnessApp/Services/MealExchangeService.swift` | 回执显示训练/动作/组计数和元数据修复计数；真机回执为0/0/0、修复1、跳过1 | PASS |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01/02 / 单元/服务测试 | 新导入及同包修复通过，编辑过的时间不覆盖 | 3项针对性测试通过；全量 392/392 通过。初次全量一次数据库锁失败，孤立复测及关闭诊断的全量重跑均通过 | PASS | `artifacts/stage-validation/notes-oct12-date-fix-20261013/unit-full-retry.xcresult` | 首次完整日志仍保留为一次失败证据 |
| AC-03 / 真机覆盖安装与 App 导入回读 | 准确 1/9/28，核心数据守恒 | 已覆盖安装；原 session 同 ID，9动作/28组，日期/时区/未知时间正确；未新增训练数据；所有核心表ID守恒 | PASS | `artifacts/stage-validation/notes-oct12-date-repair-20261013/` | 不卸载/清容器 |
| AC-03 / App 排期回读 | 两项未完成排期显示 skipped | iPhone 镜像中分别将 10/12 胸三头与轻松跳绳 1 设为“跳过训练”；返回首页，两项均显示“已跳过” | PASS | 本轮 iPhone Mirroring：训练日程页及首页 10/12 周安排 | 使用 App 正常操作；跳过原因留空；Notes 腿训未改 |
| AC-04 / 自重快照来源 | 9/23快照不作为10/12称重；新训练及备份保留来源日期；未知来源明确显示未知 | 解析器、备份回环与设备合并具名断言已在Simulator通过；首次暴露测试夹具语义不一致，仅修夹具后单项1/1通过。真机页面待集中验收 | LOCAL PASS / DEVICE PENDING | `/Users/edward/Library/Developer/Xcode/DerivedData/FitnessApp-cwwdxuvonmiqolecnxsvaxhqwiww/Logs/Test/Test-FitnessApp-2026.10.13_12-26-34-+0800.xcresult`；首次夹具失败：同目录 `Test-FitnessApp-2026.10.13_12-23-35-+0800.xcresult` | 旧记录仅在本地测量值精确匹配且日期不晚于训练时显示来源；否则显示“来源日期未知”。未创建10/12称重记录 |
| AC-05 / 导入回执 | 回执含训练、动作、组和重复/修复计数 | 显示0训练/0动作/0组、修复1、跳过1 | PASS | `artifacts/stage-validation/notes-oct12-date-repair-20261013/notes-repair/result/receipt.json` | 回执为 App 实际完成回执 |
| 真机 UI 自动化 | 真机 UI 测试套件启动并完成 | 两次均在首个用例开始前 XCTest runner code 74 / DTX 通道拒绝，0个 UI 场景 | FAIL_ENV | `artifacts/stage-validation/notes-oct12-date-repair-20261013/device-ui.xcresult` | 未继续相同条件重试；不将数据回读或模拟器测试冒充真机 UI 通过 |
| 后续统一真机复验 / UI 自动化 | Xcode 项目已打开、工具栏目标为 Edward_iPhone 后执行完整 device 入口 | D07B 仍在首个 UI 场景前 runner exit 74，0 场景；D00–D06C、D07A（392项：387 PASS/5既有SKIP/0 FAIL）、D07C–D08C PASS | FAIL_ENV（UI）/ PASS（其余设备门） | `outputs/stage-validation/goal-xcode-selected-destination-device-20261013/summary.md` | 当前停止相同条件重试；上游 DTX/IDE XCTest 根因 unknown |

## 已执行动作

- 已通过用户确认包完成原始训练首次导入，并通过相同包的幂等重试只修复日期元数据；手机未卸载/清容器。
- 已执行 unified non-device 与 device 阶段；补充全量单元复跑 392/392 PASS，真机全量单测 PASS；真机全量 UI XCTest 启动前 DTX 断连两次，停止无新证据重试。
- 后续只读展开两份 `.xcresult` 的 test details、activity tree 与诊断附件：两次均先成功连接无线 CoreDevice/testmanagerd、安装并启动 UI Runner；Runner 报告 `Running tests...` 后约 30.09 秒收到 DTX channel refusal，IDE disconnection / launch session expired，实际 UI 用例均为 0。未发现 App 测试断言执行或 runner 崩溃证据；精确上游根因仍未知。见 `artifacts/stage-validation/notes-oct12-date-repair-20261013/dtx-runner-diagnostics.json`。这只是对现有失败的诊断，不是第三次重试或故障修复。
- 用户锁屏后，iPhone 镜像恢复连接；按最新确认通过 App 将 10/12 胸三头与轻松跳绳 1 标为“已跳过”，返回首页回读一致，Notes 腿部训练记录保持不变。随后完整 device 入口在 Xcode 项目已打开、真实设备已选中的新条件下复验：D00–D06C、D07A 392 项（387 PASS/5既有SKIP/0 FAIL）、D07C–D08C PASS；D07B仍在首个UI场景前 exit74，0场景。原摘要：`outputs/stage-validation/goal-xcode-selected-destination-device-20261013/summary.md`。
- AC-04 定向测试先以缺少来源日期解析 API 的编译错误确认 RED；实现可选来源日期快照、历史补录/备份/设备合并携带，并在训练输入与详情页标注。`ScheduleAndDataTests` 114 项通过（含来源日期解析与备份往返）。后来追加的设备合并来源日期断言已通过 `build-for-testing`，但对应测试运行在模拟器启动阶段停滞且没有用例结果，停止该次运行；该断言尚未算运行通过。来源标签的真机体验留待集中真机验证；本轮未写手机数据库。

### AC-04 补充验证（更新此前“设备合并断言未实跑”状态）

- 首次具名模拟器执行失败在测试夹具：`杠铃卧推`使用bodyweight计量单位，先于来源日期断言触发合并器语义匹配拒绝。该失败不是生产代码行为证据。
- 只修正夹具为“负重俯卧撑/胸部/自重/bodyweight”，未修改生产合并逻辑；同一具名测试 `testDeviceHistoryMergePreservesAllSetStatesAndIsIdempotent` 随后在 iPhone 18 Pro / iOS 27.0 Simulator 通过，1项、0失败。通过xcresult：`/Users/edward/Library/Developer/Xcode/DerivedData/FitnessApp-cwwdxuvonmiqolecnxsvaxhqwiww/Logs/Test/Test-FitnessApp-2026.10.13_12-26-34-+0800.xcresult`；首次失败保留：同目录 `Test-FitnessApp-2026.10.13_12-23-35-+0800.xcresult`。
- 因而AC-04的本地设备合并断言现为PASS；真机页面来源标签和全量UI仍待集中验收。本补验未写手机数据库。

## 结果与遗留项

- 最新AC-04手机出口已完成：普通Build18的10/12“靠墙胫骨前肌提拉”实际显示“自重体重快照 · 来源测量 Sep 23, 2026”、87.4 kg×10，日期不是10/12。活动副本对应9/23 08:03测量；旧记录经精确值匹配的兼容来源路径显示，未回填可选字段或新建称重。本次只读前后24表旧ID/公共业务字段完全一致、新增0、SQLite ok。证据：[同批续做回读](../../../artifacts/stage-validation/four-pack-final-wireless-20261013-01/continuation-readback-02.json)。下文“来源标签未验”为前序快照；剩余完整真机UI门独立保留，不能将本项PASS当全套通过。

- 当前Build18已经统一完整本地验证并无线覆盖上手机，普通Release版本0.5.0(18)、活动schema新增`ZBODYWEIGHTSNAPSHOTSOURCEDATE`；最终24张业务表所有旧ID/公共字段未变、新增0、SQLite ok。手机界面可见10/12原名9动作28组和时长未知。AC-04具体已知体重来源日期标签仍未完成真机可见验收，不把字段上线当标签通过。当前证据：[无线批次摘要](../../../outputs/stage-validation/four-pack-final-wireless-20261013-01/summary.md)及同Run final-business-conservation.json；前序Build17无字段的readback保留历史。设备合并断言以本文件“AC-04补充验证”的PASS为准，不沿用旧尚未实跑。

- 当前结论：10/12原训练日期/时区与未知开始时间保留，胸三头/跳绳skipped、Notes事实不变。AC-04已取得完整本地PASS及Build18手机schema交付；本批原生真机单元388 PASS/5原SKIP/0 FAIL。真正IDE UI探针仍在首场景前Lost pending connection，0场景/根因unknown，已恢复普通App；对应原失败不取消。
- 未收敛项：AC-04具体来源标签真机验收与完整真机UI运行器故障。Notion在线T3已经由REQ-20261013-131921独立交付，但不据此关闭本需求或其他手机/餐食门。
- 解除条件：获取新的、可定位上游 IDE/testmanager/DTX/Runner 根因证据或 Xcode/CoreDevice 运行时版本变化后，再评估一次受控真机 UI 尝试；不因解锁、项目打开或目标已选中而重复相同测试。AC-04另走其已确认来源说明验收，不改本次训练事实。
