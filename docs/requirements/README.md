# X-Fit 需求档案

本目录是开发需求的逐条真源。每个开发请求单独保存；补充与验收回写原文件，不用聊天记录或阶段报告替代。

## 先确认，再新建需求

先做只读事实检查，并把目标、边界、冲突、AC 验收标准和验证层发给用户确认。用户确认前不得创建正式需求档案或开始开发。

```bash
XFIT_CONFIRMED=1 \
XFIT_CONFIRMATION_NOTE="用户确认的范围摘要" \
scripts/xfit-new-requirement.sh "需求标题" optional-english-slug
```

生成后，先填写原始需求、范围、验收标准和冲突检查，再开始修改代码。

## 回顾需求

按日期查看：

```bash
find docs/requirements -mindepth 2 -type f -name '*.md' | sort
```

按关键词、状态或验收 ID 查找：

```bash
rg -n "关键词|真机待验收|AC-01" docs/requirements
```

需求文件自身是状态真源；本 README 不复制状态索引，避免两处结果不一致。

## 冲突处理

若新需求与现有需求、数据边界或验收标准冲突，在新旧文件中记录关联关系，暂停冲突范围并询问用户。用户明确决定后再更新状态；不得静默覆盖旧要求。
