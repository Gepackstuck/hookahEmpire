class_name BarNameDialog
extends Control
## M11: окно «Назови свою кальянную». Название показывается в списке профилей.

## name — очищенное название ("" если игрок отложил выбор).
signal finished(bar_name: String)

var _edit: LineEdit = null
var _ok: Button = null


func setup(current_name: String) -> void:
	var panel := UiStyle.build_frame(self, Vector2(600, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var title := UiStyle.label("Как назовём твою кальянную?", 30, UiStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text := UiStyle.label("Два сильных рецепта собраны — пора дать месту имя. Оно появится в списке твоих профилей.", 20, UiStyle.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(520, 0)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	_edit = LineEdit.new()
	_edit.max_length = ProfileStore.MAX_NAME_LENGTH
	_edit.placeholder_text = "Например: Дымный гараж"
	_edit.text = current_name
	_edit.add_theme_font_size_override("font_size", 26)
	_edit.custom_minimum_size = Vector2(520, 52)
	_edit.text_changed.connect(func(_t: String) -> void: _refresh_ok())
	_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	box.add_child(_edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_ok = Button.new()
	_ok.text = "Готово"
	_ok.focus_mode = Control.FOCUS_NONE
	_ok.add_theme_font_size_override("font_size", 22)
	_ok.custom_minimum_size = Vector2(200, 48)
	_ok.pressed.connect(_submit)
	row.add_child(_ok)
	var later := Button.new()
	later.text = "Позже"
	later.focus_mode = Control.FOCUS_NONE
	later.add_theme_font_size_override("font_size", 22)
	later.custom_minimum_size = Vector2(160, 48)
	later.pressed.connect(func() -> void: finished.emit(""))
	row.add_child(later)
	_refresh_ok()
	_edit.grab_focus.call_deferred()


## Тест-прогон: вписывает название и подтверждает окно сам.
func autosubmit(bar_name: String) -> void:
	_edit.text = bar_name
	_refresh_ok()
	_submit()


func _refresh_ok() -> void:
	_ok.disabled = ProfileStore.clean_name(_edit.text).is_empty()


func _submit() -> void:
	var cleaned := ProfileStore.clean_name(_edit.text)
	if not cleaned.is_empty():
		finished.emit(cleaned)
