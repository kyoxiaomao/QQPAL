# runtime-quickchat 流式对话计划

## Summary

- 目标：把 [test-bridge-guest.ps1](file:///d:/QQPAL/test-bridge-guest.ps1) 中已经验证可用的 bridge WebSocket 收发与流式事件处理逻辑，精简后复现到 `runtime-core`，并让 Godot 桌宠“快速对话框”走 runtime 的流式链路。
- 本次范围：仅覆盖 Godot 桌宠快速对话框，不包含主应用聊天页与旧 demo 任务流。
- 传输方案：Godot 与 `runtime-core` 之间采用 SSE 单向流；Godot 上行仍保留现有 HTTP 提交消息方式。
- 兼容策略：允许重构 `runtime-core` 对外 API 以更适配流式，但会尽量保留现有可用接口，避免无关调用立即失效。

## Current State Analysis

### 1. 快速对话框 UI 已接 runtime，但只支持最终结果

- 快速对话框 UI 在 [QuickChatPanel.gd](file:///d:/QQPAL/godot-app/scripts/pet/QuickChatPanel.gd#L1-L124)，当前只有 `append_message()`，没有“更新最后一条 assistant 气泡”的能力。
- 桌宠入口在 [DesktopPet.gd](file:///d:/QQPAL/godot-app/scripts/pet/DesktopPet.gd#L236-L239)，打开后由 [Main.gd](file:///d:/QQPAL/godot-app/scripts/Main.gd#L89-L109) 把发送动作转给 `QuickChatRuntimeService`。
- [Main.gd](file:///d:/QQPAL/godot-app/scripts/Main.gd#L146-L163) 当前只接 `status_changed / message_received / system_message` 三种信号，没有流式片段信号。

### 2. Godot runtime 客户端是轮询最终状态，不是流式消费

- [QuickChatRuntimeService.gd](file:///d:/QQPAL/godot-app/scripts/services/QuickChatRuntimeService.gd#L1-L214) 现状：
  - `POST /chat/messages` 提交消息；
  - `GET /status` 每秒轮询一次；
  - 从 `latestResponse.text/error` 中一次性取最终回复；
  - 点击停止时调用 `/tasks/{id}/cancel`。
- 这套实现没有流式下行、没有 assistant 占位消息、没有片段更新语义。

### 3. runtime-core 内部仍是“单请求 -> 单最终响应”

- [server.py](file:///d:/QQPAL/runtime-core/src/api/server.py#L14-L117) 当前对外是普通 HTTP JSON 接口，没有 SSE。
- [manager.py](file:///d:/QQPAL/runtime-core/src/task/manager.py#L19-L177) 提交后异步跑 `_run_task()`，但只在结束时写入最终 `result/error`。
- [client.py](file:///d:/QQPAL/runtime-core/src/bridge/client.py#L66-L79) 的 `submit_message()` 只 `recv()` 一次，不支持 `assistant.delta / assistant.final / assistant.error` 多帧流式协议。

### 4. 已验证的流式协议逻辑在测试脚本里

- [test-bridge-guest.ps1](file:///d:/QQPAL/test-bridge-guest.ps1#L415-L596) 已能兼容：
  - `type=event + event=assistant.delta`
  - `type=event + event=assistant.final`
  - `type=event + event=assistant.error`
  - 旧 `response`
- 脚本还验证了首包耗时可能大于 6 秒，默认超时已改为 30 秒，见 [test-bridge-guest.ps1](file:///d:/QQPAL/test-bridge-guest.ps1#L1-L9) 与 [test-bridge-guest.ps1](file:///d:/QQPAL/test-bridge-guest.ps1#L794-L813)。

## Assumptions & Decisions

- 仅改造桌宠快速对话框，不切主应用聊天页。
- Godot UI 的期望交互为“单气泡实时更新”。
- 用户点击停止后，保留已收到片段，并把该条 assistant 回复标记为被中断。
- Godot <-> runtime-core 使用 SSE 单向流；消息上行继续使用 `POST /chat/messages`。
- `runtime-core` 内部 bridge 连接仍保持 WebSocket，直接复用并精简测试脚本中的流式解析思路。
- 旧 `/status` 与 `/tasks/{id}/cancel` 可继续保留，但快速对话框在流式模式下不再依赖 `/status.latestResponse` 取正文。

## Proposed Changes

### 1. runtime-core：把 bridge client 改为真正支持流式事件

#### 文件

- [runtime-core/src/bridge/client.py](file:///d:/QQPAL/runtime-core/src/bridge/client.py)

#### 变更

- 从 `test-bridge-guest.ps1` 精简迁移这些核心能力到 Python：
  - 统一事件类型识别；
  - 兼容 `type=event/event=assistant.delta|final|error`；
  - 兼容 `payload.text` 与旧 `response.text/error`；
  - 按请求维度跟踪 `requestId/sessionKey/runId`；
  - 支持首包时间、首 delta 时间、最终完成状态。
- 将当前 `submit_message()` 的一次性阻塞返回，拆成“生成事件流”的接口，例如：
  - `stream_message(...) -> Iterator[dict]`
  - 或内部回调式事件分发。
- 保留一个“收敛最终结果”的辅助方法，供非流式路径复用。

#### 为什么

- 当前 `client.py` 只会收一帧 JSON，无法驱动 SSE，也无法把 bridge 的流式响应暴露给上层。

### 2. runtime-core：扩展任务模型与任务管理，保存流式中间状态

#### 文件

- [runtime-core/src/task/models.py](file:///d:/QQPAL/runtime-core/src/task/models.py)
- [runtime-core/src/task/manager.py](file:///d:/QQPAL/runtime-core/src/task/manager.py)

#### 变更

- 在 `TaskRecord` 中新增流式字段，至少包括：
  - `stream_text`
  - `final_text`
  - `run_id`
  - `session_key`
  - `first_packet_at`
  - `first_delta_at`
  - `finished`
- 在 `TaskManager._run_task()` 中改为消费 bridge 事件流：
  - `assistant.delta` 时持续更新 `stream_text/status/status_text`
  - `assistant.final` 时写入 `final_text/result`
  - `assistant.error` 时写入 `error`
  - 停止请求时结束本地流并保留已收到文本
- 明确任务状态机：
  - 提交后进入 `talking`
  - 收到首包后进入 `running`
  - 完成后 `success`
  - 错误/取消后 `failed`

#### 为什么

- SSE 需要 runtime 持有“最新流式状态”，而不是只在结束时一次性落最终结果。

### 3. runtime-core：新增快速对话流式接口

#### 文件

- [runtime-core/src/api/server.py](file:///d:/QQPAL/runtime-core/src/api/server.py)

#### 变更

- 保留现有 `POST /chat/messages` 作为创建任务入口。
- 新增一个 SSE GET 接口，推荐形态：
  - `GET /chat/stream?taskId=...`
  - 或 `GET /chat/stream?requestId=...`
- SSE 事件约定为明确的 event type：
  - `status`
  - `assistant.delta`
  - `assistant.final`
  - `assistant.error`
  - `done`
- SSE data 中统一包含：
  - `taskId`
  - `requestId`
  - `sessionKey`
  - `runId`
  - `text`
  - `error`
  - `finished`
  - `firstPacketMs`
  - `firstDeltaMs`
- `/tasks/{id}/cancel` 保留，但需要能终止当前 SSE 对应任务。

#### 为什么

- 既然用户选择 SSE，runtime-core 就必须有一个清晰、稳定、专用于流式下行的接口，而不是继续让 Godot 从 `/status` 猜最新回复。

### 4. Godot：QuickChatRuntimeService 改成“提交 + 订阅 SSE”

#### 文件

- [godot-app/scripts/services/QuickChatRuntimeService.gd](file:///d:/QQPAL/godot-app/scripts/services/QuickChatRuntimeService.gd)

#### 变更

- 保留 `submit_text()` 提交消息，但成功后：
  - 解析返回的 `taskId/requestId`
  - 立刻发起 SSE 连接
  - 消费 `assistant.delta/final/error/done`
- 新增流式信号，预计包括：
  - `stream_started(request_id)`
  - `stream_delta(text, request_id)`
  - `stream_finished(text, request_id, finished: bool)`
  - `stream_failed(error, request_id)`
- `status_changed` 继续保留，但快速对话的正文展示不再依赖 `_handle_latest_response()`。
- `stop_current_request()` 保持原接口，但停止后要关闭当前 SSE 读取并等待 runtime 返回取消结果。
- 弱化或删除 `_last_response_signature` 这套最终响应去重逻辑在 quick chat 流式路径中的职责。

#### 为什么

- 当前服务层只懂轮询最终结果，不适合“单气泡实时更新”。

### 5. Godot：QuickChatPanel 增加“单气泡实时更新”能力

#### 文件

- [godot-app/scripts/pet/QuickChatPanel.gd](file:///d:/QQPAL/godot-app/scripts/pet/QuickChatPanel.gd)

#### 变更

- 为历史区增加“更新最后一条 assistant 消息”的能力，而不是每个片段都 `append_message()`。
- 推荐引入如下方法：
  - `begin_assistant_message()`
  - `update_assistant_message(text: String)`
  - `finish_assistant_message(text: String, interrupted: bool = false)`
  - `append_system_message(text: String)`
- 发送用户消息后先创建 assistant 占位气泡。
- 收到 `assistant.delta` 时持续覆盖更新该气泡。
- 收到 `assistant.final` 时定稿。
- 停止后若已有片段，则保留片段并追加“已停止”或等价标识。

#### 为什么

- 当前 `append_message()` 只能追加整行，无法做流式视觉体验。

### 6. Godot：Main.gd 改成消费流式信号

#### 文件

- [godot-app/scripts/Main.gd](file:///d:/QQPAL/godot-app/scripts/Main.gd)

#### 变更

- 连接 `QuickChatRuntimeService` 的新增流式信号。
- 在 `_on_quick_chat_task_requested()` 发出后，让 `QuickChatPanel` 创建 assistant 占位消息。
- 在新的回调中：
  - `delta` -> 更新最后一条 assistant 文本
  - `final` -> 完成 assistant 文本
  - `error` -> 结束占位并显示系统错误
- 保持桌宠状态与流式状态同步：
  - 连接中/等待首包 -> `talking`
  - 正在流式输出 -> `running`
  - 完成/取消 -> `idle`

#### 为什么

- 现有 `Main.gd` 只会把最终文本 `append_message("QQPAL", text)`，需要切换到流式事件驱动。

## Implementation Order

1. 精简提炼 `test-bridge-guest.ps1` 的事件解析逻辑，迁移到 `runtime-core/src/bridge/client.py`
2. 扩展 `TaskRecord` 与 `TaskManager`，让 runtime 内部保存流式中间态
3. 在 `runtime-core/src/api/server.py` 增加 SSE 流式下行接口
4. 将 `QuickChatRuntimeService.gd` 从轮询最终结果改成“HTTP 提交 + SSE 订阅”
5. 为 `QuickChatPanel.gd` 增加单气泡实时更新 API
6. 在 `Main.gd` 接入流式信号，完成 quick chat UI 联动
7. 回归验证停止逻辑、超时行为、首包耗时与最终落盘状态

## Verification

- 代码级验证：
  - `runtime-core` 可启动，SSE 接口可建立连接并持续输出事件
  - `QuickChatRuntimeService.gd` 可在 Godot 中正常建立/关闭 SSE
- 协议验证：
  - `assistant.delta` 能被逐步转发到 Godot
  - `assistant.final` 能终结 SSE 并定稿最终文本
  - `assistant.error` 能显示错误并结束会话
- UI 验证：
  - 快速对话框中用户发送后立即出现 assistant 占位消息
  - 文本随 delta 实时增长
  - 点击停止后保留已有片段
- 稳定性验证：
  - 默认 30 秒超时下能覆盖“首包 7s+”的慢响应场景
  - 至少验证一次成功流式返回和一次取消/超时路径

## Risks

- Godot 原生 SSE 读取实现复杂度高于 `HTTPRequest` 轮询，需要谨慎设计读取循环与关闭时机。
- `runtime-core` 当前 bridge keepalive 与业务收包共用同一个 WebSocket，若处理不当可能造成心跳和流式业务帧竞争。
- 现有 `/status` 拼装 `latestResponse` 的逻辑不是按 `requestId` 严格绑定，若保留旧逻辑需避免与新 SSE 路径互相干扰。
