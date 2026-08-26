# X-Fit RDS-C 真机连接测试代理报告（2026-08-23）

## 0. 最终结论（以本节为准，覆盖前文任何历史状态）

**RDS-C 整体：`PARTIAL PASS`。**

- 可自动化 6 项全部 `PASS`，P0 失败 = 0：双通道在线门、快照签名构建、D-CONN-01 安装前备份、D-CONN-02 覆盖安装、启动与版本回读、D-CONN-03 安装后守恒、D-CONN-05 真机 XCTest（单元 149/149 + UI 51/51，0 失败 0 跳过），外加测试后第三次守恒复检 `PASS`。
- 未完成 3 项：D-CONN-06 拆分为两个子路径——允许/拍照 `PASS`（真人 `DEV-MAN`），拒绝/设置恢复路径 `BLOCKED_HUMAN`（自动化能力判定结论：无官方工具或 XCTest 缝可安全控制真机 TCC，见 §5.1；且源码观察发现 App 无相机拒绝引导/跳设置 UI，属产品观察项）；D-CONN-07（通知投递）`BLOCKED_HUMAN`；D-CONN-08（真机导出回读）`NOT_RUN`——建议随 RDS-M D-MAN-12 一并执行。器械识别另受云端识别服务未配置阻断，记为 `BLOCKED_CONFIG`，不计作相机权限失败。
- RDS-M（D-MAN-01…12）全部 `NOT_RUN`（需人手，App 已装好，可断开 Mac 执行）。
- 综合分：不计算（RDS 必测项未全部完成）；结论固定为“自动化就绪 / 真机人工待验收”。
- 本轮未修改产品源码，未 commit/push；项目内仅新增/更新本报告一个文件；未卸载 App、未清容器、未 erase/reset、未删除用户数据。

> 状态演进说明：本报告前两轮连接验证时曾标 `BLOCKED_ENV`（xctrace 通道离线），经人工恢复并重开 Xcode 后第三轮在线门通过，全部设备操作随后执行完毕。历史轮次记录保留在第 2 节，仅作过程追溯；**凡与第 0 节冲突的旧状态一律以第 0 节为准。**

## 1. 最终判定表

| 项目 | 最终状态 | 证据位置 |
|---|---|---|
| 双通道在线门（devicectl + xctrace） | `PASS`（第三轮；前两轮 `BLOCKED_ENV` 已解除） | §2、§3.1 |
| L3 build（只读快照 + 独立 DerivedData + 签名） | `PASS`（BUILD SUCCEEDED） | §3.2 |
| D-CONN-01 安装前备份 | `PASS`（quick_check ok；计数与 SHA-256 已记录） | §3.3 |
| D-CONN-02 覆盖安装（禁卸载） | `PASS` | §3.4 |
| 启动与版本回读（D-CONN-04 前半） | `PASS`（0.5.0 build 11，无崩溃） | §3.5 |
| D-CONN-03 安装后守恒 | `PASS`（计数一致 + 行级指纹 IDENTICAL） | §3.6 |
| D-CONN-04 后半（持续日志审计） | `PASS`（部分，见说明） | §3.5、§4 |
| D-CONN-05 真机 XCTest | `PASS`（单元 149/149；UI 51/51） | §4.1、§4.2 |
| 测试后守恒复检（第三次回读） | `PASS`（主库零变化，隔离成立） | §4.3 |
| D-CONN-06a 相机允许路径 | `PASS`（`DEV-MAN`，真人授权后可正常拍照） | §5 |
| D-CONN-06b 相机拒绝/设置恢复路径 | `BLOCKED_HUMAN`（无自动化缝；附产品观察：App 无拒绝引导 UI，见 §5.1） | §5.1、§5.2 |
| 器械识别结果 | `BLOCKED_CONFIG`（本地未识别，云端服务未配置） | §5 |
| D-CONN-07 真实通知投递 | `BLOCKED_HUMAN` | §5 |
| D-CONN-08 真机导出回读 | `NOT_RUN` | §5 |
| RDS-M D-MAN-01…12 | `NOT_RUN`（全部） | §5 |
| P0 失败（RDS-C 已执行项） | **0** | — |
| RDS-C 结论 | 可自动化部分全部通过；整体 `PARTIAL PASS`（相机允许路径已通过，拒绝路径与通知仍待人工，导出未执行） | — |
| 回滚方式 | 无需回滚（数据零变化）；备份在 `~/Documents/xfit-device-backup-20260823/pre-install/` | §6 |

