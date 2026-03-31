extends Node2D

signal open_app_requested
signal quick_chat_open_requested
signal quick_task_requested(text: String)
signal status_requested
signal pause_toggled(paused: bool)

@export_dir var idle_frames_dir := "res://assets/pets/animations/idle"

@onready var pet_visual: AnimatedSprite2D = $PetVisual
@onready var click_area: Area2D = $ClickArea
@onready var collision_shape: CollisionShape2D = $ClickArea/CollisionShape2D
@onready var status_label: Label = $StatusLabel
@onready var pet_context_menu = $PetContextMenu
@onready var state_controller = $StateController

const HORIZONTAL_MARGIN := 0.0
const TOP_MARGIN := 0.0
const BOTTOM_MARGIN := 0.0
const MIN_BASE_SCALE := 0.1
const DRAG_THRESHOLD := 8.0

var _base_scale := 1.0
var _idle_texture_size := Vector2.ZERO
var _left_press_active := false
var _drag_started := false
var _drag_mouse_start := Vector2i.ZERO
var _drag_window_start := Vector2i.ZERO


func _ready() -> void:
	_build_idle_animation()
	get_window().size_changed.connect(_layout_pet)
	state_controller.state_changed.connect(_on_state_changed)
	click_area.input_event.connect(_on_click_area_input_event)
	click_area.mouse_entered.connect(_on_click_area_mouse_entered)
	click_area.mouse_exited.connect(_on_click_area_mouse_exited)
	pet_context_menu.open_app_requested.connect(_on_open_app_requested)
	pet_context_menu.quick_chat_requested.connect(_show_quick_chat)
	pet_context_menu.status_requested.connect(_on_status_requested)
	pet_context_menu.pause_toggled.connect(_on_pause_toggled)
	state_controller.set_state("idle", "待机中")


func apply_state(state: String, status_text: String) -> void:
	state_controller.set_state(state, status_text)


func release_interaction_state() -> void:
	if state_controller.get_state() in ["hover", "talking"]:
		state_controller.set_state("idle", "待机中")


func get_idle_texture_size() -> Vector2:
	return _idle_texture_size


func get_required_window_size(display_width: float) -> Vector2i:
	if _idle_texture_size == Vector2.ZERO or display_width <= 0.0:
		return Vector2i.ZERO

	var scale := display_width / _idle_texture_size.x
	return Vector2i(
		maxi(int(ceil(display_width + HORIZONTAL_MARGIN * 2.0)), 1),
		maxi(int(ceil(_idle_texture_size.y * scale + TOP_MARGIN + BOTTOM_MARGIN)), 1)
	)


func _build_idle_animation() -> void:
	var frames := SpriteFrames.new()
	var frame_paths := _collect_idle_frame_paths()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 12.0)

	print("[QQPAL][Pet] idle dir:", idle_frames_dir)
	print("[QQPAL][Pet] idle frame paths:", frame_paths.size())

	for resource_path in frame_paths:
		var texture := _load_texture_from_file(resource_path)
		if texture != null:
			frames.add_frame("idle", texture)
			if _idle_texture_size == Vector2.ZERO:
				_idle_texture_size = texture.get_size()
		else:
			print("[QQPAL][Pet] failed to load frame:", resource_path)

	pet_visual.sprite_frames = frames
	var frame_count := pet_visual.sprite_frames.get_frame_count("idle")
	print("[QQPAL][Pet] idle loaded frame count:", frame_count)
	if frame_count > 0:
		_layout_pet()
		pet_visual.play("idle")
	else:
		status_label.visible = true
		status_label.text = "桌宠资源未加载"


func _load_texture_from_file(resource_path: String) -> Texture2D:
	if ResourceLoader.exists(resource_path):
		return load(resource_path) as Texture2D

	return null


func _collect_idle_frame_paths() -> PackedStringArray:
	var frame_paths := PackedStringArray()
	var files := DirAccess.get_files_at(idle_frames_dir)
	files.sort()

	for file_name in files:
		if file_name.to_lower().ends_with(".png"):
			frame_paths.append("%s/%s" % [idle_frames_dir, file_name])

	if frame_paths.is_empty():
		for i in range(1, 1000):
			var resource_path := "%s/frame_%06d.png" % [idle_frames_dir, i]
			if not ResourceLoader.exists(resource_path):
				break
			frame_paths.append(resource_path)

	return frame_paths


