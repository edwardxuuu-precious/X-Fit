# T3 工作台本地创建器

- 合同、验收及实际结果：[REQ-20261009-082013](../requirements/2026-10-09/082013_notion-workspace-local-creator.md)。
- 用途：查看原T3结构、模拟创建并从同一状态续做；真实Notion接入另走[独立通道](Notion独立通道.md)和原T3权限门。
- 入口：`scripts/xfit-notion-workspace.py`。仅`preview`与`simulate`，不加载凭证，不提供线上开关。

## 查看和续做

在仓库根目录查看离线预览，不创建文件：

```bash
python3 scripts/xfit-notion-workspace.py preview --blueprint docs/operations/notion-blueprint.json
```

执行一次本地模拟时，用尚不存在的独立产物目录：

```bash
python3 scripts/xfit-notion-workspace.py simulate \
  --blueprint docs/operations/notion-blueprint.json \
  --out-dir artifacts/notion-workspace-local/my-review
```

完成条件：`result.json`为PASS，17页/3库完整回读，`review.md`可审阅。所有UUID均是模拟值；原蓝图正文是有日期的初始投影，不是当前线上事实。

从同一模拟状态复做，仍使用新的产物目录：

```bash
python3 scripts/xfit-notion-workspace.py simulate \
  --blueprint docs/operations/notion-blueprint.json \
  --inventory artifacts/notion-workspace-local/my-review/simulation-state.json \
  --out-dir artifacts/notion-workspace-local/my-repeat
```

完成条件：新增0；原对象、人工字段及模拟绑定不变。可用`--confirm-preview`绑定已审阅的本地指纹；它不是线上授权。

## 失败如何恢复

- 有未决创建且找不到同一对象：保留状态、停止检查；不要删除journal或换稳定ID重建。
- 已接收但丢响应：只在完整盘点、相同稳定ID/内容/关系和返回身份一致后采纳，继续缺步骤。
- 正文、schema、父页、关系或绑定漂移：返回conflict，保持原值；更新基线不能代替用户决定。
- 完整性、原档案访问或模拟私有父页标记不明：停止；这些标记仅检验模拟分支，不证明真实ACL。
- 输出目录已存在或为符号链接：保留原文件，换一个新产物目录；不覆盖已有报告或输入。

## 本轮可直接查看的结果

- [首次结构预览](../../artifacts/notion-workspace-local/20261009-t3-creator/first/review.md)。
- [重复执行结果](../../artifacts/notion-workspace-local/20261009-t3-creator/repeat/result.json)。
- [验收证据](../../artifacts/notion-workspace-local/20261009-t3-creator/validation.json)。

本地创建器通过只解除实现缺口。原T3的固定身份、确切私有父页、线上适配/范围确认、实际schema/关系/全文回读仍需完成；模拟绑定始终留在产物目录，不写正式Notion状态。设备、真人及训练效果门不受影响。
