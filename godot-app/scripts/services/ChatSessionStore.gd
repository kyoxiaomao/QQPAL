extends RefCounted

const SAVE_PATH := "user://chat_sessions.json"
const DOCS_ROOT_PATH := "user://generated_docs"
const DEFAULT_SYSTEM_MESSAGE := "这里会展示完整对话记录。"


func load_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return _default_state()

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return _default_state()

	var raw_text := file.get_as_text()
	if raw_text.strip_edges().is_empty():
		return _default_state()

	var parsed = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _default_state()

	return _sanitize_state(parsed)


func save_state(sessions: Array, active_session_id: String, session_serial: int) -> bool:
	var sanitized_sessions := _sanitize_sessions(sessions)
	_write_generated_files(sanitized_sessions)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false

	var payload := {
		"sessions": sanitized_sessions,
		"active_session_id": active_session_id,
		"session_serial": maxi(session_serial, sessions.size()),
		"saved_at": Time.get_unix_time_from_system()
	}
	file.store_string(JSON.stringify(payload, "\t"))
	return true


func get_save_path() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)


func get_docs_root_path() -> String:
	return ProjectSettings.globalize_path(DOCS_ROOT_PATH)


func _default_state() -> Dictionary:
	return {
		"sessions": [],
		"active_session_id": "",
		"session_serial": 0
	}


func _sanitize_state(state: Dictionary) -> Dictionary:
	var sessions := _sanitize_sessions(state.get("sessions", []))
	var active_session_id := str(state.get("active_session_id", ""))
	var session_serial := int(state.get("session_serial", 0))

	if session_serial < sessions.size():
		session_serial = sessions.size()

	if not active_session_id.is_empty() and _find_session_index(sessions, active_session_id) == -1:
		active_session_id = ""

	return {
		"sessions": sessions,
		"active_session_id": active_session_id,
		"session_serial": session_serial
	}


func _sanitize_sessions(raw_sessions) -> Array:
	var sessions: Array = []
	if typeof(raw_sessions) != TYPE_ARRAY:
		return sessions

	for raw_session in raw_sessions:
		if typeof(raw_session) != TYPE_DICTIONARY:
			continue

		var session_id := str(raw_session.get("id", "")).strip_edges()
		if session_id.is_empty():
			continue

		var title := str(raw_session.get("title", "新对话")).strip_edges()
		if title.is_empty():
			title = "新对话"

		var preview := str(raw_session.get("preview", "暂无消息")).strip_edges()
		if preview.is_empty():
			preview = "暂无消息"

		var updated_at := int(raw_session.get("updated_at", 0))
		var messages := _sanitize_messages(raw_session.get("messages", []))
		if messages.is_empty():
			messages.append({
				"role": "系统",
				"text": DEFAULT_SYSTEM_MESSAGE
			})

		var generated_files := _sanitize_generated_files(raw_session.get("generated_files", []), session_id)
		var active_file_id := str(raw_session.get("active_file_id", ""))
		if not active_file_id.is_empty() and _find_generated_file_index(generated_files, active_file_id) == -1:
			active_file_id = ""

		sessions.append({
			"id": session_id,
			"title": title,
			"preview": preview,
			"updated_at": updated_at,
			"messages": messages,
			"generated_files": generated_files,
			"active_file_id": active_file_id
		})

	return sessions


func _sanitize_messages(raw_messages) -> Array:
	var messages: Array = []
	if typeof(raw_messages) != TYPE_ARRAY:
		return messages

	for raw_message in raw_messages:
		if typeof(raw_message) != TYPE_DICTIONARY:
			continue

		var role := str(raw_message.get("role", "系统")).strip_edges()
		if role.is_empty():
			role = "系统"

		var text := str(raw_message.get("text", "")).strip_edges()
		if text.is_empty():
			continue

		messages.append({
			"role": role,
			"text": text
		})

	return messages


func _sanitize_generated_files(raw_files, session_id: String) -> Array:
	var files: Array = []
	if typeof(raw_files) != TYPE_ARRAY:
		return files

	for raw_file in raw_files:
		if typeof(raw_file) != TYPE_DICTIONARY:
			continue

		var file_id := str(raw_file.get("id", "")).strip_edges()
		if file_id.is_empty():
			continue

		var name := str(raw_file.get("name", "")).strip_edges()
		if name.is_empty():
			continue

		var content := str(raw_file.get("content", "")).strip_edges()
		if content.is_empty():
			continue

		var updated_at := int(raw_file.get("updated_at", 0))
		files.append({
			"id": file_id,
			"name": name,
			"content": content,
			"updated_at": updated_at,
			"user_path": _build_file_user_path(session_id, name)
		})

	return files


func _find_session_index(sessions: Array, session_id: String) -> int:
	for index in range(sessions.size()):
		if sessions[index].get("id", "") == session_id:
			return index
	return -1


func _find_generated_file_index(files: Array, file_id: String) -> int:
	for index in range(files.size()):
		if files[index].get("id", "") == file_id:
			return index
	return -1


func _write_generated_files(sessions: Array) -> void:
	for session in sessions:
		var generated_files: Array = session.get("generated_files", [])
		for generated_file in generated_files:
			var user_path := str(generated_file.get("user_path", "")).strip_edges()
			if user_path.is_empty():
				continue

			var absolute_path := ProjectSettings.globalize_path(user_path)
			var dir_path := absolute_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(dir_path)

			var file := FileAccess.open(absolute_path, FileAccess.WRITE)
			if file == null:
				continue

			file.store_string(str(generated_file.get("content", "")))


func _build_file_user_path(session_id: String, file_name: String) -> String:
	return "%s/%s/%s" % [DOCS_ROOT_PATH, session_id, _sanitize_file_name(file_name)]


func _sanitize_file_name(file_name: String) -> String:
	var sanitized := file_name.strip_edges()
	var invalid_chars := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
	for invalid_char in invalid_chars:
		sanitized = sanitized.replace(invalid_char, "_")

	if sanitized.is_empty():
		return "未命名文档.md"

	return sanitized
