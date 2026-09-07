# X-Fit 历史测试资料存储清理

2026-09-05，按用户要求删除不再保留的本地旧构建及真机/模拟器测试大附件。

- 已删除 364 个明确路径，清理目标原占用 13.36 GiB：旧 xcresult 8.66 GiB、Instruments trace 2.84 GiB、旧构建 1.58 GiB、测试媒体/活动日志 0.28 GiB。
- 保留源码与源码镜像、真机 App 数据及备份、签名资料、最新轻量测试日志、summary、manifest、XCBuildData。排除授权删除的嵌套生成物后，13,123 个保留文件元数据一致；清理前后 Git 状态一致。
- 这是历史附件删除记录，没有执行新的产品测试或真机验收。旧 summary 中的 PASS/FAIL 是原时间点记录；被列入清单的原始 trace/xcresult/媒体已永久删除，不能据此重新打开原始附件核查。
- 若后续需原始证据，重新执行对应测试。删除清单与磁盘读数见 [deleted-artifacts.json](deleted-artifacts.json)。
