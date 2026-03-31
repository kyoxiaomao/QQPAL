extends Node

signal status_changed(state: String, status_text: String, task_data: Dictionary)

const IDLE := "idle"
const TALKING := "talking"
const PLANNING := "planning"
const RUNNING := "running"
const SUCCESS := "success"
const FAILED := "failed"
const PAUSED := "paused"

var current_state := IDLE
var current_status_text := "待机中"
var current_task: Dictionary = {
	"task_id": "",
	"user_input": "",
	"status": IDLE,
	"result": "",
	"error": "",
	"timestamps": {}
}

var _flow_running := false
var _paused := false


func _ready() -> void:
	_emit_state()


func start_task_flow(user_input: String, should_fail: bool = false) -> void:
	if _flow_running:
		return

	_flow_running = true
	_paused = false
	current_task = {
		"task_id": "task_%s" % Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_"),
		"user_input": user_input,
		"status": TALKING,
		"result": "",
		"error": "",
		"timestamps": {
			"started_at": Time.get_unix_time_from_system()
		}
	}

	await _transition_to(TALKING, "正在和你确认需求", 0.6)
	await _transition_to(PLANNING, "正在思考任务", 0.9)
	await _transition_to(RUNNING, "正在执行任务", 1.1)

	if should_fail:
		current_task["error"] = "模拟任务执行失败"
		await _transition_to(FAILED, "执行失败", 0.8)
	else:
		current_task["result"] = "模拟任务已成功完成"
		await _transition_to(SUCCESS, "任务已完成", 0.8)

	current_task["timestamps"]["finished_at"] = Time.get_unix_time_from_system()
	await get_tree().create_timer(1.2).timeout
	reset_to_idle()
	_flow_running = false


func reset_to_idle() -> void:
	current_task["status"] = IDLE
	current_state = IDLE
	current_status_text = "待机中"
	_emit_state()


func toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		current_state = PAUSED
		current_status_text = "桌宠已暂停"
	else:
		current_state = IDLE
		current_status_text = "桌宠已恢复"
	_emit_state()


func emit_current_state() -> void:
	_emit_state()


func _transition_to(state: String, status_text: String, duration: float) -> void:
	current_task["status"] = state
	current_state = state
	current_status_text = status_text
	_emit_state()
	await get_tree().create_timer(duration).timeout


func _emit_state() -> void:
	status_changed.emit(current_state, current_status_text, current_task.duplicate(true))
