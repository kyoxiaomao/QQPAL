# runtime-core 接口协议

## 一、文档目的

这份文档用于明确 `runtime-core` 当前阶段的本地接口协议，作为：

- Godot 接入 Runtime 的依据
- 后续扩展执行器适配层的依据
- 协议固化阶段的基础文档

当前文档遵循两个原则：

- **先固化最小可用协议**
- **先描述当前已实现内容，再预留后续扩展**

---

## 二、协议范围

当前这份协议只覆盖：

- Runtime 本地 HTTP API
- 任务状态字段
- 基础错误返回格式
- Godot 与 Runtime 的最小交互约定

当前不覆盖：

- 云主 Agent -> Runtime 的完整协议
- Runtime -> OpenClaw 的执行协议
- 安装器、监控、日志上报协议

---

## 三、基础约定

### 1. 通信方式

- 协议类型：HTTP
- 数据格式：JSON
- 编码：UTF-8

### 2. 当前默认地址

```text
http://127.0.0.1:8765
```

### 3. Content-Type

请求和响应统一使用：

```text
application/json; charset=utf-8
```

---

## 四、状态枚举

当前 Runtime 已定义状态：

- `idle`
- `talking`
- `planning`
- `running`
- `waiting_user`
- `success`
- `failed`
- `paused`

### 当前最小 demo 会实际使用的状态

- `talking`
- `planning`
- `running`
- `success`
- `failed`

### 状态含义

| 状态 | 含义 |
| --- | --- |
| `idle` | 空闲，没有执行任务 |
| `talking` | 已接收输入，正在确认需求 |
| `planning` | 正在生成执行方案 |
| `running` | 正在执行任务 |
| `waiting_user` | 执行过程中等待用户补充信息 |
| `success` | 任务完成且成功 |
| `failed` | 任务完成但失败 |
| `paused` | Runtime 或任务进入暂停状态 |

---

## 五、任务对象模型

当前任务对象统一使用如下结构：

```json
{
  "task_id": "task_xxxxx",
  "user_input": "打开网页并提交表单",
  "status": "planning",
  "result": "",
  "error": "",
  "timestamps": {
    "created_at": "2026-03-25T13:51:19.788586+00:00",
    "updated_at": "2026-03-25T13:51:19.788730+00:00",
    "status_text": "正在确认需求",
    "finished_at": "2026-03-25T13:51:20.390146+00:00"
  }
}
```

### 字段说明

| 字段 | 类型 | 必填 | 含义 |
| --- | --- | --- | --- |
| `task_id` | string | 是 | 任务唯一标识 |
| `user_input` | string | 是 | 用户原始输入 |
| `status` | string | 是 | 当前任务状态 |
| `result` | string | 是 | 成功结果，未完成时可为空字符串 |
| `error` | string | 是 | 错误信息，未失败时可为空字符串 |
| `timestamps` | object | 是 | 时间与状态补充信息 |

### `timestamps` 子字段

| 字段 | 类型 | 必填 | 含义 |
| --- | --- | --- | --- |
| `created_at` | string | 否 | 任务创建时间，ISO 8601 |
| `updated_at` | string | 否 | 最近状态更新时间，ISO 8601 |
| `finished_at` | string | 否 | 任务结束时间，ISO 8601 |
| `status_text` | string | 否 | 当前状态对应的人类可读说明 |

---

## 六、接口总览

当前 Runtime 已实现 3 个接口：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `GET` | `/health` | 健康检查 |
| `POST` | `/tasks` | 创建任务 |
| `GET` | `/tasks/{task_id}` | 查询任务状态 |

---

## 七、接口详情

## 1. 健康检查

### 请求

```http
GET /health
```

### 请求体

无

### 成功响应

**状态码**

```text
200 OK
```

**响应示例**

```json
{
  "service": "runtime-core",
  "status": "ok",
  "host": "127.0.0.1",
  "port": 8765,
  "demo_mode": true
}
```

### 响应字段说明

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `service` | string | 服务名称 |
| `status` | string | 服务健康状态 |
| `host` | string | 当前监听地址 |
| `port` | number | 当前监听端口 |
| `demo_mode` | boolean | 当前是否处于 demo 模式 |

---

## 2. 创建任务

### 请求

```http
POST /tasks
```

### 请求体支持两种格式

#### 格式 A

```json
{
  "input": {
    "text": "打开网页并提交表单"
  }
}
```

#### 格式 B

```json
{
  "user_input": "打开网页并提交表单"
}
```

### 可选字段

```json
{
  "should_fail": true
}
```

这个字段只用于当前 demo 阶段，用来模拟失败流程。

### 字段说明