## 2. 连接验证三轮历史（过程追溯）

| 轮次 | devicectl | xctrace | 判定 | 处置 |
|---|---|---|---|---|
| 第 1 轮（12:0x） | available (paired)，隧道 connected | **Offline** | `BLOCKED_ENV` | 停止一切设备操作，报告并等待人手 |
| 第 2 轮（人工恢复后，两次采样） | available (paired) | **Offline**（两次一致） | `BLOCKED_ENV` 维持 | 再次停止；判定疑似锁屏或 Xcode 设备守护进程枚举陈旧 |
| 第 3 轮（用户完全退出并重开 Xcode、保持解锁亮屏后） | **connected** | **在线分组** | `PASS`，阻断解除 | 立即按序执行全部 RDS-C 步骤 |

根因结论：xctrace 通道离线由 Xcode 设备守护进程枚举陈旧导致（重开 Xcode 即恢复），与设备、线缆、信任状态无关；开发者模式与 DDI 全程正常。

## 3. RDS-C 执行记录

### 3.1 真机识别（只读，全部轮次通用）

| 项 | 值 |
|---|---|
| 设备 | Edward_iPhone / iPhone 17（iPhone18,3，V57AP），256GB |
| UDID / CoreDevice ID | `00008150-001E49912122401C` / `DC2912E0-36B3-5555-B66D-09C1A1DD12AD` |
| ECID / 序列号 | 8525136976298012 / HCD20Y0X6H |
| iOS | 26.6（23G71） |
| Developer Mode / DDI | enabled / ddiServicesAvailable true |
| 配对 | paired（manualPairing，wired） |
| 安装前 App | X-Fit `com.edward.FitnessApp` 0.5.0（build 11） |

工作区：`/Users/edward/Documents/Fitness App`（ZCode Fitness App 项目）；分支 `codex/adaptive-daily-plans`；工作树 dirty（60+ 项，本轮零触碰）；测试矩阵 `docs/X-Fit_今日体感与动作体验高鲁棒性测试与评估.md`；Bundle `com.edward.FitnessApp`；签名 Automatic / Team `664DT5VC99`；deployment target iOS 17.0。

### 3.2 build：只读快照 + 独立 DerivedData → `PASS`

- 快照：`rsync -a` → `/tmp/xfit-snap-20260823`（18M），排除 `.git`、`build`（520M 产物）、`artifacts`（202M 产物）、`*.xcresult`、`node_modules`；关键工程文件齐全；主工作区零改动。单一 scheme `FitnessApp`，无 SPM 外部依赖。
- 主工作区 `xcodebuild -list` 曾挂起 >60s，仅终止了本代理自启的该子进程（复核无残留，未触碰其他 xcodebuild）；此后所有构建均在快照内完成。
- 构建：`xcodebuild -scheme FitnessApp -configuration Debug -destination 'id=00008150-001E49912122401C' -derivedDataPath /tmp/xfit-dd-20260823 -allowProvisioningUpdates build` → `** BUILD SUCCEEDED **`（exit 0）。
- 签名链：`Apple Development: edwardxjr@gmail.com (TS95R9D66S)` + `iOS Team Provisioning Profile: com.edward.FitnessApp`；产物 0.5.0 (11)。

### 3.3 D-CONN-01 安装前备份 → `PASS`

