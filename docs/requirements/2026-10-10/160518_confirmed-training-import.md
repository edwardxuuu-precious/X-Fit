# 需求：已确认训练计划导入与恢复周R1应用

- 需求 ID：`REQ-20261010-160518`
- 创建时间：`2026-10-10 16:05:18 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-10-10 16:03 +0800`（本轮聊天确认；宿主回执16:03:42）
- 用户确认摘要：`用户明确确认最小导入功能、必要测试和无线覆盖更新；同时确认CUT-RESTORE-20261012-R1方案、排期及本轮临时调整。`
- 状态：`开发中`
- 关联需求：`REQ-20261009-214811`；本轮仅追加已确认入口增量，不废弃原验收门。
- 目标版本/阶段：0.5.0 新候选；无线覆盖更新，不提交/tag/push。

## 用户原始需求

> 确认最小导入功能；确认 R1 方案、排期及本轮临时调整。

## 目标

- App自身接收完整已确认的一周编排，预览冲突、追加保存、加入日程并回读；不需本人逐动作重抄。
- 应用未变更的`CUT-RESTORE-20261012-R1`，2026/10/12–18，基础`TP-20260928-05`；18/20/20/20组、24动作位，明确空重量、逐组目标/说明完整。
- 确认绑定的完整正文：`outputs/training-plan/2026-10-12-recovery-review-r1.md`；SHA256 `d4cafc5eb8bb1c54007d99b402817e1dc99b48f70ca88c524251bec4fdc0e491`。正文不改写，确认/应用状态在本需求维护。

## 非目标与边界

- 不改长期偏好或已展示R1、不猜历史公斤数/RIR/侧别、不导入三篇旧实际；不结束/丢弃原进行中训练，不覆盖已完成组。
- 不增服务器、在线识别、实时上传、Notion权限/共享认证或新库；其他原任务和原真机性能/人工门保持独立。
- 不用备份恢复或直接SQLite作为新计划写入口；无线覆盖而非卸载清库。未知动作身份/来源变化/既有日程冲突停止。

## 当前事实

- 10/11本人补充确认：MTS下斜推胸机、胸托T-Bar划船机、哈克深蹲机、器械臀推机均可用，口径kg。仅解决本轮新计划的器械/单位事实，不替旧Notes未知单位、侧别或RIR补值。
- 沿本需求最小导入范围补明确的动作定义：缺少精确身份时，由确认包列出名称/器械/kg和新UUID；App完整预览新增动作及日程后同次保存。碰到同名不同器械、已归档或已有不同UUID的同名条目仍停止，不恢复、合并或修改旧动作；失败全部回滚，不另造直接数据库入口。
- 10/11本人要求先准备餐食功能/UI及本地完整验证，手机覆盖、R1应用及真机实测合成最后一批。原ENTRY/餐食AC和真实性能/照片证据条件保留；这不是阶段GO，也不以未开始拍餐食阻断本地页面工作。
- 已取得明确开发与指定计划确认；之前入口审计见原需求末尾和`artifacts/project-loop/20261010-recovery-review/app-entry-audit.json`。
- 现有周版本/日程/备份模型与App配对Mac交换可复用；逐组区间/努力目标和任意新周入口缺口须补齐。
- 当前Goal宿主已恢复active；手机/偏好/日程在写前重读，不把旧副本当实时配置。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| ENTRY-01 | 版本/偏好/日期、动作顺序、顶组/回退、逐组区间/RIR/休息、替代/停止规则完整 | P0 | SERVICE/SIM-UI/DEVICE-DATA | R1逐项一致，可回看，不只比较组数 |
| ENTRY-02 | 空重量不受兼容历史25×12覆盖；目标与实际独立 | P0 | SERVICE/SIM-UI/DEVICE-DATA | 新训练仍未完成，actual为blank，无历史默认负重 |
| ENTRY-03 | 追加、幂等、漂移/冲突保护 | P0 | SERVICE/DEVICE-DATA | 同版本同内容重复新增0；未知身份、内容/日程冲突拒绝；原UUID/业务字段不减少 |
| ENTRY-04 | 失败可见/无半个生效周，旧备份兼容/新语义可恢复 | P0 | SERVICE/SIM-UI | 预检/保存失败不部分生效；隔离恢复逐项一致 |
| ENTRY-05 | 新候选分层验证、无线覆盖与回读 | P1 | GENERIC-BUILD/DEVICE-AUTO/DEVICE-DATA/DEVICE-MANUAL | 使用统一入口，版本及数据守恒；原真机/性能门不由本地PASS代替 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C01 | 原剩余任务“不改源码”与新导入入口开发 | 仅新增入口及必要依赖/测试/无线覆盖 | 是否批准最小增量 | 本轮明确确认；独立本需求，不静默替代原合同 | 已确认 |
| C02 | 基础肩臂24–28组/部分力竭与R1肩臂20组/2–3RIR | 仅10/12–18的R1临时安排 | 是否批准完整R1及临时例外 | 本轮明确确认；长期TP-05不改，到期不自动续排 | 已确认 |
| C03 | 四动作缺精确UUID与现有相近/已归档条目 | 仅本轮新计划动作定义，旧历史不变 | 是否有对应器械、单位是否kg | 10/11本人确认均有、单位kg；使用独立精确身份，不能借相似UUID | 已确认 |
| C04 | 当前L4“本地完整合格后手机”顺序与整批两间歇FAIL、原路径定向2 PASS但未稳定复现 | 仅调整本批验证顺序，不放宽原AC/预算、抹去FAIL或宣称GO | 是否允许进入最后一批无线真机诊断、覆盖候选及已确认R1应用 | 2026/10/11本人明确“允许真机运行，手机在附近”；批准集中无线批次，原完整本地FAIL保留，Notion父级/凭证不在本次授权内 | 已确认 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| ENTRY-01–04 | `ConfirmedTrainingPlanService`、显式新增动作定义、可选逐组处方、`ConfirmedTrainingPlanImportSheet`、编排/录入页、JSON恢复及配对交换 | 关键本地服务/UI PASS；10/11 App自身R1预览、应用、重复零、独立完整回读及原九表保护PASS | R1手机应用已完成；原本地完整FAIL和DEVICE UI未进入用例仍独立保留，未来训练不提前开始 |
| ENTRY-05 | 统一阶段计划/脚本、App自有交换、当前0.5.0(15) | 原non-device完整终态FAIL；本批统一device exit1，覆盖/普通Release恢复/九表保护PASS，真机单元378 PASS/5原host-only SKIP/0 FAIL；UI运行器启动失败、实际用例0 | C04批准设备先行不代表GO。旧本地两失败、设备UI/P95及未报告人工项保留；额外动作库时间戳观察另列，不伪装全库无变化 |

