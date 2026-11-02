# X-Fit 0.5.0 动作标准化高鲁棒性测试与真机评估

## 1. 测试目标

验证动作标准化功能在错误输入、重复操作、旧数据迁移、跨设备导入和真实 iPhone 环境下满足以下不变量：

1. 已完成训练的原始动作名、重量、次数、RIR、完成状态和时间不被术语审核改写。
2. 未经人工接受的候选不能参与 canonical 趋势归组。
3. 同名但肌群、器械或计量单位不同的动作不能被静默复用或合并。
4. AI 只生成结构化候选，不能携带客户端 Provider Key，也不能直接批准候选。
5. 审核、拒绝、撤销、重复启动和备份恢复保持幂等且可追溯。

## 2. 风险等级与发布硬门

- P0：可能丢失、改写或错误合并历史训练；可能泄露 API Key；可能让未审核 AI 结果成为权威数据。任何一项失败即阻断发布。
- P1：审核状态、合并组、导入原子性或 UI 主流程错误。通过率必须为 100%。
- P2：搜索、文案、排序、性能与环境稳定性。通过率不得低于 95%。

发布硬门：

- P0/P1 失败数必须为 0。
- 真机活跃数据库 `PRAGMA quick_check` 必须为 `ok`。
- 真机训练会话、动作快照、组记录和完成组数量不得减少。
- 历史内容指纹必须一致；仅允许已确认的 catalog 指针归一化，不允许快照文字或组表现字段变化。
- 完整单元测试、完整 UI 测试、签名构建和真机覆盖安装必须分别报告，不能互相替代。
- DeepSeek 代理未配置时，App 必须明确显示“AI API 未连接”，并保持本地审核闭环可用。

## 3. 评分体系

总分为 100 分，采用“维度权重 × 已通过项比例”计算；阻塞或未执行项不计为通过。

| 维度 | 权重 | 评分重点 |
|---|---:|---|
| 历史与数据安全 | 30 | 快照不可变、迁移守恒、备份恢复、无部分写入 |
| 动作身份正确性 | 20 | canonical、别名、合并组、肌群/器械/单位冲突 |
| 审核状态机 | 15 | pending/accepted/rejected、原子性、幂等、撤销 |
| AI/API 安全与合约 | 10 | HTTPS、无客户端密钥、结构版本、枚举与字段校验 |
| 兼容与导入导出 | 10 | schema v8/v9、CSV、设备合并、旧库迁移 |
| UI 可操作性 | 10 | 入口、风险文案、接受/拒绝/撤销、未知候选禁用 |
| 稳定性与可部署性 | 5 | 三轮复跑、全量回归、签名、真机启动 |

等级：

- 95–100：通过；且所有发布硬门通过时可发布本地审核功能。
- 90–94：条件通过；只允许内部测试，需关闭未通过能力。
- 80–89：高风险；阻断发布并修复。
- 低于 80：不可接受。

## 4. 高鲁棒性测试矩阵

