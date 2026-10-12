class_name MainMenu
extends Control
## M11: главное меню при запуске игры: случайный фон, кнопки «Играть» и «Выйти из игры».

signal play_requested
signal settings_requested
signal quit_requested

const BACKGROUNDS: Array[String] = [
	"res://assets/menu/bg_1.png",
	"res://assets/menu/bg_2.png",
	"res://assets/menu/bg_3.png",
]


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
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_top = -250.0
	anchor.offset_bottom = -36.0
	anchor.alignment = BoxContainer.ALIGNMENT_CENTER
	anchor.add_child(_button("▶  Играть", play_requested))
	anchor.add_child(_button("⚙️  Настройки", settings_requested))
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
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.14, 0.08, 0.92)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", UiStyle.GOLD)
	button.pressed.connect(func() -> void: target.emit())
	return button
