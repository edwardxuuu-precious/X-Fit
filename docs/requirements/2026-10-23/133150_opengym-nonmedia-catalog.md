# 需求：OpenGym MIT非媒体动作库整合与历史保护

- 需求 ID：`REQ-20261023-133150`
- 创建时间：`2026-10-23 13:31:50 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：`2026-10-23 13:31 +0800`
- 用户确认摘要：用户在完整确认单后选择“确认整合，并保留数据更新手机”。
- 状态：`真机待验收`
- 关联需求：`../2026-09-02/122104_exercise-library-dedup.md`、`../2026-09-27/100827_training-experience.md`、`114454_notes-oct23-coach-learning.md`
- 目标版本/阶段：0.5.0 OpenGym非媒体动作库增量
- 2026-10-30 本人明确以[动作说明及许可媒体需求](../2026-10-30/153829_exercise-explanation-media.md)替代本文件“图片和动画先不加”、非媒体请求与 AC-01 的无媒体限制；仅对已核实身份和许可的媒体生效。其余历史、身份、备份和验证规则保留。
- 后续本地语义复核：`../2026-10-24/091750_opengym-348.md`；只更新本地库与预览，不改变本文件Build31手机交付时的348警示快照或旧真机验收门。

## 用户原始需求

> 先按建议方案整合 OpenGym 动作库，优先用上游 MIT 许可的非媒体数据，中文名称和现有动作做好匹配，保留已有训练记录，图片和动画先不加。

用户确认全量1324条、独立扩展库、选用时加入个人动作、中文名称补齐、歧义不自动合并、完整测试后保留数据覆盖更新手机。

## 目标

2026-10-27本人明确确认以[首页当天训练清理](../2026-10-27/200712_home-current-training-cleanup.md)替代本文件补充AC-08中首页编排/旧周安排入口的位置要求；我的→动作→训练管理的编排导入及原预览/确认/重复导入保护继续保留。OpenGym、历史数据及其余验收范围不受影响。

- 现有动作选择器可搜索和浏览扩展库，支持中文名称、英文名、器械/肌群筛选及中英文参考步骤；用户可复用明确一致的已有动作，或确认单位后加入新动作。
- 固定MIT上游版本，保留版权声明；浏览不批量实例化个人动作。
- 保留全部已有动作身份、人工确认别名、计划、完成组和计量口径，含10/23的48条实际及R6原处方/丢弃草稿/替代标记。

## 非目标与边界

- 不接入媒体、媒体路径或远程图片请求；不复制OpenGym后续AGPL文字或代码；不采购、不外联。
- 不自动合并UUID或accepted canonical ID，不改写历史快照，不调整训练或恢复偏好。
- 手机先备份后覆盖安装；禁止卸载、清容器、直接改活动SQLite。没有commit/tag/push授权。
- 无法从源数据确定的单位由用户选择；辅助重量和单侧/每侧不能作为跨动作等重依据。

## 当前事实

- 上游 `hasaneyldrm/exercises-dataset` 固定commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd`，1324个唯一ID、1318个唯一英文名；6组同名条目不能按名称去重。
- 全部有中英文说明，源名称仅英文；中文名称需X-Fit本地补充。上游肌群/步骤可能与名称不一致，不能当已专业审校资料。
- 2026-10-23实际阅读固定版本LICENSE/NOTICE和全量JSON；非媒体names/categories/equipment/muscles/instructions为MIT，媒体单独授权。来源与原始JSON指纹见 `data/external-exercises/source.json`。
- 现有 `ExerciseCatalogService` 和术语审核区分搜索别名与确认身份；旧合并规则继续有效。
- 12:58手机快照25表2489条业务记录，含211条Exercise。该快照用于开发保护基线；安装前须重新读手机，不能视作实时数据。
- 工作树有其他未提交UI改动；手机版候选从已安装build28隔离基线追加本需求文件，避免部署无关预览。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| AC-01 | 来源完整且无媒体 | P0 | STATIC/UNIT/BUILD | 1324唯一来源ID，固定版本/指纹/许可，严格白名单，无媒体字段/资源/请求 |
| AC-02 | 中文与双语检索 | P1 | UNIT/SIM-UI | 全部中文名称非空，英文原名和变式保留，中英文/器械/肌群检索可用 |
| AC-03 | 安全匹配已有动作 | P0 | UNIT/SIM-UI | 已有动作优先，器械或变式冲突不自动复用；歧义候选需选择，不改历史身份/PR |
| AC-04 | 新增与幂等 | P0 | UNIT/SIM-UI | 浏览写入零，确认单位后新增；重复选用同来源同单位不重复；变更名称后仍可追溯来源 |
| AC-05 | 旧数据保护 | P0 | UNIT/SIM-DATA/DEVICE-DATA | 所有既有UUID/值/关系和文件守恒；48实际及R6状态保持；原计重口径不改 |
| AC-06 | 可用流程与署名 | P1 | SIM-UI/DEVICE | 入口、详情、匹配、新增、取消、来源许可可到达；正常中文界面可读 |
| AC-07 | 安装交付分层 | P0 | STAGE/DEVICE | 完整non-device及device统一入口；备份/覆盖安装/版本与数据回读；人工体验独立报告 |
| AC-08 | 恢复已确认旧入口 | P1 | SIM-UI/DEVICE | 首页依原条件显示周安排；管理区持久入口可达既有预览、确认和查重导入 |
| AC-09 | 训练中调整菜单入口可用 | P1 | SERVICE/SIM-UI/DEVICE | 排序页入口启用且进入原编排页；排序、零完成组调整、完成组与同场次重启保护保持 |
| AC-10 | 首页前台回今天 | P1 | SIM-UI/DEVICE | 首页存在未结束场次仍回今天，详情/输入/改期日期保护、继续训练和实际组保持 |

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 全量外部动作 vs 已有人工合并身份/历史 | 自动同名合并会污染建议 | 是否改变历史身份 | 保留现有身份，扩展库独立；只复用明确匹配，歧义供选择 | 已确认 |
| C-02 | MIT非媒体 vs 媒体/后续AGPL | 许可范围不同 | 引入范围 | 仅MIT原始非媒体及X-Fit翻译；无图片动画 | 已确认 |
| C-03 | 缺中文名/源数据内部矛盾 vs 中文覆盖 | 不能把推断当确认 | 不确定条目处理 | 补中文名并保留英文与待核对说明；禁止自动匹配含糊变式 | 已确认 |
| C-04 | 新需求真机更新 vs 旧手机更新授权仅含R6修复 | 安装范围不同 | 是否本轮更新手机 | 明确确认保留数据更新手机 | 已确认 |
| C-05 | A V3遗漏周编排/确认导入入口 vs 已确认旧功能保留 | 全量回归无法进入既有编排流程 | 是否恢复原条件首页周安排与管理区持久入口 | 2026-10-23用户明确“同意恢复原入口，继续更新手机”；只恢复访问，不自动导入 | 已确认 |
| C-06 | 训练中排序列表禁用调整菜单入口 vs 既有菜单调整功能 | 零完成组/已有完成组均无法进入原编排页 | 是否纳入最小入口修复 | 2026-10-23约15:41本人明确“同意最小修复，继续保留数据更新手机”；仅恢复同一入口，服务和数据模型不变 | 已确认 |
| C-07 | A V3首页以库内未结束场次阻止前台回今天 vs 训练体验AC-07 | 首页浏览历史日后回前台仍停历史日 | 是否仅修首页保护条件，保留详情/编辑/改期与场次数据 | 2026-10-23约15:58本人明确“同意最小修复，继续更新手机”；只限首页保护条件一行 | 已确认 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 实际验证 | 状态 |
|---|---|---|---|
| AC-01/02 | data/external-exercises、资源生成脚本、ExternalExerciseCatalogService | 1324全量覆盖；r7完整单元与独立UI通过；手机Release资源字节一致 | 本地与安装包PASS |
| AC-03/04/05 | 外部目录服务、选择器、单位确认 | 安全匹配/重复选用/重命名/历史保护服务及UI；手机全字段守恒 | 自动化已执行层PASS |
| AC-06 | 扩展库列表/详情/来源许可 | r7完整独立UI通过；主预览真实数据正常入口1324可见 | DEVICE-UI BLOCKED_ENV；人验待完成 |
| AC-07 | 阶段计划与统一脚本 | non-device全PASS；手机31覆盖安装/单元/Release恢复/数据设置回读PASS | 真机UI及人验未通过，非GO |
| AC-08/10 | EditorialHomeViews、PlanView | 周安排/管理区入口、前台今天与过去改期保护完整SIM-UI通过 | 真机自动化待验 |
| AC-09 | ActiveWorkoutView原排序页导航 | 零完成组/已有完成组/重启/排序保护完整SIM-UI通过 | 真机自动化待验 |

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| AC-01/02 / 静态与资源 | 全量来源/许可/白名单正确 | 1324唯一ID/中文覆盖完整，348待核对；手机主包/扩展签名、许可及JSON一致 | PASS | data/external-exercises/source.json；artifacts/stage-validation/20261023-opengym-device31/package-and-install-verification.json | 无媒体；同名按来源ID保留 |
| AC-01…05 / 单元服务 | 匹配/新增/历史保护 | r7完整496项，0失败/0跳过 | PASS | artifacts/stage-validation/20261023-opengym-combined31-r7/N05.log | 不替代设备层 |
| AC-02…06/08…10 / 独立SIM-UI | 新库及既有功能完整回归 | 167项：159通过，8既有跳过，0失败 | PASS | 同r7/N06.log | 7旧休息功能与1专用真实预览场景按原条件跳过；早期失败保留 |
| AC-05 / 主预览 | 手机副本正常启动且守恒 | Build31，17:46:39手机快照；25表2489条全字段一致；正常启动/云关闭；浏览1324并取消后仍一致 | PASS | artifacts/stage-validation/20261023-opengym-main-preview31/final-verification.json；outputs/simulator-real-data/20261023-175831/result.json | 单向快照，手机写入0 |
| AC-07 / non-device | 完整统一入口 | N01/N02/N03/N03B/N04/N05/N06/N07全PASS；正常偏好前后完全一致 | PASS | outputs/stage-validation/20261023-opengym-combined31-r7/summary.md；对应full-preferences-conservation.json | 全量本地层通过 |
| AC-05/07 / 手机安装与数据 | 备份、覆盖安装、Release启动与回读 | 30→31；安装后及测试后25表2489条全部业务字段/身份/关系与4份非数据库文件一致；48完成/R6 skipped、正常设置保持 | PASS | outputs/stage-validation/20261023-opengym-device31/data-conservation-post-install.json；data-conservation-post-tests.json；artifacts同run/final-delivery-verification.json、preferences-conservation-post-tests.json | 本次快照照片/外部载荷0，未宣称非零图片实测 |
| AC-07 / 手机单元 | 全量执行 | 496项，491通过、5主机文件专属跳过、0失败 | PASS | artifacts/stage-validation/20261023-opengym-device31/D07A.log | 5项在non-device均已执行通过 |
| AC-06…10 / 手机UI | 完整真机UI执行 | XCTest控制通道拒绝，runner code74；0用例执行；原脚本D07B FAIL exit65保留 | BLOCKED_ENV | artifacts/stage-validation/20261023-opengym-device31/D07B.log | 原因未知；用户选择先用31，真机UI稍后，不重复无线全量重试 |
| AC-06/07 / 真人体验 | 本人实际使用 | L01–L04及原关键项待本人填写 | BLOCKED_HUMAN | docs/X-Fit_真机人工测试清单.md | 安装成功不代替人验 |

