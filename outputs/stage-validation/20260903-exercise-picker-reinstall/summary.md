# X-Fit 阶段测试摘要

- Run ID：`20260903-exercise-picker-reinstall`
- 模式：`device`
- 时间：`2026-09-03 09:19:16 +0800`
- 仓库：`/Users/edward/Documents/Fitness App`
- Git：`main / 1b7b5c0`
- Artifacts：`/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall`

| Gate | 状态 | 检查 | 证据/说明 |
|---|---|---|---|
| D00 | PASS | 真机在线与开发服务预检 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D00.log` |
| D01 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D01.log` |
| D02 | PASS | pre-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D02.log` |
| D03 | PASS | 真机签名 Release 构建 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D03.log` |
| D04 | PASS | 签名、entitlements 与版本回读 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D04.log` |
| D05 | PASS | 真机覆盖安装、启动与版本回读（不卸载、不清容器） | 初次脚本中的自动启动被锁屏拒绝；解锁后重新覆盖安装并启动成功，设备回读 X-Fit 0.5.0 (11)。证据：`device-install-after-unlocked-tests.json`、`device-launch-after-unlocked-tests.json`、`device-app-readback-after-unlocked-tests.json` |
| D06A | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D06A.log` |
| D06B | PASS | post-install | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D06B.log` |
| D06C | PASS | 安装前后核心记录不减少 | `/Users/edward/Documents/Fitness App/artifacts/stage-validation/20260903-exercise-picker-reinstall/D06C.log` |
| D07 | PASS（本需求） | 真机 XCTest | `testExercisePickerDismissesKeyboardAndEditsBuiltInDefinitionWithoutSelecting()` 在 Edward_iPhone 通过（30.549 秒）。全量套件 77 条中 68 通过、7 跳过、2 个与本需求无关的既有失败，阶段整体仍非 GO。证据：`../20260903-template-bilingual-volume-device-tests-unlocked/device-ui.xcresult` |
| D08 | PASS | 测试后恢复 Release 与活动数据守恒 | Release 0.5.0 (11) 已再次覆盖安装并启动；`quick_check=ok`，核心记录保持 199 / 825 / 35。证据：`device-audit/post-unlocked-tests/` |
| D09 | PASS（本需求用户验收） | 用户在已知镜像不能替代真实中文软键盘及 VoiceOver 直接验证的边界下，明确确认本需求可以通过 | `/Users/edward/Documents/Fitness App/outputs/stage-validation/20260903-exercise-picker-reinstall/真机人工测试清单.md`；2026-09-03 用户聊天确认 |

## 判定边界

- 任一 FAIL 均阻断 GO。
- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。
- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。

## 解锁后复核

- 2026-09-03 10:43，设备解锁后 `devicectl` 自动启动成功。
- 两次单独定向复跑受到同设备另一条全量 XCTest 接管影响，分别表现为 App 进程被替换和 Runner 启动被系统终止，不作为产品失败计入。
- 等待设备测试串行化后，同一条本需求用例在全量真机 UI 结果包中通过。
- 2026-09-03 11:20，再次覆盖安装 Release 候选包并启动成功；设备应用清单回读为 0.5.0 (11)。
- 2026-09-03 11:21，复制活动 App Group 数据并检查：SQLite 完整，核心记录 199 / 825 / 35，与安装前一致。

## iPhone 镜像可视复核

- 2026-09-03 16:12 后通过 iPhone Mirroring 直接操作活动 X-Fit；进入当天训练动作选择器，确认现有动作行尾均有菜单，菜单明确显示“编辑动作定义”。
- 进入“传统硬拉”的编辑页，全部定义字段正确回填；将默认休息由 90 秒临时改为 300 秒并保存，页面返回动作选择器，动作没有自动加入当天菜单。
- 通过“训练 → 动作库”重新打开传统硬拉，将默认休息恢复为 90 秒；再次打开回读为 90 秒。
- 点击动作库搜索结果下方空白区域后，`dead` 搜索文本保留而输入光标消失，焦点收起。iPhone Mirroring 把 Mac 键盘作为硬件键盘，不能显示或验证真实中文软键盘。
- 测试前后 App Group SQLite 均 `quick_check=ok`；全部业务表记录数无差异；核心记录保持 199 / 825 / 35；数据库回读传统硬拉与单腿钟摆推举默认休息均为 90 秒。
- 镜像坐标点击期间曾穿透误开“本次设置”并形成未提交编排草稿；已取消并退出，测试前后所有业务表记录数一致，未留下新增动作或训练记录。

## 用户验收

- 2026-09-03 16:30，设备应用清单即时回读 X-Fit 0.5.0 (11) 已安装在 Edward_iPhone；证据：`device-app-readback-user-accepted.json`。
- 用户明确确认本需求“可以通过”，需求 `REQ-20260902-125001` 已按用户验收收口。
- 此结论只代表“动作选择器键盘收起与动作定义编辑入口”需求通过；阶段全量 UI 的 2 个无关失败仍阻断整个阶段 `GO`。
