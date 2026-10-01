class_name StatsPanel
extends PanelContainer
## Окно статистики для ручного тестирования (кнопка 📊 справа вверху). Не блокирует игру, обновляется само.

signal reset_requested
signal speed_selected(value: float)

## Варианты ускорения игры (Engine.time_scale). Выше ×10 кадры становятся слишком «крупными»: таймеры и анимации теряют точность.
const SPEEDS: Array[float] = [1.0, 10.0]

var _speed_buttons: Array[Button] = []

var provider: Callable = Callable()
var _label: Label
var _timer := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "📊 Статистика теста"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset_button := Button.new()
	reset_button.text = "Сброс"
	reset_button.add_theme_font_size_override("font_size", 12)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.tooltip_text = "Обнулить счётчики за запуск"
	reset_button.pressed.connect(func() -> void: reset_requested.emit())
	head.add_child(reset_button)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.add_theme_font_size_override("font_size", 12)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: visible = false)
	head.add_child(close_button)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	box.add_child(speed_row)
	var speed_title := Label.new()
	speed_title.text = "Скорость:"
	speed_title.add_theme_font_size_override("font_size", 14)
	speed_row.add_child(speed_title)
	for value: float in SPEEDS:
		var button := Button.new()
		button.text = "×%d" % int(value)
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 12)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Ускорить всю игру в %d раз(а)" % int(value)
		button.button_pressed = value == 1.0
		button.pressed.connect(func() -> void: speed_selected.emit(value))
		speed_row.add_child(button)
		_speed_buttons.append(button)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(380, 0)
	box.add_child(_label)


## Подсвечивает выбранную скорость.
func show_speed(value: float) -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], value))


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	if _label != null and provider.is_valid():
		_label.text = "\n".join(provider.call())


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer >= 0.25:
		_timer = 0.0
		refresh()