## 已执行动作

- 只读核对全量上游JSON、许可、当前选择器/术语/编辑/去重规则；用户确认后归档本需求。
- 只提取明确非媒体字段到固定版本源文件；中文命名分三块独立产物，Coordinator串行合并，其他共享状态由Coordinator写入。

## 结果与遗留项

- 已交付：手机0.5.0（31）已保留数据覆盖安装并恢复正常Release；1324条非媒体扩展库、中文名称/双语说明、筛选、安全复用与确认单位新增已接入。另聊天的过去待练改期入口和本轮三个已确认旧功能修复同时保留。
- 数据：安装前后、测试后、最终手机快照全业务字段守恒，Notes48与R6保持；正常App设置一致。主预览已以17:46:39手机快照正常启动并浏览新库，退出后2489条仍完全一致。
- 未完成：真机UI自动化BLOCKED_ENV（0用例）与本人体验BLOCKED_HUMAN；需求保持“真机待验收”，阶段非GO。用户明确选择“先使用 Build 31，真机 UI 稍后”。未来设备连接条件改变时先做单条UI探测，通过后完成全量真机UI；任何新测试后仍须恢复Release和核对数据设置。
- 当前权威证据：本文件分层验证、阶段计划及对应r7/device31/main-preview31结果；以下为保留的执行历史，不代表当前状态。

