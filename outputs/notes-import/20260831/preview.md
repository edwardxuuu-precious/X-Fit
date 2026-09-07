# Notes 补录预览（未导入）

- 来源：Notes / 健身 / `Week of Aug 3`、`Week of Aug 10`、`Week of Aug 17`
- 目标：13 个缺失训练日；CSV 使用稳定 `session_id=notes-YYYY-MM-DD`，导入标识为 `history-csv:<session_id>`。
- 明确排除：2026-08-22 已有 App 现场记录；休息日；无组数的 `cable torso rotate`；末尾空项。
- 非力量记录：跳绳 5 次（1600、1600、1600、1600、1500 个），步行 6 km 1 次。
- 热身：8 月 3 日的开合跳、乌龙盘杠、最伟大拉伸写入训练备注，不创建工作组。
- 明确别名：RDL→罗马尼亚硬拉；cable torso twist/rotate→绳索躯干旋转；pull down→高位下拉；behind neck pull down→颈后下拉；tight grip pull down→窄握下拉；Leg Press→腿举；Leg curl→腿弯举。
- 待审核原名：`declined bench press`、`seated dip`、`fly`、`shoulder press`、`side press`、`rear dealt`、壶铃饶颈侧拉、臀桥壶铃侧旋等；不在导入前强行归并。
- 自重行的 `weight_kg` 保持 0，仅表示 Notes 没写体重；正式导入后由训练日前最近体重生成 `bodyWeightKgSnapshot`，无体重时保持“暂无体重”，不产生 0 kg volume。
- 当前状态：仅生成文件和本地预览，未写入 App Group、未覆盖安装、未执行正式导入。
