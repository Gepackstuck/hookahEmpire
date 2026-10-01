class_name FurnitureContextMenu
extends PanelContainer
## M9: маленькое меню у выбранного в мире предмета: переместить, повернуть, убрать.

signal move_requested(uid: String)
signal rotate_requested(uid: String)
signal remove_requested(uid: String)

var _uid := ""
var _title: Label
var _rotate_button: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	box.add_child(_title)
	box.add_child(_button("✋ Переместить", func() -> void: _emit_and_hide(move_requested)))
	_rotate_button = _button("↻ Повернуть", func() -> void: _emit_and_hide(rotate_requested, false))
	box.add_child(_rotate_button)
	box.add_child(_button("🗑 Убрать на склад", func() -> void: _emit_and_hide(remove_requested)))


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button


func _emit_and_hide(request: Signal, hide_menu: bool = true) -> void:
	request.emit(_uid)
	if hide_menu:
		close()


## Показывает меню рядом с точкой screen_position (в координатах окна), не выходя за экран.
func open_for(uid: String, item_name: String, can_rotate: bool, screen_position: Vector2) -> void:
	_uid = uid
	_title.text = item_name
	_rotate_button.disabled = not can_rotate
	visible = true
	reset_size()
	var viewport_size := get_viewport_rect().size
	position = Vector2(
		clampf(screen_position.x + 12.0, 8.0, maxf(viewport_size.x - size.x - 8.0, 8.0)),
		clampf(screen_position.y + 12.0, 8.0, maxf(viewport_size.y - size.y - 8.0, 8.0)))


func close() -> void:
	visible = false
	_uid = ""