- 专项证据：`outputs/test-results/20261023-opengym/targeted-unit.log` 83项通过；最终资源/服务12项通过见 `targeted-ui.log`。专项UI首次定位筛选/原生搜索关闭控件失败，按AX实际Close修正测试；`ui-close-control.log` 余下2项通过，已有动作复用见 `targeted-ui.log`。未更改产品断言。
- 早期build29冻结及原始范围见 `artifacts/stage-validation/20261023-opengym-nondevice/frozen-inputs.json`；当前候选以本文件末尾r7实际验证为准，不能安装旧29。

- 全量门发现现有空云恢复仓在allowInitialSeed=false时仍运行Notes补充（N05现有断言失败）。按现有保护规则给SeedDataService加hasExercises护栏；已有库路径保持不变。首候选UI在该P1确认后停止，保留失败及部分验证，不作为最终验收；候选r2补齐5份仓库已有的host-only测试输入，避免因冻结源码在/tmp而漏验。

- 补充确认后实现：首页沿用原有未导入/占用/已关联判断恢复“安排本周/继续安排本周”，保留训练编排入口；我的→模板与动作新增“训练编排与导入”。不修改导入服务、已确认计划或历史数据。补充验收 AC-08：两条公开访问路径及原预览/确认/重复导入保护通过独立UI验证。

