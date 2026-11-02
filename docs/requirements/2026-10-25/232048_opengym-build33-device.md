# 需求：Build33 动作库保留数据无线更新

- 需求 ID：`REQ-20261025-232048`
- 创建/确认归档时间：`2026-10-25 23:20:48 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：本轮直接确认，精确消息时间未提供；2026-10-25 23:20:48 +0800归档，未用归档时间冒充消息时间。
- 用户确认摘要：用户明确“好的 更新到手机”；已知本地329待核、手机最后验证Build32/335待核，授权保留数据无线覆盖安装。
- 状态：`真机待验收`
- 目标版本/阶段：0.5.0 Build33
- 关联需求：阶段计划逐项列出的6份本地修正需求；Build32阶段基线。

## 用户原始需求

> 好的 更新到手机

## 目标

- 将累计已本地核实的非媒体动作库修正交付现有手机，目录1324条、329待核；手机正常Release启动并回读33。
- 保留UI风格、紧凑折叠、Build32已有功能，以及当前手机全部训练历史和10/26 C1＋高翻计划。
- 以安装前新鲜手机备份核对安装及测试后全部业务字段、关系、设置与原图；分开报告本地、设备、人验和训练效果。

## 非目标与边界

- 不把根工作树其他修改纳入手机；不重导计划/48条实际，不自动合并个人动作，不加媒体、不改训练。
- 不卸载、清容器或把旧快照写回手机；不提交Git、打tag或发布。
- 完整真机UI专项沿用暂停规则，不在同无线条件无新证据下重试；人工体验和真实效果不代填。

## 当前事实

- 2026-10-26安装前无线回读Edward_iPhone解锁且0.5.0(32)。本轮已通过统一device覆盖安装，完成全量真机单元后恢复正常Release；最终启动及版本回读0.5.0(33)。
- 交付源从Build32冻结基线复制，仅目录JSON、相关保护测试及33版本配置变化；原181输入保持一致，独立测试支持夹具未进入手机Release。UI、模型及其他运行逻辑保持。
- 目录1324条、329待核，SHA256：`baff92017623fcd33db6514375484bd80ee23432d3291ece30c0e2a160636104`。较32基线335→329；来源ID/英文/英中原步骤/器械/MIT保持，不增加媒体或身份合并。
- 新鲜安装前07:46与恢复正常Release后07:49完整副本均为25表2523行；全部业务字段、UUID/关系、4个非DB文件和主/共享设置一致。原图样本0，不作有图恢复证明。
- 当前训练已由本人后续确认修订为下肢专项周五日安排，升级前已独立导入。五日全部字段与07:45:58写后副本一致；原周一C1已skipped且处方/来源留档，6动作20位置仅是该旧处方。本轮不重导或变更计划/实际。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 范围与版本冻结 | P0 | RESOURCE/PACKAGE | 仅批准差异，1324/329，App/扩展0.5.0(33)，签名/组正确 |
| AC-02 | 完整本地回归 | P0 | N01–N07 | 统一入口全部必要检查通过，不新增跳过或删断言 |
| AC-03 | 当前手机安全覆盖 | P0 | D00–D06 | 先备份可读当前库/设置/文件，再覆盖及正常启动/版本33 |
| AC-04 | 全业务数据守恒 | P0 | DEVICE-DATA | 安装后/测试后相对新鲜备份字段/UUID/关系/偏好/资产一致；10/26计划、48实际与R6保留，计划及实际新增0 |
| AC-05 | 真机及人工门真实 | P0 | D07–D09 | 单元依据本次实际；暂停UI保持BLOCKED_ENV，人工BLOCKED_HUMAN，不能标GO |
| AC-06 | 主预览和原看板同步 | P1 | PREVIEW/DOC | 正常33无测试参数、云关闭，官方单向刷新本次手机副本；原看板更新实际分层状态 |
| AC-07 | 验证入口冲突处置 | P1 | HOST/DEVICE | 落实已有UI暂停及本次验证授权，分离UI开关，不暗中改门或重试暂停UI |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C01 | 历轮仅本地 vs 本次手机交付 | 交付范围扩展 | 是否更新手机 | 用户明确“好的 更新到手机”；旧本地事实保留，新需求独立授权 | 已解决 |
| C02 | 统一脚本将单元/UI同开关 vs 完整真机UI暂停 | 无法只跑新鲜单元且不重试UI | 最小独立UI开关，或本次整层XCTest暂缓 | 此前按既有授权撤回重复确认；本次用户进一步明确选择“做最小开关，跑真机单元，UI继续待验”，并回复已解锁保持亮屏。已即时回读解锁、仍Build32，继续同一授权范围 | 已解决 |

## 实现映射

| AC | 实现与实际结果 | 状态 | 证据 |
|---|---|---|---|
| AC-01 | 原冻结交付源及持久归档签名包；1324/329、主App/扩展33、签名/组正确 | PASS | prepared-package-verification.json、device-final-app-readback.json |
| AC-02 | 完整统一本地8门通过；502单元，161UI通过/8原跳过/0失败 | PASS | 20261026-opengym-build33-validation/results.tsv及两个summary |
| AC-03 | 新鲜完整备份后覆盖，正常Release33启动/版本回读；无卸载/清容器 | PASS | results.tsv D00–D06、D07C |
| AC-04 | 安装后及测试后25表2523行全业务字段/身份/关系、文件/设置守恒；旧C1/R6/48实际及现五日计划保持 | PASS | conservation-phone-post-tests-full.json、weekly-plans-preservation.json |
| AC-05 | 单元、UI、人工、效果分别如实记录；阶段仍非GO | PASS（分层报告）；未验门独立保留 | 下表 |
| AC-06 | 主预览正常33并单向刷新07:49真实副本；原固定看板17任务更新、历史和人填字段保持 | PASS | main-preview/final-verification.json、notion-delivered/readback.json |
| AC-07 | 最小独立UI开关；真实执行单元1/UI0，恢复Release与守恒继续，无暗中重试 | PASS | results.tsv D07A/B/C、runner-switch-verification.json |

上述短文件名默认位于artifacts/stage-validation/20261026-opengym-build33-device/；主机开关mock位于20261025-opengym-build33-device/，不冒充真机证据。

## 分层验证

| AC ID / 层级 | 预期 | 实际 | 状态 | 证据 |
|---|---|---|---|---|
| AC-01 / 资源及签名 | 批准范围、版本/组/签名正确 | 原181输入一致；1324/329，正常主App及扩展33，正确AppGroup，无测试夹具 | PASS | prepared-package-verification.json、device-final-app-readback.json |
| AC-02 / 完整本地 | 统一8门全部通过 | N01/02/03/03B/04/05/06/07全部PASS；502单元0失败0跳过，161UI0失败8原跳过 | PASS | artifacts/stage-validation/20261026-opengym-build33-validation/results.tsv、unit-summary.json、ui-summary.json |
| AC-02 / 入口收尾 | 完整保留实际结果 | 原运行中热改脚本导致最终收尾退出2；8检查已结束，原write_summary补报告，原错误保留；后续冻结完整脚本文本执行 | PASS（报告恢复） | 同本地目录runner-finalization-recovery.json |
| AC-03 / 设备与备份 | 当前手机可读、备份完整 | 07:46解锁无线32，完整AppGroup/SQLite/WAL/主及共享设置备份，25表2523行；与统一D01同批基线一致 | PASS | resume-preflight/lock.json、phone-pre-install-full-audit.json、D01-full-baseline-binding.json |
| AC-03 / 安装与启动 | 覆盖安装正常33 | D00–D06 PASS；D05安装，测试后D07C恢复正常Release33并无参数启动 | PASS | results.tsv、device-final-app-readback.json、device-final-launch.json |
| AC-04 / 安装后守恒 | 全业务字段/关系/文件保持 | 25表2523行字段/UUID/关系相等、4文件一致；设置于最终完整快照核对 | PASS | post-install-all-fields-conservation.json |
| AC-05 / 真机单元 | 新鲜全量，无新增跳过 | 502总计：497通过/0失败/5旧跳过，逐名比对与32相同；非本地结果替代 | PASS | device-unit-summary.json、device-skip-comparison.json、device-unit.xcresult |
| AC-05 / 完整真机UI | 保留暂停规则 | XFIT_ALLOW_DEVICE_UI_TESTS=0，本轮未运行；此前无线控制通道未解，不重试、不计PASS | BLOCKED_ENV | results.tsv D07B |
| AC-04 / 测试后守恒 | 恢复正常Release再完整比较 | 07:49完整副本25表2523行全部业务字段/UUID/关系，4文件、主/共享设置相同；48/48、R6、旧C1和当前五日全部保持；计划/实际新增0 | PASS | conservation-phone-post-tests-full.json、weekly-plans-preservation.json |
| AC-05 / 人工体验 | 真人填写 | 未执行，不代填 | BLOCKED_HUMAN | outputs/stage-validation/20261026-opengym-build33-device/真机人工测试清单.md |
| AC-05 / 训练效果 | 自然训练与恢复反馈 | 尚未发生，不从计划导入/测试数推断效果 | NOT_RUN | 原复盘/训练需求 |
| AC-07 / 主机开关 | 默认行为保持、UI可独立暂停 | 四分支/默认值/非法值/语法检查通过；真实device已执行单元与Release恢复 | PASS | artifacts/stage-validation/20261025-opengym-build33-device/runner-switch-verification.json、当前results.tsv |
| AC-06 / 主预览 | 正常33、当前真实副本、云关闭 | 保护旧包/数据/设置后覆盖正常33，官方单向刷新07:49手机副本，25表2523行字段/关系/4文件/偏好匹配，0测试参数/云关闭 | PASS | main-preview/final-verification.json；artifacts/simulator-real-data/20261026-075306/result.json |
| AC-06 / 原固定看板 | 当前状态准确、历史/人填字段保持 | 原两页已更新33/329、17任务及当前五日安排；完整受管文本/数字/嵌套与源相同，历史后缀/属性/标题/归属不变；租约释放 | PASS | notion-delivered/readback.json、release.json |

CoreData内部Z_ENT/Z_OPT记账字段按既有业务快照口径排除；业务主键、UUID及关系均纳入。原图样本0保留限制。显式Release覆盖动作2次（D05/D07C）；XCTest受控安装独立，不把安装次数记成训练数据写入。

## 已执行动作

- 冻结批准候选并完成完整本地检查；保留首轮失败和独立测试支持的范围证据。
- 按用户明确选择应用最小UI开关；新鲜完整备份后统一device覆盖安装、全量真机单元、恢复正常Release及全字段/设置/文件核对。
- 保护主预览原数据和正常包后覆盖33，官方单向刷新本次真实手机副本；更新原固定R4看板并完整回读、释放连接。

## 历史失败与处理边界

- 首轮non-device为7门PASS、N06 FAIL：155UI通过/6失败/8原跳过。5项为周一边界测试前置失效，独立测试支持修正场景前置；原断言/预算/跳过保持。过去hero的条件选日不冒充通用跨周首页选择，未加产品UI。
- 术语重启定位失败后定向及完整复验均未复现，根因unknown，不声称已修复。定向6/6仅局部证据，完整8门另有实际结果。
- 本地入口热修改导致报告收尾退出2，保留原错并补同一原函数报告；本轮设备以冻结完整脚本正文执行，统一device退出0。测试支持不进入手机Release。
- 看板首次回读发现Notion自动把文件名转成无效http链接；仅在受管前缀做代码格式修正，最终文本/数字/嵌套与所有旧内容完整核对通过。

## 当前可用结果与剩余门

- 手机已交付0.5.0 Build33，可以正常使用；1324来源/329待核，原紧凑UI保持。当前五日计划、原C1/R6留档、48实际及全部历史保持，不重导。
- 签名包、181文件冻结交付源与全部设备结果持久归档，入口为artifacts/stage-validation/20261026-opengym-build33-device/delivery-status.json；不依赖/tmp唯一副本。
- 完整真机UI仍BLOCKED_ENV；须本人明确恢复且有新的连接/定位证据后再开对应专项。人工体验BLOCKED_HUMAN，由真人填写；训练效果等待自然反馈。
- 状态仍为真机待验收、阶段非GO。已安装/数据守恒/单元PASS不替代上述未验门；无需继续占用手机或重复无变化的本地全套。
