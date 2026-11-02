# 需求：Notion协调接入软件、受控执行与只读恢复

- 需求 ID：`REQ-20261007-194550`
- 创建时间：`2026-10-07 19:45:50 +0800`
- 来源：用户直接请求
- 用户确认状态：`已确认`
- 用户确认时间：2026-10-07本轮直接指令；精确消息时间未知，归档时间不冒充消息时间。
- 用户确认摘要：`用户要求“你来处理遇到的问题然后继续推进”；执行上一轮已展示第5.5节的本地接入软件包及模拟测试，不授予真实凭证读取、真实Notion请求、线上写入、手机安装、共享认证或全局Skill修改权限。`
- 状态：`本地已验证`
- 关联需求：[原协调底座](102225_notion-global-coordination.md)；[已展示的软件包](../../../outputs/planning/notion-global-coordination-r1.md#55-当前阶段剩余软件一次实施确认包待用户选择)。
- 目标版本/阶段：协调接入本地软件增量；不改变App版本或真实访问权限。

## 用户原始需求

> 你来处理遇到的问题然后继续推进。

本指令沿上一轮已展示的软件包继续实施，仅执行本地代码、项目内调用说明和模拟测试；不把总项目“继续”用作真实凭证、线上写入或手机授权。

## 目标

- 补齐固定HTTP通道、公开连接检查、预览、受控执行、未知结果只读核实和项目调用说明；沿原11任务，不重做已完成底座。
- 场景：同一反馈先本地保存；连接就绪后预览；具体意图获准才写入并回读；失响应先核实原结果，不重复录入。两项目各走原追加/负责区域更新合同。
- 按依赖和证据收口，不按日期排期，不把本地软件通过当成真实免切换使用已验收。

## 非目标与边界

- 不读取、配置或保存真实凭证，不访问真实Notion，不开启原registry的liveRead/liveWrite，不切共享认证、不扩大私有权限。
- 不操作手机、不创建T3三库、不改原8绑定或原循环、不新增训练处方、不搬旧库、不改其他仓库或全局skill。
- 不发布、部署、提交/tag/push；不使用TTL或强制夺取未决租约，不把可调用软件入口视为线上写入grant。

## 归档时事实与本轮证据边界

- 公开CLI四命令，engine仅offline/fixture；profile已有固定身份、明确endpoint/能力与凭证引用门，但没有默认网络transport。
- 原本地测试95/95、旧工具38/38、复用同步器26/26已验证；本轮扩展公开调用后重新走原统一入口。
- 两真实profile的bot/负责字段及足球凭证引用仍未知；保留关闭状态，不靠本地代码补成已核验。
- 官方Versioning明确分页游标为不透明字符串；现代码将其当UUID会拒绝合法分页。只修游标透传与循环/预算检查，不改变实体UUID、目标范围或写入能力。

## 验收标准

| ID | 可检查结果 | 优先级 | 验证层 | 预期结果 |
|---|---|---|---|---|
| I-01 | 默认关闭及旧命令兼容 | P0 | CLI/LOCAL | 默认凭证读取和外部请求0；未知/错区不回退 |
| I-02 | 固定transport与能力分离 | P0 | UNIT/LOCALHOST | 固定origin、拒绝重定向、有限请求/字节/等待、错误脱敏；POST查询是读，不授予插入 |
| I-03 | 连接检查不激活权限 | P0 | SERVICE/LOCALHOST | 核身份、对象、分页、正文完整性和schema；只返回证据候选，不改配置/ACL/允许字段 |
| I-04 | 预览与具体许可绑定 | P0 | CLI/SERVICE | 源/路由/内容/人工漂移作废；live执行须同意图/预览/来源版本grant，缺许可写0 |
| I-05 | 受控执行全链 | P0 | SERVICE/MULTIPROCESS | 两项目模拟写入、完整回读、人工守恒、重复新增0；未结清调用不释放 |
| I-06 | 未知结果只读恢复 | P0 | SERVICE/CLI | 同一operation核实，新增写0；未核实保持unknown，不重发、不TTL夺取；未决崩溃租约明确停止 |
| I-07 | 项目调用 | P1 | CLI/DOC | 两项目同入口、隔离进程交替、一区受阻另一区可保存；不冒充真实会话采用 |
| I-08 | 完整回归与可恢复收尾 | P0 | LOCAL-REGRESSION | 原统一入口覆盖新行为、旧回归、6保护源守恒、版本证据及真实层未验证状态 |

已展示并由本次继续指令承接的公共测试seams：公开CLI、FixedProfileClient+HTTP外部接口、doctor、CoordinationEngine的save/preview/apply/reconcile、原OperationQueue的单写者/未决停止行为；不新增私有SQL测试缝。

## 冲突与用户决定

| ID | 冲突双方 | 影响 | 需要用户决定的问题 | 用户决定 | 状态 |
|---|---|---|---|---|---|
| C-01 | 原本地底座与新增接入软件 | 软件范围 | 是否把本地能力等同真实授权 | 本次仅补本地能力；真实操作分列 | 已确认兼容增量 |
| C-02 | 游标UUID校验与官方不透明游标合同 | 合法分页读取 | 是否改变实体或目标范围 | 仅透传游标并保留有限/循环检查；不放宽实体UUID或目标范围 | 已检查，接口兼容修复 |
| C-03 | 能访问对象与允许修改范围 | 数据所有权 | 能否自动从读取schema生成写权限 | 不能；证据候选与允许字段分开 | 沿已确认边界 |

## 实现映射

| 需求/验收 ID | 代码或文档 | 测试 | 状态 |
|---|---|---|---|
| I-01/04/07 | notion-coordinate.mjs；runtime.mjs；无副作用解析helpers | 原CLI5、新CLI5、runtime3；两独立进程共用队列 | 本地PASS |
| I-02/03 | transport.mjs；profiles.mjs；doctor.mjs | transport9、profile34、doctor12；实际localhost接口 | 本地PASS |
| I-04/05/06 | engine.mjs；adapters.mjs | engine11、execution18（含子测试）、adapter26、原queue23 | 本地PASS |
| I-08 | 原统一验证入口、本需求及原任务投影 | 全152、旧38/26、三批2/2、6保护源与复用源守恒 | 本地PASS |

调用合同正文只在[运行手册](../../operations/notion-coordination/README.md)维护；计数、命令、I-01–08映射、版本与保护源摘要只在[原统一证据](../../../outputs/test-results/NGC-R1-local/validation.json)维护。原11任务不增加，本需求是其软件子交付，不是另一套任务真源。

## 分层验证

| AC ID / 层级 | 预期结果 | 实际结果 | 状态 | 证据 | 说明 |
|---|---|---|---|---|---|
| I-01–08 / L0 | 合同/静态/默认入口一致 | 23份JS静态、文档/图/链接/默认关闭通过 | PASS | 原统一入口 | 不执行App固化 |
| I-01–08 / L1 | 公共interface关键正常/失败行为 | 152/152、旧X-Fit38/38、复用同步器26/26；无跳过 | PASS | 原统一入口 | 包含子测试，不虚称独立研究链 |
| I-02–07 / L2 | localhost两区与进程贯穿 | 两项目完整CLI、重复写0、失响应只读恢复；三批并发2/2 | PASS | 原统一入口 | 不使用真实凭证 |
| L3 / 真实身份/范围 | 两区具名验证 | 软件已就绪；bot/owner授权/对象范围仍未核验，未运行 | BLOCKED_ENV | 后续独立核验 | 不启用registry；不是软件缺口 |
| L4 / 真实写入/回读 | 具体意图与完整回读 | 本需求不授权写入 | NOT_RUN | 后续具体预览/grant | 不由软件确认解锁 |
| L5 / 真人使用 | 两真实会话免切换/重录 | 尚未进行 | NOT_RUN | 本人体验 | 不以模拟替代 |
| App/设备/训练效果 | 不在本增量范围 | 未执行 | NOT_RUN | 原各自需求 | 原门不变 |

## 已执行动作

- 已读取当前规则/手册、原需求、CLI/engine/profile/adapter/queue及已展示5.5合同；保留脏工作树及原源边界。
- 已通过项目模板生成本需求，记录本次直接继续指令和限定范围；尚未操作真实凭证、Notion、手机或共享认证。
- 已按公共接口red→green补齐doctor、HTTP/runtime、live执行/恢复与游标兼容；新增无副作用读入口，CLI在错误输入校验前不再初始化queue/outbox。
- 已修复source查询后子页面块树只读遗漏、多target误读、live错误approval、fixture回执跨mode误用、提交后本地结算失效及未决租约处理。存储未结清时明确停止，不伪称自动解锁。
- 已通过实际localhost与独立CLI进程验证X-Fit追加、足球负责区域更新、人工字段守恒、重复提交写0、失响应后同operation只读恢复；假凭证仅用于替身，不读取真实Keychain。
- Coordinator已汇总两个实现分支及独立只读审计；按原入口全量回归，I-01–08均本地PASS，六保护源及复用文件不变。原95基线保留为历史结果，不冒充当前计数。
- 已更新仓库内调用手册及原任务投影，仅移除已满足的软件缺项；未把NGC-08/09/10或原T3/T7关闭。

## 并行/串行边界与分工

- 独立代码分支可并行：transport/doctor/profile兼容，engine/adapter执行恢复；第三分支只读审计安全和反例。
- Coordinator串行维护CLI/runtime、原统一验证、需求/任务投影、最终证据与本轮唯一Context Router收尾。

## 决策、取舍和停止条件

- D1 复用旧profile/adapter/queue，小公开interface承载完整行为；不另建认证体系或调度器。
- D2 software确认与实际操作grant分开。代价是线上使用仍要安全授权；收益是默认0真实访问、不能因doctor自动开放写权限。
- D3 localhost作为当前验证层，真实域名固定且默认关闭；本地通过不证明Notion ACL、真实工作区采用或手机效果。
- 停止：源/路由/人工内容漂移、错身份、读取不完整、无具体许可、未知结果或未结清租约，停止相关动作而保留意图。
- 暂不做：跨host/按对象多写者、后台无限同步、强夺崩溃租约、全局skill安装、手机实时上传和新私有父页选择。

## 已确认问题与解决结果

| 问题/decision | 最小解决 | 取舍及结论上限 |
|---|---|---|
| 错误输入开queue、缺operation建outbox | public inspect/read在构造queue前无副作用校验 | 保留正常显式status --queue初始化，不泛化为所有调用零本地写 |
| 合法opaque游标被UUID拒绝 | 字符串原样透传/URL编码；跨页循环和预算仍停止 | UUID实体/父级不放宽；官方API合同不是当前远端权限证明 |
| query子页根树缺只读权限 | 仅正确source父级的已观察页可GET children | 普通POST新页、错parent/跨source不给此能力；发现ID不进写scope |
| fixture多target快照越界 | 两mode都只读取所选target | 不用扩大grant掩盖错误；其余alias不参与该预览 |
| approval或证据层可混用 | 两mode核同approval，preview/receipt核executionMode | fixture不能升级成live；mock live单元也不是L3证据 |
| provider提交后结算失败 | unknown+安全storage原因，未决持久lease保留 | 不能靠TTL/强夺/重发恢复，完整owner恢复工具未实现 |
| doctor“完整”口径过宽 | records仅页面枚举；schema仅观察元数据；propertyValues未检查 | Markdown/块树实际完整另核；不新增property-item端点或声称所有属性值完整 |

方法：项目当前代码优先；限定问题与结论上限；公共接口逐片测量/修复/复测，再跨进程和外部localhost反例。后补已有护栏验证明确记为回归，不冒充实际red→green。API依据：[不透明游标](https://developers.notion.com/reference/versioning)、[Markdown完整性](https://developers.notion.com/reference/retrieve-page-markdown)、[POST数据源查询](https://developers.notion.com/reference/query-a-data-source)。这些引用未晋升为全局知识或真实授权。

## 结果与遗留项

- 当前结论：本地已验证，接入软件缺项已解除；真实访问/写入、全局skill采用、手机/人工/效果门不变。原NGC-08 blocked，09–11 pending；授权执行就绪集合仍为空。
- 下一步P0：NGC-08具名安全授权和固定身份/原对象/负责字段核验；随后NGC-09同一意图预览与具体写入grant，再串行写入/完整回读。不重问已知工作区或原档案ID，不切共享认证、不让用户重复录入。
- NGC-10全局调用/两个真实会话采用及本人体验、原T3私有父页/三库创建器、T7新鲜训练输入、设备安装/真机/本人验收分别继续原需求；本地PASS不替代。
- 本轮Context Router建议跟踪：`adv_43ade246385a4ccdeb037ce26454e188`；实际本地实现与验证满足公开入口/6源守恒/真实动作0三项标准，根turn收尾单独提交，不改知识生命周期。
