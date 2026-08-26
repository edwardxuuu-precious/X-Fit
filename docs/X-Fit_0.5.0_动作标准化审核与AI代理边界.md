# X-Fit 0.5.0 动作标准化审核与 AI 代理边界

## 交付结论

X-Fit 已加入受控动作术语层：当前动作可获得标准中文、Standard English、canonical ID、审核状态、置信度与歧义说明。候选只在“我的 → 设置 → 动作标准化”中供用户审核；默认不批准、不改名、不合并历史。

## 数据边界

- `Exercise.name`：继续保存用户当时的原始动作名。
- `SessionExercise.exerciseName`：继续作为完成训练时的不可变历史快照。
- `terminology*`：保存候选名称、canonical ID、审核状态、人工决定与词典版本。
- 只有 `terminologyDecision == accepted` 时，指标层才可使用 canonical ID 归组。
- 接受合并候选会同步审核同组名称，但不合并动作 UUID、逐组记录、PR 或上次重量。
- “严格深蹲 → 深蹲”沿用用户此前已确认的无损合并；历史快照仍保留“严格深蹲”。

## 当前候选库

- 审计来源：55 个原始名称。
- 当前已确认“严格深蹲/深蹲”为同一动作后：49 个 canonical 候选。
- 其余 5 组合并候选仍需在 App 内人工确认。
- 本地候选库版本：`xfit-terminology-2026-08-03-v1`。

## DeepSeek / AI API

已实现 Provider 无关的请求与响应合约，默认 `providerPreference=deepseek`，但当前没有连接外部服务。

- App 只允许 HTTPS 代理端点。
- App 不写入或发送 Provider API Key。
- 代理必须返回版本化结构化 JSON。
- 非 `unresolved` 结果必须同时包含 canonical ID、标准中文、标准英文、审核状态与置信度。
- AI 结果只能更新候选层，不能直接批准、改历史、合并 UUID 或更新 PR。

正式联网仍需要一个用户控制的服务端代理、密钥保管、配额/超时/日志脱敏和回放验证；本版本只交付客户端合约与本地审核闭环。

## 冲突保护

- 动作库同名复用会同时校验肌群、器械和计量单位。
- CSV 同场同名动作出现不同肌群、器械或计量单位时停止导入。
- 设备合并即使 UUID 或名称命中，也会校验肌群、器械和计量单位。
- 备份 schema v9 会保存术语候选和人工审核决定；旧备份仍可读取。

## 验证

- iOS Simulator 无签名构建：通过。
- 新增 8 项术语层单元测试：通过。
- 完整 79 项单元测试：通过。
- 完整 19 项 UI 测试：通过；包含“动作标准化”入口与历史保护说明。
- `Edward_iPhone` 覆盖安装并启动 `0.5.0 (10)`：通过；未卸载、未清空数据。高鲁棒性补丁 `0.5.0 (11)` 已完成签名构建，待设备恢复 DDI/Xcode destination 后覆盖安装。
- development 签名与嵌入描述文件校验：通过；当前描述文件到期时间为 `2026-08-27T15:05:49Z`。
- 真机活跃 App Group 数据库 `PRAGMA quick_check`：`ok`。
- 真机迁移后保留 15 次训练、101 条训练动作快照、442 组记录和 431 组已完成记录。
- 训练会话内容哈希一致；动作快照与组记录在排除 catalog `exerciseID` 指针后内容哈希一致。
- 已确认的“严格深蹲 → 深蹲”归一化只重定向 1 条动作快照和 4 条组记录的 catalog 指针；历史快照文字仍为“严格深蹲”。
- 真机共 56 条动作目录记录，其中 1 条已归档；56 条均已生成审核状态，55 条有 canonical 候选，`传统硬拉` 因未进入本地候选库保持 `unresolved`。

## 真机备份说明

`devicectl` 读回确认当前活跃 SwiftData 库位于 `group.com.edward.FitnessApp` 的 App Group 数据容器。最初从 App Data Container 复制到的文件是旧镜像，不作为当前活跃库证明；安装后的活跃库及 WAL/SHM 已另行完整备份到：

`/Users/edward/Documents/X-Fit Device Backups/2026-08-21_post-0.5.0-build10/app-group-active/`
