extends PopupMenu

signal open_app_requested
signal quick_chat_requested
signal status_requested
signal pause_toggled(paused: bool)

var _paused := false


func _ready() -> void:
	clear()
	add_item("打开应用", 0)
	add_item("快速对话", 1)
	add_item("查看状态", 2)
	add_item("暂停桌宠", 3)
	add_separator()
	add_item("退出", 4)
	id_pressed.connect(_on_id_pressed)


func popup_above_global(anchor_position: Vector2, screen_rect: Rect2i) -> void:
	reset_size()
	var popup_size := get_contents_minimum_size()
	var target_x := anchor_position.x - popup_size.x * 0.5
	var target_y := anchor_position.y - popup_size.y - 10.0
	target_x = clampf(target_x, screen_rect.position.x + 8.0, screen_rect.position.x + screen_rect.size.x - popup_size.x - 8.0)
	target_y = clampf(target_y, screen_rect.position.y + 8.0, screen_rect.position.y + screen_rect.size.y - popup_size.y - 8.0)
	position = Vector2i(target_x, target_y)
	print("[QQPAL][Menu] popup global anchor:", anchor_position, " popup size:", popup_size, " screen rect:", screen_rect, " final position:", position)
	popup()


func _on_id_pressed(id: int) -> void:
	match id:
		0:
			open_app_requested.emit()
		1:
			quick_chat_requested.emit()
		2:
			status_requested.emit()
		3:
			_paused = not _paused
			set_item_text(3, "恢复桌宠" if _paused else "暂停桌宠")
			pause_toggled.emit(_paused)
		4:
			get_tree().quit()
