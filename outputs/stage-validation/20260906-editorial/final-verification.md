# 运动杂志风精修 · 最终本地验证

统一入口：`XFIT_RUN_ID=20260906-editorial XFIT_DERIVED_PATH=/tmp/xfit-editorial scripts/xfit-stage-validation.sh non-device`。

- 原始统一全量结果：6 后端、248 单元通过；93 UI 中 76 通过、10 失败、7 既有跳过。保留原始 `summary.md` 和日志，不改写 FAIL。
- 第一次针对性补测：18 项中 15 通过、3 失败，见 `supplement.log`。
- 最终针对性补测：12 项全部通过，包含最后 3 个失败项、训练感受保存恢复和全部 8 个核心重设计用例，见 `supplement-final.log`。
- 按每个用例最新证据汇总：86 UI 通过、7 既有跳过、0 未解决失败，逐项映射在 `final-verification.json`。此结论为统一全量加必要补测的组合证据，不是重新全量运行全部用例。
- 最终 SwiftUI 源码在最后补测中成功构建；iPhoneOS Release 结果见下方。
- 27 个 App / 模型 / 服务保护文件保持原样，见 `final-protected-source-comparison.json`。本轮所有源码指纹见 `final-source-sha256.json`，统一全量前的原始指纹仍保留。
- 13 张实际模拟器截图导出至 `outputs/ui-redesign/editorial-preview/`；首页展示 12 张核心界面。来源与导出映射见 `screenshot-manifest.json`。Agent 视觉核对了训练、饮食、目标、肌群、周复盘截图；不代替本人实际操作验收。

修复闭环：开放式列表整行点击范围；组数/动作数完整无障碍标签；原生长菜单真实滚动；训练结束按钮中心滚入屏内；周复盘截图增加导航成功断言。

边界：模拟器使用隔离演示数据。真机覆盖安装、活动数据库守恒、真机自动化 NOT_RUN；本人体验 BLOCKED_HUMAN。整体阶段不标记 GO，未 commit/tag/push、卸载、清空真实 App 或发布。

浏览器工具拒绝自动打开本地 file URL；没有绕过该策略。截图文件和本地 HTML 已交付，HTML 图片引用完整性通过；网页按钮未进行浏览器运行验收。

最终无签名 iPhoneOS Release 构建：PASS，见 `final-release-build.log`。本地结论 PASS；真机和本人验收仍待完成。
