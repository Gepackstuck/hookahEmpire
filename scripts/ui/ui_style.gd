class_name UiStyle
extends RefCounted
## Общие стили для экранов M3 (смеситель, книга рецептов): тема и рамка панели.

const GOLD := Color(0.96, 0.85, 0.55, 1)
const MUTED := Color(0.7, 0.66, 0.6, 1)


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 24
	if VisualStyle.modern:
		_add_modern_controls(theme)
	return theme


## Тема только для кнопок и ползунков (без размера шрифта): ставится на главный интерфейс в новом виде.
static func make_controls_theme() -> Theme:
	var theme := Theme.new()
	_add_modern_controls(theme)
	return theme


static func _button_box(bg: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 7.0
	box.content_margin_bottom = 7.0
	box.shadow_size = 4
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_offset = Vector2(0, 2)
	return box


## Новый вид кнопок: фиолетовая плашка с тёплой рамкой, при наведении светлее, при нажатии темнее.
static func _add_modern_controls(theme: Theme) -> void:
	var warm := Color(0.95, 0.78, 0.5)
	var normal := _button_box(Color(0.15, 0.09, 0.2, 0.92), Color(warm.r, warm.g, warm.b, 0.45))
	var hover := _button_box(Color(0.23, 0.14, 0.3, 0.96), Color(warm.r, warm.g, warm.b, 0.9))
	var pressed := _button_box(Color(0.09, 0.05, 0.13, 0.98), Color(warm.r, warm.g, warm.b, 1.0))
	pressed.shadow_size = 0
	var disabled := _button_box(Color(0.12, 0.09, 0.14, 0.6), Color(0.5, 0.45, 0.5, 0.3))
	disabled.shadow_size = 0
	for kind in ["Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, normal)
		theme.set_stylebox("hover", kind, hover)
		theme.set_stylebox("pressed", kind, pressed)
		theme.set_stylebox("disabled", kind, disabled)
		theme.set_stylebox("focus", kind, StyleBoxEmpty.new())
		theme.set_color("font_color", kind, Color(0.98, 0.93, 0.8))
		theme.set_color("font_hover_color", kind, Color(1.0, 0.97, 0.88))
		theme.set_color("font_pressed_color", kind, GOLD)
		theme.set_color("font_disabled_color", kind, Color(0.6, 0.56, 0.58))
	# Галочки не должны выглядеть кнопками: у CheckButton плашка прозрачная.
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 6.0
	flat.content_margin_right = 6.0
	flat.content_margin_top = 4.0
	flat.content_margin_bottom = 4.0
	for kind in ["CheckButton", "CheckBox"]:
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			theme.set_stylebox(state, kind, flat)
		theme.set_icon("checked", kind, _check_icon(true))
		theme.set_icon("unchecked", kind, _check_icon(false))
		theme.set_icon("checked_disabled", kind, _check_icon(true))
		theme.set_icon("unchecked_disabled", kind, _check_icon(false))
		theme.set_constant("h_separation", kind, 10)
	# Ползунок: тонкая дорожка, заполненная часть — тёплая.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.2, 0.14, 0.26, 1.0)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(warm.r, warm.g, warm.b, 0.85)
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4.0
	fill.content_margin_bottom = 4.0
	# Списки, поля ввода, выпадающие меню, полосы прокрутки.
	var list_panel := card_box(Color(0.1, 0.06, 0.14, 0.9), 12, 6.0)
	theme.set_stylebox("panel", "ItemList", list_panel)
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var selected := _button_box(Color(warm.r, warm.g, warm.b, 0.22), Color(warm.r, warm.g, warm.b, 0.8), 8)
	selected.shadow_size = 0
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	var hovered := _button_box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 8)
	hovered.shadow_size = 0
	theme.set_stylebox("hovered", "ItemList", hovered)
	theme.set_color("font_color", "ItemList", Color(0.95, 0.9, 0.82))
	theme.set_color("font_selected_color", "ItemList", GOLD)
	theme.set_constant("v_separation", "ItemList", 6)
	var edit := _button_box(Color(0.07, 0.04, 0.1, 0.95), Color(warm.r, warm.g, warm.b, 0.4), 10)
	edit.shadow_size = 0
	theme.set_stylebox("normal", "LineEdit", edit)
	theme.set_stylebox("focus", "LineEdit", _button_box(Color(0.07, 0.04, 0.1, 0.95), Color(warm.r, warm.g, warm.b, 1.0), 10))
	theme.set_color("font_color", "LineEdit", Color(1.0, 0.96, 0.88))
	var popup := card_box(Color(0.1, 0.06, 0.14, 0.98), 12, 6.0)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", selected)
	theme.set_color("font_color", "PopupMenu", Color(0.95, 0.9, 0.82))
	theme.set_color("font_hover_color", "PopupMenu", GOLD)
	var scroll_grab := StyleBoxFlat.new()
	scroll_grab.bg_color = Color(warm.r, warm.g, warm.b, 0.55)
	scroll_grab.set_corner_radius_all(5)
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(1, 1, 1, 0.05)
	scroll_bg.set_corner_radius_all(5)
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("grabber", bar, scroll_grab)
		theme.set_stylebox("grabber_highlight", bar, scroll_grab)
		theme.set_stylebox("grabber_pressed", bar, scroll_grab)
		theme.set_stylebox("scroll", bar, scroll_bg)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.055, 0.045, 0.96)
	style.set_border_width_all(3)
	style.border_color = GOLD
	style.set_corner_radius_all(14)
	if VisualStyle.modern:
		# Новый вид: глубокий фиолетово-коричневый фон, тонкая тёплая рамка, мягкая тень.
		style.bg_color = Color(0.085, 0.05, 0.11, 0.95)
		style.set_border_width_all(2)
		style.border_color = Color(0.95, 0.78, 0.5, 0.9)
		style.set_corner_radius_all(20)
		style.shadow_size = 18
		style.shadow_color = Color(0, 0, 0, 0.5)
		style.shadow_offset = Vector2(0, 6)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	return style


