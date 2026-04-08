extends PanelContainer

signal quick_task_requested(text: String)
signal stop_requested
signal open_app_requested
signal close_requested

@onready var status_label: Label = $MarginContainer/VBoxContainer/HeaderRow/IdentityBlock/TextBlock/StatusLabel
@onready var history_label: RichTextLabel = $MarginContainer/VBoxContainer/HistoryLabel
@onready var input_line: LineEdit = $MarginContainer/VBoxContainer/InputRow/InputLine
@onready var send_button: Button = $MarginContainer/VBoxContainer/InputRow/SendButton
@onready var minimize_button: Button = $MarginContainer/VBoxContainer/HeaderRow/WindowActions/MinimizeButton
@onready var maximize_button: Button = $MarginContainer/VBoxContainer/HeaderRow/WindowActions/MaximizeButton

const DRAG_THRESHOLD := 6.0
const WINDOW_ICON_COLOR := Color(1, 0.956863, 0.909804, 0.96)

var _drag_active := false
var _drag_started := false
var _drag_mouse_start := Vector2i.ZERO
var _drag_window_start := Vector2i.ZERO
var _busy := false
var _messages: Array[Dictionary] = []
var _active_assistant_index := -1


func _ready() -> void:
	minimize_button.icon = _create_minimize_icon()
	maximize_button.icon = _create_maximize_icon()


func focus_input() -> void:
	input_line.grab_focus()


func set_status_text(text: String) -> void:
	status_label.text = text


func set_busy(busy: bool) -> void:
	_busy = busy
	send_button.text = "停止" if busy else "发送"


func set_action_enabled(enabled: bool) -> void:
	send_button.disabled = not enabled
	input_line.editable = enabled and not _busy


func append_message(role: String, text: String) -> void:
	_messages.append({
		"role": role,
		"text": text,
	})
	_render_history()


func append_system_message(text: String) -> void:
	append_message("系统", text)


func begin_assistant_message() -> void:
	_active_assistant_index = _messages.size()
	_messages.append({
		"role": "QQPAL",
		"text": "…",
	})
	_render_history()


func update_assistant_message(text: String) -> void:
	if _active_assistant_index < 0 or _active_assistant_index >= _messages.size():
		begin_assistant_message()
	_messages[_active_assistant_index]["text"] = text if not text.is_empty() else "…"
	_render_history()


func finish_assistant_message(text: String, interrupted: bool = false) -> void:
	update_assistant_message(text)
	if _active_assistant_index >= 0 and _active_assistant_index < _messages.size():
		var final_text := str(_messages[_active_assistant_index].get("text", ""))
		if interrupted and not final_text.contains("已停止"):
			final_text = "%s\n[已停止]" % final_text.strip_edges()
		_messages[_active_assistant_index]["text"] = final_text
	_active_assistant_index = -1
	_render_history()


func _render_history() -> void:
	var lines: Array[String] = []
	for item in _messages:
		lines.append("[%s] %s" % [str(item.get("role", "")), str(item.get("text", ""))])
	history_label.text = "\n".join(lines)
	history_label.scroll_to_line(history_label.get_line_count())


func _on_send_button_pressed() -> void:
	if _busy:
		stop_requested.emit()
		return

	var text := input_line.text.strip_edges()
	if text.is_empty():
		return

	append_message("你", text)
	input_line.clear()
	quick_task_requested.emit(text)


func _on_maximize_button_pressed() -> void:
	open_app_requested.emit()


func _on_minimize_button_pressed() -> void:
	close_requested.emit()


func _on_avatar_wrap_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_active = true
			_drag_started = false
			_drag_mouse_start = DisplayServer.mouse_get_position()
			_drag_window_start = get_window().position
		else:
			_drag_active = false
			_drag_started = false


func _input(event: InputEvent) -> void:
	if not _drag_active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_active = false
		_drag_started = false
	elif event is InputEventMouseMotion:
		var current_mouse: Vector2i = DisplayServer.mouse_get_position()
		var delta: Vector2i = current_mouse - _drag_mouse_start
		if not _drag_started and delta.length() >= DRAG_THRESHOLD:
			_drag_started = true
		if _drag_started:
			get_window().position = _drag_window_start + delta


func _create_minimize_icon() -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(5, 19):
		image.set_pixel(x, 16, WINDOW_ICON_COLOR)
		image.set_pixel(x, 17, WINDOW_ICON_COLOR)
	return ImageTexture.create_from_image(image)


func _create_maximize_icon() -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(5, 19):
		image.set_pixel(x, 5, WINDOW_ICON_COLOR)
		image.set_pixel(x, 6, WINDOW_ICON_COLOR)
		image.set_pixel(x, 17, WINDOW_ICON_COLOR)
		image.set_pixel(x, 18, WINDOW_ICON_COLOR)
	for y in range(5, 19):
		image.set_pixel(5, y, WINDOW_ICON_COLOR)
		image.set_pixel(6, y, WINDOW_ICON_COLOR)
		image.set_pixel(17, y, WINDOW_ICON_COLOR)
		image.set_pixel(18, y, WINDOW_ICON_COLOR)
	return ImageTexture.create_from_image(image)
