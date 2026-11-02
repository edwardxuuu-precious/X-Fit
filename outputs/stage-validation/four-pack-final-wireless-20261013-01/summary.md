# X-Fit 阶段测试摘要

- Run ID：`four-pack-final-wireless-20261013-01`
- 模式：`device`
- 时间：`2026-10-13 18:33:24 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / b2ec4ab`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D00.log` |
| D01 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D01.log` |
| D02 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D03.log` |
| D04 | PASS | 签名、entitlements 与版本回读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D04.log` |
| D05 | PASS | 真机覆盖安装、启动与版本回读（不卸载、不清容器） | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D05.log` |
| D06A | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D06A.log` |
| D06B | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D06B.log` |
| D06C | PASS | 安装前后核心记录不减少 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/D06C.log` |
| D07 | NOT_RUN | 未授权真机 XCTest | `设置 XFIT_ALLOW_DEVICE_TESTS=1` |
| D09 | BLOCKED_HUMAN | 真机人工体验与系统权限清单 | `/Users/edward/Documents/Fitness App/outputs/stage-validation/four-pack-final-wireless-20261013-01/真机人工测试清单.md` |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。

## 本批后续实际结果（当前状态）

### 10/14 本批收好（C-10，当前恢复入口）

本人明确将餐食留到实际使用后验收，本批只恢复/精确清理/核真实数据/原Notion归档，已全部完成。普通0.5.0(18)无测试参数前台启动成功（PID4955）；启动后真实24类业务表旧ID及公共字段新增/缺失/变化0、SQLite ok，47场训练/1162条全部组记录（含热身及未完成）/33餐/22体重/44排期保留。旧独立1场/9条/0餐目录DB/WAL与原备份字节一致、24类业务字段/ID一致；本批没有新餐食、照片或训练，副本内新增1版偏好和10条动作元数据变化已随恢复撤回，可由受保护本地备份恢复。真实照片仍空且守恒，不作照片恢复验收证据。

原Edward/R3、工作台、迭代和T8四处管理进度已真正更新并读回，全部返回正文/人工及其他属性/原归属/子库一致，新对象/认证/权限变化0，租约释放、active calls=0。当前无需本人再操作手机。餐食原图边界NOT_RUN、真实周评估NOT_RUN分别由实际使用/指定真实周和一次确认触发；完整真机UI BLOCKED_ENV及严格物理P95 NOT_RUN仍后续专项，不将本批关闭冒充全部原阶段GO。没有重装、重跑XCTest或扩建框架；139绑定源/HEAD保持。下方“当前只余原图、本批待方便拍测试餐”等均为C-10前历史。

本批证据：[餐食收尾回执](</Users/edward/Documents/Fitness App/artifacts/stage-validation/four-pack-final-wireless-20261013-01/meal-03-xeAzHu/receipt.json>)；[原Notion回执](</Users/edward/Documents/Fitness App/artifacts/project-loop/20261013-four-pack-closeout/notion-receipt.json>)的`wireless_device_outcomes.meal_acceptance_deferred_closeout_05`。原raw副本仅存受保护本地临时目录，不进入Notion或本次项目正文。

当前增量以本节及同Run `continuation-readback-02.json` 为准；下方前序草稿/待确认说明保留历史。本人明确确认收尾C-08只操作独立测试环境并恢复原环境，C-09以手机关键场景直接操作、保存重开与活动数据/照片回读取代本阶段完整真机UI硬门。原完整真机UI仍BLOCKED_ENV/0场景、严格物理P95仍NOT_RUN，转后续专项，不填PASS。

| 续做业务出口 | 实际结果 | 当前状态 |
|---|---|---|
| 来源日期 | 普通Build18的10/12自重动作显示9/23/87.4kg；旧记录精确匹配回退，不新建称重、不回填可选列；只读前后24表公共字段/ID守恒 | PASS |
| 数字/RIR/备注保存重开 | 现有47场/1162条历史规模的隔离副本：25.5kg、12次、RIR3和具名中文粘贴备注，离开/后台/冷启动后仍在，无重复会话；中文粘贴不冒充全部输入法手打测试，辅助前缀字符保留 | PASS_bounded |
| 搜索和动作分类 | `seated dip`及“坐姿器械臂屈伸”均显示可添加标准动作，三头主导/胸辅助和旧项已合并说明正确，器械未误标肩推；具名候选保留小场景已观察 | PASS_bounded |
| 完成记账 | 独立副本仅勾1组，完成前提示还有19组未做；活动副本实际completed且仅1个完成工作组/19未完成，不夸大计划完成；保存后总结屏未独立回读，本人既有庆祝体验接受保留 | PASS_record / NOT_RUN_summary_readback |
| App侧采集 | 原生Console仅com.xfit.input：数字60样本P95=37.92ms、最大64.43ms、0个>250ms帧间隔；搜索12样本P95=56.04ms、2个间隔，有限对照仍2个、原因unknown | PASS_capture；异常观察保留 |
| 餐食原图/最终恢复 | 本人最新明确现在不便拍照、先恢复正常App并保留结果；原图保存/追加/重开/导出/App备份恢复未验。旧独立1场/9条已恢复，DB/WAL与备份SHA一致且24表旧业务字段/ID守恒；普通0.5.0(18)无参数运行，最终真实24表无新增/缺失/变化、SQLite ok | 原图NOT_RUN / 恢复PASS |
| 原Notion四处进度 | 新鲜Edward身份后原迭代/T8/工作台/R3管理段定向更新；完整返回正文、人工/其他属性、子库结构一致，新增0、租约释放 | PASS |

