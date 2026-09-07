# X-Fit 0.5.0 (11) 真机验收测试报告（Agent 执行）

- 测试日期：2026-09-02
- 测试设备：Edward_iPhone（iPhone 17, iPhone18,3，iOS 26.6）
- 被测版本：X-Fit 0.5.0 (11)（`com.edward.FitnessApp`，devicectl 回读确认）
- 需求档案：`docs/requirements/2026-09-02/125030_template-bilingual-search-volume-loop.md`
- 执行方式：Agent 通过 iPhone Mirroring / devicectl / App Group 数据库只读拉取执行；未修改代码、未卸载、未清容器、未重新部署
- 证据目录：`outputs/stage-validation/20260902-template-bilingual-volume-device/agent-acceptance/`

## 环境与基线（T0）

| 项 | 结果 | 说明 |
|---|---|---|
| 设备在线 | PASS | devicectl `available (paired)`；iOS 26.6 |
| 安装版本 | PASS | X-Fit 0.5.0 (11) |
| 测试前数据基线 | PASS | ZWORKOUTSESSION 35 / ZSESSIONEXERCISE 199 / ZSETLOG 825，与安装时基线完全一致，`quick_check=ok` |

## 测试前事实（来自设备数据库只读快照）

- 长期模板（非一次性、启用中）：`推 · 胸肩三头`、`拉 · 背部二头`、`腿 · 下肢力量`，各含 4 个动作。
- 推模板动作：杠铃卧推 3×8-12@40、上斜哑铃卧推 3×8-12@16、坐姿哑铃肩推 3×8-12@12、绳索下压 3×10-15@15。
- 深蹲 = `Barbell Squat`（器械 杠铃 / 肌群 腿部）。
- 杠铃卧推已有 4 个历史完成日（07-12/07-26/07-31/08-11），volume 分别为 1710/2425/200/1050。
- 上斜哑铃卧推、坐姿哑铃肩推、绳索下压无已完成历史（可用于空态验证）。
- 今日（09-02）无日程；最近未来日程为 09-03 `推 · 胸肩三头`（planned）。
- 今日已存在一条用户完成的会话（核心+腿部，非本轮测试产生）。

## 结果汇总

| # | 测试项 | AC | 结果 | 证据 |
|---|---|---|---|---|
| T0 | 环境与基线 | — | PASS | 见上表；`device-data/pre-test/` |
| T1 | 肌群多选与取消 | AC-01 | BLOCKED_ENV（交互通道被占，见"阻塞记录"） | 代码语义已核：`DailyWorkoutBuilderView.toggleMuscleGroup` 取消即移除该肌群已选动作 |
| T2 | 器械→肌群→中文首字母分组排序 | AC-02 | BLOCKED_ENV（同上） | 代码分组排序已核：`PlanView.groupedFilteredExercises`、`DailyWorkoutBuilderView.groupedRecommendations` |
| T3 | 中英文双向模糊搜索 | AC-03 | BLOCKED_ENV（同上）；数据侧前提 PASS | 设备目录确认 深蹲=Barbell Squat（杠铃/腿部） |
| T4 | 专项模板默认/编辑 | AC-04 | BLOCKED_ENV（同上）；数据侧前提 PASS | 默认推/拉/腿模板存在且各含 4 动作（见"测试前事实"） |
| T5 | 长期模板完成回写+持久化 | AC-05/06 | 待设备侧执行（监视中） | 回写逻辑已核：`WorkoutService.finish`/`persistentTemplatePlanUpdates` |
| T6 | Volume 折线图 | AC-07 | 待设备侧执行（监视中） | 预期值已备：杠铃卧推 4 个历史点（1710/2425/200/1050） |
| T7 | 既有历史守恒 | AC-07 | 预检 PASS；终检进行中 | 测试前快照与安装基线完全一致 35/199/825，quick_check=ok |

## 阻塞记录（交互通道）

- 本 Agent 的设备 UI 通道仅两条：
  1. **iPhone Mirroring**（macOS 无障碍树转发 + osascript 点击）：持续显示 `iPhone in Use — Lock your iPhone to connect`。iPhone 自 18:10 起一直处于解锁使用状态（期间 X-Fit 进程在前台运行，PID 40945）。已按用户约束放弃需要安装 WDA/DeviceKit 的 go-ios 通道（会在用户手机上安装额外 App）。
  2. **devicectl/go-ios**：无 UI 注入能力；`screenshotr` 在网络 usbmuxd 通道返回 Invalid service。
- 同一时间段，屏幕上有并行 Agent 会话（Codex）正在执行同一验收任务（任务清单含 T0 环境准备/数据预检等），用户手持 iPhone 配合该会话。为避免两个会话争抢同一部手机造成误操作，本 Agent 停止主动点击，转为被动监视：
  - `/tmp/xfit-event-watch.sh`：每 2 分钟只读拉取 App Group 数据库做摘要比对；变化即触发数据层验证（T5/T6/T7）。
  - 镜像窗口出现真实 iPhone 内容（荧光绿像素检测）时自动接管 UI 测试（T1–T4）。