| 字段 | 类型 | 必填 | 含义 |
| --- | --- | --- | --- |
| `input.text` | string | 二选一 | 推荐格式中的用户输入 |
| `user_input` | string | 二选一 | 兼容格式中的用户输入 |
| `should_fail` | boolean | 否 | 是否触发失败演示路径 |

### 成功响应

**状态码**

```text
202 Accepted
```

**响应示例**

```json
{
  "task_id": "task_c91de327ef81",
  "user_input": "打开网页并提交表单",
  "status": "talking",
  "result": "",
  "error": "",
  "timestamps": {
    "created_at": "2026-03-25T13:51:19.788586+00:00",
    "updated_at": "2026-03-25T13:51:19.788730+00:00",
    "status_text": "正在确认需求"
  }
}
```

### 失败响应

**状态码**

```text
400 Bad Request
```

**响应示例**

```json
{
  "error": "user_input or input.text is required"
}
```

---

## 3. 查询任务

### 请求

```http
GET /tasks/{task_id}
```

### 路径参数

| 参数 | 类型 | 必填 | 含义 |
| --- | --- | --- | --- |
| `task_id` | string | 是 | 要查询的任务 ID |

### 成功响应

**状态码**

```text
200 OK
```

**响应示例**

```json
{
  "task_id": "task_c91de327ef81",
  "user_input": "打开网页并提交表单",
  "status": "success",
  "result": "已完成示例任务：打开网页并提交表单",
  "error": "",
  "timestamps": {
    "created_at": "2026-03-25T13:51:19.788586+00:00",
    "updated_at": "2026-03-25T13:51:20.390101+00:00",
    "status_text": "任务执行完成",
    "finished_at": "2026-03-25T13:51:20.390146+00:00"
  }
}
```

### 未找到任务

**状态码**

```text
404 Not Found
```

**响应示例**

```json
{
  "error": "task not found: task_xxxxx"
}
```

---

## 八、错误响应规范

当前最小版本统一使用：

```json
{
  "error": "错误说明"
}
```

### 当前已定义错误场景

| 场景 | 状态码 | 响应 |
| --- | --- | --- |
| 路由不存在 | `404` | `{"error":"route not found"}` |
| 创建任务缺少输入 | `400` | `{"error":"user_input or input.text is required"}` |
| 任务不存在 | `404` | `{"error":"task not found: xxx"}` |

### 后续建议扩展

后续可以升级为：

```json
{
  "error": {
    "code": "TASK_NOT_FOUND",
    "message": "task not found",
    "detail": "task_xxxxx"
  }
}
```

但当前阶段不建议过早复杂化。

---

## 九、当前状态流转协议

当前 demo 任务流转：

```text
创建任务
-> talking
-> planning
-> running
-> success / failed
```

### 成功路径

```text
talking -> planning -> running -> success
```

### 失败路径

```text
talking -> planning -> running -> failed
```

### 当前约定

- `POST /tasks` 返回时，任务已经进入 `talking`
- `GET /tasks/{task_id}` 用于轮询获取后续状态
- `result` 只在 `success` 时具备有效内容
- `error` 只在 `failed` 时具备有效内容

---

## 十、Godot 接入约定

Godot 当前建议按下面方式接入：

### 1. 提交任务

- 快捷对话框提交内容到 `POST /tasks`
- 主窗口对话页提交内容到 `POST /tasks`

### 2. 保存 task_id

- 当 `POST /tasks` 返回后，保存 `task_id`

### 3. 轮询状态

- 定时请求 `GET /tasks/{task_id}`
- 直到任务进入：
  - `success`
  - `failed`
  - 后续扩展的终止状态

### 4. 展示映射

Godot 消费的核心字段：

- `task_id`
- `status`
- `result`
- `error`
- `timestamps.status_text`

### 5. 当前不建议 Godot 自己推断业务状态

也就是说：

- Runtime 是状态源
- Godot 是展示层

---

## 十一、后续扩展接口建议

当前不要求立即实现，但建议后续补齐：

### 1. 任务列表

```http
GET /tasks
```

### 2. 取消任务

```http
POST /tasks/{task_id}/cancel
```

### 3. 暂停任务

```http
POST /tasks/{task_id}/pause
```

### 4. 恢复任务

```http
POST /tasks/{task_id}/resume
```

### 5. Runtime 配置查询

```http
GET /runtime/config
```

---

## 十二、版本说明

这份协议文档对应的是：

- 当前 `runtime-core` 最小 demo 版本
- 当前 `src/api/server.py` 的实际已实现行为

因此这份文档属于：

**当前实现协议**

后续如果接口发生变化，应优先更新这份文档，再同步 Godot 和 Runtime 实现。

---

## 十三、一句话结论

当前 `runtime-core` 协议已经足够支撑 **Godot -> Runtime 的最小联调**，下一步可以直接据此开始写 `RuntimeTaskService`。 
