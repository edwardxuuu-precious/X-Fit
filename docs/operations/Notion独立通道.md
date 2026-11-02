# X-Fit Notion 独立通道

- 实施范围：[REQ-20261004-195337](../requirements/2026-10-04/195337_notion-independent-access.md)。
- 入口：`scripts/xfit-notion-access.py`；公开配置：`docs/operations/notion-access.json`。
- 当前结论（10/6本地复核）：专用通道可运行但生产凭证未配置，独立在线核验与同步未执行。10/5共享MCP已读到正确原库并匹配8条返回内容；完整性标志缺失，尚非严格可写同步通过。两个通道结果分开，原绑定不变，不再要求反复重连共享插件。
- 10/9剩余项核对：只读`status`再次确认原工作区/数据库及8条绑定保持；`dedicated_credential_present=false`、`private_parent_page_id=null`、`writes_enabled=false`、`remote_calls=0`。这是本机固定通道状态，不是共享插件当前认证或远端权限检查；已连接共享插件不自动配置这条专用通道。

### 10/13 当前恢复与授权说明

- 本人已确认现有 R3 私有规划页 `3f74c857-b834-8004-8a2d-ca7863ccfc2b` 为 T3 父页；不再要求另建空页。原训练档案保留，新增范围仍为1总览、3库、17语义记录。
- **访问令牌不是 Notion 登录密码。** 令牌由 Notion 为内部连接生成；系统隐藏输入只是保护令牌，不表示索要账号密码。尚未创建令牌时不得打开输入框让本人猜填。
- 共享 MCP 与本机专用脚本是两条不同的授权通道。现有 MCP 可直接执行其已授权工具，不必把插件凭证导出给本机脚本。独立连接用于避免多项目工作区切换影响固定调用，不是当前所有业务工作的必需前置。
- 本轮先核验既有 MCP 的身份、准确父页和创建权限，沿共享使用权协议推进已确认 T3；不重新登录、不切换共享认证、不扩大页面访问。专用传输实现作为已准备的独立备选保留，尚无真实令牌/在线验证。
- 本次令牌输入已取消，未保存新凭证、未发生该通道远端调用。MCP 请求 `XFIT-T3-EXISTING-CONNECTION-20261013-01` 正常入队；取得有限租约前不调用，不能把排队写成同步成功。
- 本批结束没有取得使用权，只取消本人该connector请求及旧9/23原生等待请求，均未有实际调用；不取消其他项目，不留空占队首。恢复用新的就绪有限批次入队、核验现有MCP，不再次盲开令牌输入。
- 本地真实传输入口 `scripts/xfit-notion-live-workspace.py` 已具备准备、预览、受控创建、未知结果恢复和回读；本地55项边界检查通过只证明实现，不证明线上创建或两个工作区实际采用。

下文 `private_parent_page_id=null` 和“尚未实现线上创建器”保留为原版本历史，不作为当前缺口。当前身份/范围/写后回读仍须实际验证。

## 1. 解决什么问题

让 X-Fit 的档案读取、差异预览和受控追加不再依赖 Codex 共享 Notion 插件当前选中的连接。脚本直接使用官方 HTTPS API 和 X-Fit 专用内部连接，可在 Mac 终端独立运行，也可由 Codex 调用。

内部连接固定属于一个工作区。因此 Notion 窗口或其他项目切换工作区，不应改变该连接的目标；这项远端行为仍需首次真实连接验证。旧插件认证为何未切换的原因未确认，本通道不修改旧插件，不把绕开依赖当作查明旧问题。

它不是后台服务器、定时任务或手机接口；不声称能在手机未连接时取得训练实际。

## 2. 固定对象与归属