static var _check_cache: Dictionary = {}


## Квадратная галочка в стиле игры: скруглённый квадрат с тёплой рамкой; включённая — залита золотом с тёмной «птичкой».
static func _check_icon(checked: bool) -> Texture2D:
	if _check_cache.has(checked):
		return _check_cache[checked]
	var size := 26
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	var corner := 7.0
	var warm := Color(0.95, 0.78, 0.5)
	var fill := warm if checked else Color(0.08, 0.05, 0.12)
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half)
			var q := Vector2(absf(p.x), absf(p.y)) - Vector2(half - 1.5 - corner, half - 1.5 - corner)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner
			var color := Color(0, 0, 0, 0)
			if d < 0.5:
				var edge := clampf(0.5 - d, 0.0, 1.0)
				color = fill if d < -2.0 else warm
				color.a = edge
			if checked and d < -2.0:
				for seg: Array in [[Vector2(7.0, 13.5), Vector2(11.0, 17.5)], [Vector2(11.0, 17.5), Vector2(19.0, 8.0)]]:
					var a: Vector2 = seg[0]
					var b: Vector2 = seg[1]
					var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
					var t := clampf((pt - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
					if pt.distance_to(a + (b - a) * t) < 1.7:
						color = Color(0.12, 0.07, 0.14, 1.0)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_check_cache[checked] = texture
	return texture


static func card_box(bg: Color, radius: int = 14, margin: float = 16.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = Color(0.95, 0.78, 0.5, 0.3)
	box.set_content_margin_all(margin)
	return box


## Карточка внутри окна (детали рецепта и т. п.): в новом виде — скруглённая плашка, в классическом — без оформления.
static func card_style() -> StyleBox:
	if not VisualStyle.modern:
		return StyleBoxEmpty.new()
	return card_box(Color(0.12, 0.07, 0.16, 0.85), 16, 18.0)


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


## Плашка поверх игры (подсказки, сообщения, диалог): в новом виде — тёмная фиолетовая со светлой рамкой и тенью.
## classic — стиль из сцены (возвращается как есть). Для окон меньше panel_style(): компактнее.
static func plate_style(classic: StyleBox, radius: int = 16, margin_x: float = 18.0, margin_y: float = 10.0, border: float = 2.0) -> StyleBox:
	if not VisualStyle.modern:
		return classic
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.05, 0.11, 0.92)
	style.set_border_width_all(int(border))
	style.border_color = Color(0.95, 0.78, 0.5, 0.8)
	style.set_corner_radius_all(radius)
	style.shadow_size = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style


## Клавиша «E» в подсказке: золотая таблетка в новом виде.
static func key_style(classic: StyleBox) -> StyleBox:
	if not VisualStyle.modern:
		return classic
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.78, 0.5, 1.0)
	style.set_corner_radius_all(9)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	return style