- 2026-10-23本人明确授权跨聊天协调，最终保留过去待练改期与OpenGym。安装串行：另聊天先交付Build30；本轮最终候选在其已确认2个UI增量上整合，使用高于30构建号并重新完整验证。安装前核对其交付证据与实际手机版本，不安装旧29候选。
- 恢复入口定向验证：周安排+管理区持久入口通过；原导入页可进入。旧编辑路径44pt断言发现日期菜单“管理安排”AX仅14.3pt，给现有44pt布局补contentShape并明确最小宽度，保持业务操作不变；不删断言。

- 组合Build31冻结：`/tmp/xfit-opengym-build31-source`，173项输入及13项生产路径增量见 `artifacts/stage-validation/20261023-opengym-combined31/frozen-inputs.json`。EditorialHomeViews通过以28为共同祖先的三方并集验证；ScheduleView与已确认30字节一致；数据模型与ScheduleService不变。DEBUG新增/修正fixture仅用于隔离测试。此冻结尚未完成最终阶段，不表示可安装。

- 14:53另聊天已释放手机安装窗口，已只读核验其 `outputs/stage-validation/20261023-past-reschedule-phone/delivery.json`：手机Build30，25表2489条及4份资源全部原字段不变，48实际与R6保持。当时本轮尚未安装；后续device31已独立核对实际版本并重新备份，见上方当前结果。

