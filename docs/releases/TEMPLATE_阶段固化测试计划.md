# X-Fit <版本> 阶段固化测试计划

- 阶段：`<名称>`
- 版本/Build：`<version> (<build>)`
- Git branch / HEAD：`<branch> / <sha>`
- 测试状态：`NOT_RUN`
- 决策：`PARTIAL/BLOCKED`

## 纳入需求

| 需求文件 | 状态 | 纳入原因 |
|---|---|---|
|  |  |  |

## 未纳入需求

| 需求文件 | 原因 | 后续阶段 |
|---|---|---|
|  |  |  |

## 测试环境

| 层级 | 环境 |
|---|---|
| Mac / Xcode |  |
| Simulator |  |
| iPhone / iOS |  |
| App Group | `group.com.edward.FitnessApp` |

## 执行命令

```bash
scripts/xfit-stage-validation.sh non-device

XFIT_DEVICE_ID='<device-id>' \
XFIT_ALLOW_DEVICE_INSTALL=1 \
XFIT_ALLOW_DEVICE_TESTS=1 \
scripts/xfit-stage-validation.sh device
```

## 分层结果

| AC ID / Gate | 预期结果 | 实际结果 | 状态 | 证据 | 阻塞/说明 |
|---|---|---|---|---|---|
| AC-__ / 非真机静态检查与构建 |  |  | NOT_RUN |  |  |
| AC-__ / 全量单元/服务测试 |  |  | NOT_RUN |  |  |
| AC-__ / 全量 Simulator UI |  |  | NOT_RUN |  |  |
| AC-__ / 真机签名 Release 构建 |  |  | NOT_RUN |  |  |
| AC-__ / 安装前活动数据备份 |  |  | NOT_RUN |  |  |
| AC-__ / 覆盖安装与启动回读 |  |  | NOT_RUN |  |  |
| AC-__ / 真机单元/UI 自动化 |  |  | NOT_RUN |  |  |
| AC-__ / 安装后/测试后数据守恒 |  |  | NOT_RUN |  |  |
| AC-__ / 真人体验清单 |  |  | BLOCKED_HUMAN |  |  |

## 发布门

- [ ] P0/P1 失败为 0。
- [ ] 非真机完整测试全部通过。
- [ ] 真机必测项全部执行，无跳过冒充通过。
- [ ] 活动 App Group `quick_check=ok`，核心记录不减少。
- [ ] 覆盖安装，没有卸载或清容器。
- [ ] 真人关键体验完成并签字。
- [ ] 未解决需求冲突为 0。

## 最终结论

- 决策：`GO / NO-GO / PARTIAL-BLOCKED`
- 已完成：
- 阻塞：
- 下一步：
