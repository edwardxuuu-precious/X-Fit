# 全界面重构：本地验证结果

- 需求：`docs/requirements/2026-09-06/100804_ui-redesign.md`（REQ-20260906-100804）。
- 本地实现与回归：PASS。真实设备：NOT_RUN。人工体验：BLOCKED_HUMAN；阶段不标记 GO。
- 首先执行项目统一 `scripts/xfit-stage-validation.sh non-device`，再修复并复测受影响路径。原始结果完整保留。

| 验证层 | 最终结果 | 证据 |
|---|---|---|
| 静态 / Scheme | PASS；最终 diff-check 与源码指纹核对通过 | N01/N02.log；final-source-sha256.json |
| 后端 | 6 项通过 | N03.log |
| 全量单元 | 248 项通过 | supplement-1.log |
| 全量 UI + 必要补验 | 当前 92 个用例：85 通过、0 未解决失败、7 既有停用功能跳过 | final-verification.json 逐项映射原始日志 |
| Simulator 构建 | PASS | N04.log 及 supplement 日志 |
| 无签名 iPhoneOS Release | PASS；最后源码重新构建 | release-final-2.log |
| 真机安装 / 活动库数据守恒 / 真机自动化 | NOT_RUN | 未安装、卸载或清空手机 App |
| 本人实际操作 / 易用性 | BLOCKED_HUMAN | docs/X-Fit_真机人工测试清单.md |

UI 数量按当前测试名去重：首轮 91 项，之后新增完整身体记录用例；一项键盘用例更名以符合本次已确认交互。首轮 13 项失败，后续修正与补验后均有通过证据；不把任何原始失败日志改为通过。

七个跳过项均为此前停用的倒计时/自由组间计时及通知用例，本次没有新增跳过项。具体名称与最后证据在 JSON 中。

## 本轮修复与回归范围

- 四Tab及新导航、开始/继续/完成记录、RIR辅助入口、秒数输入、单/双侧与已完成组保真、动作搜索/肌群多选、五轮创建取消压力测试。
- 实吃/腹胀/部分营养读回、换菜历史、备餐系统分享及周复盘；营养折叠子输入保持独立可访问标识。
- 七自然日体重覆盖、医学未确认目标、周期预览导入与CSV导出、旧餐食防重复、周期日期上下文。
- 腰围独立新增、取消不写入、95cm修改、同UUID重启读回且体重保持空；编辑表单以携带记录的单一状态打开，修复首次打开错用空记录问题。
- 普通与辅助大字体核心操作；演示标识移至预览说明，避免挤压导航栏。

## 证据位置

- 原始日志：`artifacts/stage-validation/20260906-ui-redesign-local/`。
- 逐项最新结果：`final-verification.json`；完整源码指纹：`final-source-sha256.json`。
- 补验命令、退出码与xcresult摘要：本目录 `supplement-*` 文件；原始结果包保留于日志所列路径。
- 八个核心界面：`outputs/ui-redesign/core-preview/index.html`，图片由 SwiftUI 模拟器实际操作生成，全部为隔离演示数据。