- App 当时在运行（PID 3513），先 `devicectl process terminate` 冻结数据库（非卸载、不清数据）。
- 拉取至 `/Users/edward/Documents/xfit-device-backup-20260823/pre-install/`：主库 `default.store{,-wal,-shm}`、`XFitUITesting/FreestylePersistence.store{,-wal,-shm}`、`Documents/{device-history-merge-receipt,history-import-receipt}.json`；大小与设备 listing 一致。
- `PRAGMA quick_check`：双库均 `ok`。结构发现：`DailyBodyCheckIn` 实体在 Freestyle 库（`ZDAILYBODYCHECKIN`），主库无此表（0.5.0 拆库存储）。

| 库（SHA-256） | Session | SessionExercise | SetLog | 已完成组 | DailyBodyCheckIn |
|---|---:|---:|---:|---:|---:|
| default.store `1918418f5a573e98ff54596249fb9e5e3cc4dbf34fb151a78440360976fc1e4a` | 15 | 101 | 442 | 431（全非热身） | — |
| FreestylePersistence.store `51303bfa1e9505cda3088c74475d35759b3701c893375194008bf8ff606a518f` | 1 | 2 | 3 | 3 | 0 |

其余指纹：主库 wal `85471b3b5734d76e55c2b347823d936b72a3fb1556581ab394b11f4754ef48cf`、shm `e16b5096314fb15b28c307f3f0a1d2b0fca80a4bcb878095da620898fd2d1fc4`；Freestyle wal `6c8397048a6913a27a42537f4482b00ae336f5b3452045bac35339a020259c9b`、shm `1589c56069ee1e046ef086de40b81349019ff44d574486a9c3bc5127064a82b9`。

### 3.4 D-CONN-02 覆盖安装 → `PASS`

`devicectl device install app`（未卸载、未清容器）→ `App installed: com.edward.FitnessApp`；bundle 路径更新为 `62DDD0BC-363A-43A7-9947-203F5E25FCDA`，数据容器不动；databaseUUID `EF032F89-8FFE-444A-B66A-E5F3ED0D46C1`，sequence 2844。

### 3.5 启动与版本回读（D-CONN-04 前半）→ `PASS`

- 版本回读：`X-Fit  com.edward.FitnessApp  0.5.0  11`，与构建产物一致。
- `process launch` 启动成功（PID 3637），运行约 8 秒无崩溃后正常终止。
- D-CONN-04 后半（持续 crash/SwiftData 日志流审计）说明：本轮以 xcresult 全程交互日志 + 三轮 quick_check 佐证无错误；长时间日志审计属 RDS-M 阶段，故标 `PASS`（部分）。

### 3.6 D-CONN-03 安装后守恒 → `PASS`

- `quick_check`：双库 `ok`。
- 计数与安装前完全一致（主库 15/101/442/431；Freestyle 1/2/3/3、CheckIn 0）。
- 行级指纹（`SELECT * ORDER BY Z_PK` → SHA-256）：主库 `ZWORKOUTSESSION`/`ZSESSIONEXERCISE`/`ZSETLOG` 与 Freestyle 库全部 4 表 **IDENTICAL** —— 历史内容未被回写。
- 文件级说明：6 文件字节级 SHA 变化属 SQLite 内务（干净关闭后 WAL 清空为空文件），逻辑数据零变化。安装后主库 SHA `38fd35b58afbd8f9624a908aa5abddf10f19cf6e862203bb4865b46e07406e6e`、Freestyle `b234eef7386b46c6e72138cdf53a8efe0ee682ba25d2297d9de2004363355abd`。

## 4. D-CONN-05 真机 XCTest（`DEV-XCT`）

### 4.1 FitnessAppTests（单元）→ `PASS`

xcresult `Test-FitnessApp-2026.08.23_12-31-12-+0800.xcresult`：设备 `Edward_iPhone / iPhone 17 / iOS 26.6 (23G71) / deviceId 00008150-001E49912122401C`，**passed 149 / failed 0 / skipped 0 / expectedFailures 0**，`** TEST SUCCEEDED **`。与 NDS 轮 Simulator 149/149 一致，单元层真机无行为差异。

