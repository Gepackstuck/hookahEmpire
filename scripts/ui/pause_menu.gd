class_name PauseMenu
extends Control
## M11: меню паузы (Esc): логотип, «Продолжить», «Профили», «В главное меню», «Выйти из игры».

signal resume_requested
signal profiles_requested
signal stats_requested
signal main_menu_requested
signal quit_requested

const LOGO_PATHS: Array[String] = [
	"res://assets/menu/logo_1.png",
	"res://assets/menu/logo_2.png",
	"res://assets/menu/logo_3.png",
]


var _panel: PanelContainer
var _box: VBoxContainer
var _settings: SettingsPanel = null


## Настройки открываются внутри этого же меню (вместо основных кнопок); page готовит Main.
func embed_settings(page: SettingsPanel) -> void:
	_settings = page
	_settings.visible = false
	_panel.add_child(_settings)
	_settings.closed.connect(_close_settings)


func _open_settings() -> void:
	if _settings == null:
		return
	_box.visible = false
	_settings.visible = true


func _close_settings() -> void:
	if _settings != null:
		_settings.visible = false
	_box.visible = true


func setup() -> void:
	var panel := UiStyle.build_frame(self, Vector2(620, 0))
	_panel = panel
	var box := VBoxContainer.new()
	_box = box
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	# Сверху — случайный логотип, под ним пункты списком.
	var logo_path := LOGO_PATHS[randi() % LOGO_PATHS.size()]
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(520, 250)
		box.add_child(logo)
	else:
		var title := UiStyle.label("Hookah Empire", 40, UiStyle.GOLD)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
	var pause := UiStyle.label("Пауза", 28, UiStyle.GOLD)
	pause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pause)
	box.add_child(_button("▶  Продолжить", resume_requested))
	box.add_child(_button("🪔  Профили", profiles_requested))
	box.add_child(_action_button("⚙️  Настройки", _open_settings))
	box.add_child(_button("📊  Статистика", stats_requested))
	box.add_child(_button("🏠  В главное меню", main_menu_requested))
	box.add_child(_button("Выйти из игры", quit_requested))


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings != null and _settings.visible:
			_close_settings()
		else:
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


func _action_button(text: String, action: Callable) -> Button:
	var button := _button(text, resume_requested)
	for connection in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"])
	button.pressed.connect(action)
	return button
