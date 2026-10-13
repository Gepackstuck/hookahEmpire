class_name SettingsMenu
extends Control
## Отдельное окно настроек (запасной вариант): та же панель SettingsPanel в рамке.

signal volume_changed(percent: float)
signal volume_committed(percent: float)
signal style_changed(modern: bool)
signal names_changed(show: bool)
signal closed


func setup(volume_percent: float, modern_graphics: bool = false, show_names: bool = true) -> void:
	var panel := UiStyle.build_frame(self, Vector2(560, 0))
	var page := SettingsPanel.new()
	panel.add_child(page)
	page.setup(volume_percent, modern_graphics, show_names)
	page.volume_changed.connect(func(v: float) -> void: volume_changed.emit(v))
	page.volume_committed.connect(func(v: float) -> void: volume_committed.emit(v))
	page.style_changed.connect(func(m: bool) -> void: style_changed.emit(m))
	page.names_changed.connect(func(n: bool) -> void: names_changed.emit(n))
	page.closed.connect(func() -> void: closed.emit())


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
