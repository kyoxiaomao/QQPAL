extends Node

signal status_changed(status_text: String, is_busy: bool, can_submit: bool)
signal message_received(text: String)
signal system_message(text: String)
signal stream_started(request_id: String)
signal stream_delta(text: String, request_id: String)
signal stream_finished(text: String, request_id: String, interrupted: bool)
signal stream_failed(error_text: String, request_id: String)

const RUNTIME_HTTP_BASE_URL := "http://127.0.0.1:8765"
const RUNTIME_POLL_SECONDS := 1.0
const DEVICE_CONFIG_PATH := "user://quick_chat_runtime.cfg"
const STARTUP_NOTICE_PATH := "user://runtime_startup_notice.json"
const QUICK_CHAT_TRACE_PATH := "user://quick-chat.trace.jsonl"
const RUNTIME_HTTP_HOST := "127.0.0.1"
const RUNTIME_HTTP_PORT := 8765
const STREAM_FIRST_PACKET_HINT_SECONDS := 8.0
const STREAM_RECONNECT_DELAY_SECONDS := 1.0
const STREAM_MAX_RECONNECT_ATTEMPTS := 2

var _status_request: HTTPRequest
var _message_request: HTTPRequest
var _cancel_request: HTTPRequest
var _poll_timer: Timer
var _device_id := ""
var _runtime_online := false
var _ai_state := "disconnected"
var _active_task_id := ""
var _active_request_id := ""
var _stream_client: HTTPClient
var _stream_buffer := ""
var _stream_request_started := false
var _stream_started_emitted := false
var _stream_finished_locally := false
var _stream_text := ""
var _stream_wait_started_at_msec := 0
var _stream_first_packet_received := false
var _stream_first_packet_hint_emitted := false
var _stream_reconnect_attempt := 0
var _stream_reconnect_due_at_msec := 0
var _stream_cancel_requested := false
var _current_client_message_id := ""
var _status_in_flight := false
var _message_in_flight := false


func _ready() -> void:
	_device_id = _load_or_create_device_id()
	_status_request = HTTPRequest.new()
	_status_request.timeout = 5.0
	_status_request.request_completed.connect(_on_status_request_completed)
	add_child(_status_request)

	_message_request = HTTPRequest.new()
	_message_request.timeout = 10.0
	_message_request.request_completed.connect(_on_message_request_completed)
	add_child(_message_request)

	_cancel_request = HTTPRequest.new()
	_cancel_request.timeout = 5.0
	_cancel_request.request_completed.connect(_on_cancel_request_completed)
	add_child(_cancel_request)

	_poll_timer = Timer.new()
	_poll_timer.one_shot = false
	_poll_timer.wait_time = RUNTIME_POLL_SECONDS
	_poll_timer.timeout.connect(_request_status)
	add_child(_poll_timer)
	_poll_timer.start()
	set_process(true)
	_emit_startup_notice_if_any()
	_request_status()


func _process(_delta: float) -> void:
	_maybe_retry_stream()
	_maybe_emit_first_packet_hint()
	_poll_stream()