func _layout_pet() -> void:
	if _idle_texture_size == Vector2.ZERO:
		return

	var window_size := Vector2(get_window().size)
	_base_scale = min(
		(window_size.x - HORIZONTAL_MARGIN * 2.0) / _idle_texture_size.x,
		(window_size.y - TOP_MARGIN - BOTTOM_MARGIN) / _idle_texture_size.y
	)
	_base_scale = max(_base_scale, MIN_BASE_SCALE)

	var displayed_size := _idle_texture_size * _base_scale
	pet_visual.scale = Vector2.ONE * _base_scale
	pet_visual.position = Vector2(
		window_size.x * 0.5,
		TOP_MARGIN + displayed_size.y * 0.5
	)

	var rect_shape := collision_shape.shape as RectangleShape2D
	if rect_shape != null:
		rect_shape.size = Vector2(displayed_size.x * 0.84, displayed_size.y * 0.96)
	click_area.position = pet_visual.position + Vector2(0, displayed_size.y * 0.02)

	print("[QQPAL][Pet] texture size:", _idle_texture_size, " window size:", window_size, " base scale:", _base_scale, " displayed size:", displayed_size)


func _get_pet_top_center() -> Vector2:
	var displayed_size := _idle_texture_size * _base_scale
	return Vector2(
		pet_visual.position.x,
		pet_visual.position.y - displayed_size.y * 0.5 + TOP_MARGIN
	)


func _on_state_changed(state: String, status_text: String) -> void:
	status_label.text = "状态：%s" % status_text
	pet_visual.modulate = Color.WHITE
	pet_visual.scale = Vector2.ONE * _base_scale

	match state:
		"idle":
			pet_visual.play("idle")
		"hover":
			pet_visual.play("idle")
			pet_visual.modulate = Color(1.0, 0.98, 0.8, 1.0)
			pet_visual.scale = Vector2.ONE * (_base_scale * 1.03)
		"talking":
			pet_visual.play("idle")
			pet_visual.modulate = Color(0.9, 1.0, 1.0, 1.0)
		"planning":
			pet_visual.play("idle")
			pet_visual.modulate = Color(0.88, 0.92, 1.0, 1.0)
		"running":
			pet_visual.play("idle")
			pet_visual.modulate = Color(1.0, 0.92, 0.8, 1.0)
		"waiting_user":
			pet_visual.play("idle")
			pet_visual.modulate = Color(1.0, 0.95, 0.72, 1.0)
		"success":
			pet_visual.play("idle")
			pet_visual.modulate = Color(0.84, 1.0, 0.84, 1.0)
		"failed":
			pet_visual.play("idle")
			pet_visual.modulate = Color(1.0, 0.8, 0.8, 1.0)
		"paused":
			pet_visual.play("idle")
			pet_visual.modulate = Color(0.7, 0.7, 0.7, 1.0)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_press_active = true
				_drag_started = false
				_drag_mouse_start = DisplayServer.mouse_get_position()
				_drag_window_start = get_window().position
			else:
				if _drag_started:
					print("[QQPAL][Pet] drag end position:", get_window().position)
				elif _left_press_active:
					_show_quick_chat()
				_left_press_active = false
				_drag_started = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var local_menu_anchor := _get_pet_top_center()
			var global_menu_anchor := Vector2(get_window().position) + local_menu_anchor
			var screen_rect := DisplayServer.screen_get_usable_rect()
			print("[QQPAL][Pet] local menu anchor:", local_menu_anchor, " global menu anchor:", global_menu_anchor, " window pos:", get_window().position, " screen rect:", screen_rect)
			pet_context_menu.popup_above_global(global_menu_anchor, screen_rect)
	elif event is InputEventMouseMotion and _left_press_active:
		var current_mouse: Vector2i = DisplayServer.mouse_get_position()
		var delta: Vector2i = current_mouse - _drag_mouse_start
		if not _drag_started and delta.length() >= DRAG_THRESHOLD:
			_drag_started = true
			print("[QQPAL][Pet] drag start:", _drag_window_start, " mouse:", _drag_mouse_start)
		if _drag_started:
			get_window().position = _drag_window_start + delta


func _on_click_area_mouse_entered() -> void:
	if state_controller.get_state() == "idle":
		state_controller.set_state("hover", "准备交互")


func _on_click_area_mouse_exited() -> void:
	if state_controller.get_state() == "hover":
		state_controller.set_state("idle", "待机中")


func _show_quick_chat() -> void:
	quick_chat_open_requested.emit()
	if state_controller.get_state() in ["idle", "hover"]:
		state_controller.set_state("talking", "对话中")


func _on_open_app_requested() -> void:
	open_app_requested.emit()


func _on_status_requested() -> void:
	status_requested.emit()


func _on_pause_toggled(paused: bool) -> void:
	pause_toggled.emit(paused)