| ID | 级别 | 测试项 | 核心断言 | 执行层 |
|---|---|---|---|---|
| DS-01 | P0 | 接受候选不改原始动作名 | `Exercise.name` 和 UUID 不变 | 单元 |
| DS-02 | P0 | 接受候选不改历史快照 | `SessionExercise.exerciseName` 不变 | 单元/真机回读 |
| DS-03 | P0 | 趋势归组不改组记录 | 重量、次数、RIR、完成状态与时间指纹一致 | 单元/真机回读 |
| DS-04 | P0 | 迁移数量守恒 | session/snapshot/set/completed-set 不减少 | 真机 SQLite |
| DS-05 | P0 | 活跃库完整性 | App Group store `quick_check=ok` | 真机 SQLite |
| DS-06 | P0 | CSV 冲突无部分写入 | 冲突前后的 exercise/session/set 均为 0 增量 | 单元 |
| DS-07 | P0 | 设备合并冲突回滚 | 即使 UUID 命中也不产生 session/snapshot/set | 单元 |
| DS-08 | P0 | 术语决定备份恢复 | 所有候选、决定、版本和审核时间完整往返 | 单元 |
| ID-01 | P1 | 审计名称无碰撞 | 55 个 raw name 全部唯一 | 单元 |
| ID-02 | P1 | canonical 格式稳定 | 仅小写字母、数字和下划线 | 单元 |
| ID-03 | P1 | 双语字段完整 | 候选中文、英文均非空 | 单元 |
| ID-04 | P1 | 合并组结构完整 | 5 组、每组 2 个别名、状态为 mergeReview | 单元 |
| ID-05 | P1 | 宽字符/大小写/空白归一 | 全角 MTS、英文大小写、首尾空白均命中 | 单元 |
| ID-06 | P0 | 同名不同肌群拒绝 | 返回 conflictingIdentity | 单元 |
| ID-07 | P0 | 同名不同器械拒绝 | 返回 conflictingIdentity | 单元 |
| ID-08 | P0 | 同名不同单位拒绝 | 返回 conflictingIdentity | 单元 |
| ID-09 | P1 | 双语/canonical 搜索 | 中文、英文、canonical 均可找回原动作 | 单元 |
| SM-01 | P1 | 候选 staging 幂等 | 重复 staging 不变名、不改决定 | 单元 |
| SM-02 | P0 | merge 接受原子性 | 同组全部接受；任一字段缺失时全部不写 | 单元 |
| SM-03 | P1 | merge 拒绝与撤销 | 同组同步，组外动作不受影响 | 单元 |
| SM-04 | P1 | 已处理状态保持 | 重复 staging 不覆盖 accepted/rejected 或 reviewedAt | 单元 |
| SM-05 | P0 | unresolved 不可接受 | canonical 为空、决定保持 pending | 单元/UI |
| SM-06 | P0 | pending/rejected 不归组 | 同 canonical 候选仍产生独立趋势 | 单元 |
| SM-07 | P0 | 不同单位不归组 | accepted canonical 仍按 kg/个/米隔离 | 单元 |
| SM-08 | P0 | merge 语义一致性 | canonical、中英文、肌群、器械、单位、状态或置信度任一冲突时整组拒绝 | 单元 |
| SM-09 | P1 | 审核保存失败回滚 | 模拟 save 失败后同组决定和 reviewedAt 全部恢复 | 单元 |
| API-01 | P0 | 禁止 HTTP | 非 HTTPS 立即拒绝 | 单元 |
| API-02 | P0 | 客户端无 Provider Key | 无 Authorization 和 apiKey 字段 | 单元/代码审计 |
| API-03 | P1 | 请求 schema 类型 | `schemaVersion` 为 JSON number | 单元 |
| API-04 | P1 | 响应版本校验 | 非 v1 返回 unsupportedSchema | 单元 |
| API-05 | P1 | 枚举白名单 | 非法 reviewStatus/confidence 被拒绝 | 单元 |
| API-06 | P0 | 完整候选字段 | 非 unresolved 缺任一中英名/canonical 即拒绝 | 单元 |
| IO-01 | P1 | 旧备份兼容 | schema v8 无 terminology 字段时导入为 pending | 单元 |
| IO-02 | P1 | schema v9 完整恢复 | 决定、置信度、合并组、备注、版本和时间保留 | 单元 |
| IO-03 | P0 | CSV 全文件身份预检 | 跨 session 同名冲突在首条写入前终止 | 单元 |
| IO-04 | P0 | 设备 exact UUID 冲突 | UUID 不能绕过肌群/器械/单位保护 | 单元 |
| UI-01 | P1 | 设置入口可达 | 我的 → 设置 → 动作标准化成功 | UI/真机 |
| UI-02 | P1 | 边界文案可见 | 不改历史、AI API 未连接均可见 | UI/真机 |
| UI-03 | P1 | 接受与撤销闭环 | 确认、完成提示、撤销后恢复 pending | UI/真机 |
| UI-04 | P0 | unresolved 禁止接受 | 禁用接受按钮，仍允许保留当前名称 | UI/真机 |
| UI-05 | P0 | 决定持久化与历史保护 | 接受、撤销、拒绝跨冷启动保持；历史原名、完成组、重量和 RIR 不变 | UI/真机 |
| ENV-01 | P0 | UI 测试外部副作用隔离 | 默认不触碰真实训练提醒或 App Group 分享草稿 | 单元/代码审计 |
| REL-01 | P1 | 专项三轮无重试 | 26 项 × 3 轮，78 次运行全部通过 | 模拟器 |
| REL-02 | P1 | 完整单元回归 | 107 项，0 失败 | 模拟器 |
| REL-03 | P1 | 完整 UI 回归 | 26 项，0 失败 | 模拟器 |
| REL-04 | P1 | 签名构建 | 0.5.0 (11) deep codesign 校验通过 | iPhoneOS build |
| REL-05 | P1 | 真机覆盖安装与启动 | 不卸载、不清空，版本回读正确 | 真机 |

## 5. 本轮自动化结果