### 4.2 FitnessAppUITests（UI）→ `PASS`

xcresult `Test-FitnessApp-2026.08.23_12-32-33-+0800.xcresult`：同设备，**Executed 51 tests, with 0 failures (0 unexpected)，1466.9 秒**，`** TEST SUCCEEDED **`。覆盖 D-CONN-05 所列主链路（体感点亮、休息弹窗、RIR/单边、上次设置、自重、历史详情等）；套件当前计数 51（NDS Simulator 轮为 50），真机 0 失败。逐步交互日志（tap/断言/accessibility 快照）在 xcresult 包内。

### 4.3 测试后守恒复检（第三次回读）→ `PASS`

- `quick_check`：双库 `ok`。
- **主库（真实用户历史）：计数 15/101/442/431 不变；三张历史表行级指纹与安装前 IDENTICAL** —— 覆盖安装 + 启动 + 149 单元 + 51 UI 测试全程零减少、零回写。
- Freestyle 库（UI 测试专用隔离存储）：`ZSESSIONEXERCISE` 2→4、`ZSETLOG` 3→12，为 UI 夹具预期写入（该库安装前内容即 8/22 UI 测试遗留）；`ZDAILYBODYCHECKIN` 保持 0、IDENTICAL。测试写入只落隔离库、不触主库，隔离设计在真机成立。

## 5. 人工门与未执行项

| ID | 状态 | 需要的人手动作 / 说明 |
|---|---|---|
| D-CONN-06a 相机允许路径（授权→进入相机→拍照） | `PASS`（`DEV-MAN`，真人） | 真人回报：已授予相机权限，可正常进入相机并拍照 |
| D-CONN-06b 相机拒绝路径（拒绝→App 引导→设置恢复→重拍） | `BLOCKED_HUMAN`（附产品观察，见 §5.1） | 系统权限开关只能真人操作；自动化能力判定结论为"无可安全自动化缝"（§5.1）。最少人手步骤见 §5.2 |
| 器械识别 | `BLOCKED_CONFIG` | 真人回报：拍照后本地未识别到器械，界面提示云端识别服务尚未配置。相机链路正常；识别服务配置缺失单独记账，不归因为相机权限缺陷 |
| D-CONN-07 通知投递 | `BLOCKED_HUMAN` | 启动组间计时 → 切后台/锁屏 → 归零时验证锁屏 exactly-one 通知、点击回到正确训练；前台场景验证弹窗只弹一次、“+30 秒/开始下一组”一致 |
| D-CONN-08 导出回读 | `NOT_RUN` | 建议随 RDS-M D-MAN-12：真机导出 JSON/CSV → 分享到“文件”→ 拉回比对新字段与 UI 一致 |
| D-MAN-01…12（RDS-M） | `NOT_RUN`（全部 12 项） | App 已覆盖安装完毕，可断开 Mac 按 `docs/X-Fit_今日体感与动作体验高鲁棒性测试与评估.md` §6.2 执行（触控、可读性、VoiceOver、大字、中文键盘、真实拍照、训练闭环、强退/重启、锁屏中断、触觉、相机隐私、文件导出），录屏/截图留证 |

### 5.1 D-CONN-06b 自动化能力判定与源码观察（2026-08-23 补充）

**判定：真机相机权限拒绝/恢复路径在本边界内无法自动化验证；本轮未运行任何以模拟器或代码断言冒充真人真机的结果。**

逐项能力核查：

1. `xcrun simctl privacy <sim> grant/revoke camera <bundle>` 仅作用于 **Simulator**，按规则禁止以模拟器证据冒充真机。
2. `xcrun devicectl` 现有子命令（device info/copy/process/install 等）**无 TCC/隐私状态读取或设置能力**。
3. XCTest/XCUITest 只能对**真实弹出**的系统授权弹窗挂 interruption monitor；当前设备上权限已被真人授予，弹窗不会再出现；重新触发需要 reset privacy 或卸载重装——两者均在禁止清单。
4. 直接修改系统隐私设置本身即被禁止，未尝试。