func submit_text(text: String) -> bool:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return false
	if not _can_submit():
		return false
	if _message_in_flight:
		return false

	_message_in_flight = true
	_current_client_message_id = "msg_%s" % Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	_write_trace("godot.submit.request", {
		"source": "godot",
		"text": clean_text,
		"deviceId": _device_id,
		"clientMessageId": _current_client_message_id
	})
	var body := JSON.stringify({
		"source": "quick_chat",
		"sessionId": "quick_chat_default",
		"deviceId": _device_id,
		"text": clean_text,
		"clientMessageId": _current_client_message_id
	})
	var error := _message_request.request(
		"%s/chat/messages" % RUNTIME_HTTP_BASE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		_message_in_flight = false
		_write_trace("godot.submit.error", {
			"source": "godot",
			"clientMessageId": _current_client_message_id,
			"error": "request_start_failed"
		})
		return false
	return true


func stop_current_request() -> void:
	if _active_task_id.is_empty():
		return
	if _cancel_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_stream_cancel_requested = true
	var error := _cancel_request.request(
		"%s/tasks/%s/cancel" % [RUNTIME_HTTP_BASE_URL, _active_task_id],
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		"{}"
	)
	if error != OK:
		_stream_cancel_requested = false
		system_message.emit("停止任务失败。")


func _request_status() -> void:
	if _status_in_flight:
		return
	_status_in_flight = true
	var error := _status_request.request("%s/status" % RUNTIME_HTTP_BASE_URL)
	if error != OK:
		_status_in_flight = false
		_runtime_online = false
		_ai_state = "disconnected"
		_active_task_id = ""
		_emit_current_status()


func _emit_current_status() -> void:
	var is_busy := not _active_task_id.is_empty() or _ai_state == "thinking" or _ai_state == "running" or _ai_state == "recovering"
	var can_submit := _runtime_online and _ai_state == "online" and _active_task_id.is_empty()
	var status_text := "AI离线"
	if _ai_state == "service_offline":
		status_text = "服务离线"
	elif _ai_state == "service_error":
		status_text = "服务异常"
	elif _ai_state == "recovering":
		status_text = "连接恢复中"
	elif not _active_task_id.is_empty() and _stream_reconnect_due_at_msec > 0:
		status_text = "连接波动，正在重连"
	elif _ai_state == "thinking":
		if _stream_first_packet_hint_emitted:
			status_text = "等待首包（响应较慢）"
		else:
			status_text = "等待首包"
	elif _ai_state == "running":
		status_text = "AI回复中"
	elif _ai_state == "online":
		status_text = "AI空闲"
	status_changed.emit(status_text, is_busy, can_submit)


func _maybe_emit_first_packet_hint() -> void:
	if _active_task_id.is_empty():
		return
	if _stream_first_packet_received or _stream_first_packet_hint_emitted:
		return
	if _stream_wait_started_at_msec <= 0:
		return
	var elapsed_ms := Time.get_ticks_msec() - _stream_wait_started_at_msec
	if elapsed_ms < int(STREAM_FIRST_PACKET_HINT_SECONDS * 1000.0):
		return
	_stream_first_packet_hint_emitted = true
	system_message.emit("首包响应较慢，正在继续等待…")
	_emit_current_status()


func _maybe_retry_stream() -> void:
	if _stream_reconnect_due_at_msec <= 0:
		return
	if Time.get_ticks_msec() < _stream_reconnect_due_at_msec:
		return
	_stream_reconnect_due_at_msec = 0
	_open_stream_client()


func _open_stream_client() -> void:
	_dispose_stream_client()
	_stream_client = HTTPClient.new()
	var error := _stream_client.connect_to_host(RUNTIME_HTTP_HOST, RUNTIME_HTTP_PORT)
	if error != OK:
		_handle_stream_transport_error("建立流式连接失败。")
		return
	_ai_state = "thinking" if not _stream_first_packet_received else "running"
	_emit_current_status()


func _has_pending_stream() -> bool:
	return not _active_task_id.is_empty() and (_stream_client != null or _stream_reconnect_due_at_msec > 0)


func _load_or_create_device_id() -> String:
	var config := ConfigFile.new()
	var load_error := config.load(DEVICE_CONFIG_PATH)
	if load_error == OK:
		var existing_id := str(config.get_value("device", "id", "")).strip_edges()
		if not existing_id.is_empty():
			return existing_id

	var new_id := "godot-%s" % Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	config.set_value("device", "id", new_id)
	config.save(DEVICE_CONFIG_PATH)
	return new_id


func _emit_startup_notice_if_any() -> void:
	if not FileAccess.file_exists(STARTUP_NOTICE_PATH):
		return
	var file := FileAccess.open(STARTUP_NOTICE_PATH, FileAccess.READ)
	if file == null:
		return
	var raw_text := file.get_as_text()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STARTUP_NOTICE_PATH))
	if raw_text.strip_edges().is_empty():
		return
	var payload = JSON.parse_string(raw_text)
	if typeof(payload) != TYPE_DICTIONARY:
		return
	var message := _build_startup_notice_message(payload)
	if not message.is_empty():
		_write_trace("godot.startup.notice", {
			"source": "godot",
			"code": str(payload.get("code", "")),
			"detail": str(payload.get("detail", "")),
			"message": message
		})
		system_message.emit(message)


