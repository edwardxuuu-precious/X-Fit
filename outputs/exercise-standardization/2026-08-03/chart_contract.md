# Chart contract

- Decision question: 人工审核工作主要集中在哪类状态，多少历史完成组会受影响？
- Intended takeaway: 既要看名称数量，也要看历史影响；“可审批”不等于已写入，“待合并/变式/未解析”必须先人工确认。
- Chart family: 单系列分类柱状图。
- Renderer: canonical artifact native `bar` chart，portable HTML builder。
- Data shape: 每个审核状态一行；包含原始名称数、候选 canonical 数、受影响完成组数。
- Encodings: x=审核状态；y=原始名称数；详情保留完成组数和 canonical 候选数。
- Color/legend: 单系列，不显示冗余图例。
- Label/format: 名称数为整数；无小数、无百分比。
- Interaction: 只读 source affordance；无筛选、无外部请求。
- QA: artifact validation + portable builder desktop/narrow verification；精确明细由 55 行审计表承载。
