extends MarginContainer

signal submit_requested(text: String)

const ChatSessionStore = preload("res://scripts/services/ChatSessionStore.gd")
const DEFAULT_SYSTEM_MESSAGE := "这里会展示完整对话记录。"
const DEFAULT_FILE_CONTENT := "当前会话还没有生成文档。"

@onready var status_label: Label = $RootRow/ChatPanel/ChatMargin/ChatVBox/HeaderRow/StatusPanel/StatusLabel
@onready var history_label: RichTextLabel = $RootRow/ChatPanel/ChatMargin/ChatVBox/HistoryLabel
@onready var input_line: LineEdit = $RootRow/ChatPanel/ChatMargin/ChatVBox/InputRow/InputLine
@onready var search_input: LineEdit = $RootRow/TaskPanel/TaskMargin/TaskVBox/SearchInput
@onready var record_list: ItemList = $RootRow/TaskPanel/TaskMargin/TaskVBox/RecordList
@onready var records_empty_label: Label = $RootRow/TaskPanel/TaskMargin/TaskVBox/RecordsEmptyLabel
@onready var task_footer_label: Label = $RootRow/TaskPanel/TaskMargin/TaskVBox/TaskFooterLabel
@onready var file_list: ItemList = $RootRow/FilePanel/FileMargin/FileVBox/FileList
@onready var file_empty_label: Label = $RootRow/FilePanel/FileMargin/FileVBox/FileEmptyLabel
@onready var file_meta_label: Label = $RootRow/FilePanel/FileMargin/FileVBox/FileMetaLabel
@onready var file_content: RichTextLabel = $RootRow/FilePanel/FileMargin/FileVBox/FileContent

var _sessions: Array = []
var _active_session_id := ""
var _session_serial := 0
var _session_store := ChatSessionStore.new()


func _ready() -> void:
	search_input.text_changed.connect(_on_search_input_text_changed)
	record_list.item_selected.connect(_on_record_list_item_selected)
	file_list.item_selected.connect(_on_file_list_item_selected)
	_load_sessions()


func focus_input() -> void:
	input_line.grab_focus()


func set_status_text(text: String) -> void:
	status_label.text = text


func append_message(role: String, text: String) -> void:
	if _active_session_id.is_empty():
		_create_session()

	var session_index := _find_session_index(_active_session_id)
	if session_index == -1:
		return

	var session: Dictionary = _sessions[session_index]
	var messages: Array = session.get("messages", [])
	messages.append({
		"role": role,
		"text": text
	})
	session["messages"] = messages
	session["preview"] = _clip_text(text, 24)
	session["updated_at"] = Time.get_unix_time_from_system()

	if role == "你" and not _session_has_user_message(session, messages.size() - 1):
		session["title"] = _build_session_title(text)

	session = _refresh_generated_files_for_session(session)
	_sessions[session_index] = session
	_move_session_to_front(session_index)
	_persist_sessions()
	_refresh_session_list()
	_render_active_session()


func _on_send_button_pressed() -> void:
	var text := input_line.text.strip_edges()
	if text.is_empty():
		return

	append_message("你", text)
	input_line.clear()
	submit_requested.emit(text)


func _on_new_chat_button_pressed() -> void:
	_create_session()
	focus_input()


func _on_search_input_text_changed(_text: String) -> void:
	_refresh_session_list()


func _on_record_list_item_selected(index: int) -> void:
	var session_id = record_list.get_item_metadata(index)
	if typeof(session_id) != TYPE_STRING:
		return

	_active_session_id = session_id
	_persist_sessions()
	_refresh_session_list()
	_render_active_session()


func _on_file_list_item_selected(index: int) -> void:
	var file_id = file_list.get_item_metadata(index)
	if typeof(file_id) != TYPE_STRING:
		return

	var session_index := _find_session_index(_active_session_id)
	if session_index == -1:
		return

	var session: Dictionary = _sessions[session_index]
	session["active_file_id"] = file_id
	_sessions[session_index] = session
	_persist_sessions()
	_render_active_session()


func _create_session() -> void:
	_session_serial += 1
	var title := "新对话"
	if _session_serial > 1:
		title = "新对话 %d" % _session_serial

	var session_id := "chat_%d" % _session_serial
	_sessions.push_front({
		"id": session_id,
		"title": title,
		"preview": "暂无消息",
		"updated_at": Time.get_unix_time_from_system(),
		"messages": [
			{
				"role": "系统",
				"text": DEFAULT_SYSTEM_MESSAGE
			}
		],
		"generated_files": [],
		"active_file_id": ""
	})
	_active_session_id = session_id
	_persist_sessions()
	_refresh_session_list()
	_render_active_session()


