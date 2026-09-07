# X-Fit Equipment Recognition Backend

无状态的器械照片识别 API。客户端先做本地 OCR；服务端优先匹配版本化器械词库，配置视觉模型后再对陌生器械生成候选。任何响应都要求用户确认，不会直接改写动作库。

## Local run

```bash
npm install
npm test
npm run dev
```

默认监听 `http://127.0.0.1:8787`。将 iOS Build Setting `EQUIPMENT_RECOGNITION_ENDPOINT` 配置为完整路径，例如：

```text
http://127.0.0.1:8787/v1/equipment/recognitions
```

## Optional model adapter

通过服务端环境变量配置 OpenAI-compatible、支持图片输入和 JSON 输出的模型：

- `VISION_MODEL_API_URL`
- `VISION_MODEL_API_KEY`
- `VISION_MODEL_NAME`

照片仅在当前请求内存中处理，不写入磁盘。生产部署需在网关设置 TLS、鉴权、速率限制和请求体上限。

## Wellness Agent proxy

`POST /v1/wellness/agent` 是手机与 DeepSeek 之间的受限代理。手机只发送最近最多 8 条对话和当天的喝水、跳绳、久坐聚合；服务端只会返回固定协议中的 7 个白名单工具提案，所有写入仍由 iOS 本地确认和执行。

服务端环境变量：

- `DEEPSEEK_API_URL`：例如 `https://api.deepseek.com/chat/completions`
- `DEEPSEEK_API_KEY`：只配置在服务端，不得进入 App 包
- `DEEPSEEK_MODEL`：可选，默认 `deepseek-v4-flash`
- `DEEPSEEK_TIMEOUT_MS`：可选，默认 20000

将 iOS Build Setting `WELLNESS_AGENT_ENDPOINT` 配置为该 HTTPS 路由的完整公开地址。未配置、网络失败或返回协议不可信时，App 自动使用本地受限解析器。代理公开部署前还必须补齐用户/设备鉴权（建议 App Attest）、每用户速率与费用限制；当前代码不应作为匿名公网端点直接发布。