func _build_startup_notice_message(payload: Dictionary) -> String:
	var code := str(payload.get("code", ""))
	var detail := str(payload.get("detail", ""))
	match code:
		"runtime_start_failed":
			if detail == "process_exited":
				return "runtime 自动拉起后很快退出了，请检查 runtime-core 启动日志。"
			return "runtime 自动拉起超时，已启动前端，但 AI 服务暂时不可用。"
		"runtime_entrypoint_missing":
			return "未找到 runtime-core 启动入口，请检查 runtime-core/src/main.py 是否存在。"
		"python_missing":
			return "本机未找到 Python，无法自动启动 runtime-core。"
		_:
			return ""


func _can_submit() -> bool:
	return _runtime_online and _ai_state == "online" and _active_task_id.is_empty()


func _start_stream(task_id: String, request_id: String) -> void:
	_reset_stream_state()
	_active_task_id = task_id
	_active_request_id = request_id
	_stream_wait_started_at_msec = Time.get_ticks_msec()
	_write_trace("godot.submit.accepted", {
		"source": "godot",
		"taskId": task_id,
		"requestId": request_id,
		"clientMessageId": _current_client_message_id
	})
	_open_stream_client()


func _poll_stream() -> void:
	if _stream_client == null:
		return
	var poll_error := _stream_client.poll()
	if poll_error != OK:
		_handle_stream_transport_error("流式连接失败。")
		return
	var status := _stream_client.get_status()
	if status == HTTPClient.STATUS_CONNECTED and not _stream_request_started:
		var path := "/chat/stream?taskId=%s" % _active_task_id.uri_encode()
		var request_error := _stream_client.request(HTTPClient.METHOD_GET, path, ["Accept: text/event-stream"])
		if request_error != OK:
			_handle_stream_transport_error("打开流式接口失败。")
			return
		_stream_request_started = true
		return
	if status == HTTPClient.STATUS_BODY:
		while true:
			var chunk := _stream_client.read_response_body_chunk()
			if chunk.is_empty():
				break
			_stream_buffer += chunk.get_string_from_utf8()
		_consume_stream_buffer()
		return
	if status == HTTPClient.STATUS_DISCONNECTED and _stream_request_started and not _stream_finished_locally:
		_handle_stream_transport_error("流式连接已断开。")


func _consume_stream_buffer() -> void:
	_stream_buffer = _stream_buffer.replace("\r\n", "\n")
	while true:
		var separator_index := _stream_buffer.find("\n\n")
		if separator_index < 0:
			return
		var chunk := _stream_buffer.substr(0, separator_index)
		_stream_buffer = _stream_buffer.substr(separator_index + 2)
		_handle_sse_chunk(chunk)


func _handle_sse_chunk(chunk: String) -> void:
	var event_name := "message"
	var data_lines: Array[String] = []
	for raw_line in chunk.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with(":"):
			continue
		if line.begins_with("event:"):
			event_name = line.substr(6).strip_edges()
			continue
		if line.begins_with("data:"):
			data_lines.append(line.substr(5).strip_edges())
	if data_lines.is_empty():
		return
	var payload = JSON.parse_string("\n".join(data_lines))
	if typeof(payload) != TYPE_DICTIONARY:
		return
	_handle_stream_event(event_name, payload)