已确认测试seam：①公开计划包预览/应用/回读服务；②App导入与查看/开始训练完整UI；③现有JSON备份导出/恢复；④真机交换回执与安装前后核心数据守恒。先一条失败行为再最小实现，不用私有方法或直接改数据库替代入口。

## 分层验证

以下为C04批准后本批最新设备结果；后表是原批次历史，不能覆盖本批实际状态。统一Run：`goal-confirmed-wireless-device-batch-20261011`，原摘要exit1保留。

| AC ID / 层级 | 实际结果 | 状态 | 证据 |
|---|---|---|---|
| ENTRY-01/03 / DEVICE-DATA | App新鲜预览无冲突；新增4个精确动作、7日程、1周版本；独立回读原文、24动作位、78工作组的所有组次/RIR/休息及三有氧规则一致；同包重试新增动作/日程均0 | PASS | 同批`r1-semantic-verification.json`及`r1-{preview,apply,repeat,readback}/result` |
| ENTRY-02 / DEVICE-DATA | 78组显式blank，计划重量仅内部0占位；没有新实际训练/组，原进行中训练仍保留 | PASS | 同批完整回读、`business-field-conservation-final.json`；手机真实开始/输入情景NOT_RUN，不将计划层当实际录入层 |
| ENTRY-03/05 / DEVICE-DATA | 安装后、测试恢复后、R1后quick_check=ok；原九表全部旧UUID/业务字段无变化；日程37→44、周版本4→5，其他核心数不变 | PASS | 同批`business-field-conservation-{post-install,final}.json`；final附加ZEXERCISE全字段检查为FAIL，见下方单独观察 |
| ENTRY-05 / DEVICE-INSTALL | 0.5.0(15)无线覆盖/签名/启动；测试后恢复普通Release，最终无测试参数PID93605绑定实际同一安装容器；169来源未漂移 | PASS | 同批`device-delivery-binding.json`及`device-post-r1-{normal-launch,app-readback}.json` |
| ENTRY-05 / DEVICE-UNIT | 原383项真机单元范围，378 PASS/0 FAIL/5既有host-only资料SKIP；没有新增排除 | PASS | 同批`device-unit-summary.json`、`D07A.log`；跳过内容由原non-device资料层覆盖，不冒充手机执行 |
| ENTRY-05 / DEVICE-UI | 宿主exit65，运行器exit74；XCTestDriverInterface通道被拒、IDE断连，实际UI用例0。xcresult的1个failure是Runner启动失败，不是1个产品断言 | BLOCKED_ENV | 同批`device-ui-summary.json`、`D07B.log`；原统一脚本D07B FAIL保留。action仅同一启动错误，console不可用；根因unknown，本批不重试 |
| ENTRY-05 / DEVICE-MANUAL/PERF | 新入口本人体验、真实键盘到像素P95尚无本批证据；原四项本人接受仍有效 | NOT_RUN | `device-delivery-binding.json`；镜像恢复后提示iPhone in Use，停止接管，不要求本人再次锁屏或重复原体验 |
| ENTRY-01/05 / DEVICE-VISUAL（代理） | 10/11本人锁屏后无线镜像一次Connect成功；今天10/11与原进行中状态保留；7项R1日程均待完成；第5版日期/TP-05/确认导入提示及18/20/20/20组可见，展开首项卧推核顶组/回退/RIR/休息及重量留空 | PASS | 同批`r1-native-visual-verification.json`；只读导航后返回今天首页，没有安装、再次导入、编辑或开始未来训练。不是本人体验、XCTest或客观P95；完整24动作语义由独立App回读证明，不称全部动作逐行视觉验收 |

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| ENTRY-01–04 / 定向服务与既有交换 | 完整保存/回读、空重量、失败回滚、恢复、漂移拒绝 | 14服务/兼容用例PASS | PASS | `/tmp/xfit-import-green-final-targeted-20261010.xcresult` | 非全量、非手机；会在新统一入口再验证 |
| ENTRY-01–02 / 模拟器完整录入UI | 预览→导入→首个训练日→开始，逐组目标可见/重量空白/未完成 | 1用例PASS，全部关键断言保留 | PASS | 同一定向xcresult | 隔离fixture改为当天课；未放开未来日期提前记实际的产品规则 |
| ENTRY-01 / R1内容比对 | 与已确认正文逐行匹配 | 24动作位、78逐组次数/强度/休息一致；原文字节及SHA一致 | PASS | `outputs/training-plan/2026-10-12-r1-import-pending.json` | 4动作UUID明确null，待身份核实；不是已应用包 |
| ENTRY-05 / 原完整non-device | 全部层通过 | N01–N05/N07 PASS；N06四项断言失败后中断，10 PASS/4 FAIL/1取消 | FAIL | `artifacts/stage-validation/goal-confirmed-plan-import-20261010` | 首批终态exit1；UI仅前缀，未跑完整；不改写失败 |
| ENTRY-05 / 修复后定向UI | 原生全选粘贴、选择拖动、滚动收键盘、秒单位保存、新导入完整录入 | 5 PASS/0 FAIL/0 SKIP，断言和预算未修改 | PASS | `artifacts/stage-validation/goal-confirmed-plan-import-20261010/paste-scroll-boundary-green.xcresult` | 仅调整AppTheme滚动阶段条件；其余三项间歇点击无确定根因，不称已修复 |
| ENTRY-05 / 滚动阶段假设完整non-device | 同一源码完整统一层 | 376单元PASS/1FAIL；UI前缀12 PASS/3实际FAIL/1取消；整轮exit1 | FAIL | `artifacts/stage-validation/goal-confirmed-plan-import-fixed-20261010` | 假设未解决粘贴，已撤回；原断言与失败完整保留；不把中断前缀当全量 |
| ENTRY-05 / 测试异步边界有限诊断 | 精确粘贴结果、原2秒内关闭键盘/原3秒焦点；旧迁移失败含真实SQLite代码 | 1迁移单元及4UI全部PASS，exit0 | PASS | 同目录`async-boundary-diagnostic.xcresult`与`async-boundary-source.json` | 产品源码已恢复首批导入实现，仅两份测试文件不同；旧迁移读取原因仍未知，非完整验收 |
| ENTRY-05 / 最终统一non-device | 同一最终源码统一全层 | N01–N05/N07 PASS，全量单元377 PASS/0 FAIL/0 SKIP；UI前缀54 PASS/1实际断言FAIL/7原退役SKIP/1取消，整轮exit1 | FAIL | `artifacts/stage-validation/goal-confirmed-plan-import-final-20261010/ui-terminal-summary.json`、统一摘要 | 快速体重入口未出现导航栏；停止UI后剩余未运行，不把前缀称全量。xcresult failedTests=2包括1取消，不报2个产品故障 |
| ENTRY-05 / 新失败有限复查 | 同一源码、同一测试及原等待预算 | 快速体重完整录入单项PASS，exit0；整批失败保留 | PASS | 同目录`quick-weight-diagnostic-summary.json`、`quick-weight-unchanged-diagnostic.xcresult` | 只说明间歇性，根因未知；不以单项PASS消除统一层FAIL，不无变化重跑整批 |
| ENTRY-05 / 真机覆盖安装 | 签名覆盖、启动/版本回读 | 统一device入口D00–D06 PASS，签名0.5.0(13)实际覆盖/启动；预览后普通无参数启动PID90190绑定同安装容器 | PASS | `artifacts/stage-validation/goal-confirmed-import-wireless-delivery-20261010/device-delivery-binding.json`、统一摘要 | 没有卸载/清容器；完整non-device FAIL仍保留，覆盖交付不是GO |
| ENTRY-03/05 / 活动库保护 | 原UUID和旧业务字段守恒 | 安装前→安装后、安装前→预览后两次九表比较均无原UUID丢失/字段改变；quick_check=ok | PASS | 同目录`business-field-conservation.json`、`business-field-conservation-after-preview.json` | 45/275/1097/33/22/37/5/4/2保持；不是全库/真机自动化/真实照片恢复验收 |
| ENTRY-03 / 真机R1预览 | 未知身份可见，未应用时零训练变动 | App实际回执completed，准确返回MTS下斜/胸托T-Bar/哈克/器械臀推四项身份冲突；未请求apply，R1版本0、日程仍37 | PASS | 同目录`r1-preview-pending/result/{receipt,training-preview}.json` | 预览的7项是拟新增数，不是已写入数；偏好仍TP-20260928-05，不能关闭ENTRY-01/02手机应用门 |
| ENTRY-05 / 真机完整自动化与客观性能 | 原device XCTest及P95验收 | 本次XCTest未重试；既有UI-driver连接失败未解除；P95未测 | BLOCKED_ENV | 原无线控制连接证据；本次`device-delivery-binding.json` | 已有测试授权有效。脚本D07“未授权”是开关0的通用标签，真实原因是无新恢复证据时停止同环境重试，不再索要许可 |
| ENTRY-05 / 真人新入口体验 | 查看完整计划及实际录入体验 | 未报告新入口；原四项本人接受不重新索要 | NOT_RUN | 原本人确认维护在当前轮 | 不把自动化或原体验接受当新入口验收 |
| ENTRY-05 / Build14完整统一non-device | 原117 UI全部终态、不主动中断，明确来源守恒 | N01–N05/N07 PASS；383单元PASS；107 UI PASS/3 FAIL/7既有退役SKIP；169源及Git守恒 | FAIL | `artifacts/stage-validation/goal-catalog-local-complete-20261011/{ui-terminal-summary,source-after}.json` | 不把完整FAIL改成局部PASS；失败原因后续定向调查另证 |
| ENTRY-04/05 / 导入反馈因果与最小修复 | 公共单击导入后原5秒内结果可见，不改变数据/滚动/内容 | 原三项有限复现2 PASS/1 FAIL；公共探针证明已保存3日程但提示屏幕外，再只读预览0可导入/1已有/3已导入。结果移到固定顶部后原用例PASS | PASS | 同目录`cycle-feedback-causal-result.json`、RED/GREEN xcresult及界面附件 | 临时探针首次编译引号错误已纠正，不算产品RED；全部探针清理。术语筛选/RIR展开单项PASS但根因未知 |
| ENTRY-01/02/04 / Build15清理后相关UI | 原周期导入/CSV、新动作开始、空重量/逐组目标完整 | 3 PASS/0 FAIL/0 SKIP，exit0；单次点击/原5秒预算不变，固定提示截图已读 | PASS | 同目录`final-import-paths-summary.json`、`final-import-feedback-evidence/manifest.json` | 只证明相关路径，不代替新完整回归或手机 |
| ENTRY-05 / Build15完整统一non-device | 绑定实际修改后的候选、全层终态及源守恒 | N01–N05/N07 PASS、383单元PASS；完整117 UI为108 PASS/2 FAIL/7既有退役SKIP；169来源全部同SHA，分支与HEAD相同，整轮exit1 | FAIL | `outputs/stage-validation/goal-import-feedback-local-complete-20261011/summary.md`、同批`{ui-terminal-summary,source-after}.json` | 无主动中断或取消用例；搜索输入前无焦点、压力场景点击后缺设置页，原因未知。关键导入、历史预填、Seated Dip及三条餐食UI在整批通过，不替代全层/手机合格 |
| ENTRY-05 / Build15原两失败有限复现 | 同源同模拟器、原断言/等待上限，保留5轮取消压力操作 | 2 PASS/0 FAIL/0 SKIP，exit0；日志逐项确认压力1–5，169来源及Git仍一致 | PASS | 同批`triage-original-pickers-summary.json`、`picker-diagnostic-result.json` | 仅说明本次原失败未重现，尚无稳定RED，不宣称修复、不覆盖整批FAIL、不无变化重跑全量。C04仅建议调整验证顺序，待本人决定 |
| ENTRY-05 / Build15原前序场景有限复现 | 原日志两条动作库搜索/编辑删除恢复→两条失败选择器；同源同模拟器、原断言与预算 | 4 PASS/0 FAIL/0 SKIP，exit0；独立summary与tests及activities核对实际五轮1–5；169来源/Git守恒 | PASS | 同批`pickers-with-library-predecessors.xcresult`、`picker-predecessor-sequence-result.json` | 本次该前序不足以稳定重现，根因仍unknown，不称已修复或覆盖完整FAIL。一个通过用例有frame运行警告，关联未知。停止无变化全量；C04顺序与T3父级以弹窗分别请求，未取得决定前不调用手机或远端 |