func _refresh_session_list() -> void:
	record_list.clear()

	var keyword := search_input.text.strip_edges().to_lower()
	var matched_count := 0

	for session in _sessions:
		if not keyword.is_empty() and not _session_matches(session, keyword):
			continue

		record_list.add_item(_format_record_text(session))
		var item_index := record_list.get_item_count() - 1
		record_list.set_item_metadata(item_index, session.get("id", ""))

		if session.get("id", "") == _active_session_id:
			record_list.select(item_index)

		matched_count += 1

	record_list.visible = matched_count > 0
	records_empty_label.visible = matched_count == 0

	if keyword.is_empty():
		task_footer_label.text = "共 %d 条对话" % _sessions.size()
	else:
		task_footer_label.text = "找到 %d 条对话" % matched_count


func _render_active_session() -> void:
	var session_index := _find_session_index(_active_session_id)
	if session_index == -1:
		history_label.text = "[系统] %s\n" % DEFAULT_SYSTEM_MESSAGE
		_render_empty_files()
		return

	var session: Dictionary = _sessions[session_index]
	var messages: Array = session.get("messages", [])
	var lines: PackedStringArray = []

	for message in messages:
		lines.append("[%s] %s" % [message.get("role", "系统"), message.get("text", "")])

	history_label.text = "\n".join(lines) + "\n"
	history_label.scroll_to_line(history_label.get_line_count())
	_render_file_panel(session)


func _render_file_panel(session: Dictionary) -> void:
	file_list.clear()

	var generated_files: Array = session.get("generated_files", [])
	if generated_files.is_empty():
		_render_empty_files()
		return

	file_list.visible = true
	file_empty_label.visible = false

	var active_file_id := str(session.get("active_file_id", ""))
	if active_file_id.is_empty() or _find_generated_file_index(generated_files, active_file_id) == -1:
		active_file_id = generated_files[0].get("id", "")
		session["active_file_id"] = active_file_id
		var session_index := _find_session_index(session.get("id", ""))
		if session_index != -1:
			_sessions[session_index] = session

	for generated_file in generated_files:
		file_list.add_item(generated_file.get("name", "未命名文档"))
		var item_index := file_list.get_item_count() - 1
		file_list.set_item_metadata(item_index, generated_file.get("id", ""))
		if generated_file.get("id", "") == active_file_id:
			file_list.select(item_index)

	var active_file_index := _find_generated_file_index(generated_files, active_file_id)
	if active_file_index == -1:
		_render_empty_files()
		return

	var active_file: Dictionary = generated_files[active_file_index]
	file_meta_label.text = "存储位置：%s" % active_file.get("user_path", "")
	file_content.text = str(active_file.get("content", DEFAULT_FILE_CONTENT))
	file_content.scroll_to_line(0)


func _render_empty_files() -> void:
	file_list.visible = false
	file_empty_label.visible = true
	file_meta_label.text = "未选择文件"
	file_content.text = DEFAULT_FILE_CONTENT


func _find_session_index(session_id: String) -> int:
	for index in range(_sessions.size()):
		if _sessions[index].get("id", "") == session_id:
			return index
	return -1


func _move_session_to_front(session_index: int) -> void:
	if session_index <= 0 or session_index >= _sessions.size():
		return

	var session = _sessions[session_index]
	_sessions.remove_at(session_index)
	_sessions.push_front(session)


func _session_matches(session: Dictionary, keyword: String) -> bool:
	if str(session.get("title", "")).to_lower().contains(keyword):
		return true

	if str(session.get("preview", "")).to_lower().contains(keyword):
		return true

	for message in session.get("messages", []):
		if str(message.get("text", "")).to_lower().contains(keyword):
			return true

	for generated_file in session.get("generated_files", []):
		if str(generated_file.get("name", "")).to_lower().contains(keyword):
			return true
		if str(generated_file.get("content", "")).to_lower().contains(keyword):
			return true

	return false


func _format_record_text(session: Dictionary) -> String:
	return "%s｜%s" % [
		session.get("title", "新对话"),
		session.get("preview", "暂无消息")
	]


func _session_has_user_message(session: Dictionary, ignore_index: int = -1) -> bool:
	var messages: Array = session.get("messages", [])
	for index in range(messages.size()):
		if index == ignore_index:
			continue
		if messages[index].get("role", "") == "你":
			return true
	return false


func _build_session_title(text: String) -> String:
	return _clip_text(text, 12)


func _clip_text(text: String, max_length: int) -> String:
	var plain_text := text.strip_edges()
	if plain_text.length() <= max_length:
		return plain_text
	return plain_text.substr(0, max_length) + "..."


