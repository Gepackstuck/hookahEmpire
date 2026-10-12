class_name SettingsMenu
extends Control
## M11: окно настроек: громкость (настройка общая для всех профилей и запоминается).

signal volume_changed(percent: float)
signal volume_committed(percent: float)
signal closed


func setup(volume_percent: float) -> void:
	var panel := UiStyle.build_frame(self, Vector2(560, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
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


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
