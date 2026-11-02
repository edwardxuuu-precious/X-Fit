# 10/12 Notes 训练日期修复：补充验证记录

- 关联需求：`REQ-20261013-090344`
- 范围：修复已确认导入训练的来源日期/时区和未知开始时间；不新增训练或改排期。

## 结果

- 10/12原训练经同一批准包重试：0场/0动作/0组新增，修复日期元数据1条，跳过重复训练1场。
- 活动 App Group 只读副本：同一 session ID `5CE18525B9EF461D9B3A1E244B520420`；9个动作、28组；`trainingLocalDay=2026-10-12`、`trainingTimeZoneIdentifier=Asia/Shanghai`、开始时间未知；SQLite `quick_check=ok`。
- 10/12两条已有排期仍为 `planned`；真机核心记录计数在测试前、覆盖安装后、自动化测试后和元数据补修后均无减少。补修前后训练、动作、组及核心表计数未增加。
- 训练名称和组次保持原始Notes文本；未知侧别、RIR、时长未推断。87.4kg为9/23历史体重快照，不是10/12称重。

## 验证

- 日期新增、幂等元数据修复、保留本人改过开始时间的3项定向单测通过。
- 初次完整模拟器单测392项中391项通过，1项因SQLite `database is locked` 失败；该具名测试孤立重跑通过，随后关闭诊断采集进行完整单测重跑，392/392通过。初次失败保留为历史证据，不覆盖。
- Simulator UI：118项，7项既有跳过，0失败；iPhoneOS Release无签名构建通过。
- 真机无线：安装前备份、SQLite检查、签名覆盖安装、核心数据守恒、全量真机单测均通过。
- 真机全量UI自动化两次均在首个测试用例开始前 XCTest runner code 74 / DTX channel refused 退出；实际UI场景数为0。未再重复相同尝试。此为未解决的测试环境门，不是UI测试通过，也不是产品断言失败。
- 真人真机体验清单保持独立状态；自动化运行不能代替真人体验，也不影响已完成的App数据修复。

## 证据索引

- 需求与分层结果：`docs/requirements/2026-10-13/090344_notes-import-date-unknown-time.md`
- 统一本地阶段：`outputs/stage-validation/notes-oct12-date-fix-20261013/summary.md`
- 全量单测补跑：`artifacts/stage-validation/notes-oct12-date-fix-20261013/unit-full-retry.xcresult`
- 真机阶段：`outputs/stage-validation/notes-oct12-date-repair-20261013/summary.md`
- 日期补修回执：`artifacts/stage-validation/notes-oct12-date-repair-20261013/notes-repair/result/receipt.json`
- 日期补修回读：`artifacts/stage-validation/notes-oct12-date-repair-20261013/device-data/post-repair/default.store`
- 最新Notes与记录事实：`artifacts/project-loop/20261013-notes-refresh.json`