func _load_sessions() -> void:
	var state := _session_store.load_state()
	_sessions = state.get("sessions", [])
	_active_session_id = state.get("active_session_id", "")
	_session_serial = int(state.get("session_serial", 0))

	if _sessions.is_empty():
		_create_session()
		return

	for index in range(_sessions.size()):
		_sessions[index] = _refresh_generated_files_for_session(_sessions[index])

	if _active_session_id.is_empty():
		_active_session_id = _sessions[0].get("id", "")

	_persist_sessions()
	_refresh_session_list()
	_render_active_session()


func _persist_sessions() -> void:
	_session_store.save_state(_sessions, _active_session_id, _session_serial)


func _refresh_generated_files_for_session(session: Dictionary) -> Dictionary:
	var messages: Array = session.get("messages", [])
	var user_messages := _collect_user_messages(messages)
	var assistant_messages := _collect_assistant_messages(messages)
	var generated_files: Array = []

	if messages.size() > 1:
		generated_files.append(_build_generated_file(
			"summary",
			"对话纪要.md",
			_build_summary_document(session, user_messages, assistant_messages)
		))

	if not user_messages.is_empty():
		generated_files.append(_build_generated_file(
			"requirements",
			"需求清单.md",
			_build_requirements_document(user_messages)
		))

	var latest_reply := _get_latest_assistant_reply(messages)
	if not latest_reply.is_empty():
		generated_files.append(_build_generated_file(
			"latest_reply",
			"最新回复.md",
			_build_latest_reply_document(latest_reply)
		))

	session["generated_files"] = generated_files

	var active_file_id := str(session.get("active_file_id", ""))
	if generated_files.is_empty():
		session["active_file_id"] = ""
	elif active_file_id.is_empty() or _find_generated_file_index(generated_files, active_file_id) == -1:
		session["active_file_id"] = generated_files[0].get("id", "")

	return session


func _build_generated_file(file_id: String, file_name: String, content: String) -> Dictionary:
	return {
		"id": file_id,
		"name": file_name,
		"content": content,
		"updated_at": Time.get_unix_time_from_system()
	}


func _build_summary_document(session: Dictionary, user_messages: Array, assistant_messages: Array) -> String:
	var lines: PackedStringArray = [
		"# 对话纪要",
		"",
		"## 会话标题",
		session.get("title", "新对话"),
		"",
		"## 用户需求"
	]

	if user_messages.is_empty():
		lines.append("- 暂无用户需求")
	else:
		for message in user_messages:
			lines.append("- %s" % message.get("text", ""))

	lines.append("")
	lines.append("## AI 输出")
	if assistant_messages.is_empty():
		lines.append("- 暂无 AI 输出")
	else:
		for message in assistant_messages:
			lines.append("- %s：%s" % [message.get("role", "QQPAL"), message.get("text", "")])

	return "\n".join(lines)


func _build_requirements_document(user_messages: Array) -> String:
	var lines: PackedStringArray = [
		"# 需求清单",
		"",
		"以下内容来自当前会话中的用户输入：",
		""
	]

	for index in range(user_messages.size()):
		lines.append("%d. %s" % [index + 1, user_messages[index].get("text", "")])

	return "\n".join(lines)


func _build_latest_reply_document(latest_reply: Dictionary) -> String:
	var lines: PackedStringArray = [
		"# 最新回复",
		"",
		"## 角色",
		latest_reply.get("role", "QQPAL"),
		"",
		"## 内容",
		latest_reply.get("text", "")
	]

	return "\n".join(lines)


func _collect_user_messages(messages: Array) -> Array:
	var user_messages: Array = []
	for message in messages:
		if message.get("role", "") == "你":
			user_messages.append(message)
	return user_messages


func _collect_assistant_messages(messages: Array) -> Array:
	var assistant_messages: Array = []
	for message in messages:
		var role := str(message.get("role", ""))
		var text := str(message.get("text", ""))
		if role == "你":
			continue
		if role == "系统" and text == DEFAULT_SYSTEM_MESSAGE:
			continue
		assistant_messages.append(message)
	return assistant_messages


func _get_latest_assistant_reply(messages: Array) -> Dictionary:
	for index in range(messages.size() - 1, -1, -1):
		var message: Dictionary = messages[index]
		var role := str(message.get("role", ""))
		var text := str(message.get("text", ""))
		if role == "你":
			continue
		if role == "系统" and text == DEFAULT_SYSTEM_MESSAGE:
			continue
		return message

	return {}


func _find_generated_file_index(generated_files: Array, file_id: String) -> int:
	for index in range(generated_files.size()):
		if generated_files[index].get("id", "") == file_id:
			return index
	return -1
