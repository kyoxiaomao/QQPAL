# Godot 对接独立中转服务协议

## 1. 连接信息

- HTTP 基地址：`http://127.0.0.1:18790`
- WebSocket 地址：`ws://127.0.0.1:18790/ws`
- 数据格式：UTF-8 JSON
- 当前无需额外鉴权头

## 2. HTTP 接口

### `GET /health`

用于健康检查。

返回示例：

```json
{
  "status": "ok",
  "service": "standalone-python-bridge",
  "gatewayUrl": "ws://127.0.0.1:18789"
}
```

### `GET /status`

用于查看服务状态。

返回字段：

- `status`：固定为 `ok`
- `service`：服务名
- `port`：监听端口
- `devicesOnline`：当前在线设备数
- `devicesTotal`：累计注册设备数
- `uptime`：服务运行时长，单位毫秒
- `gatewayUrl`：后端 Gateway 地址
- `gatewayReady`：Gateway 是否就绪
- `transportMode`：最近一次实际使用的转发通道
- `lastError`：最近一次错误文本

### `GET /devices`

返回当前设备会话列表。

返回示例：

```json
[
  {
    "deviceId": "godot-demo",
    "sessionKey": "device-godot-demo",
    "status": "online",
    "capabilities": ["text"],
    "metadata": {
      "platform": "godot"
    },
    "transport": "gateway-ws",
    "lastSeenAt": "2026-04-03T08:00:00Z"
  }
]
```

### 其他路径

- `/` 和 `/ws` 允许升级为 WebSocket
- 其他 HTTP 路径返回 `404`

## 3. WebSocket 上行消息

Godot 端连上 WebSocket 后，发送以下 JSON 消息。

### 3.1 注册

```json
{
  "type": "register",
  "deviceId": "godot-demo",
  "capabilities": ["text"],
  "metadata": {
    "platform": "godot",
    "version": "4.x"
  }
}
```

规则：

- `type` 必须为 `register`
- `deviceId` 必填，建议全局唯一
- `capabilities` 可选，字符串数组
- `metadata` 可选，对象

服务端返回：

```json
{
  "type": "ack",
  "success": true,
  "message": "registered"
}
```

如果 `deviceId` 缺失，返回：

```json
{
  "type": "ack",
  "success": false,
  "message": "deviceId required"
}
```

### 3.2 心跳

建议每 15~30 秒发送一次。

```json
{
  "type": "heartbeat",
  "deviceId": "godot-demo",
  "status": "online"
}
```

说明：

- `status` 可选，默认可传 `online`
- 服务端会更新该设备最后活跃时间

返回：

```json
{
  "type": "ack",
  "success": true,
  "message": "heartbeat"
}
```

### 3.3 发送文本消息

```json
{
  "type": "message",
  "deviceId": "godot-demo",
  "text": "你好，请介绍一下你自己"
}
```

字段说明：

- `type` 必须为 `message`
- `deviceId` 必填
- `text` 为要转给后端 Agent 的文本
- `attachments` 当前可传但暂不支持真正处理

如果带附件：

```json
{
  "type": "message",
  "deviceId": "godot-demo",
  "text": "帮我看图",
  "attachments": [
    {
      "name": "image.png"
    }
  ]
}
```

当前返回固定提示：

```json
{
  "type": "response",
  "text": "当前独立中转服务已支持文本链路，附件识别稍后补齐。"
}
```

## 4. WebSocket 下行消息

### 4.1 通用确认

用于 `register` / `heartbeat` / 非法消息反馈。

```json
{
  "type": "ack",
  "success": true,
  "message": "registered"
}
```

错误示例：

```json
{
  "type": "ack",
  "success": false,
  "message": "unsupported type: xxx"
}
```

或：

```json
{
  "type": "ack",
  "success": false,
  "message": "invalid json"
}
```

### 4.2 文本回复

当后端处理成功时：

```json
{
  "type": "response",
  "text": "这里是后端返回给设备的最终文本"
}
```

当后端处理失败时：

```json
{
  "type": "response",
  "error": "具体错误信息"
}
```

## 5. 推荐对接流程

1. Godot 启动时请求 `GET /health`
2. 成功后连接 `ws://127.0.0.1:18790/ws`
3. 建立连接后立即发送 `register`
4. 定时发送 `heartbeat`
5. 玩家发言时发送 `message`
6. 收到 `response.text` 就展示回复
7. 收到 `response.error` 就提示失败并允许重试

## 6. 实现约束

- 一个 WebSocket 连接对应一个当前活跃设备会话
- 服务端仅接受路径 `/` 或 `/ws` 的 WebSocket 连接
- 设备断开后，服务端会把该设备状态标记为 `disconnected`
- `sessionKey` 由服务端生成，格式近似 `device-{deviceId}`
- 当前最稳定能力是纯文本问答
- 大消息体上限约 4 MB

## 7. Godot 侧最小建议

- `deviceId` 固定保存在本地，不要每次启动随机生成
- 收到 `ack.success=false` 或 `response.error` 时做 UI 提示
- WebSocket 断开后自动重连，并重发 `register`
- 心跳与业务消息都带上同一个 `deviceId`
