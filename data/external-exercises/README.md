# MIT 非媒体扩展动作库

源：`hasaneyldrm/exercises-dataset`，固定版本 `7455efae41b330c265e7cd4b78dfa848e7ce5ebd`，2026-10-23读取。

- `source.json`：完整1324条的非媒体白名单投影，保留上游原始JSON SHA256、固定版本、完整LICENSE、中英文步骤。没有图片、动画、媒体ID、媒体路径或媒体下载。
- `localization/chunk-*.json`：X-Fit根据MIT源名称/步骤形成的中文名称与具体核对备注；不是上游既有中文名称，也不是OpenGym后续AGPL文字。含糊名称/步骤冲突保留英文原名及待核对状态。
- `matching-review.json`：个人动作的检索词义匹配。`aliases`要求名称与动作方式明确；`candidateAliases`只帮助发现，不能批准身份。任何匹配都不会写入accepted canonical ID或合并历史/PR。器械、名称、来源复核由App继续执行。
- `semantic-review.json`：原348条疑点的可追溯覆盖层，保留固定源、初始名称/备注与完整原文引用。历轮审查保留，最新`targetedCrossCheck329`记录去重取证；当前原348条中19条已解释旧疑点、329条继续待核。解除不代表全步骤专业审校或个人身份批准。无实质增量条目的原产品字段保持，生成器校验原源指纹/翻译后才应用本地名称与短备注。
- 打包入口：`python3 scripts/xfit-build-external-catalog.py`，本地生成 `FitnessApp/Resources/ExternalExerciseCatalog.json`。只保留允许字段，不联网、不写数据库。
- 上游`target`用于扩展库筛选；保留来源标签，不能据此覆盖个人肌群、纠正训练记录或制定处方。`muscle_group`在上游常是协同肌群，不能覆盖`target`作为主肌群。源数据本身可能有生物力学/翻译错误，完整覆盖不代表专业动作审校。

扩展库使用来源ID区分条目，原同名记录不删除。新增个人动作前明确选择单位，来源链接记录ID，后续重命名仍可追溯。已有动作只由用户明确选用，原UUID、定义、单位、人工别名与历史不变。浏览与检索没有写入。

更新上游版本必须重核LICENSE/NOTICE、全量ID差异、中文覆盖、匹配候选和无媒体白名单，重新生成并验证；禁止运行时跟随main自动更新。

用户确认与验收真源：`docs/requirements/2026-10-23/133150_opengym-nonmedia-catalog.md`。

复核历史与当前真源：首轮见`docs/requirements/2026-10-24/091750_opengym-348.md`，后续345条见同目录`100221_opengym345.md`，335条见`220739_opengym335.md`。各轮结果保留在原需求/报告。本轮331条新增证据见同目录`231501_opengym331.md`及`outputs/external-exercises/20261024-cross331/331条新增证据复核.md`；排序依据为10/24 22:00:01手机快照中171个有完成记录动作，不表示实时同步。个人动作身份、机型与计重口径不从外部近似动作推断。

关键标题/步骤/握法/支撑/轨迹冲突仍未解时保留待核；普通缺精确型号、角度、滑轮倍率不单独阻断通用定义。新增证据若只证明旧疑点源于误解通用术语或可行器械配置，可按固定源已写明的完整设置谨慎重开；不得以外部相似动作替作者选择应改哪一项。已解除项的中文、英文及原别名仍为candidate-only，除原已链接同源记录外不自动升级exact、批准身份或共享PR。

本轮仅本地资源与验证；目录View/服务/模型保持32已交付基线。个人动作UUID/名称/人工别名、训练计划/完成组、计量与设置不改，手机不安装。原始EN/中文步骤及MIT来源不覆盖，不加入媒体。来源元数据的肌群/器械标签仍可能有技术局限，不据此制定训练处方。

2026-10-25追加本人明确确认的0381最小匹配修正：固定源要求双手各持哑铃，本人已有“反向箭步蹲”为单哑铃扶架，泛称仅保留在`candidateAliases`。名称仍可搜索，已显式来源链接仍可复用；不改个人别名/UUID/单位/历史、固定步骤或330条待核状态。当前证据见`REQ-20261025-095837/AC-07`与`artifacts/external-exercises/20261025-0381-candidate/final-verification.json`。


2026-10-25追加330条复核：`targetedCrossCheck330`保存194真实query（覆盖231条）、99条未新搜的具体缺口及来源/反证，保留最早queryLog不可用限制。本人确认REQ-20261025-133416后只收窄1343/0111/5201三个reviewNote及必要解释，全部继续待核，原源/名称/器械/步骤/MIT/匹配与0381保持。报告及验证：`outputs/external-exercises/20261025-cross330/330条新增证据复核.md`、`artifacts/external-exercises/20261025-cross330/final-verification.json`。正常主预览25表2497行（含10/26计划）/4文件/设置守恒，手机本轮零操作；旧真机UI/人工门独立保留。

2026-10-25第二轮去重取证：REQ-20261025-184150，最新targetedCrossCheck330R2。1396按固定八步及Toe raises两义反证纠正为史密斯站姿提踵，待核329；新增四个candidate标签，原123匹配不动。330逐项结论、32实际网页query/39定向外查ID/291无新外查及1重复1部分重叠均留痕；正文、反证与分层验收见artifacts/external-exercises/20261025-cross330-r2/final-verification.json及同目录research-review.json。仅本地，无手机更新。

2026-10-25追加329条去重核查：REQ-20261025-200715；1415的neutral wrist被旧本地误引为Neutral Grip，新读腕位与掌向的直接兼容文字后纠正中文与短说明，继续待核329。新/旧中文与英文仅candidate，原124匹配不动；1396/0381与其他1323资源保持。逐项结论、9成功query/4定向外查ID/325无新增外查、摘要/正文/失败边界及验证见artifacts/external-exercises/20261025-cross329/final-verification.json。仅本地，不更新手机。