## 已执行动作

- 已读当前确认正文、偏好/工作流、入口审计与测试技能；正式需求已生成，原Goal已恢复active。未修改任何真实训练。
- 按公共seam逐项RED→GREEN实现完整预览/追加/回读、同版重试0、失败回滚、计时有氧、显式空重量和完整UI；未知动作/单位/原文不兼容保持未写入。
- 公开恢复测试抓到排期被重新归零点：最小复现`/tmp/xfit-import-red-restore-instant-20261010.xcresult`；恢复时保留原绝对时间后，完整备份恢复/日期/空重量测试通过。未删除断言或放宽校验。
- 内容/完整性seal与目标漂移测试实际FAIL后补齐：原文/规范化包/冻结日程完整性回读；目标周期关闭、来源链接/日程/时区变化拒绝旧预览。失败证据`/tmp/xfit-import-ui-seal-red-20261010.xcresult`、`/tmp/xfit-import-red-drift-20261010.xcresult`；最终定向15全部PASS。
- 增加App文件导入入口与计划目标展示、配对Mac三项训练命令，并更新`docs/training/训练档案工作流.md`。目标Build13已生成工程，150条明确源码在完整回归前绑定；没有提交/tag/push。
- 本地只读Notion status再次确认专用凭证缺失、写入关闭、父页null及远端调用0；不切共享认证、不创建/搬迁原库，不把本地入口交付冒充T3线上完成。
- 新候选完整入口实际exit1：N01–N05/N07通过；N06在四项原界面断言失败后主动中断，完整UI未跑完，xcresult为10通过/4断言失败/1取消。原四项仅一次定点核查为3通过/1粘贴失败；不是整轮通过，也未确定其余间歇点击的根因。公开粘贴场景两次实际RED，疑似`.tracking`阶段过早收键盘，按原录入兼容范围仅调整该条件并验证，断言及时间预算不改。Apple阶段定义参考`https://developer.apple.com/documentation/swiftui/scrollphase/tracking`；不将文档定义当本App因果证明。原N06及定点xcresult完整保留。
- 18:44修复后5项定向UI全部PASS：只在真实`.interacting`滚动时收键盘，保留触摸追踪期间的文字选择与系统编辑菜单；秒单位保存及完整导入/开始录入同时通过。新150条源码在完整复测前绑定，仅AppTheme不同；不使用旧完整结果认证新源码，也不以一次GREEN宣称全部间歇问题消失。
- 18:53修复后全量单元376 PASS/1 FAIL/0 SKIP；旧历史迁移用例在`identifiers(in: copy)`末次临时副本读取抛Cocoa259，旧helper将open/prepare/step错误统一映射为格式错误，尚不能确定损坏、锁等待或产品迁移缺陷。此前同一测试及源文件通过、此次仅AppTheme变化；原源库当前只读字节774144/SHA256 `122264740584bb6e1a351a8c1ae9111a7cb07dead9cbbd4cf56d56c523f267c1`、SQLite头正常，不把原文件可读当迁移用例通过。完整UI继续，未改源码/断言/预算或重跑该单元。
- 第二批真实UI仍有粘贴、输入前焦点和键盘关闭断言失败，主动中断后12 PASS/3实际FAIL/1取消，N07仍完成；150条前后未漂移。滚动阶段假设被反证，已仅撤回本轮三行试改，保留其他既有AppTheme修改。
- 两段失败录像在即时断言后已显示正确粘贴名称：首批定点录像65秒帧、第二批完整录像42.5秒帧，均只含隔离假数据。新诊断针对自动化时序：保留原完整值断言，新增精确结果的2秒条件等待并记录即时/稳定值；这不是触屏P95测量，也不降低100ms业务指标。选择测试将原3秒键盘前置条件移到输入前；关闭测试用原2秒上限的`waitForNonExistence`替换错误的“等待出现再取反”。旧迁移helper只增加open/prepare/step真实SQLite代码，不改断言、重试、数据库或产品迁移逻辑。Apple原生期望和消失等待说明已读，记录在下节；尚未声称诊断通过。

