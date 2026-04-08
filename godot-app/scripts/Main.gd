extends Node

const QuickChatRuntimeService = preload("res://scripts/services/QuickChatRuntimeService.gd")

@onready var desktop_pet = $DesktopPet
@onready var quick_chat_window: Window = $QuickChatWindow
@onready var quick_chat_panel = $QuickChatWindow/QuickChatPanel
@onready var main_app_window: Window = $MainAppWindow
@onready var main_app = $MainAppWindow/MainApp
@onready var mock_task_service = $MockTaskService

const DEFAULT_PET_WINDOW_SIZE := Vector2i(520, 560)
const PET_IMAGE_WIDTH_RATIO := 0.125
const QUICK_CHAT_WINDOW_SIZE := Vector2i(460, 340)
const APP_WINDOW_SIZE := Vector2i(1040, 720)
const WINDOW_MARGIN := Vector2i(24, 32)

var _quick_chat_runtime_service


func _ready() -> void:
	_configure_root_window()
	_configure_subwindows()
	_quick_chat_runtime_service = QuickChatRuntimeService.new()
	desktop_pet.open_app_requested.connect(_on_open_app_requested)
	desktop_pet.quick_chat_open_requested.connect(_on_quick_chat_open_requested)
	desktop_pet.quick_task_requested.connect(_on_quick_task_requested)
	desktop_pet.status_requested.connect(_on_status_requested)
	desktop_pet.pause_toggled.connect(_on_pause_toggled)
	quick_chat_panel.quick_task_requested.connect(_on_quick_chat_task_requested)
	quick_chat_panel.stop_requested.connect(_on_quick_chat_stop_requested)
	quick_chat_panel.open_app_requested.connect(_on_quick_chat_open_open_app_requested)
	quick_chat_panel.close_requested.connect(_on_quick_chat_close_requested)
	quick_chat_window.close_requested.connect(_on_quick_chat_close_requested)
	main_app.close_requested.connect(_on_close_app_requested)
	main_app.task_flow_requested.connect(_on_task_flow_requested)
	main_app.chat_submitted.connect(_on_quick_task_requested)
	main_app_window.close_requested.connect(_on_close_app_requested)
	mock_task_service.status_changed.connect(_on_status_changed)
	_quick_chat_runtime_service.status_changed.connect(_on_quick_chat_runtime_status_changed)
	_quick_chat_runtime_service.system_message.connect(_on_quick_chat_runtime_system_message)
	_quick_chat_runtime_service.stream_started.connect(_on_quick_chat_runtime_stream_started)
	_quick_chat_runtime_service.stream_delta.connect(_on_quick_chat_runtime_stream_delta)
	_quick_chat_runtime_service.stream_finished.connect(_on_quick_chat_runtime_stream_finished)
	_quick_chat_runtime_service.stream_failed.connect(_on_quick_chat_runtime_stream_failed)
	add_child(_quick_chat_runtime_service)

	quick_chat_window.visible = false
	main_app_window.visible = false
	mock_task_service.emit_current_state()


func _configure_root_window() -> void:
	var root_window := get_window()
	var pet_window_size := _get_dynamic_pet_window_size()
	_sync_root_content_scale_size(pet_window_size)
	get_tree().root.gui_embed_subwindows = false
	get_tree().root.transparent_bg = true
	root_window.transparent = true
	root_window.transparent_bg = true
	root_window.borderless = true
	root_window.always_on_top = true
	root_window.unresizable = true
	root_window.size = pet_window_size
	root_window.position = _get_pet_window_position(root_window.size)


func _configure_subwindows() -> void:
	quick_chat_window.borderless = true
	quick_chat_window.always_on_top = true
	quick_chat_window.unresizable = true
	quick_chat_window.transparent = true
	quick_chat_window.transparent_bg = true
	quick_chat_window.size = QUICK_CHAT_WINDOW_SIZE
	quick_chat_window.min_size = QUICK_CHAT_WINDOW_SIZE

	main_app_window.unresizable = false
	main_app_window.min_size = Vector2i(860, 620)
	_fit_main_app_window_to_screen()


func _on_open_app_requested(page_name: String = "home") -> void:
	_fit_main_app_window_to_screen()
	main_app.open_app(page_name)
	main_app_window.visible = true


func _on_close_app_requested() -> void:
	main_app_window.visible = false


func _on_quick_chat_open_requested() -> void:
	_position_quick_chat_window()
	quick_chat_window.visible = true
	quick_chat_panel.focus_input()


func _on_quick_task_requested(text: String) -> void:
	var should_fail := text.contains("失败") or text.to_lower().contains("fail")
	_on_open_app_requested("chat")
	main_app.append_chat_message("你", text)
	main_app.append_chat_message("QQPAL", "已收到请求，开始模拟执行。")
	mock_task_service.start_task_flow(text, should_fail)


func _on_quick_chat_task_requested(text: String) -> void:
	if not _quick_chat_runtime_service.submit_text(text):
		quick_chat_panel.append_system_message("当前无法发送，请等待连接完成。")
		return
	quick_chat_panel.begin_assistant_message()


func _on_quick_chat_stop_requested() -> void:
	_quick_chat_runtime_service.stop_current_request()


func _on_status_requested() -> void:
	_on_open_app_requested("home")


