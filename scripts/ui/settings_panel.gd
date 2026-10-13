class_name SettingsPanel
extends VBoxContainer
## Содержимое настроек (громкость, графика, имена): вставляется внутрь меню паузы / главного меню или в отдельное окно.

signal volume_changed(percent: float)
signal volume_committed(percent: float)
signal style_changed(modern: bool)
signal names_changed(show: bool)
signal closed


func setup(volume_percent: float, modern_graphics: bool = false, show_names: bool = true) -> void:
	var box := self
	add_theme_constant_override("separation", 18)
	var title := UiStyle.label("⚙️ Настройки", 34, UiStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	row.add_child(UiStyle.label("🔊 Громкость", 24))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = clampf(volume_percent, 0.0, 100.0)
	slider.custom_minimum_size = Vector2(240, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var value_label := UiStyle.label("%d%%" % int(slider.value), 22, UiStyle.MUTED)
	value_label.custom_minimum_size = Vector2(64, 0)
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%%" % int(value)
		volume_changed.emit(value))
	slider.drag_ended.connect(func(_changed: bool) -> void: volume_committed.emit(slider.value))
	var style_check := CheckButton.new()
	style_check.text = "🎨 Новая графика (мягкие гости, тёплый пол и стены)"
	style_check.focus_mode = Control.FOCUS_NONE
	style_check.add_theme_font_size_override("font_size", 22)
	style_check.button_pressed = modern_graphics
	style_check.toggled.connect(func(on: bool) -> void: style_changed.emit(on))
	box.add_child(style_check)
	var names_check := CheckButton.new()
	names_check.text = "🏷️ Имена над головами друзей"
	names_check.focus_mode = Control.FOCUS_NONE
	names_check.add_theme_font_size_override("font_size", 22)
	names_check.button_pressed = show_names
	names_check.toggled.connect(func(on: bool) -> void: names_changed.emit(on))
	box.add_child(names_check)
	var close := Button.new()
	close.text = "Назад"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 22)
	close.custom_minimum_size = Vector2(200, 48)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		volume_committed.emit(slider.value)
		closed.emit())
	box.add_child(close)
