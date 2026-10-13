class_name MainMenu
extends Control
## M11: главное меню при запуске игры: случайный фон, кнопки «Играть» и «Выйти из игры».

signal play_requested
signal quit_requested

const BACKGROUNDS: Array[String] = [
	"res://assets/menu/bg_1.png",
	"res://assets/menu/bg_2.png",
	"res://assets/menu/bg_3.png",
]


var _anchor: VBoxContainer
var _settings_holder: Control = null


## Настройки открываются поверх фона вместо кнопок меню; page готовит Main.
func embed_settings(page: SettingsPanel) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(panel)
	panel.add_child(page)
	page.closed.connect(_close_settings)
	_settings_holder = center


func _open_settings() -> void:
	if _settings_holder == null:
		return
	_anchor.visible = false
	_settings_holder.visible = true


func _close_settings() -> void:
	if _settings_holder != null:
		_settings_holder.visible = false
	_anchor.visible = true


func _input(event: InputEvent) -> void:
	if visible and _settings_holder != null and _settings_holder.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_settings()


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiStyle.make_theme()
	var path := BACKGROUNDS[randi() % BACKGROUNDS.size()]
	if ResourceLoader.exists(path):
		var picture := TextureRect.new()
		picture.texture = load(path)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(picture)
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	else:
		var fill := ColorRect.new()
		fill.color = Color(0.07, 0.055, 0.045, 1)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Кнопки внизу по центру: фон-картинка со своим логотипом остаётся целиком видимой.
	var anchor := VBoxContainer.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_theme_constant_override("separation", 14)
	add_child(anchor)
	_anchor = anchor
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_top = -250.0
	anchor.offset_bottom = -36.0
	anchor.alignment = BoxContainer.ALIGNMENT_CENTER
	anchor.add_child(_button("▶  Играть", play_requested))
	anchor.add_child(_action_button("⚙️  Настройки", _open_settings))
	anchor.add_child(_button("Выйти из игры", quit_requested))


func _button(text: String, target: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 28)
	button.custom_minimum_size = Vector2(320, 58)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := UiStyle.panel_style()
	style.bg_color = Color(0.07, 0.055, 0.045, 0.82)
	if VisualStyle.modern:
		style.bg_color = Color(0.11, 0.065, 0.15, 0.9)
		style.set_corner_radius_all(18)
		style.set_border_width_all(1)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.14, 0.08, 0.92) if not VisualStyle.modern else Color(0.22, 0.13, 0.3, 0.95)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", UiStyle.GOLD)
	button.pressed.connect(func() -> void: target.emit())
	return button


func _action_button(text: String, action: Callable) -> Button:
	var button := _button(text, play_requested)
	for connection in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"])
	button.pressed.connect(action)
	return button
