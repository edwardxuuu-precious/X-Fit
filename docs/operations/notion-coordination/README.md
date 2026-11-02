# 多项目双 Notion 工作区：协调底座与显式接入 0.2

本入口让 AI 按项目确定目的地，保存一次反馈，并以同一意图恢复。它不是共享 Notion 插件的认证切换器，也不是手机实时上传服务。

权威范围：[原协调底座需求](../../requirements/2026-10-07/102225_notion-global-coordination.md)与[接入软件增量](../../requirements/2026-10-07/194550_notion-coordination-connection.md)。任务投影：[NGC-R1](../../../outputs/planning/notion-global-coordination-r1.tasks.json)。固定候选配置：[registry.json](registry.json)。原项目档案、绑定和调用器保留，不复制旧库；Notion 协作内容不直接成为 App 或项目规则。

## 1. 当前可用与不可用

- 可用：本地确定性路由、固定 profile 公共适配、项目私有反馈、持久索引队列、预览版本保护、两区替身执行与只读恢复、有限统一验证。
- CLI 开放 `status / resolve / record / preview / doctor / apply / reconcile`，默认 `offline`；不会因有网络代码而启用真实访问。没有 `token / auth-switch / force` 命令。
- `FixedProfileClient` 仍没有默认 transport 或 credential reader。新增 runtime 只有在显式模式、私有 access 文件、匹配固定 profile 和目标、实际 route 读写门全部满足后才构造连接；读路径强制 `write:false`。主配置仍全关，真实凭证读取及 Notion 请求未执行。
- fixture 贯穿结果标明 `fixture_only_not_live`；engine 单元中的 live 分支替身也只是逻辑验证，不能当真实身份/权限证明。真实模式预览与回执不能复用 fixture 证据。
- 未完成：真实 bot、专用凭证和对象权限核验、私有范围核验、具名线上写入、两个真实会话采用与本人体验。代码可调用与真实使用通过分别记录。
- 旧调用器、共享插件、原生窗口、其他 host 和人工编辑尚未强制接入；本机队列只能约束采用它的调用，不宣称全局互斥。

## 2. 用户场景与 AI 调用

用户日常不需要手写 JSON 或切到 Notion 录入。授权接入后，预期是用户在相应项目对话说“保存这次反馈”，AI 完成路由、构造来源与稳定 ID、预览、有限提交、回读和报告；当前本地版已具备保存与验证机制，尚未启用真实同步或修改全局 skill。

AI 调用步骤：

1. 读取所属项目当前真源和本轮授权。确认是反馈、观察或待确认建议；不能把意见直接升级成正式规则。
2. 用明确 `projectId` 或唯一 root/subproject 解析；两候选共用目录时要求业务子项目，不猜目标。未知目的地停止相关提交。
3. 在该项目内准备来源明确的意图。保留用户来源，生成稳定 `operationId` 与 `recordId`；秘密不进入正文、命令或配置。
4. `record` 先保存完整私有意图，再登记公共索引。重复同意图新增为零；同 ID 改内容保留冲突，不覆盖旧记录。
5. 按当前层级报告 `saved_local / blocked_access / conflict / result_unknown / readback_verified`；当前 `record` 成功只代表本地已存。
6. 显式接入后，每次有限写入先验证 identity、完整对象和已批准范围，绑定预览指纹；写后回读通过才显示同步完成。丢响应先核实，不要求用户重录。当前真实连接尚未核验，不得把模拟结果报告为同步成功。

原 T3 三库创建和初始关联仍是原需求的独立任务。本框架不建立这些库、不重建原八条绑定，也不关闭 T3/T7。

## 3. 本地命令与输入合同

从项目根目录执行（Node 24 的 `node:sqlite`）：

```sh
node scripts/notion-coordinate.mjs status
node scripts/notion-coordinate.mjs resolve --project fitness-app
node scripts/notion-coordinate.mjs resolve --project football
node scripts/notion-coordinate.mjs doctor --project fitness-app
node scripts/notion-coordinate.mjs record --project fitness-app --input <项目内已准备的JSON文件>
node scripts/notion-coordinate.mjs preview --project fitness-app --operation <同一稳定ID>
node scripts/notion-coordinate.mjs status --queue <明确的本机私有队列绝对路径>
node scripts/notion-coordination-validate.mjs
```

`status` 不指定队列时只读候选配置，不创建默认队列、不读钥匙串；指定队列可查看或初始化该私有索引。`doctor` 不使用队列、不创建 outbox，离线时直接报告具体门。其他操作默认队列位置为 `/Users/edward/.codex/coordination/notion-projects.sqlite`，各项目共同使用同一 host-local 路径才能共同仲裁。开发测试均显式使用隔离临时目录，没有初始化默认队列。`--queue` 用于测试/具名实例，不能用另建队列绕过同资源租约。命令专属参数、路由、来源/既有意图及 access 先校验，随后才打开所需队列；错误输入不应创建队列或待发送目录。

具备**另行核验**的真实授权后，AI 使用同一入口：

