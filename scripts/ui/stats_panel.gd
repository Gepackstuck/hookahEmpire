class_name StatsPanel
extends PanelContainer
## Окно статистики для ручного тестирования (кнопка 📊 справа вверху). Не блокирует игру, обновляется само.

signal reset_requested
signal speed_selected(value: float)
signal trend_next_requested
signal money_requested
signal goal_reset_requested
signal money_zero_requested

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
	var copy_button := Button.new()
	copy_button.text = "📋"
	copy_button.add_theme_font_size_override("font_size", 12)
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.tooltip_text = "Скопировать весь текст статистики в буфер обмена"
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(_label.text))
	head.add_child(copy_button)
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
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 4)
	box.add_child(test_row)
	for entry: Array in [["Тренд ▶", "Переключить на следующий тренд", trend_next_requested], ["+1000 💰", "Добавить 1000 денег", money_requested], ["Сброс цели", "Сбросить прогресс «сильный рецепт»", goal_reset_requested], ["💰 → 0", "Обнулить деньги (проверка платных рецептов и бесплатных ингредиентов)", money_zero_requested]]:
		var test_button := Button.new()
		test_button.text = str(entry[0])
		test_button.tooltip_text = str(entry[1])
		test_button.add_theme_font_size_override("font_size", 12)
		test_button.focus_mode = Control.FOCUS_NONE
		var test_signal: Signal = entry[2]
		test_button.pressed.connect(func() -> void: test_signal.emit())
		test_row.add_child(test_button)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(380, 0)
	# Текст длинный: он лежит в прокручиваемой области, а панель растягивается на высоту экрана (см. Main._add_stats_panel).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(380, 120)
	box.add_child(scroll)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_label)


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
