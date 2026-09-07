# 正常字号与全量本地回归

本地验证 **PASS**；整体 **PARTIAL**。真机当前离线，覆盖安装、活动数据库守恒和本人实际操作验收尚未完成，不标记 GO。

## 实际修改

- 默认页面标题统一为 22pt，统计数字为 28pt；目标均重由 88pt 收紧至 36pt，并移除负字距和斜体。身体体重输入同步收紧，保留动态字号和正常触控区域。
- 审核撤销/保留按钮的整个标签区域可点击，触控高度至少 44pt。审核保存、撤销及历史数据处理逻辑不变。
- 稳定 DEBUG、非持久 UI 演示数据的周期日期，避免随真实日期轮换导致食材断言失效；正式计划仍为 2026-09-06 至 2026-12-06。
- 测试适配当前设置分段、历史“工作组”文案，以及固定底栏上方的可点击区域；未增加跳过项。

## 验证结果

| 层 | 结果 | 证据 |
|---|---|---|
| 静态、工程读取、模拟器构建 | PASS | 统一入口 N01/N02/N04；最终补验重新构建 |
| 后端 | 6/6 PASS | 统一入口 N03 |
| 单元测试 | 258/258 PASS | 统一入口 N05；修改后 supplement.log 再次全量通过 |
| 界面测试 | 91 PASS、7 既有跳过、0 未闭环失败 | ui-test-results.json 覆盖当前全部 98 个用例 |
| 最终 iPhoneOS Release 无签名构建 | PASS | final-release-build.log |
| 正常字号视觉检查 | 已查看实际模拟器截图，主操作可见 | [正常字号预览](../../ui-redesign/normal-type/index.html)；22 张图的来源和哈希可核对 |
| 真机在线条件 | BLOCKED_ENV | device-availability.json：Edward_iPhone unavailable |
| 覆盖安装、真机自动化、活动库/UUID 守恒 | NOT_RUN | 手机未安装、未卸载、未清数据 |
| 本人实际操作与审美验收 | BLOCKED_HUMAN | 由用户实际使用确认，自动测试不代签 |

## 原始失败与补验

统一入口：`scripts/xfit-stage-validation.sh non-device`，Run ID `20260907-full-ui-final`。原始 `summary.md` 保留 N06 FAIL，未改写为 PASS；下列按每个用例的最新证据闭环，不宣称首次整套运行零失败。

| 执行 | 原始结果 | 后续处理 |
|---|---|---|
| N06 全量 | 85 PASS / 6 FAIL / 7 SKIP | 四类问题逐项诊断，全部进入补验 |
| reset-viewport-probe | 1 PASS | 只改变测试滚动操作，确认原撤销流程正常；失败层级显示按钮在底部导航下方 |
| supplement | 258 单元 PASS；15 UI PASS / 2 FAIL | 后续才执行到的历史摘要旧文案、备餐说明底栏误点继续修正 |
| final-two | 2 UI PASS | 历史名称/重量/次数/RIR 完整回看；备餐说明打开、关闭和返回菜单通过 |

初始 `20260907-full-ui-regression` 在字号改动前已开始构建，N01–N05 通过后主动中止旧二进制的 N06，再从统一入口运行上述最终批次。初始中止不计作通过。

失败原因与修改边界见 `final-verification.json`；98 个用例逐项证据见 `ui-test-results.json`。最终 113 个源码/资源文件指纹见 `final-source-sha256.json`。补验的原始 xcresult 已保存至 `artifacts/stage-validation/20260907-full-ui-final/`。

## 保留边界

没有 commit/tag/push 或发布。工具页保持已确认的助手优先顺序，另一顺序建议仍待决定。医学目标和个人份量保持待确认，不生成默认热量/蛋白预算。完整验收仍需真机与真人两层证据。
