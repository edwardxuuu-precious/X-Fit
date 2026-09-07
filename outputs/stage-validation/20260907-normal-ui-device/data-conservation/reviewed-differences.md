# 最终 Release 备份差异归因

数据守恒审核：PASS_WITH_EXPLAINED_TIMESTAMP_CHANGE。本结论仅针对下载备份，不代表阶段 GO 或人工体验通过。

七个时间点均通过完整性检查，原始备份哈希未变。首次安装前 14 个实体，安装后 22 个，新增 8 个减脂实体均为空；原有 1257 行及所有 UUID 全部保留，无新增、缺失、重复或空 UUID。

首次安装前至最终 Release：仅已归档“严格深蹲”记录的 ZUPDATEDAT 改变，其他全部共同业务字段及 UUID 引用一致。当前 ExerciseCatalogService.consolidateConfirmedSquatDuplicate 对该类已归档重复动作仍会在每次启动时无条件刷新 updatedAt，SeedDataService 会调用它。代码可解释该时间戳差异，未发现记录损坏或历史业务内容改写；没有该次方法调用的运行追踪，因此不把来源解释说成调用实测。

全量 UI 测试后至 4 条定向补验后：全部共同业务字段完全一致。最终 Release 正常启动后仍仅上述时间戳刷新。

原始 conservation.json 保留 REQUIRES_CHANGE_REVIEW，不通用忽略 updatedAt。源码 SHA 和对应行号见 reviewed-differences.json。七份完整实体快照、原始数据库三件套 SHA、逐字段差异和 UUID 引用多重集均在同目录中，可复跑 audit_backup_conservation.py。脚本 4 项自检通过（WAL、字段改写、等量 UUID 替换、重复 UUID）。
