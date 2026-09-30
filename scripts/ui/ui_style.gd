class_name UiStyle
extends RefCounted
## Общие стили для экранов M3 (смеситель, книга рецептов): тема и рамка панели.

const GOLD := Color(0.96, 0.85, 0.55, 1)
const MUTED := Color(0.7, 0.66, 0.6, 1)


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 24
	return theme


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.055, 0.045, 0.96)
	style.set_border_width_all(3)
	style.border_color = GOLD
	style.set_corner_radius_all(14)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	return style


## Полноэкранный корень экрана: затемнение + центрированная панель. Возвращает панель.
static func build_frame(root: Control, panel_size: Vector2) -> PanelContainer:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = make_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	panel.add_theme_stylebox_override("panel", panel_style())
	center.add_child(panel)
	return panel


static func label(text: String, size: int = 24, color: Color = Color.WHITE) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node
