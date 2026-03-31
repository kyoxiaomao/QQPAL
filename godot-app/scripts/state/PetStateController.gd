extends Node

signal state_changed(state: String, status_text: String)

const ALL_STATES := {
	"idle": "待机中",
	"hover": "准备交互",
	"talking": "对话中",
	"planning": "思考中",
	"running": "执行中",
	"waiting_user": "等待确认",
	"success": "已完成",
	"failed": "执行失败",
	"paused": "已暂停"
}

var current_state := "idle"
var current_status_text := "待机中"


func set_state(state: String, status_text: String = "") -> void:
	if not ALL_STATES.has(state):
		return

	current_state = state
	current_status_text = status_text if not status_text.is_empty() else ALL_STATES[state]
	state_changed.emit(current_state, current_status_text)


func get_state() -> String:
	return current_state
