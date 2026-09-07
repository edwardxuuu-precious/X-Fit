# X-Fit 0.5.0（11）安装与真机验证

已在 Edward_iPhone 覆盖安装并启动 **Release** 版本。自动化验证完成，状态 **真机待验收 / 非 GO**；本人体验未代签。

| 层 | 实际结果 | 证据 |
|---|---|---|
| 本地基线 | 6 后端、258 单元、91 有效 UI；7 既有停用跳过；Release 构建通过 | ../20260907-full-ui-final/final-verification.json |
| 真机单元 | 256 PASS；2 个仅主机 fixture 跳过，由本地门覆盖 | device-test-results.json |
| 真机 UI | 首轮 87 PASS / 4 FAIL / 7 SKIP；4 个失败完整流程补验通过；最终有效 91 PASS / 7 SKIP | device-test-results.json |
| 修正后的模拟器兼容 | 同四个完整流程 4 PASS | ../../../../artifacts/stage-validation/20260907-normal-ui-device-retry/simulator-harness-regression.log |
| 最终安装 | 签名核验、Release 覆盖安装、正常启动、版本回读均 PASS；未卸载/清容器 | final-release-package.json / final-release-results.json（artifacts 对应 run） |
| 数据守恒 | 七份备份完整，1257 行、全部原 UUID 保留；36 次训练 / 203 动作 / 837 组 | data-conservation/conservation.json |
| 人工体验 | BLOCKED_HUMAN | ../20260907-normal-ui-device-retry/真机人工测试清单.md |

## 修正与边界

本轮仅修改三份 UI 测试文件中的四个失败测试，App 源码、界面、计算和保存逻辑均未变。空字段必须匹配精确 placeholder，数值 0 不当成未知；体感保存和草稿重查确认转场及有效点击，仍验证原数据语义。腰围 96→95、同 UUID 唯一、取消不保存及重启持久化断言全部保留。

初次运行因 UI runner 连接中断，UI 测试及测试后核验未完整结束；重跑已完成。原始失败与补验日志均保留，不宣称首轮零失败。原失败自动附件导出为空，不声称看到了原失败截图；结论依据原始操作日志、字段读取及补验结果。

数据比较唯一变化为同一已归档“严格深蹲”的 updatedAt，由现有启动去重逻辑刷新；所有其他共同业务字段及 UUID 引用一致。原始差异未被忽略，详情见 data-conservation/reviewed-differences.md。新增八个减脂实体为空，不代表周期或餐单已导入。

最终包来自 D03 Release 构建，签名与可执行文件 SHA 已保存。开发签名 get-task-allow=true 不代表 Debug；最初额外校验曾误以此判断配置，已纠正并保留 finalize-release-probe-note.md；未因此修改签名或 App。

## 本人接下来操作

打开新版体验开始/继续训练与记组、实吃及明日备餐、目标与复盘。减脂周期尚未创建：在目标页创建周期，再分别预览确认餐单与训练日程。医学份量/营养目标仍待确认。人工清单由本人填写后才可更新为已验收；无 commit/tag/push 或发布。

需求：docs/requirements/2026-09-06/100804_ui-redesign.md。阶段计划：docs/releases/0.5.0/2026-09-06-ui-redesign/阶段固化测试计划.md。完整机器结果与证据指针见同目录 final-verification.json。

## 知识收尾门

Context Router context_closeout 使用原回执和同一 payload 重试，均返回 Transport closed。学习收尾未完成；安装、测试及上述文件证据已完成，不将本地文件冒充服务收尾成功。
