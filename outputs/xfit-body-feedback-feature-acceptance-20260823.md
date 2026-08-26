# X-Fit 今日体感与动作 Emoji 专项验收（2026-08-23）

## 0. 最终结论

**验收结论：FAIL，阻断发布。**

阻断项为 `N-MAP-03 / P1`：正面人体图 7 对、共 14 个左右区域的解剖学语义反转。点击“右肩”等 `front-right-*` 控件时，红色标记落在面对观察者的人体左侧；背面映射正常。

除此之外，今日体感模型/保存、红区与红点共存、五档 Emoji、重启持久化、历史回看和普通模式 App Group 活动库 schema/既有数据回读均通过现有自动化证据。当前专项真机重跑因 Mac 锁屏后设备双通道离线而中断，测试后 App Group 回读标 `BLOCKED_ENV`；不把中断任务或遗留非活动数据库冒充 PASS。

本轮是验收，不修改业务源码。相机、器械识别、云端识别、通知、导出 UI 和其他训练能力均排除，不影响本结论。

## 1. 冻结范围

### 纳入

1. 今日体感 1–5 分、不适备注、同日保存/修改/取消。
2. 正面/背面完整人体图 34 个区域；肌肉/部位为红色区域，关节/筋膜为红点；文字列表与可访问性语义。
3. 动作完成后出现且仅出现 5 个 Emoji：`😣 / 😥 / 😮 / 🙂 / 😄`，对应“不适/疼痛 / 太难 / 有挑战 / 正合适 / 轻松顺畅”。
4. 单选、重启持久化、历史回看、备份兼容、坏数据关闭、活动数据库 schema 与历史数据守恒。

### 排除

- 相机权限、器械识别、云端识别服务。
- 组间通知、系统通知投递。
- 导出 UI、训练计划、术语审核及其他无关训练能力。

## 2. 证据分层结果

| 层 | 状态 | 结果与证据 |
|---|---|---|
| 静态/模型审计 | `FAIL` | 34 区域为 17 正面 + 17 背面、ID 唯一、命中目标最小 44pt、红区/红点/文字与 VoiceOver 语义均存在；但正面 7 对区域左右坐标语义反转，见第 3 节。 |
| NDS 单元 + Simulator UI | `PASS`（但不能覆盖视觉失败） | 17 项 × 连续 3 轮 = 51 次，0 失败、0 跳过、0 自动重试。3 个主结果包：`/tmp/xfit-dd-20260823/Logs/Test/Test-FitnessApp-2026.08.23_13-56-53-+0800.xcresult`、`13-58-40`、`13-59-46`。每轮原始 16 项通过；遗漏的双侧多部位解析另补 3/3 轮通过。 |
| Simulator 视觉 | `FAIL` | 截图证明红区、红点、图例、备注和大字深色布局可见；同时直接暴露正面右肩落点在解剖学左侧。证据见 `outputs/device-evidence/2026-08-23-body-feedback-front-right.png`、`2026-08-23-body-feedback-dark-xxxl.png`。 |
| 普通模式活动数据库 | `PASS`（测试前） | 真源为 `group.com.edward.FitnessApp` App Group 共享容器，不是 App data container 中的遗留库。备份三件套位于 `/Users/edward/Documents/xfit-device-backup-20260823/pre-feature-device-appgroup/`；`quick_check=ok`，存在 `ZDAILYBODYCHECKIN` 和 `ZSESSIONEXERCISE.ZFEELINGRAW`。活动基线：Session 17、SessionExercise 114、SetLog 487、完成组 458；已有 1 条体感和 6 条合法动作体验记录。 |
| 同版本真机回归（复用当日证据） | `PASS` | X-Fit 0.5.0 (11)，真机单元 149/149、UI 51/51；相关 4 条 feature UI 测试包含在全量套件中。证据摘要见 `outputs/xfit-rds-device-agent-20260823.md`。该证据使用隔离 UI 测试库，不替代活动 App Group 数据回读。 |
| 本轮 feature-only 真机重跑 | `BLOCKED_ENV` | 测试进程在结果包完成前中断；随后 Mac 锁屏，设备在 `devicectl` 为 unavailable、在 `xctrace` 位于 Devices Offline。未生成可判定的 feature-only xcresult，不计 PASS。 |
| 测试后活动库守恒 | `BLOCKED_ENV` | 因设备离线，无法拉取 App Group 三件套做 post-feature 指纹与计数对比。遗留 App data container 的 15/101/442/431 不是活动真源，不作为替代证据。 |
| DEV-MAN 人工体验 | `NOT_RUN` | 低亮度、相邻区域连续触控、VoiceOver、真机最大字体和中文键盘需真人。因 P1 已阻断且设备离线，本轮按停止条件不继续，不计算综合分。 |