- AC-09证据与最小实施：两份完成r2失败AX均停在动作顺序页，入口Disabled，证据与草案在 `artifacts/stage-validation/20261023-opengym-combined31/active-menu-proposal/`。本人确认后将该导航改为独立按钮状态导航，目的地仍为原DailyWorkoutBuilderView，列表排序模式保留。退出条件为两条调整用例、排序回归、完整阶段和手机守恒通过；不扩服务/模型/计划语义。
- 首组合31完整UI已终态167项、35失败、8项既有跳过；原FAIL保留。496项单元通过；UI失败逐项区分改版后测试路径、已批准菜单入口缺陷及待决定首页日期回归。r3专项中菜单零完成组删除重启、已有完成组保护与摘要重排已通过，尚不替代完整阶段。
- 本人确认C-07后，仅将EditorialTrainingHomeView的hasActiveSession保护限定为showActive且存在进行中场次；isEditing/isShowingDetail与通用TrainingDateSelection未改。原5秒前台回今天断言保持，待专项及完整阶段验证。
- 真机验证准备仅修测试隔离：三个旧单元类在临时关闭提醒后恢复原UserDefaults值（含原未设置状态）；不修改正常App偏好或通知逻辑。统一non-device入口沿用device已有的关闭额外系统诊断参数，保留全量用例、原断言、xcresult及附件，解决测试终态后诊断打包不退出的实际环境问题。

- r5已知回归专项18项终态16通过/2失败：已确认菜单/首页日期、大字号完整说明、Seated Dip按当前组数、原周编排、周期导出、备餐、恢复、跳绳与4条过去日程改期通过。剩余为动作编辑取消后返回与容量趋势控件定位，保留失败待AX核对。
- 设备测试隔离补充：DEBUG且--ui-testing时仅SwiftUI AppStorage使用独立UITestingPreferences域，避免测试动作展开状态/工具展开状态覆盖正常用户设置；正常Release仍standard。最终候选完整UI前后须核对正常偏好域，当前尚未验证此补充。
- 最终r7统一non-device入口N01–N07全部PASS：496单元0失败0跳过；167 UI中159通过、8既有跳过、0失败；无签名iPhoneOS Release构建PASS。完整单元/UI前后正常偏好字典完全相同，测试域独立实测通过。173项冻结输入及15项生产路径见`artifacts/stage-validation/20261023-opengym-combined31-r7/frozen-inputs.json`；结果见同目录results.tsv。当时手机仍为30、device尚未安装；现已交付31，见上方当前结果，人工L01–L04继续BLOCKED_HUMAN。
- 手机device已执行D00–D06C：新鲜备份25表2489条、Notes48完成与R6 skipped保留；签名Release31覆盖安装/正常参数启动/版本回读PASS。安装前后25表全部原业务列、PK、UUID、关系、JSON、NULL及4份非数据库文件完全相同；正常偏好字典相同。证据`outputs/stage-validation/20261023-opengym-device31/data-conservation-post-install.json`及对应artifacts。当时真机测试运行中；现单元491通过/5跳过/0失败，UI启动前环境阻塞；Release恢复、最终回读及主预览刷新已完成，见上方当前结果，阶段仍非GO。

- 最终收口：用户决定真机UI稍后；未重试设备或变更手机设置。D07B原始FAIL保留，按失败发生层归因为BLOCKED_ENV；无产品用例执行证据。主预览首次重签未生成模拟器嵌入entitlements，刷新在数据替换前安全退出；改用同r7冻结输入的Xcode正常签名构建后App Group回读和真实数据刷新通过。手机签名Release未受此模拟器包装问题影响。

- 2026-10-24后续本地复核：剩余345条外部交叉核实及UI紧凑呈现，见`../2026-10-24/100221_opengym345.md`。本地新增解除10、保留335、15改名；不更新手机，不改变本需求的旧真机UI/人工待验门。

## 2026-10-24 Build32后续交付

- 已按独立确认无线覆盖32，继承31功能并加入两轮动作库修正/紧凑UI，当前手机全业务字段及偏好守恒；真机UI仍为控制通道环境阻塞，人工待验。见`../2026-10-24/202853_build32-ui.md`与Build32阶段计划；不将原31历史结果改写成新设备验收。