func _handle_stream_event(event_name: String, payload: Dictionary) -> void:
	var request_id := str(payload.get("requestId", _active_request_id))
	var text := str(payload.get("text", ""))
	var error_text := str(payload.get("error", ""))
	var interrupted := bool(payload.get("interrupted", false))
	var trace_payload := {
		"source": "godot",
		"taskId": str(payload.get("taskId", _active_task_id)),
		"requestId": request_id,
		"clientMessageId": _current_client_message_id,
		"event": event_name,
		"text": text,
		"error": error_text,
		"interrupted": interrupted,
		"firstPacketMs": payload.get("firstPacketMs", null),
		"firstDeltaMs": payload.get("firstDeltaMs", null),
		"totalMs": payload.get("totalMs", null)
	}
	if not _stream_started_emitted and not request_id.is_empty():
		_stream_started_emitted = true
		stream_started.emit(request_id)
	match event_name:
		"status":
			_write_trace("godot.sse.event", trace_payload)
			var status_value := str(payload.get("status", ""))
			if status_value == "running":
				_ai_state = "running"
			elif status_value == "failed":
				_ai_state = "online"
			else:
				_ai_state = "thinking"
			_emit_current_status()
		"assistant.delta":
			_mark_first_packet_received()
			trace_payload["firstPacketMs"] = _first_packet_elapsed_ms()
			_write_trace("godot.sse.event", trace_payload)
			_stream_text = text
			_ai_state = "running"
			_emit_current_status()
			stream_delta.emit(_stream_text, request_id)
		"assistant.final":
			_mark_first_packet_received()
			trace_payload["firstPacketMs"] = _first_packet_elapsed_ms()
			_write_trace("godot.sse.event", trace_payload)
			_stream_text = text
			_ai_state = "online"
			_emit_current_status()
			stream_finished.emit(_stream_text, request_id, interrupted)
			_stream_finished_locally = true
			_reset_stream_state()
		"assistant.error":
			_mark_first_packet_received()
			trace_payload["firstPacketMs"] = _first_packet_elapsed_ms()
			_write_trace("godot.sse.event", trace_payload)
			_ai_state = "online"
			_emit_current_status()
			if not error_text.is_empty():
				stream_failed.emit(error_text, request_id)
			if interrupted and (not text.is_empty() or not _stream_text.is_empty()):
				if text.is_empty():
					text = _stream_text
				stream_finished.emit(text, request_id, true)
			_stream_finished_locally = true
			_reset_stream_state()
		"done":
			_write_trace("godot.sse.event", trace_payload)
			_stream_finished_locally = true
			_reset_stream_state()


func _handle_stream_transport_error(message: String) -> void:
	if _schedule_stream_reconnect():
		return
	_ai_state = "online" if _runtime_online else "disconnected"
	_write_trace("godot.stream.error", {
		"source": "godot",
		"taskId": _active_task_id,
		"requestId": _active_request_id,
		"clientMessageId": _current_client_message_id,
		"error": message,
		"firstPacketMs": _first_packet_elapsed_ms()
	})
	stream_failed.emit(message, _active_request_id)
	_reset_stream_state()
	_emit_current_status()


func _schedule_stream_reconnect() -> bool:
	if _active_task_id.is_empty():
		return false
	if _stream_cancel_requested:
		return false
	if _stream_reconnect_attempt >= STREAM_MAX_RECONNECT_ATTEMPTS:
		return false
	_stream_reconnect_attempt += 1
	_stream_reconnect_due_at_msec = Time.get_ticks_msec() + int(STREAM_RECONNECT_DELAY_SECONDS * 1000.0)
	_dispose_stream_client()
	_write_trace("godot.stream.reconnect", {
		"source": "godot",
		"taskId": _active_task_id,
		"requestId": _active_request_id,
		"clientMessageId": _current_client_message_id,
		"attempt": _stream_reconnect_attempt
	})
	system_message.emit("连接波动，正在尝试重连…")
	_emit_current_status()
	return true


func _mark_first_packet_received() -> void:
	if _stream_first_packet_received:
		return
	var first_packet_ms := _first_packet_elapsed_ms()
	_stream_first_packet_received = true
	_stream_first_packet_hint_emitted = false
	_stream_wait_started_at_msec = 0
	_write_trace("godot.stream.first_packet", {
		"source": "godot",
		"taskId": _active_task_id,
		"requestId": _active_request_id,
		"clientMessageId": _current_client_message_id,
		"firstPacketMs": first_packet_ms
	})


func _dispose_stream_client() -> void:
	if _stream_client != null:
		_stream_client.close()
	_stream_client = null
	_stream_buffer = ""
	_stream_request_started = false


