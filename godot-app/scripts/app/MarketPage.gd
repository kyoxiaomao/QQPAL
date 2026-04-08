extends MarginContainer

@onready var cards_grid: GridContainer = $VBoxContainer/ScrollContainer/CardsGrid

var _apps: Array[Dictionary] = [
	{
		"title": "OpenClaw",
		"subtitle": "经典平台冒险游戏运行包",
		"description": "OpenClaw 是对经典 Captain Claw 的开源实现，适合体验原版关卡、角色动作和社区扩展内容。",
		"installed": true,
		"badge": "精选",
		"category": "动作冒险",
		"version": "v1.0.0",
		"size": "248 MB",
		"rating": "4.9",
		"icon": "OC",
		"accent": Color(0.929412, 0.470588, 0.27451, 1)
	},
	{
		"title": "OpenClaw 启动器",
		"subtitle": "快速进入游戏与参数配置",
		"description": "统一管理启动参数、窗口模式与基础资源检测，适合日常快速启动游戏。",
		"installed": false,
		"badge": "推荐",
		"category": "启动工具",
		"version": "v0.9.2",
		"size": "36 MB",
		"rating": "4.7",
		"icon": "启",
		"accent": Color(0.490196, 0.65098, 1, 1)
	},
	{
		"title": "OpenClaw 关卡编辑器",
		"subtitle": "地图与机关编辑工具",
		"description": "可视化编辑地形、敌人、机关与奖励道具，适合制作自定义挑战关卡。",
		"installed": false,
		"badge": "创作",
		"category": "开发工具",
		"version": "v0.8.5",
		"size": "82 MB",
		"rating": "4.6",
		"icon": "编",
		"accent": Color(0.372549, 0.862745, 0.682353, 1)
	},
	{
		"title": "OpenClaw Mod 管理器",
		"subtitle": "安装与切换社区模组",
		"description": "集中管理常见模组包，支持启用、停用与本地版本切换。",
		"installed": false,
		"badge": "社区",
		"category": "内容管理",
		"version": "v1.2.1",
		"size": "44 MB",
		"rating": "4.8",
		"icon": "模",
		"accent": Color(0.760784, 0.501961, 1, 1)
	},
	{
		"title": "OpenClaw 资源浏览器",
		"subtitle": "查看贴图、音效与动画",
		"description": "用卡片化方式快速预览资源文件，方便整理素材和二次创作。",
		"installed": false,
		"badge": "素材",
		"category": "浏览工具",
		"version": "v0.7.4",
		"size": "58 MB",
		"rating": "4.5",
		"icon": "资",
		"accent": Color(1, 0.729412, 0.356863, 1)
	},
	{
		"title": "OpenClaw 联机实验版",
		"subtitle": "社区联机功能预览",
		"description": "提供联机大厅、房间信息和延迟检测入口，适合体验多人实验功能。",
		"installed": false,
		"badge": "实验",
		"category": "多人联机",
		"version": "v0.5.0",
		"size": "190 MB",
		"rating": "4.3",
		"icon": "联",
		"accent": Color(0.392157, 0.854902, 0.960784, 1)
	},
	{
		"title": "OpenClaw 成就中心",
		"subtitle": "挑战记录与进度追踪",
		"description": "同步查看通关成就、隐藏挑战与最佳成绩，方便长期游玩记录。",
		"installed": false,
		"badge": "成长",
		"category": "玩家服务",
		"version": "v1.1.3",
		"size": "24 MB",
		"rating": "4.7",
		"icon": "成",
		"accent": Color(1, 0.631373, 0.321569, 1)
	},
	{
		"title": "OpenClaw 社区精选",
		"subtitle": "推荐内容与创作者作品",
		"description": "收录热门地图、玩法拓展与社区作者推荐内容，方便发现新作品。",
		"installed": false,
		"badge": "发现",
		"category": "社区内容",
		"version": "v0.6.8",
		"size": "72 MB",
		"rating": "4.8",
		"icon": "荐",
		"accent": Color(1, 0.513726, 0.65098, 1)
	}
]

var _card_widgets: Dictionary = {}


