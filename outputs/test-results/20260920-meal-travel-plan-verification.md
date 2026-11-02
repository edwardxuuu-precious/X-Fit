# 旅行周真机写入回读

- 用户确认：已查看 2026-09-21 至 2026-09-27 完整计划并明确同意写入。
- 写前预览：无日期冲突；待写入 4 个力量训练、2 个恢复训练。
- 首次应用：新增 6 项。
- 写后预览：6 个代码全部已存在；待写入力量 0、恢复 0；无冲突。
- 重复应用：新增 0 项。
- 日程回读：9/21 胸肩 A 15 组；9/22 背腹 A 16 组；9/23 胸肩 B 12 组；9/24、9/25 恢复；9/26 酒店背腹 B 16 组。
- 计划负荷：四次力量合计 59 个计划组；预设重量全部为 0，重量侧全部为 unknown，等待当天填写。
- 有效期：TP-20260921-04 于 9/21 生效；TP-20260928-05 于 9/28 恢复长期偏好，不生成新日程；9/28 及以后没有旅行周日程。
- 数据守恒：体重 19、餐食 33、训练 43、训练动作 261、训练组 1049、跳绳 2 均保持；既有九张核心表记录未缺失、既有业务字段未变化。日程 31→37、偏好版本 3→5、编排版本 3→4，均为本次预期追加。
- 数据库完整性：SQLite quick check 通过。

证据：

- `20260920-meal-travel-plan-preview-confirmed/result/travel-preview.json`
- `20260920-meal-travel-plan-apply-confirmed/result/travel-result.json`
- `20260920-meal-travel-plan-post-apply-preview/result/travel-preview.json`
- `20260920-meal-travel-plan-repeat-apply/result/travel-result.json`
- `20260920-meal-travel-plan-data-readback.json`
- `20260920-meal-travel-post-plan-data/default.store`