| 对象 | 目标/规则 |
|---|---|
| 工作区 | Edward’s Notion，`c63f367d-6f39-41c0-9a28-e4ad2ce10251` |
| 原训练档案 | [原数据库](https://app.notion.com/p/6d6b5fb7de5c446aa5038b6462833486)，`6d6b5fb7-de5c-446a-a503-8b6462833486` |
| 原数据源 | `09fd5db5-21f6-4d39-869d-e3ad0b2f444e` |
| 绑定和内容 | `docs/training/notion-sync-state.json`、`archive-records.json`；现有 8 条，不自动迁移或重建 |
| 专用凭证 | macOS Keychain：service `com.xfit.notion-access`，account 为目标工作区 UUID |
| 新框架工作台 | 独立对象；蓝图在 `notion-blueprint.json`，尚未创建 |

App 保存真实训练；仓库保存已确认规则和代码；Notion 保存协作和受控镜像。传输方式改变不改变这套归属。

## 3. 只做一次的配置

1. 打开 [Notion 官方开发者入口](https://app.notion.com/developers/connections)，创建内部连接 **X-Fit Sync**，选择 **Edward’s Notion**。需要工作区负责人权限；权限不足时由负责人处理，不改用其他工作区。
2. 初次核验只需 **Read content**。在连接的 **Content access** 授权原“X-Fit 训练档案”；若界面通过页面菜单提供连接授权，使用该页面的“添加连接”入口。不要授权无关顶层页。
3. 复制专用 API 凭证，在本机执行以下安全输入命令，或由 Codex 打开同一个窗口。**不要把凭证发到聊天、放在命令参数、环境变量或项目文件中。**

```bash
python3 "/Users/edward/Documents/Fitness App/scripts/xfit-notion-access.py" auth-set --dialog
```

窗口隐藏输入；脚本先核验工作区、原库及数据源，正确才写入专用 Keychain 项。取消、错误工作区、401/403/404 或不可访问时停止，不保存错误凭证、不新建替代档案。已有凭证只有明确使用 `--replace` 才能替换。终端交互也支持不回显的 `auth-set`，不接受管道传入令牌。

将来确有本次授权的新版本需要追加时，才启用 **Insert content** 并核实私有访问范围。旧快照不开放更新或删除，本期不需要 Update content。API 可读不能证明页面未共享，私有权限必须另外确认；不能用 `doctor` 的 PASS 代替隐私确认。

## 4. 每次调用的完整流程

在仓库根目录运行，下列读取不需要再操作共享插件：

```bash
python3 scripts/xfit-notion-access.py status
python3 scripts/xfit-notion-access.py doctor
python3 scripts/xfit-notion-access.py snapshot --output artifacts/notion-independent/current-snapshot.json
python3 scripts/xfit-notion-access.py preview --output artifacts/notion-independent/current-preview.json
```

- `status`：只读本地配置与专用凭证元数据，不联网；显示目标、8 条绑定和当前写入开关，不代表远端已通过。
- `doctor`：读取 token 的 bot 身份、确切原数据库和数据源。凭证缺失时直接返回一个恢复动作，远端请求为 0。
- `snapshot`：完整分页查询、逐页读取属性和 Markdown，再盘点一次检测漂移；保存来源时间和人工字段。
- `preview`：基于新鲜快照调用原离线训练档案规则，输出 create / adopt_existing / no_op / conflict 与预览指纹。内容或身份有冲突时不可执行。

完整快照、预览和回读候选只写入 `artifacts/notion-independent/`，新文件权限 0600；常规终端输出不打印照片、凭证或完整个人正文。建议使用带轮次的文件名保留证据；重复使用 `current-*` 只更新本地检查产物，不改原绑定。

### 受控追加，不是自动同步授权

默认 `writes_enabled=false`。实际写入必须同时满足：用户已确认的具体新版本／稳定ID、真实目标和私有范围核验、无冲突预览、明确开启配置写入、匹配当前预览指纹、逐条允许的记录ID以及 `--allow-write`。

命令形态如下，尖括号须替换为当前预览和已确认 ID，不能直接复制执行：

```text
python3 scripts/xfit-notion-access.py sync \
  --confirm-preview <当前preview_hash> \
  --allow-record <本次已确认的新档案ID> \
  --allow-write \
  --output artifacts/notion-independent/<本轮回读结果>.json
```

若预览中还有未授权的新记录，本批整体停止，不悄悄扩写。只创建新档案ID，不 PATCH / DELETE 旧快照，不写“我的备注”和“建议调整”。每次创建前重读，之后完整回读并核对原记录守恒，重复执行新增应为零。

脚本返回 `verified_binding_candidate`，**不自动替换原 `notion-sync-state.json`**。Coordinator 需核对新回读、冲突和确认范围后才能登记新的绑定版本；读取成功或 `can_apply=true` 不代表批准登记或写手机。

### 请求结果不确定时

创建意图和结果保存在本机专用运行目录 `~/Library/Application Support/XFit/Notion/<workspaceUUID>/write-journal.json`，不含凭证或个人正文。写入超时不自动重发；重新取得新预览，只有同一稳定ID、内容和返回页身份能核实时才恢复确认。若查不到或不一致，停止人工检查，不换ID重建。

同一台 Mac 的专用通道用文件锁串行批次；这不代表所有跨机器或人工修改均被锁住。Notion 没有本工具可用的原子 CAS，写前／写后检测可以降低风险，不能承诺并发零风险。

## 5. 新工作台为何单独留一道门

“原训练档案可读”与“新建项目总览和三个库”是两个交付物。内部连接不能创建用户根级 private page，需要具体父页。当前配置的 `private_parent_page_id=null`，因此新工作台仍未创建。

要完成原 T3：由用户在 Edward’s Notion 新建一个空的私有容器页，授权 X-Fit Sync，并提供该页链接；核对确切 ID 和私有范围后，再按已有蓝图创建／绑定。不能把某条旧训练记录偷偷用作父页，也不能用 PAT 或其他项目凭证绕开归属决定。

若用户指定的是现有空私有容器页，也先核验同一ID和范围，不另建重复页。共享MCP路径按相同已确认合同与使用权协议处理；专用路径另外核验X-Fit Sync访问。用户提供父页链接不等于允许移动或覆盖父页原有人工作业内容。

本版网络脚本覆盖原训练档案通道，不伪装已实现三库在线创建器。2026-10-09已确认并完成独立[本地创建器](Notion工作台本地创建器.md)，仅结构预览/模拟创建与恢复，不加载本通道凭证。真实父页和范围确定后仍须完成线上适配、结构写入和回读，不重建原8条。

## 6. 技能与 AI 怎么调用

- `$xfit-project-loop` → [项目循环手册](项目循环手册.md) → 当前轮状态 → 本文 → 本地 status / doctor / preview。先核实这轮依赖，不再默认要求共享插件重新认证。
- `$xfit-training-coach` → [训练档案工作流](../training/训练档案工作流.md) → 有效偏好和近期实际 → 档案预览。计划仍须完整展示、确认、由 App 支持的入口写入并回读。
- 原 `xfit-project-loop.py` 与 `xfit-training-archive.py` 仍只做离线检查，网络能力没有混入其合同。skill 保存方法；个人数据、账号绑定和版本留在项目。
- 共享插件或原生窗口若另有实际需要，仍先使用 `notion-session-coordination`；本专用 HTTPS 通道不占用、夺取或重连它们。

## 7. 失败、验证与下一步

| 信号 | 必须怎么处理 |
|---|---|
| credential_missing | 一次创建、授权和安全输入；不得借用全局令牌 |
| workspace／database／source／page 不匹配 | 停止；不在别处复制、创建或“恢复”原档案 |
| 截断、未知块、重复ID、查询上限、读中变化 | 不声明完整，不形成可写预览 |
| 旧管理内容与基线不同 | conflict；保留原文，等待确认新版本 |
| 创建超时／回读不同／旧记录变化 | 保留日志、停止重试；核对同一稳定ID |
| API访问限制或配额限制 | 按明确错误停止，不轮换令牌或换连接规避 |

当前证据与每层状态只维护在 [本次需求](../requirements/2026-10-04/195337_notion-independent-access.md) 和 [当前连接状态](notion-state.json)。真实远端、人工体验、手机与训练效果分开，不用边界替身测试冒充在线验证。

decision：先用系统 Python3 和官方 HTTPS 建立固定原档案通道；tradeoff：维护一个小型适配器并进行首次人工授权，换取独立凭证、固定范围与可检查的失败。先完整读取而非增量，付出少量读取成本换取版本一致性。未来可在真机／远端证据成熟后增加独立 MCP 外壳、增量缓存或有限调度，本期不增加服务器、定时器或无界自动写入。

官方依据（2026-10-04 阅读，API pin `2026-03-11`）：[内部连接和授权](https://developers.notion.com/guides/get-started/internal-connections)、[bot工作区身份](https://developers.notion.com/reference/user)、[Markdown完整性](https://developers.notion.com/reference/retrieve-page-markdown)、[创建页与父页限制](https://developers.notion.com/reference/post-page)、[大查询结果上限](https://developers.notion.com/guides/data-apis/query-large-data-sources)。这些说明支持接口方案，不证明本项目远端已生效。