## 3. 缺陷与定级

### P1：正面人体图左右语义反转

- `BodyRegionCatalog` 的正面 `right` 区域全部使用 `x > 0.5`，落在画面右侧。
- 正面人物面向观察者时，画面右侧是人体自身左侧；所以 `front-right-shoulder` 等控件的视觉落点与“右”标签、备注解析和 VoiceOver 文案矛盾。
- 背面人物背对观察者，`back-right-*` 使用 `x > 0.5` 是正确的。
- 受影响 7 对、14 区：肩、肱二头肌、前臂、髋/腹股沟、股四头肌、膝、小腿前侧。
- 现有 UI 测试只验证 `body-region-front-right-shoulder` 的按钮 ID、选中态与保存结果，没有断言红色落点位于解剖学右侧，因此自动化绿灯不能覆盖该缺陷。

截图 SHA-256：

- `2026-08-23-body-feedback-front-right.png`：`e8ee2ce0a1305bf4a235cdf885fd3682022fca22cab58d15fa921ba6abfe7a65`
- `2026-08-23-body-feedback-dark-xxxl.png`：`bd8e870dc84409ab085015412ac716c9b1785ae301a74ff8d95102527d4045f9`

## 4. 通过项明细

### 今日体感与人体图

- 分数上下界钳制为 1...5，日期归一到当天。
- 同日 upsert、重复记录清理、取消不落盘、备注 trim。
- 34 区域 ID 唯一，17 正面 + 17 背面；坐标与布局在界内。
- 坏 marker JSON fail closed；同一区域可同时保存红区与红点。
- “右肩前侧”“左膝后侧”、否定句、双侧和多明确部位解析均有测试。
- 红区、红点、文字列表、稳定 accessibility ID、选中 trait 和最小 44pt 命中目标已实现。
- 深色模式 + 最大辅助字体的保存入口和摘要卡可操作。

### 每动作五档 Emoji

- 预设数量、顺序和语义完全一致：`😣 😥 😮 🙂 😄`。
- 仅在动作完成后显示；同一动作单选，可从痛苦切换到轻松。
- 强退/重启后选择仍存在；完成历史显示体验。
- `feelingRaw` 备份往返；未知未来枚举不会阻塞导入。

### 数据安全

- 普通模式活动库已完成新 schema，且已有真实用户路径写入并回读的体感/动作体验数据。
- 本轮读取与备份未卸载 App、未清容器、未 reset、未修改用户历史。
- 活动库与遗留库已明确区分；后续必须以 App Group 共享库作为唯一数据守恒真源。

## 5. 发布门与下一步

当前不计算 NDS/RDS 综合分：存在 P1 失败，且测试后活动库回读和 DEV-MAN 未完成。

修复验收顺序：

1. 仅修正正面 7 对区域的解剖学左右映射；背面保持不变。
2. 新增视觉/几何断言：正面 `right` 必须落在画面左半，背面 `right` 必须落在画面右半；备注解析也覆盖相同规则。
3. 连续 3 轮重跑本专项 17 项，0 自动重试。
4. 设备在线后重跑 feature-only 真机测试，并对 App Group 活动库做前后 `quick_check`、计数和行指纹对比。
5. 最后再执行相邻区域触控、低亮度、VoiceOver、最大字体和中文键盘的 DEV-MAN 清单。

只有 P1 修复且上述门全部通过，才能把本 feature 标为通过。
