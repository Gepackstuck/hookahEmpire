class_name DragToken
extends Button
## Кнопка-источник перетаскивания (порция ингредиента, уголь). Клик тоже работает — на случай, когда перетаскивать неудобно.

var payload: Dictionary = {}
var preview_text: String = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = preview_text
	preview.add_theme_font_size_override("font_size", 46)
	set_drag_preview(preview)
	return payload