本轮测试边界参考：[XCTNSPredicateExpectation](https://developer.apple.com/documentation/xctest/xctnspredicateexpectation)、[waitForNonExistence(timeout:)](https://developer.apple.com/documentation/xcuiautomation/xcuielement/waitfornonexistence(timeout:))。浏览器Markdown读取失败后只读取同一官方Markdown正文；来源支持API含义，不替代本App录像/实测因果证据。

- 20:06有限诊断终态exit0：旧迁移1 PASS、粘贴/选择/三位小数与收键盘/完整新导入4 UI PASS。旧读取未再失败，仍保留间歇原因未知，不称存储缺陷已修；三项既有界面测试只修自动化异步边界。最后全量批次`goal-confirmed-plan-import-final-20261010`在150条源码绑定后启动，产品源码与首批导入实现一致，两份测试文件差异明确，未继续改源码。
- 20:51最终统一批次终态exit1：377单元通过，N01–N05/N07通过；N06快速体重入口在点击后未出现导航栏而FAIL，保留录像/界面树/合成触点，确认触点位于按钮矩形内，但未证明按钮action执行或产品根因。UI停止后的54 PASS/1断言FAIL/7既有退役SKIP/1取消由日志与独立xcresult核对，剩余未运行；150条前后内容/Git未漂移。20:55同源同断言只复查失败用例一次，完整录入PASS，不称已修复，不继续刷绿整批。
- 无线开发通道只读检查返回Connection reset by peer；已有镜像Resume后提示iPhone Not Found，没有更改配对/网络/安全设置、结束手机训练或安装新包。Notion 20:10本机status仍为专用凭证false、父页null、写入关闭、远端调用0；不作为新鲜线上身份或原库完整性证明。
- 续做有限诊断：只加入本地UI测试事件记录，分别执行同页面8次单击打开/取消、8次从“我的”重新进入身体数据后的单击；两用例终态exit0，70.897秒及176.945秒。捕获点击/状态/表单节点，未捕获失败，不确定按钮、呈现或自动化哪一层导致原FAIL，不试改多sheet或增加点击重试。临时探针与日志代码全部移除；150条原绑定源码及Git逐项一致，`git diff --check`通过。证据只在`artifacts/stage-validation/quick-weight-causal-probe-20261010`，不是新的完整回归PASS。
- 无线恢复有新证据：21:21只读锁状态true；原生镜像实际恢复并打开X-Fit，首页选10/10且原进行中训练仍在，未填字/结束/丢弃；21:29新鲜CLI锁状态false。安装交付可独立推进，但不解除整批UI FAIL、设备XCTest控制连接和客观性能门；四个器械事实核实仍待答，R1不提前应用。
- 21:45统一device入口实际exit0，D00–D06通过；Build13无线覆盖到原App，安装、应用清单与实际启动进程的同容器绑定可回读。安装前后九表原UUID及全部旧业务字段守恒；不把脚本exit0或D07未运行标签当完整device PASS，测试授权仍有效。
- 21:54通过App自身`previewTrainingPlan`实际读取R1包，回执04710C3A-DF78-47B8-9397-F1768A6D3618只列四项动作身份冲突；没有apply调用，也没有半周生效。随后普通无参数启动PID90190、版本13再次回读；新副本R1版本数0、九表业务字段仍完全守恒。镜像一次Resume后显示找不到手机，未继续重试，所以新入口真实画面/本人体验未验证。
- 21:55新鲜手机副本33餐食、0照片、0评估；不生成空周评估、测试图回写或真实照片恢复通过。原Notes体重三条及原本人四项体验接受继续保留，不重复要求。

## 结果与遗留项

- 10/11本轮C04已确认并已执行集中无线批次。手机已覆盖0.5.0(15)、正常Release无参数启动；R1已实际应用并独立完整回读，重复新增0。统一device原exit1保留：单元层PASS，UI仅运行器启动失败、实际界面用例0。结果与证据以上方最新表及`device-delivery-binding.json`为准；原完整non-device两FAIL、P95、新入口人工和真实照片资料门没有关闭。
- 附加动作库检查发现旧已归档`严格深蹲`（稳定ID `08d277e0-ac9d-4b72-96ff-31b90eba38aa`）仅`updatedAt`在每次普通启动后变化，名称、器械、口径、归档及其他原字段一致。原`consolidateConfirmedSquatDuplicate`在重复项上无条件设置时间戳；本批不改代码、回滚数据或再安装。扩展十表全字段receipt的FAIL如实保留，原九表业务保护单独PASS；这是需后续具名修复的启动幂等性观察，不能称全库零变化，也不增设新的已完成项。
- 原进行中训练仍1场，未结束/丢弃；实际餐食照片仍0，不制造周评估或真实照片恢复PASS。本轮Notion线上写入0，T3目的地/独立凭证门不被手机授权关闭。当前产品交付已可用，但阶段仍PARTIAL/BLOCKED，需求保持开发中。
- 10/11 21:10–21:14本人锁屏后已完成普通App无线页面核验，证据为同批`r1-native-visual-verification.json`。R1的真实日程、版本、四课组数及首项逐组目标可见；已返回今天首页，旧进行中训练未动。仅关闭代理视觉展示缺口；原本地完整FAIL、真机UI运行器、P95、新入口本人体验、真实餐食资料及T3门不变。

### 10/11续作：计时有氧展示与记录入口的有限缺口

- 10/12本人对前条两项规则明确回复“好的 你可以推进”；归档启动幂等、计时跳绳未知个数按独立[REQ-20261012-204928](../2026-10-12/204928_archive-idempotence-timed-rope.md)实施。以下“待确认/未改”是此前快照，原R1正文/日程及历史不变，最终验收仍独立。
- 原ENTRY-01/05内核对发现：`cardioVolumeSummary`无条件显示轮数，R1单车1200–1800秒因此显示“0轮／约20分钟”。本轮仅修摘要：没有间歇轮数的单车按已保存时长区间显示；跳绳继续显示轮数及含休息时长，不改确认包、源正文、日程或实际。
- 测试沿已确认查看UI的公开展示接口`TrainingPlanPresentation.cardioVolumeSummary`：单车独立期望“20–30 分钟”，跳绳对照仍为“8 轮 / 约 12 分钟”；先实际RED再最小实现，定向通过后结束该修复分支。完整分层和集中真机仍单独验收，不将单项通过标成GO。
- 实际结果：原实现单项1 FAIL（错误显示0轮/约20分钟），最小修复后相关`ConfirmedTrainingPlanTests`18 PASS/0 FAIL/0 SKIP。本地候选单独标0.5.0(16)，手机仍是已交付Build15；R1正文与确认包SHA均保持。证据：`artifacts/stage-validation/goal-cardio-summary-20261011/cardio-summary-{red,green}.xcresult`。
- 完整统一批次`goal-cardio-local-complete-20261011`已终态exit1：N01–N06及N03B PASS；384全量单元PASS/0 FAIL/0 SKIP已独立回读，完整N06日志为117个不同用例、110 PASS/0 FAIL/7原退役SKIP，与Build15测试集合及跳过ID完全一致。旧两picker本批通过仅是本次反证，不宣称未知根因已修。N07实际FAIL/exit69，原日志明确提示尚未同意Xcode／Apple SDK许可；按环境门记BLOCKED_ENV，保留脚本原FAIL，整层不合格。
- N06终态xcresult已形成Info.plist，但独立`xcresulttool`回读同样被许可门阻断，不能把逐用例日志核对称作独立回读。169明确来源终态SHA、branch/HEAD均与本批开始一致；仅覆盖已列来源，不代表全工作区或手机守恒。本轮无手机调用，手机仍是已交付Build15。证据：同批`{ui-terminal-summary,source-after,environment-gate}.json`、N07原日志及统一摘要。
- 许可条款须本人在Mac审阅并决定是否同意；本轮已发送一次弹窗请求，答复未知。没有代为接受、请求聊天密码、改系统许可或重启整批测试；恢复后先核源未漂移，补被阻断的Release及独立结果核对，再按统一验收口径判断，不把重新堆全套测试当推进。
- 只读入口核对另发现R1跳绳code不满足既有`ROPE_`前缀，故走通用秒数训练而非`JumpRopeEntry`。通用路线能够记录活动秒数并完成排期，不能称无法保存；实际个数未给出，不能强制新增必填负担。本轮已请求“只记时长、个数可留空”的具名范围确认，未收到回复前不改该记录语义。
- 已归档深蹲启动时间戳小修复同样单独弹窗请求；未确认前不修改该范围。旧进行中训练保留，已成功R1不重导，原其他验收FAIL/门禁保留。
- 对前序失败真机UI仅导出并读取已完成xcresult诊断，没有再次操作手机：testmanagerd控制会话和runner会话成功、运行器安装并取得PID，随后XCTestDriver通道被拒绝并exit74，实际界面用例0。失败边界已收窄，根因仍未知；现有日志不能证明镜像、锁屏、USB或性能基线警告为原因。有限取证到此停止，有新控制恢复证据或单独确认的诊断变更才重开。证据：`artifacts/stage-validation/goal-confirmed-wireless-device-batch-20261011/device-ui-bootstrap-diagnostic.json`。

### 前序批次历史结果（以下“未手机/待C04”不代表本批现状）

- 10/11当前结论：四器械及kg已明确确认；新增精确身份定义、同周保存/回滚、同包重复零、同名冲突/归档保护、完整来源/公开备份/配对交换回读和新增动作UI定向通过。原文/逐组目标未变，完整待导入包为`outputs/training-plan/2026-10-12-r1-import-confirmed-catalog.json`；证据`artifacts/project-loop/20261011-local-ready/{local-paths-result,r1-packet-evidence}.json`。
- 前一候选0.5.0(14)完整统一批次`goal-catalog-local-complete-20261011`终态exit1：N01–N05/N07通过，383单元PASS；完整117 UI为107 PASS/3 FAIL/7既有退役SKIP，没有主动中断。169明确来源及Git守恒PASS。三失败原AX/录像保留；术语筛选仍待审核、RIR仍折叠，不证明数据丢失；历史三组25×12/双边/未完成的前置断言通过，后续恢复未走完。一次原三个用例有限复现终态2 PASS/1 FAIL，恢复40×8及术语完整流程均单项PASS但原因未知，导入反馈稳定FAIL；原13/14整批失败仍保留，后续因果与修复证据单列。
- 当前0.5.0(15)仅修复已确认的导入反馈可见性：公开入口实际保存3日程后提示位于屏幕外，固定顶部结果保留列表位置，代价为少量顶部高度；不改计划/保存/目标/等待预算。临时诊断清理后3条相关完整UI PASS并读固定提示截图。新169来源只比14改变4文件（该页面、结果截图测试、Build源与生成工程）；统一`goal-import-feedback-local-complete-20261011`已终态exit1：383单元PASS、108 UI PASS/2 FAIL/7既有SKIP，其余层PASS，169来源/Git守恒。关键导入、餐食、历史整组预填及Seated Dip在整批PASS，但整轮仍FAIL，不进入手机批次；术语/RIR本批通过仍不证明原间歇根因已修。正式导入因果记录不变。
- 手机上次实读为0.5.0(13)，旧九表保护为10/10证据；本轮未安装/启动/交换/读取手机数据，R1仍未应用。仍待合格完整终态后的一次集中设备批次：新鲜预览/应用/重复零/完整回读、新入口体验及原XCTest/P95。真实餐食资料、T3位置/独立授权等原门另列，不被定向或原库Notion更新关闭；不结束原进行中训练、不改长期偏好。
- 10/11该完整批次的新失败：动作选择器在首次搜索输入前没有焦点；压力场景末次搜索结果已出现但点击后缺“本次设置”。独立xcresult及原AX已回读，完整终态证据为同批`ui-terminal-summary.json`；原始附件导出至`ui-failure-attachments`和`stress-failure-attachments`。仅一次原两用例同源/同模拟器/同预算定向复现终态2 PASS/0 FAIL/0 SKIP，压力操作1–5均实际执行，169来源及Git仍守恒；未取得稳定RED，产品/自动化原因unknown，没有代码修复或再次全量重试。C04弹窗待本人决定，仅建议调整手机验证顺序，原验收标准和整批FAIL不变；未提前调用手机。
- 10/11续作仅按原日志加入紧邻的两条动作库前序，四个原UI用例实际终态4 PASS/0 FAIL/0 SKIP；独立xcresult summary/tests及活动记录证明五轮取消均执行。测试期间169绑定来源及Git逐项未变，没有产品/测试修改，没有完整刷绿或设备调用；该前序未构成稳定RED，停止盲试。只读Notion本地配置仍为专用凭证false/父级null/写入关闭/远端0；共享connector有另一聊天的未决调用，未抢占。已弹窗请求原C04顺序与私有父级选择，原验收和长期偏好均不变；证据在同批`picker-predecessor-sequence-result.json`。