func _on_pause_toggled(_paused: bool) -> void:
	mock_task_service.toggle_pause()


func _on_task_flow_requested(flow_type: String) -> void:
	var should_fail := flow_type == "fail"
	var text := "模拟主应用任务"
	if should_fail:
		text = "模拟失败任务"
	_on_open_app_requested("home")
	main_app.append_chat_message("系统", "已从主应用发起 %s 流程。" % flow_type)
	mock_task_service.start_task_flow(text, should_fail)


func _on_status_changed(state: String, status_text: String, task_data: Dictionary) -> void:
	desktop_pet.apply_state(state, status_text)
	main_app.update_task_state(state, status_text, task_data)


func _on_quick_chat_open_open_app_requested() -> void:
	quick_chat_window.visible = false
	desktop_pet.release_interaction_state()
	_on_open_app_requested("chat")


func _on_quick_chat_close_requested() -> void:
	quick_chat_window.visible = false
	desktop_pet.release_interaction_state()


func _on_quick_chat_runtime_status_changed(status_text: String, is_busy: bool, can_submit: bool) -> void:
	quick_chat_panel.set_status_text(status_text)
	quick_chat_panel.set_busy(is_busy)
	quick_chat_panel.set_action_enabled(can_submit)
	var pet_state := "idle"
	if is_busy:
		pet_state = "talking" if status_text == "等待首包" or status_text == "连接恢复中" else "running"
	elif status_text == "连接中" or status_text == "服务异常":
		pet_state = "talking"
	desktop_pet.apply_state(pet_state, status_text)


func _on_quick_chat_runtime_stream_started(_request_id: String) -> void:
	pass


func _on_quick_chat_runtime_system_message(text: String) -> void:
	quick_chat_panel.append_system_message(text)


func _on_quick_chat_runtime_stream_delta(text: String, _request_id: String) -> void:
	quick_chat_panel.update_assistant_message(text)


func _on_quick_chat_runtime_stream_finished(text: String, _request_id: String, interrupted: bool) -> void:
	quick_chat_panel.finish_assistant_message(text, interrupted)


func _on_quick_chat_runtime_stream_failed(error_text: String, _request_id: String) -> void:
	if error_text.is_empty():
		return
	quick_chat_panel.append_system_message(error_text)


func _position_quick_chat_window() -> void:
	var pet_window := get_window()
	var screen_rect := DisplayServer.screen_get_usable_rect()
	var horizontal_gap := 2
	var vertical_target := pet_window.position.y + pet_window.size.y - quick_chat_window.size.y
	var right_target_x := pet_window.position.x + pet_window.size.x + horizontal_gap
	var left_target_x := pet_window.position.x - quick_chat_window.size.x - horizontal_gap
	var right_edge_limit := screen_rect.position.x + screen_rect.size.x - quick_chat_window.size.x - 8
	var left_edge_limit := screen_rect.position.x + 8

	var target := Vector2i(right_target_x, vertical_target)
	if right_target_x > right_edge_limit:
		target.x = left_target_x
	if target.x < left_edge_limit:
		target.x = clampi(target.x, left_edge_limit, right_edge_limit)

	target.y = clampi(
		vertical_target,
		screen_rect.position.y + 2,
		screen_rect.position.y + screen_rect.size.y - quick_chat_window.size.y - 8
	)

	print(
		"[QQPAL][QuickChat] pet window pos:", pet_window.position,
		" pet size:", pet_window.size,
		" quick chat size:", quick_chat_window.size,
		" bottom aligned y:", vertical_target,
		" target:", target,
		" screen rect:", screen_rect
	)
	quick_chat_window.position = target


func _fit_main_app_window_to_screen() -> void:
	var screen_rect := DisplayServer.screen_get_usable_rect()
	main_app_window.position = screen_rect.position
	main_app_window.size = screen_rect.size


func _get_pet_window_position(window_size: Vector2i) -> Vector2i:
	var screen_rect := DisplayServer.screen_get_usable_rect()
	return Vector2i(
		screen_rect.position.x + screen_rect.size.x - window_size.x - WINDOW_MARGIN.x,
		screen_rect.position.y + screen_rect.size.y - window_size.y - WINDOW_MARGIN.y
	)


func _get_dynamic_pet_window_size() -> Vector2i:
	var target_image_width := _get_target_pet_image_width()
	var pet_window_size: Vector2i = desktop_pet.get_required_window_size(target_image_width)
	if pet_window_size == Vector2i.ZERO:
		return DEFAULT_PET_WINDOW_SIZE

	return pet_window_size


func _sync_root_content_scale_size(pet_window_size: Vector2i) -> void:
	get_tree().root.content_scale_size = pet_window_size


func _get_target_pet_image_width() -> float:
	var screen_rect := DisplayServer.screen_get_usable_rect()
	return maxf(round(screen_rect.size.x * PET_IMAGE_WIDTH_RATIO), 1.0)


func _get_centered_window_position(window_size: Vector2i) -> Vector2i:
	var screen_rect := DisplayServer.screen_get_usable_rect()
	return Vector2i(
		screen_rect.position.x + int((screen_rect.size.x - window_size.x) / 2.0),
		screen_rect.position.y + int((screen_rect.size.y - window_size.y) / 2.0)
	)