func _reset_stream_state() -> void:
	_dispose_stream_client()
	_stream_started_emitted = false
	_stream_finished_locally = false
	_stream_text = ""
	_stream_wait_started_at_msec = 0
	_stream_first_packet_received = false
	_stream_first_packet_hint_emitted = false
	_stream_reconnect_attempt = 0
	_stream_reconnect_due_at_msec = 0
	_stream_cancel_requested = false
	_active_task_id = ""
	_active_request_id = ""
	_current_client_message_id = ""


func _first_packet_elapsed_ms() -> int:
	if _stream_wait_started_at_msec <= 0:
		return 0
	return Time.get_ticks_msec() - _stream_wait_started_at_msec


func _on_status_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_status_in_flight = false
	if response_code != 200:
		if _has_pending_stream():
			return
		_runtime_online = false
		_ai_state = "service_offline"
		_active_task_id = ""
		_emit_current_status()
		return
	var body_text := body.get_string_from_utf8().strip_edges()
	if body_text.is_empty():
		if _has_pending_stream():
			return
		_runtime_online = false
		_ai_state = "service_offline"
		_active_task_id = ""
		_emit_current_status()
		return
	var payload = JSON.parse_string(body_text)
	if typeof(payload) != TYPE_DICTIONARY or str(payload.get("status", "")) != "ok":
		if _has_pending_stream():
			return
		_runtime_online = false
		_ai_state = "service_offline"
		_active_task_id = ""
		_emit_current_status()
		return
	_runtime_online = true
	if not _has_pending_stream():
		_ai_state = str(payload.get("aiState", "disconnected"))
	var active_task = payload.get("activeTask", {})
	if typeof(active_task) == TYPE_DICTIONARY:
		if _active_task_id.is_empty():
			_active_task_id = str(active_task.get("task_id", active_task.get("taskId", "")))
	else:
		if _stream_client == null:
			_active_task_id = ""
	_emit_current_status()


func _on_message_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_message_in_flight = false
	if response_code < 200 or response_code >= 300:
		_write_trace("godot.submit.error", {
			"source": "godot",
			"clientMessageId": _current_client_message_id,
			"error": "submit_http_%s" % response_code
		})
		system_message.emit("提交消息失败。")
		_request_status()
		return
	var body_text := body.get_string_from_utf8().strip_edges()
	if body_text.is_empty():
		_write_trace("godot.submit.error", {
			"source": "godot",
			"clientMessageId": _current_client_message_id,
			"error": "submit_empty_response"
		})
		system_message.emit("提交消息失败。")
		_request_status()
		return
	var payload = JSON.parse_string(body_text)
	if typeof(payload) != TYPE_DICTIONARY:
		_write_trace("godot.submit.error", {
			"source": "godot",
			"clientMessageId": _current_client_message_id,
			"error": "submit_invalid_json"
		})
		system_message.emit("提交消息失败。")
		_request_status()
		return
	var task_id := str(payload.get("taskId", ""))
	var request_id := str(payload.get("requestId", ""))
	if task_id.is_empty():
		_write_trace("godot.submit.error", {
			"source": "godot",
			"clientMessageId": _current_client_message_id,
			"error": "task_id_missing"
		})
		system_message.emit("提交消息失败。")
		_request_status()
		return
	_start_stream(task_id, request_id)


func _on_cancel_request_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		_write_trace("godot.cancel.error", {
			"source": "godot",
			"taskId": _active_task_id,
			"requestId": _active_request_id,
			"clientMessageId": _current_client_message_id,
			"error": "cancel_http_%s" % response_code
		})
		system_message.emit("停止任务失败。")
		return
	_write_trace("godot.cancel.sent", {
		"source": "godot",
		"taskId": _active_task_id,
		"requestId": _active_request_id,
		"clientMessageId": _current_client_message_id
	})
	system_message.emit("已发送停止请求。")


func _write_trace(kind: String, payload: Dictionary) -> void:
	var line_payload := {
		"ts": Time.get_datetime_string_from_system(true, true),
		"kind": kind
	}
	for key in payload.keys():
		line_payload[key] = payload[key]
	var file := FileAccess.open(QUICK_CHAT_TRACE_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(QUICK_CHAT_TRACE_PATH, FileAccess.WRITE)
		if file == null:
			return
	file.seek_end()
	file.store_line(JSON.stringify(line_payload))