```sh
node scripts/notion-coordinate.mjs doctor --project <明确项目ID> --mode live --access <项目内私有access.json>
node scripts/notion-coordinate.mjs preview --project <明确项目ID> --operation <同一稳定ID> --mode live --access <项目内私有access.json>
node scripts/notion-coordinate.mjs apply --project <明确项目ID> --operation <同一稳定ID> --mode live --access <项目内私有access.json> --owner <当前会话ID> --approval <该预览的SHA256>
node scripts/notion-coordinate.mjs reconcile --project <明确项目ID> --operation <同一稳定ID> --mode live --access <项目内私有access.json>
```

以上是调用合同，不是现在执行的指令；当前主 registry 不能直接执行 live。`--mode fixture` 只接受 `http://127.0.0.1:<端口>`，使用固定假凭证，永不读真实钥匙串。live origin 固定 `https://api.notion.com`，拒绝 fixtureOrigin、任意 URL、重定向与共享认证回退。

access 文件须项目内普通文件、当前用户拥有、无 symlink/额外硬链接、组/其他用户无访问位，通常 `0600`；不是 token 文件。只接受 `schemaVersion:1`、`mode`、`grant`、可选 `executionGrant`，fixture 另有 `fixtureOrigin`。不接受明文 token、密码、环境变量或任意 executable 定位器。凭证引用只来自固定 profile 的既有 Keychain service/account，不从聊天或命令参数采集。

- `grant`：`mode / reference / profileId / workspaceId / read / write / scopeTargets`；scope 必须精确等于选定 target 与已允许的 block IDs，不自动加入发现对象作为写目标。读操作强制降级写能力。
- `executionGrant`：基本 grant 加 `projectId / targetId / operationId / previewDigest / sourceDigest / payloadDigest / routeDigest`。只有 `apply` 使用；所有版本须一致，且 `route.liveWrite` 独立开启。仅一个哈希不是写入许可。
- `reference` 指向真实对话/审批证据。文件是对已有授权的记录，不能证明人类批准、创造 Notion ACL 或代替账号所有人的授权。AI 不得自行把候选 profile 改 verified、生成批准或启用 live flags。
- `doctor` 只返回身份、精确对象、计数、完整性与 schema 候选，不回显餐食/训练/人工正文、不改 registry/ACL/allowed 清单。私有可见性与允许修改范围仍各自核验。

`doctor.evidenceScope` 限定证据：records 是页面枚举完整；schema 是已观察的属性元数据；propertyValues 为 `not_inspected`，不宣称 relation/person/rollup 的属性值全部读取。完整 Markdown 与块树另有完整性检查。查到的数据源子页面及后续块，只沿实际验证的父级展开只读范围，绝不把发现的 ID 加入写目标。

示意输入，不是要上传的实际反馈，也不是正式规则：

```json
{
  "source": {
    "author": "user",
    "kind": "user_feedback",
    "reference": "明确的对话或记录定位"
  },
  "intent": {
    "operationId": "feedback-example-1",
    "kind": "append-record",
    "target": "archive",
    "record": {
      "recordId": "feedback-example-1",
      "title": "本人反馈，待复盘",
      "body": "本人原始反馈",
      "properties": {}
    }
  }
}
```

`source.kind` 只接受 `user_feedback / project_observation / proposed_decision`，可选 `observedAt` 只作来源证据，不作任务排期。`owned-update` 使用具名 property/block 变更；实际允许清单目前为空，不能照示例猜在线字段。源文件必须属于已注册项目，拒绝 symlink、越界、凭证内容与过大记录。

## 4. 记录与恢复

私有意图、预览和回执保存在所属项目 `artifacts/notion-coordination/outbox`，新目录 0700、文件 0600。先完整写入并 fsync，再原子发布；不改宽泛上级目录或原用户文件权限。公共 SQLite 仅存稳定 ID、来源路径/指纹、profile/target/adapter、状态及回执引用，不存个人正文或 token。

| 状态 | 含义 | 后续动作 |
|---|---|---|
| saved_local | 私有内容与索引已存 | 具备访问条件后准备预览 |
| blocked_access | 该项目缺少明确身份/授权/范围 | 解决具名门；不借另一区权限 |
| preview_ready | 内容、目的地与完整读取绑定 | 对应预览获得授权后 claim |
| executing | 一个 owner 持有该批单写者 | 结清 active calls，再保存回执或未知状态 |
| result_unknown | 请求可能已被接受 | 同 ID 只读 reconcile；禁止自动重写 |
| conflict | 原源、route、preview 或人工区域变化 | 保留双方，重新确认新意图；不覆盖旧意图 |
| readback_verified | 指纹与保护区回读通过 | 保留不可变回执；重复意图不再写 |
| cancelled | 该意图明确结束 | 不重开旧意图 |

完整读取有有限预算：query 最多 20 页；块树最多 20 次分页、8 层、1000 块；执行最多 300 次受跟踪调用。wire 默认最多100请求、单请求总时限10秒、响应实际字节2MiB；构造参数硬上限300请求/30秒/8MiB，不是业务排期。超出是未完整，不能按空内容写入。分页游标只透传不透明字符串，拒绝空值/循环/缺完整标志；实体和目标 UUID 校验保持不变。GET 暂时性错误最多三次，无等待提示才重试；429/529 和等待提示停止，不切 profile 规避。写入及 POST 查询不自动重试。