- 术语与测试隔离专项单元测试：26/26 通过，其中术语 24 项、外部副作用隔离 2 项。
- 专项无重试稳定性复跑：78/78 通过（26 项 × 3 轮）。
- 持久化术语 UI：1/1 通过；覆盖接受、撤销、拒绝、多次冷启动及历史快照保护。
- 完整单元测试：107/107 通过。
- 完整 UI 测试：26/26 通过。
- `git diff --check`：通过。
- iPhoneOS 0.5.0 (11) 签名构建与 deep codesign：通过；App Group 与 HealthKit entitlement 回读正确。
- 签名产物主 dylib SHA-256：`b4971b520aa8163bdb8745dbd512fd2b1737f30e26e942430553009e80fabba5`。
- Edward_iPhone 真机专项 UI：4/4 通过，0 失败；覆盖入口与边界文案、接受/撤销、unresolved 禁止接受、接受/撤销/拒绝跨冷启动持久化及历史原始值保护。
- 真机覆盖安装与生产模式启动：通过；设备端版本由 0.5.0 (10) 升级并回读为 0.5.0 (11)，未卸载 App、未清空 App Group。

测试证据：

- `/tmp/xfit-terminology-fix-unit/Logs/Test/Test-FitnessApp-2026.08.21_21-42-53-+0800.xcresult`
- `/tmp/xfit-terminology-fix-unit/Logs/Test/Test-FitnessApp-2026.08.21_21-48-22-+0800.xcresult`
- `/tmp/xfit-fix-repeat/run-1.xcresult`、`run-2.xcresult`、`run-3.xcresult`
- `/tmp/xfit-fix-full-unit/Logs/Test/Test-FitnessApp-2026.08.21_21-51-42-+0800.xcresult`
- `/tmp/xfit-fix-full-ui/Logs/Test/Test-FitnessApp-2026.08.21_21-51-43-+0800.xcresult`
- `/tmp/xfit-physical-20260822-0003.xcresult`

## 6. 真机验收与数据守恒

- 设备：Edward_iPhone，iPhone 17，iOS 26.6；Developer Mode 已启用。
- 活跃库：`group.com.edward.FitnessApp` App Group。
- 安装前备份：`/Users/edward/Documents/X-Fit Device Backups/2026-08-21_pre-0.5.0-build11-fixed-physical-tests/app-group-active/`。
- 安装后备份：`/Users/edward/Documents/X-Fit Device Backups/2026-08-22_post-0.5.0-build11-fixed-physical-tests/app-group-active/`。
- 两份备份均包含 `default.store`、`default.store-wal`、`default.store-shm`，且 `PRAGMA quick_check=ok`。
- 安装前后计数均为：56 个动作、15 次训练、101 条动作快照、442 组记录、431 组完成记录；accepted=0、rejected=0、pending_review=0。
- 训练会话内容 SHA-256 安装前后均为 `b5e556b74cde8d90a32886d681a243ac2bf3e75d87c38009c6b731cd8267b8f3`。
- 历史动作快照内容 SHA-256 安装前后均为 `2a6149d18f3d1184ae1c653ee23cd013875e4b4553c25c76bbb2c7f78a1bc460`。
- 组记录内容 SHA-256 安装前后均为 `90b4b18866c7b5f709649b3b7cf1afc3caa89c4ce255c8603e3ae08fe49a7e14`。
- 真机 UI 在隔离的 `XFitUITesting` store 中执行；默认不读取生产 App Group 分享草稿，也不同步真实训练提醒。
- 覆盖安装后以无测试参数的生产模式成功启动，进程可回读并正常终止；设备端版本回读为 0.5.0 (11)。
- 前两次尝试分别因设备不可用和锁屏未进入用例执行，均属于环境前置条件，不计为产品失败；解锁后的正式运行 4/4 通过。

## 7. 当前判定

已修复此前审计出的四类缺陷：UI 测试不再默认同步真实训练提醒或读取真实分享草稿；merge 接受增加严格语义一致性校验；审核保存失败会 rollback；持久化 UI 夹具包含 2 个原名快照和 3 条完成组，并跨多次冷启动验证接受、撤销和拒绝。

最终评分：**100/100，通过**。P0/P1 失败数为 0；专项三轮复跑、完整单元回归、完整 UI 回归、签名构建、真机 4 项专项 UI、覆盖安装、生产模式启动和安装后数据守恒均已通过。0.5.0 (11) 的本地动作标准化审核功能满足发布硬门。

DeepSeek/其他 AI 在线代理仍未配置，因此本结论不代表在线 AI 候选生成链路已验收；当前版本会明确显示“AI API 未连接”，本地候选库和人工审核闭环可正常使用，AI 不可直接批准或改写历史。
