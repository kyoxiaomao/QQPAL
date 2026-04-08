extends Control

signal close_requested
signal task_flow_requested(flow_type: String)
signal chat_submitted(text: String)

@onready var page_container: Control = $RootPanel/MarginContainer/RootVBox/BodyRow/PageContainer
@onready var home_page = $RootPanel/MarginContainer/RootVBox/BodyRow/PageContainer/HomePage
@onready var chat_page = $RootPanel/MarginContainer/RootVBox/BodyRow/PageContainer/ChatPage
@onready var model_config_page = $RootPanel/MarginContainer/RootVBox/BodyRow/PageContainer/ModelConfigPage
@onready var skill_config_page = $RootPanel/MarginContainer/RootVBox/BodyRow/PageContainer/SkillConfigPage
@onready var market_page = $RootPanel/MarginContainer/RootVBox/BodyRow/PageContainer/MarketPage
@onready var system_settings_page = $RootPanel/MarginContainer/RootVBox/BodyRow/PageContainer/SystemSettingsPage
@onready var subtitle_label: Label = $RootPanel/MarginContainer/RootVBox/TopBarPanel/TopBarMargin/TopBar/SubtitleLabel
@onready var home_button: Button = $RootPanel/MarginContainer/RootVBox/TopBarPanel/TopBarMargin/TopBar/TopNav/HomeButton
@onready var chat_button: Button = $RootPanel/MarginContainer/RootVBox/TopBarPanel/TopBarMargin/TopBar/TopNav/ChatButton
@onready var model_button: Button = $RootPanel/MarginContainer/RootVBox/TopBarPanel/TopBarMargin/TopBar/TopNav/ModelButton
@onready var skill_button: Button = $RootPanel/MarginContainer/RootVBox/TopBarPanel/TopBarMargin/TopBar/TopNav/SkillButton
@onready var market_button: Button = $RootPanel/MarginContainer/RootVBox/TopBarPanel/TopBarMargin/TopBar/TopNav/MarketButton
@onready var system_button: Button = $RootPanel/MarginContainer/RootVBox/TopBarPanel/TopBarMargin/TopBar/TopNav/SystemButton

var _pages: Dictionary
var _nav_buttons: Dictionary
var _page_titles := {
	"home": "首页",
	"chat": "对话",
	"model_config": "模型配置",
	"skill_config": "技能配置",
	"market": "龙虾市场",
	"system_settings": "系统设置"
}


func _ready() -> void:
	_pages = {
		"home": home_page,
		"chat": chat_page,
		"model_config": model_config_page,
		"skill_config": skill_config_page,
		"market": market_page,
		"system_settings": system_settings_page
	}
	_nav_buttons = {
		"home": home_button,
		"chat": chat_button,
		"model_config": model_button,
		"skill_config": skill_button,
		"market": market_button,
		"system_settings": system_button
	}

	home_page.simulate_flow_requested.connect(_on_home_page_simulate_flow_requested)
	chat_page.submit_requested.connect(_on_chat_page_submit_requested)
	show_page("home")


func open_app(page_name: String = "home") -> void:
	show_page(page_name)
	if page_name == "chat":
		chat_page.focus_input()


func show_page(page_name: String) -> void:
	if not _pages.has(page_name):
		page_name = "home"

	for key in _pages.keys():
		_pages[key].visible = key == page_name
		_nav_buttons[key].set_pressed_no_signal(key == page_name)

	subtitle_label.text = "当前页面：%s" % _page_titles.get(page_name, page_name)


func update_task_state(state: String, status_text: String, task_data: Dictionary) -> void:
	home_page.update_task_state(state, status_text, task_data)
	chat_page.set_status_text(status_text)

	if state == "success":
		append_chat_message("QQPAL", task_data.get("result", "任务已完成"))
	elif state == "failed":
		append_chat_message("QQPAL", task_data.get("error", "任务失败"))


func append_chat_message(role: String, text: String) -> void:
	chat_page.append_message(role, text)


func _on_home_page_simulate_flow_requested(flow_type: String) -> void:
	task_flow_requested.emit(flow_type)
	show_page("home")


func _on_chat_page_submit_requested(text: String) -> void:
	chat_submitted.emit(text)


func _on_close_button_pressed() -> void:
	close_requested.emit()


func _on_home_button_pressed() -> void:
	show_page("home")


func _on_chat_button_pressed() -> void:
	show_page("chat")


func _on_model_button_pressed() -> void:
	show_page("model_config")


func _on_skill_button_pressed() -> void:
	show_page("skill_config")


func _on_market_button_pressed() -> void:
	show_page("market")


func _on_system_button_pressed() -> void:
	show_page("system_settings")