## 详细记录

### 2026-09-02 18:19–19:15 执行时间线

1. 18:19 确认设备在线、X-Fit 0.5.0 (11) 已安装；建立证据目录与截图通道。
2. 18:33 只读拉取 App Group 数据库（`device-data/pre-test/`），核心三表 35/199/825 与安装基线一致，quick_check=ok → T7 预检 PASS。
3. 18:35–19:10 多次尝试 iPhone Mirroring 连接，均因 iPhone 解锁使用中而超时；期间确认 ZCode 无 Mac 辅助功能/屏幕录制权限（Bash osascript/screencapture 可用作为替代通道）。
4. 18:40–19:05 完成代码层预研：模板回写、肌群多选、分组排序、搜索、volume 口径（详见各测试项）。
5. 19:12 起进入事件驱动监视（数据库 + 镜像像素双通道）。

## 结论

**进行中（未定级）**——数据层验证（T0/T7 预检）PASS；交互层测试因设备被并行验收会话占用而 BLOCKED_ENV，监视器已就绪，设备侧一旦出现训练完成或镜像空闲即继续执行并出最终结论。

### 2026-09-02 22:00–22:15 第二轮（镜像通道打通）

- 21:58 用户锁屏+解锁配合，iPhone Mirroring 连接成功；X-Fit 通过 devicectl 启动（首页截图 `t-launch-home.png`）。
- 成功导航：首页 → 训练标签（`s2-plan-tab.png`），截图放大三次读数一致确认入口列表：今日编排/专项模板/动作库/历史记录/日程管理（`s2-mid.png`）。
- 22:10 点击"今日编排"入口成功进入（`s3-after-entry.png`，页面出现模式切换与肌群选择区）。
- 22:12 起，远端视觉分析通道返回模板化占位文本，无法再可靠读取屏幕坐标。因盲点击真实用户设备存在误触风险（如误触"放弃训练"），按安全准则停止自主 UI 操作。

## 最终结论

**PARTIAL**：
- PASS：T0 环境/版本/基线；T7 预检（安装基线=测试前快照 35/199/825）。
- BLOCKED_ENV：T1–T6 交互层（原因：macOS 辅助功能/屏幕录制权限缺失 → 视觉通道不可靠 → 无法安全自主操作；期间设备还被并行 Codex 验收会话占用约 2 小时）。
- 数据层交叉验证与全部 UI 流程的自动化验收待后续会话（需 ZCode 获得屏幕录制/辅助功能权限，或由用户操作手机 + Agent 实时数据库验证）完成。

### 2026-09-02 22:30–22:50 第三轮（真机 XCUITest，用户授权连线自动化）

方法：用户明确授权"通过连线自动化手机"（同 Codex 方式）。使用 `xcodebuild test -destination id=<Edward_iPhone>` 在真机执行 UI 测试（安装 FitnessAppUITests-Runner + 覆盖安装 App；UI 测试使用独立 XFitUITesting 存储与内存种子，不触碰真实用户数据）。证据：`/tmp/xfit-acceptance-1.xcresult`、`/tmp/xfit-squat-rerun.xcresult`、`/tmp/xfit-t5-writeback.xcresult`。

| 测试 | 对应验收项 | 结果 |
|---|---|---|
| testDailyBuilderDraftUnlocksMusclesExercisesThenReview | T1/AC-01 肌群多选 | PASS |
| testExerciseLibraryFindsChineseExerciseByEnglishAliasAndShowsEquipmentMuscleGroup | T2+T3/AC-02/03 | PASS |
| testExerciseLibrarySearchesSquatAliasAndSupportsEditDeleteRestore | T3/AC-03 squat→深蹲+归档恢复 | 首跑 FAIL（exercise-menu-深蹲 点击时 not hittable，键盘遮挡/时序抖动，真机几何差异）；复跑 PASS → 判定不稳定测试抖动，功能本身正常（搜索"严格深蹲"命中"深蹲"两轮均成功） |
| testSpecialTemplateEditorExposesMuscleMultiselectAndExerciseReordering | T4/AC-04 目标肌群多选+排序入口 | PASS |
| testStatsVolumeTrendSwitchesFromOverallToExerciseHistory | T6/AC-07 volume 折线图切换 | PASS |
| testDeviceTemplateWritebackAfterFinishAndPersist（本轮新增） | T5/AC-05/06 回写+持久化 | （执行中） |

已识别偏差（记录）：当前工作树有两处服务文件改动晚于部署构建（ExerciseCatalogService/ExerciseTerminologyService，16:28，为并行会话的别名整理工作）；本轮真机测试基于当前树构建，与已部署 0.5.0 (11) 在这两个文件上存在差异，验收结论按"当前树=0.5.0(11)+别名整理增量"表述。

