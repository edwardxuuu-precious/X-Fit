# X-Fit 0.4.0 动作补录与当天菜单实施报告

## 结论

已把“外部学习一个新动作，并加入今天训练”收口为一条连续路径：进入当天菜单或训练中菜单，搜索完整动作库；没有结果时原地新建；保存后自动加入当前菜单。首页、日程、训练中和 Safari 分享入口均已接入同一动作目录与编辑规则。

本地代码、工程生成、模拟器编译和 47 项单元测试已通过。Share Extension 已同时嵌入模拟器与真机签名产物。2026-08-03 已通过 Xcode 自动签名为主 App 和 Share Extension 刷新 development provisioning profile，签名权限均包含 App Group，并已把真机版本安装到 `Edward_iPhone`。设备因锁屏拒绝远程启动，因此 Safari 分享与保存后的真机数据验收仍待解锁后完成。

## 已交付体验

- 当天菜单始终显示“添加动作”，不再要求用户先选到匹配肌群。
- 动作选择器搜索名称、肌群、器械、备注和参考链接。
- 搜索零结果时显示“新建并加入”；保存后返回原菜单并自动追加动作。
- 同名可用动作直接复用；同名归档动作恢复原记录，避免产生重复动作。
- 首页今日计划提供“调整菜单”；日程页区分“自选动作编排”和“从现有模板安排”。
- planned 与 skipped 日程都可进入指定日期编排；调整跳过日程会生成新的可训练当天菜单。
- 训练进行中复用同一个动作选择器，可原地新增动作。
- 自定义动作支持 HTTP/HTTPS 参考链接；链接随训练开始进入 `SessionExercise` 历史快照。
- Safari/其他 App 分享的 URL 与文字先写入 App Group 草稿；主 App 激活后允许补全、稍后处理或明确丢弃。

## 数据与失败保护

- 保存当天菜单前先校验动作存在、未归档且无重复；校验失败不会删除旧的一次性计划，也不会跳过原日程。
- 开始训练前完整校验模板动作；缺失或归档动作不会被静默跳过。
- 已结束训练不能再增加动作或组数。
- 参考链接进入动作、训练快照、JSON 备份、设备历史合并与训练 CSV 导出。
- JSON 备份 schema 升级到 5；旧版本备份继续按可选字段导入。
- Share Extension 不直接访问 SwiftData，只保存一个待确认草稿；新分享会替换未消费的旧草稿。

## 验证结果

本功能的测试环境分层、完整测试矩阵、结果状态、评分公式与发布硬门见《[X-Fit 动作补录、当天菜单与分享入口高鲁棒性测试与评估](X-Fit_动作补录与当天菜单高鲁棒性测试与评估.md)》。该测试契约明确区分“不连接真机的 70 分”和“必须连接并解锁真机的 30 分”；未完成真机层时不生成最终发布分。

- `xcodegen generate`：成功。
- iOS Simulator generic build：成功，构建产物包含 `PlugIns/XFitShareExtension.appex`。
- 单元测试：47/47 通过，0 failure。
- 新增回归覆盖：归档动作恢复、非法来源链接、菜单校验失败不覆盖旧计划、训练来源快照、来源链接备份往返、分享草稿按 ID 安全清除。
- 模拟器现有数据升级：新构建成功打开既有训练日程，未出现 SwiftData 启动失败。
- 手工模拟器冒烟：已确认“今日计划 → 调整菜单 → 添加动作 → 全库搜索 → 零结果新建并加入”入口和表单可达。
- 新 UI 自动化首次执行已走到保存动作，原断言因第五个动作位于懒加载列表下方而失败；断言已改为先验证动作数再滚动查找。修正后的重跑受到另一条既有 Xcode UI 测试进程和 `DebuggerVersionStore: no debugger version` 干扰，Runner 未稳定启动，因此不把该项记为通过。
- iOS 真机签名构建：成功；`ValidateEmbeddedBinary` 通过，产物为 `/tmp/xfit-device-signing-20260803/Build/Products/Debug-iphoneos/FitnessApp.app`。
- 签名权限回读：主 App 与 Share Extension 均包含 `group.com.edward.FitnessApp`；主 App 保留 HealthKit 权限。
- 真机安装：成功更新 `com.edward.FitnessApp`，未执行卸载或清除设备数据。
- 真机启动：安装后首次远程启动被 iOS 以 `Locked` 拒绝；这证明安装完成，但不计为启动或体验验收通过。

## 真机签名与剩余验收

当前已配对设备为 `Edward_iPhone`。Xcode 已自动创建/刷新以下 development provisioning profile：

- 主 App：`f20b7490-5e62-468b-8bff-9f7b417c3eba`
- Share Extension：`b6f69335-3752-49b9-9b81-0c6bb8280cb4`
- 两份 profile 到期时间：2026-08-10

这是 Personal Team 的短期 development profile，到期后需要重新自动签名。剩余真机验收：

1. 解锁 `Edward_iPhone`，确认主 App 可启动且既有数据仍可见。
2. 在 Safari 分享真实动作页面，确认 X-Fit 出现在分享面板。
3. 回到 X-Fit 补全并保存动作，确认动作进入当天菜单。
4. 开始训练后确认来源链接进入训练快照；最后验证 JSON 备份恢复。

## 状态

- 本地实现：完成。
- 工程接入：完成。
- 模拟器编译：通过。
- 单元测试：通过。
- UI 自动化最终重跑：基础设施阻塞，未记通过。
- App Group 与两份 development profile：完成，签名权限已回读。
- 真机签名构建与安装：通过。
- 真机启动：设备锁屏阻塞，未记通过。
- Safari Share Extension 真机体验：等待解锁后验收。
