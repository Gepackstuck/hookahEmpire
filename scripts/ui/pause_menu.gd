class_name PauseMenu
extends Control
## M11: меню паузы (Esc): логотип, «Продолжить», «Профили», «В главное меню», «Выйти из игры».

signal resume_requested
signal profiles_requested
signal settings_requested
signal stats_requested
signal main_menu_requested
signal quit_requested

const LOGO_PATHS: Array[String] = [
	"res://assets/menu/logo_1.png",
	"res://assets/menu/logo_2.png",
	"res://assets/menu/logo_3.png",
]


func setup() -> void:
	var panel := UiStyle.build_frame(self, Vector2(940, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)
	# Слева — случайный логотип, справа — кнопки.
	var logo_path := LOGO_PATHS[randi() % LOGO_PATHS.size()]
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(500, 380)
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(logo)
	else:
		var title := UiStyle.label("Hookah Empire", 40, UiStyle.GOLD)
		title.custom_minimum_size = Vector2(500, 0)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(title)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	var pause := UiStyle.label("Пауза", 30, UiStyle.GOLD)
	pause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pause)
	box.add_child(_button("▶  Продолжить", resume_requested))
	box.add_child(_button("🪔  Профили", profiles_requested))
	box.add_child(_button("⚙️  Настройки", settings_requested))
	box.add_child(_button("📊  Статистика", stats_requested))
	box.add_child(_button("🏠  В главное меню", main_menu_requested))
	box.add_child(_button("Выйти из игры", quit_requested))


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _button(text: String, target: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.custom_minimum_size = Vector2(330, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void: target.emit())
	return button