源码级观察（证据：`/tmp/xfit-snap-20260823` 快照，与设备安装产物同源）：

- 全源码检索无相机授权检查（`AVAuthorizationStatus` / `requestAccess` 无命中）、无跳系统设置入口（`UIApplication.openSettingsURLString` 无命中）、无“相机权限被拒绝”类文案。
- `FitnessApp/Shared/EquipmentRecognitionSheet.swift:139` 处唯一检查为 `UIImagePickerController.isSourceTypeAvailable(.camera)`——这是**硬件可用性**检查而非 TCC 授权状态；无相机硬件时提示“当前设备没有可用相机；可以从相册选择图片。”
- 推论：若用户拒绝相机权限，App 仍会呈现 `UIImagePickerController`（表现为系统级受限/黑屏视图），**App 内无拒绝引导文案、无“去设置”按钮**，恢复完全依赖用户自行到系统设置开启。这是**产品观察项**（潜在体验缺口，不计为本轮测试 FAIL）；是否补做“拒绝引导 + 跳设置”属产品源码变更决策，超出本轮测试边界。
- 已有 `DEV-XCT` 证据的边界澄清：`testEquipmentPhotoRecognitionShowsMachineMusclesAndAddsConfirmedExercise`（`--ui-testing-equipment-recognition` 夹具注入）验证的是识别 sheet 的确认流程，**不含权限路径**，已计入 51/51 xcresult；不得作为 D-CONN-06b 的通过证据。

### 5.2 D-CONN-06b 最少人手步骤（当前停在此门，等待真人）

1. 设置 → 隐私与安全性 → 相机 → X-Fit → **关闭**（此开关只能真人操作）。
2. 回到 X-Fit → “拍照识别器械” → 点“拍照”，**录屏记录实际表现**（按源码观察预期：系统受限/黑屏视图，App 无引导提示）。
3. 设置中**重新开启** X-Fit 相机权限 → 回 App 再点“拍照”，确认相机恢复可用并成功拍照。
4. 将 2–3 步录屏/截图对照本节：若拒绝表现与恢复符合预期，D-CONN-06b 收敛为 `PASS`（拒绝路径证据为 `DEV-MAN`）；若拒绝时出现崩溃、无相册兜底误导或恢复失效，记 `FAIL` 并保留现场。

## 6. 证据与回滚索引

| 层 | 证据 |
|---|---|
| build | `/tmp/xfit-dd-20260823/Build/Products/Debug-iphoneos/FitnessApp.app`；快照 `/tmp/xfit-snap-20260823` |
| install/launch | 本报告 §3.4/§3.5 命令输出（bundle 路径、PID、版本回读） |
| DB（三轮） | `~/Documents/xfit-device-backup-20260823/{pre-install,post-install,post-test}/` |
| 真机 XCTest | `/tmp/xfit-dd-20260823/Logs/Test/Test-FitnessApp-2026.08.23_12-31-12-+0800.xcresult`（单元）与 `…12-32-33-+0800.xcresult`（UI） |
| 人工项 | 待 RDS-M 录屏/截图（尚未产生） |

回滚：本轮数据零变化，无需回滚。若后续人工阶段出现数据问题，用 `pre-install/` 三件套恢复（SHA-256 见 §3.3）。进入任何后续安装前仍须先做新一轮备份，禁止卸载或清容器。

守门确认：全程未卸载、未清容器、未 erase/reset、未删用户数据；主工作区源码零改动（构建全在 `/tmp` 快照 + 独立 DerivedData）；未 commit/push；项目内除本报告外零新增文件；所有备份/检测门通过后才进入安装。

报告人：X-Fit 真机测试 Agent（ZCode）｜日期：2026-08-23（RDS-C 收口：可自动化全部 PASS，P0=0；整体 PARTIAL PASS，人工门待执行）
