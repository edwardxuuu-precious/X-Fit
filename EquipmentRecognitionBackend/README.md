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