代理时序是UIKit输入回调到下一CADisplayLink回调，不是触键到屏幕；21次保存调用不等于21次成功写入，数据正确性用独立回读判定。没有修复前同口径基线，不宣称提速比例；搜索两次长帧间隔不得抹除或宣称根因已修。未建立重复可见卡顿/丢字，后续仅在新具名症状或定位证据时重开，不重复同条件诊断。

续做证据：`input-app-proxy-02.json`、`device-data/isolated-after-cold-reopen-02/`、`device-data/isolated-completion-02/`、`continuation-readback-02.json`与最终`continuation-final-conservation-02.json`。本次具名测试场仅从隔离副本移除、完整快照保留本地可恢复，真实记录未删除/新增/改写。Notion沿原receipt的acceptance_progress_03及final_restoration_progress_04；最终四处返回正文、属性、子库均一致/零新增/租约释放。当前仍PARTIAL、不GO，业务出口只余餐食原图链，不可由原空照片基线替代。

辅助遗留：Mac TextEdit中仅含本次中性测试文字的临时窗口，保存/关闭状态因原生操作通道连续超时未确认；已停止重试，未永久删除、未改原文档或改用Shell控制界面。此项不影响已完成的手机恢复、真实库保护或正常使用，不作为新的业务前置。

原表由统一入口生成，保留不改。D07“未授权”来自CLI开关0，不代表本人缺少授权：为停止旧同条件CLI重试，本批改由Xcode原生Run入口有限执行。

| 业务出口/验证 | 实际结果 | 状态 | 证据 |
|---|---|---|---|
| Build18手机交付 | 无线覆盖安装、普通Release启动和最终版本回读0.5.0(18)；未卸载/清库 | PASS | D00–D06C；final-normal-app.json、final-normal-launch.json |
| 真机全量单元 | 原目标393项：388通过、5个原有host-only跳过、0失败 | PASS | ide-unit-result.json；原生xcresult |
| 真机UI启动 | 原有Today/Schedule用例由IDE真正发起；首场景前Lost pending connection，0实际场景/1合成runner失败，根因unknown | BLOCKED_ENV | ide-ui-probe.json；不重复同条件尝试，不把GUI绿色当用例通过 |
| 原始数据保护 | 安装前→安装后→原生测试后→最终普通App，24张ZID表旧ID和全部公共业务字段未变；最终无新增ID、SQLite quick_check=ok | PASS | install-business-conservation.json、post-ide-business-conservation.json、final-business-conservation.json |
| 来源日期交付 | 活动schema已交付；续做在普通Build18的10/12自重动作中实际看见“来源测量 Sep 23, 2026”及87.4kg；只读前后旧字段/ID未变，无新称重 | PASS_schema / PASS_label | continuation-readback-02.json；旧记录兼容精确匹配路径，不声称新字段已回填 |
| 手机页面只读 | 冷启动选中10/13今天，排期列表今天置顶；历史显示44次完成；10/12原名9动作28组、时长未知及首6组可见 | PASS_limited | mirror-checks.json；普通App实际镜像观察 |
| 输入草稿 | 20轮次数清空重输尝试，最终13可见，第一组RIR3；未逐轮计时或保存。中文/重量小数/后台保存重开及工程采集未完成 | PARTIAL / NOT_RUN_remaining | mirror-checks.json；镜像控制出现noWindowsAvailable，未据此认定App缺陷 |
| 餐食完整链路 | 本人最新答复现在不便拍照、保留已完成结果；未新建餐食，相机拒绝/多图保存重开/周导出/原图删除恢复未执行 | NOT_RUN | mirror-checks.json；原照片基线0不证明恢复 |
| 原严格物理P95 | 无数值、未测；沿本人C-07转后续非阻断专项 | NOT_RUN_nonblocking | 原训练C-04；工程代理也无数值，不冒充通过 |
| 候选守恒 | 139绑定App/测试/项目文件SHA和Git HEAD不变 | PASS | source-final-check.json |

未保存草稿已通过普通App终止重开丢弃；最终活动库确认训练47、SetLog1162、餐食33、体重22、排期44，24表全部原业务字段不变、新增0。未完成虚假训练或写健康记录，未删除任何已有或测试记录。本阶段仍PARTIAL、不GO。

计数澄清：1162是全部SetLog组记录，不是全部已完成工作组。只读分组为完成/非热身1109、完成/热身6、未完成/非热身47；这仍不是排除丢弃场次后的真实容量统计，不据此评价训练强度。前次更正因实际占用未调用的记录保留；续做已取得有限租约、新鲜Edward身份，只将工作台/R3两处改为“组记录1162条（包含热身及未完成组）”。完整返回正文、原属性/子库均回读一致，新增0，租约释放。证据：同一notion-receipt.json#wireless_device_outcomes.metric_label_correction。

续做导出真正IDE探针原xcresult的4个诊断文件：设备/testmanagerd连接、控制会话和Runner安装/PID均成功，随后DTX拒绝IDE配置通道，配置获取失败；scheduling.log显示cancelled=No。失败层定位为首产品场景前的配置/握手，上游根因仍unknown，无新XCTest运行。安全测试路径核查发现正常餐食删除为软标记、导入为仅新增，不能用它们伪证恢复；旧独立测试环境1场/9条已只读备份，暂未重置。隔离环境操作范围及原完整真机UI阶段出口已合并弹窗待本人决定；决定前不改原门、不创建或删除测试数据。证据：continuation-readback-02.json。

当前恢复条件：本轮已结束并恢复普通App，用户现在无需解锁或拍照。方便后重新做精确隔离交接：同一餐两张具名照片→只续原图保存/重开/导出/App备份恢复→清理/普通App恢复/真实回读。原完整UI与严格物理P95后续保留，不重装、不重测已过项、不扩框架/凭证。前序“暂未重置/等待决定/无代理数值/仍在测试模式”为各自当时快照。