func _ready() -> void:
	_build_cards()


func _build_cards() -> void:
	for child in cards_grid.get_children():
		child.queue_free()

	_card_widgets.clear()

	for index in range(_apps.size()):
		var app_data: Dictionary = _apps[index]
		var card := _create_card(app_data, index)
		cards_grid.add_child(card)
		_refresh_card_state(index)


func _create_card(app_data: Dictionary, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 272)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _build_card_style(app_data))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	column.add_child(header_row)

	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(54, 54)
	icon_panel.add_theme_stylebox_override("panel", _build_icon_style(app_data))
	header_row.add_child(icon_panel)

	var icon_label := Label.new()
	icon_label.text = str(app_data.get("icon", "应"))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_color_override("font_color", Color(1, 0.976471, 0.956863, 1))
	icon_label.add_theme_font_size_override("font_size", 22)
	icon_panel.add_child(icon_label)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 4)
	header_row.add_child(title_column)

	var title_top_row := HBoxContainer.new()
	title_top_row.add_theme_constant_override("separation", 8)
	title_column.add_child(title_top_row)

	var title_label := Label.new()
	title_label.text = str(app_data.get("title", "应用"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_color_override("font_color", Color(1, 0.960784, 0.92549, 1))
	title_label.add_theme_font_size_override("font_size", 20)
	title_top_row.add_child(title_label)

	var rating_label := _create_badge_label("★ %s" % str(app_data.get("rating", "4.8")), _color_from_value(app_data.get("accent", Color(1, 0.6, 0.3, 1))))
	title_top_row.add_child(rating_label)

	var subtitle_label := Label.new()
	subtitle_label.text = str(app_data.get("subtitle", ""))
	subtitle_label.add_theme_color_override("font_color", Color(1, 0.878431, 0.792157, 0.76))
	subtitle_label.add_theme_font_size_override("font_size", 13)
	title_column.add_child(subtitle_label)

	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 8)
	column.add_child(chips_row)

	chips_row.add_child(_create_badge_label(str(app_data.get("badge", "推荐")), _color_from_value(app_data.get("accent", Color(1, 0.6, 0.3, 1)))))
	chips_row.add_child(_create_badge_label(str(app_data.get("category", "应用")), Color(0.431373, 0.541176, 0.8, 1)))

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	column.add_child(meta_row)

	var version_label := Label.new()
	version_label.text = str(app_data.get("version", "v1.0.0"))
	version_label.add_theme_color_override("font_color", Color(1, 0.894118, 0.807843, 0.8))
	version_label.add_theme_font_size_override("font_size", 13)
	meta_row.add_child(version_label)

	var dot_label := Label.new()
	dot_label.text = "•"
	dot_label.add_theme_color_override("font_color", Color(1, 0.894118, 0.807843, 0.5))
	dot_label.add_theme_font_size_override("font_size", 13)
	meta_row.add_child(dot_label)

	var size_label := Label.new()
	size_label.text = str(app_data.get("size", "0 MB"))
	size_label.add_theme_color_override("font_color", Color(1, 0.894118, 0.807843, 0.8))
	size_label.add_theme_font_size_override("font_size", 13)
	meta_row.add_child(size_label)

	var description_label := Label.new()
	description_label.text = str(app_data.get("description", ""))
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description_label.add_theme_color_override("font_color", Color(1, 0.941176, 0.901961, 0.88))
	description_label.add_theme_font_size_override("font_size", 15)
	column.add_child(description_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	column.add_child(status_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	column.add_child(button_row)

	var install_button := Button.new()
	install_button.custom_minimum_size = Vector2(118, 40)
	install_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_button.text = "安装"
	_apply_button_theme(install_button, _color_from_value(app_data.get("accent", Color(1, 0.6, 0.3, 1))), true)
	install_button.pressed.connect(_on_install_button_pressed.bind(index))
	button_row.add_child(install_button)

	var uninstall_button := Button.new()
	uninstall_button.custom_minimum_size = Vector2(118, 40)
	uninstall_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uninstall_button.text = "卸载"
	_apply_button_theme(uninstall_button, Color(0.372549, 0.317647, 0.435294, 1), false)
	uninstall_button.pressed.connect(_on_uninstall_button_pressed.bind(index))
	button_row.add_child(uninstall_button)

	_card_widgets[index] = {
		"status_label": status_label,
		"install_button": install_button,
		"uninstall_button": uninstall_button,
		"card": card
	}

	return card


func _refresh_card_state(index: int) -> void:
	if not _card_widgets.has(index):
		return

	var app_data: Dictionary = _apps[index]
	var widgets: Dictionary = _card_widgets[index]
	var installed := bool(app_data.get("installed", false))
	var status_label: Label = widgets["status_label"]
	var install_button: Button = widgets["install_button"]
	var uninstall_button: Button = widgets["uninstall_button"]
	var card: PanelContainer = widgets["card"]

	status_label.text = "状态：%s" % ("已安装，可直接使用" if installed else "未安装，可立即部署")
	status_label.add_theme_color_override("font_color", Color(1, 0.768627, 0.552941, 1) if installed else Color(0.807843, 0.788235, 0.85098, 0.92))
	install_button.disabled = installed
	uninstall_button.disabled = not installed
	card.add_theme_stylebox_override("panel", _build_card_style(app_data))


func _build_card_style(app_data: Dictionary) -> StyleBoxFlat:
	var accent := _color_from_value(app_data.get("accent", Color(1, 0.6, 0.3, 1)))
	var installed := bool(app_data.get("installed", false))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.133333, 0.105882, 0.180392, 0.98) if installed else Color(0.121569, 0.0980392, 0.164706, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = accent.darkened(0.15) if installed else accent.darkened(0.35)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 18
	style.shadow_color = accent.darkened(0.4)
	style.shadow_size = 14
	style.expand_margin_left = 1.0
	style.expand_margin_top = 1.0
	style.expand_margin_right = 1.0
	style.expand_margin_bottom = 1.0
	return style


func _build_icon_style(app_data: Dictionary) -> StyleBoxFlat:
	var accent := _color_from_value(app_data.get("accent", Color(1, 0.6, 0.3, 1)))
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 18
	style.shadow_color = accent.darkened(0.25)
	style.shadow_size = 8
	return style


func _create_badge_label(text_value: String, tint: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _build_badge_style(tint))

	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 0.972549, 0.945098, 1))
	badge.add_child(label)
	return badge


func _build_badge_style(tint: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.22)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(tint.r, tint.g, tint.b, 0.52)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 10.0
	style.content_margin_top = 6.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 6.0
	return style


func _apply_button_theme(button: Button, tint: Color, filled: bool) -> void:
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(1, 0.976471, 0.952941, 1) if filled else Color(1, 0.933333, 0.878431, 0.96))
	button.add_theme_stylebox_override("normal", _build_button_style(tint, filled, 0.0))
	button.add_theme_stylebox_override("hover", _build_button_style(tint, filled, 0.08))
	button.add_theme_stylebox_override("pressed", _build_button_style(tint, filled, -0.06))
	button.add_theme_stylebox_override("disabled", _build_button_style(Color(0.34902, 0.313726, 0.411765, 1), filled, -0.02))


func _build_button_style(tint: Color, filled: bool, delta: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base_color := tint.lightened(delta) if delta > 0.0 else tint.darkened(-delta)
	style.bg_color = base_color if filled else Color(base_color.r, base_color.g, base_color.b, 0.18)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = base_color if filled else Color(base_color.r, base_color.g, base_color.b, 0.72)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	return style


func _color_from_value(value: Variant) -> Color:
	return value if value is Color else Color(1, 0.6, 0.3, 1)


func _on_install_button_pressed(index: int) -> void:
	var app_data: Dictionary = _apps[index]
	app_data["installed"] = true
	_apps[index] = app_data
	_refresh_card_state(index)


func _on_uninstall_button_pressed(index: int) -> void:
	var app_data: Dictionary = _apps[index]
	app_data["installed"] = false
	_apps[index] = app_data
	_refresh_card_state(index)