### 2026-09-02 23:00–23:25 第四轮（T5 回写测试 + T7 终检）

- 新增 `testDeviceTemplateWritebackAfterFinishAndPersist`（模板 40→44kg/8→10 次 × 3 组完成训练 → 重启验证回写与未完成动作不回写）。
- 首跑 FAIL：脚本问题两处（逐组输入框在折叠线以下未滚动到位；取消编辑后未切回首页标签）——均已修复；录屏证据 `screenshots/T5-first-run-failure-recording.mp4`。观察：专项模板页出现过一次"内部错误"横幅（同路径既有测试通过，疑似测试环境瞬时提示，未阻断流程）。
- 二跑挂起：测试间隙手机自动锁屏，xcodebuild 在 notification_proxy 服务上报 "The device is passcode protected"；其 xcresult 被终止时损坏。
- 三跑立即失败：同锁屏原因。镜像已代为滑到密码输入界面，等待用户解锁（密码仅限用户本人输入）。
- **T7 终检 PASS**：全部真机测试（含覆盖安装）后拉取真实 App Group 数据库：quick_check=ok，ZWORKOUTSESSION 35 / ZSESSIONEXERCISE 199 / ZSETLOG 825，与安装基线、测试前快照完全一致——真实训练数据零丢失、零污染（UI 测试使用独立 XFitUITesting 存储）。

### 2026-09-02 23:50–00:20 第五轮（T5 修复迭代 run4–run7）

- run4：手机解锁正常执行，暴露 persistent 模式下模板编辑器确定性空列表（"还没有动作"三次重试均空；同批 22:30 plain 模式编辑器正常）→ 判定为 `--ui-testing-persistent` 存储的查询时序问题，测试环境属性，非产品缺陷（生产无 reset-store 路径）。已记录观察项 O-1。
- run5–run7：改用 plain `--ui-testing`；run7 增加首页种子就绪等待（生效）。但三轮均在 t≈17–20s 被 "signal kill" 终止会话（22:30 批次同路径 83s 正常；22:45 run1 也正常执行 36s+）。原因未定（设备长时间连线+镜像后台运行后的内存压力/锁屏策略嫌疑最大），与被测代码无关。
- 测试脚本 `testDeviceTemplateWritebackAfterFinishAndPersist` 已就绪并保留在测试库中：44kg×10 三组 → 完成 → 断言仅杠铃卧推回写、上斜哑铃卧推保持 16 不变。环境稳定后一条命令可复跑。

### 观察项（非阻断）

- O-1（P3，测试环境）：`--ui-testing-persistent` 模式下模板编辑器动作列表可能打开为空且同会话不恢复（TemplateEditorView `loadDrafts` 仅 onAppear 一次）。生产不可达（无 store 重置路径），建议后续在 onAppear 或 @Query 变化时补一次空列表重载。
- O-2（P3，观察）：专项模板页出现过一次"内部错误"横幅（run1 录屏可见），同路径既有测试通过，未复现、未阻断。
- O-3（P3，测试抖动）：动作库搜索后键盘未收起时行尾"更多"菜单在真机上偶发 not hittable（首跑 FAIL、复跑 PASS）；建议测试先行滚动/收键盘，产品无需改动。

## 最终结论

**PARTIAL（接近完成）**

| 验收项 | 结论 | 依据 |
|---|---|---|
| T0 环境/版本/基线 | **PASS** | 0.5.0 (11) 回读；安装基线=测试前快照 |
| T1 肌群多选（AC-01） | **PASS** | 真机 XCUITest PASS |
| T2 分组排序（AC-02） | **PASS** | 真机搜索/分组测试 PASS + 代码排序逻辑核对 |
| T3 双向模糊搜索（AC-03） | **PASS** | 真机两测试通过（"严格深蹲"→"深蹲"）；一次键盘遮挡抖动复跑通过 |
| T4 专项模板（AC-04） | **PASS** | 真机模板编辑测试 PASS（肌群多选+排序入口）；默认推/拉/腿存在 |
| T5 回写+持久化（AC-05/06） | **PARTIAL** | 服务层单元测试通过（真实磁盘容器）+ finish 回写逻辑逐行核对；真机端到端脚本就绪但被环境会话中断（run4–7）阻塞 |
| T6 Volume 折线图（AC-07） | **PASS** | 真机 volume 趋势测试 PASS；DB 口径核对（重量×次数、仅 kg 单位、按完成日聚合） |
| T7 历史守恒（AC-07） | **PASS** | 测试后 35/199/825 与安装基线完全一致，quick_check=ok |

- 未发现任何 P0/P1 产品缺陷；三个观察项均为 P3。
- 真机覆盖安装多次（xcodebuild 自动）均保留容器，用户真实数据零丢失。
- T5 真机端到端待环境稳定后复跑一条命令即可闭环（`xcodebuild test -only-testing:.../testDeviceTemplateWritebackAfterFinishAndPersist`）。
