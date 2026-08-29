# 2026-08-28 真机续测阻塞说明

## 已完成

- 设备在线、配对、Developer Mode 与 DDI 服务检查通过。
- 覆盖安装前已只读备份活动 App Group。
- SQLite `quick_check=ok`；核心记录为 `ZSESSIONEXERCISE=137`、`ZSETLOG=581`、`ZWORKOUTSESSION=20`。
- 未卸载 App、未清容器、未覆盖安装、未执行真机写入测试。

## 阻塞证据

- 真机签名 Release 构建失败：Xcode 报告未登录账号，无法为 `com.edward.FitnessApp` 与 `com.edward.FitnessApp.XFitShareExtension` 生成描述文件。
- 本机 Apple Development 证书仍有效，但旧的免费开发描述文件已于 `2026-08-27 15:05:49 +0000` 过期。
- iOS 对已安装版本的启动回读明确返回：描述文件/签名无效，拒绝启动。

## 恢复条件

在 `Xcode → Settings… → Accounts` 登录项目使用的 Apple ID / Personal Team，随后重新运行真机签名构建。成功后继续覆盖安装、全量真机 XCTest、Instruments 与测试后数据守恒回读。