同一 owner 的 active call 也不能并行执行，未结清时不能释放。进程崩溃不按时间过期夺取租约；当前 CLI 没有 force/reopen 操作，实际恢复须先核未决结果，不能靠改 SQLite 消除门。

普通反馈无改动重复提交可继续同 ID；同 ID 内容变化不覆盖。source/route/payload 变化使待处理预览失效并记录 conflict。已完成回执不可重开；源内容以后被用户改动，也不能用新内容冒充旧成功。

## 5. 决策、取舍、假设与检验

| 决策/方法 | 当前做法与原因 | 代价/假设 | 检验与暂不做 |
|---|---|---|---|
| 确定性路由 | project/subproject→固定 profile→精确 target，版本绑定本地真源 | 一次性配置成本；本地绑定不能证明远端权限 | 错区/未知远端零；不自动发现或按标题猜 |
| capability 与显式授权分离 | read/update/insert、bot/workspace、目标范围分别验证 | owner 授权仍不可省；grant 本身不创造 Notion 权限 | 错 bot/父级/目标全部停止；不提取共享 OAuth |
| 项目权属分离 | X-Fit append-only；足球 owned-update；人工值保护 | 一套接口不等于通用数据库编辑器 | 人工值/样式/链接回读；不搬旧库、不任意 PATCH |
| 单写者与 FIFO 就绪批 | 同 host 采用者串行写；blocked 项不持锁 | 吞吐保守；绕过入口不受锁约束 | 真多进程/崩溃测试；不做分布式锁或按对象并行 |
| 本地先存与幂等意图 | 私有完整文件先发布，索引后登记；operation ID 可恢复 | 崩溃残留临时文件需审查；不承诺硬盘损坏恢复 | 并发冷启动与重复零新增；不做无限后台同步 |
| 预览绑定与完整回读 | source/route/intent/人工快照变化停；未知写只读核实 | 额外读取；远端无跨对象事务，仍可能并发变化 | 丢响应/局部提交/回读失败不误报；不靠 HTTP 2xx 判完成 |
| TDD 与分层证据 | 公共 seam red→green，再真实进程贯穿；L0–L5 分开 | fixture 无法证明真实 schema、ACL 或本人体验 | 固定统一入口；不把本地测试当线上或手机验收 |
| 依赖驱动有限迭代 | 11任务冻结、就绪集合重算，空集停止 | 外部真门仍由 owner/真实环境解锁 | 每项有出口与回执；后续候选最多三个重点，不按日期续跑 |

可借鉴的实际例子：完整 CLI 首次并发录入揭示了 SQLite identity/version 分步初始化竞争；直接公共进程测试先失败，改为同一事务后通过。另一个并发相同反馈测试揭示文件 `EEXIST`，改为完整私有文件原子不覆盖发布后通过。这些是本轮本地真实结果，不是线上事故、跨项目成熟经验或已激活的全局规则。

## 6. 统一验证与下一门

执行 `node scripts/notion-coordination-validate.mjs`：检查静态、配置/依赖/链接、新公共测试、三次有限额外 CLI 并发探针、旧 X-Fit 工具和固定同步器替身回归、六份原真源写前/写后摘要。结果写到 [统一证据](../../../outputs/test-results/NGC-R1-local/validation.json)，只保存计数/状态/命令/摘要，不存执行输出全文或反馈正文。

保护摘要是本轮新取证基线，不能用于抹掉上轮原循环旧摘要不一致；原异常仍保留在任务投影。以后合法改变这些源须重新具名确认基线，不能自动刷新期望值掩盖漂移。普通 `git diff --check` 不覆盖未跟踪新文件，统一入口另做新文件的空白检查。

下一门是 NGC-08 的真实接入包：每个固定 profile 的 owner 安全授权、精确 bot/workspace、原 target/父级、负责属性/块及私有范围、具名只读范围。先合并现有已知信息，未知项一次汇总；不让用户反复切共享连接，也不让用户在聊天发送 token。软件增量按独立需求验证，不再重复要求确认其开发；真实身份/范围通过后，NGC-09 再核具体线上意图/预览与写入范围，随后是 NGC-10 的真实会话采用及全局 skill 接入确认。

使用共享 connector/native-app 时仍须原 `notion-session-coordination` 协议；本入口不替代其两类租约、未决调用结清和人工作业保护。没有具名真实凭证及对象门，本地就绪不等于线上可用。

当前 API 合同参考 [Notion bot 身份字段](https://developers.notion.com/reference/get-self)、[完整 Markdown 与 unknown/truncated 条件](https://developers.notion.com/reference/retrieve-page-markdown)、[版本与不透明游标](https://developers.notion.com/reference/versioning)、[data-source查询是POST读取](https://developers.notion.com/reference/query-a-data-source)。它们支持边界设计，不证明实际连接配置、远端对象完整性或私有 ACL。
