extends MarginContainer

signal simulate_flow_requested(flow_type: String)

@onready var current_state_label: Label = $VBoxContainer/CurrentStateLabel
@onready var task_id_label: Label = $VBoxContainer/TaskIdLabel
@onready var summary_label: Label = $VBoxContainer/SummaryLabel


func update_task_state(state: String, status_text: String, task_data: Dictionary) -> void:
	current_state_label.text = "当前状态：%s（%s）" % [status_text, state]
	task_id_label.text = "任务 ID：%s" % task_data.get("task_id", "")

	var result_text: String = str(task_data.get("result", ""))
	var error_text: String = str(task_data.get("error", ""))
	if not error_text.is_empty():
		summary_label.text = "最近结果：%s" % error_text
	elif not result_text.is_empty():
		summary_label.text = "最近结果：%s" % result_text
	else:
		summary_label.text = "最近结果：暂无"


func _on_simulate_success_button_pressed() -> void:
	simulate_flow_requested.emit("success")


func _on_simulate_fail_button_pressed() -> void:
	simulate_flow_requested.emit("fail")
