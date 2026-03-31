extends MarginContainer

signal submit_requested(text: String)

@onready var status_label: Label = $RootRow/ChatPanel/ChatMargin/ChatVBox/HeaderRow/StatusPanel/StatusLabel
@onready var history_label: RichTextLabel = $RootRow/ChatPanel/ChatMargin/ChatVBox/HistoryLabel
@onready var input_line: LineEdit = $RootRow/ChatPanel/ChatMargin/ChatVBox/InputRow/InputLine


func focus_input() -> void:
	input_line.grab_focus()


func set_status_text(text: String) -> void:
	status_label.text = text


func append_message(role: String, text: String) -> void:
	history_label.text += "[%s] %s\n" % [role, text]
	history_label.scroll_to_line(history_label.get_line_count())


func _on_send_button_pressed() -> void:
	var text := input_line.text.strip_edges()
	if text.is_empty():
		return

	append_message("你", text)
	input_line.clear()
	submit_requested.emit(text)


func _on_draft_task_button_pressed() -> void:
	_submit_preset("请先帮我梳理当前需求，并列出关键目标。")


func _on_plan_task_button_pressed() -> void:
	_submit_preset("请根据当前需求生成一份执行方案，并说明先后顺序。")


func _on_summary_task_button_pressed() -> void:
	_submit_preset("请总结当前进展，并列出下一步要做的事情。")


func _on_continue_task_button_pressed() -> void:
	_submit_preset("请继续当前任务，保持现有上下文直接往下执行。")


func _submit_preset(text: String) -> void:
	append_message("你", text)
	submit_requested.emit(text)
