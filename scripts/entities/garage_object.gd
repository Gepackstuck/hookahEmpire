class_name GarageObject
extends Node2D
## Визуальное представление объекта гаража (стол, кальян, ящик...) по data-описанию.
## Позиция ноды = экранная проекция точки опоры на пол; Y-sort родителя сортирует по ней.

const FALLBACK_EMOJI := "❓"

var object_id: String = ""
## Высота визуала над полом (отрицательная, в экранных пикселях) — для подсказки.
var top_y: float = -48.0

var _visual: Dictionary = {}
var _lift: float = 0.0
var _glow_enabled: bool = false
var _glow_target: float = 0.0
var _glow_level: float = 0.0
var _glow_time: float = 0.0
var _glow_center: Vector2 = Vector2(0, -24)
var _props: Array = [] # предметы на поверхности (visual.props), отсортированы для правильного перекрытия
var _footprint: Vector2i = Vector2i.ONE


func setup(definition: Dictionary) -> void:
	object_id = definition["id"]
	name = "Obj_%s" % object_id
	_visual = definition["visual"]
	_footprint = definition["size"]
	position = IsoProjection.grid_to_screen(definition["anchor"])
	_lift = float(_visual.get("lift", 0.0))
	_glow_enabled = bool(_visual.get("glow", false))
	set_process(false)
	match str(_visual["type"]):
		"emoji":
			_add_emoji(str(_visual["text"]), int(_visual.get("size", 40)))
		"texture":
			_add_texture(str(_visual["path"]), float(_visual.get("height", 64.0)))
		"box":
			top_y = -float(_visual.get("height", 24.0)) - 6.0
	_props = _sorted_props(_visual.get("props", []))
	if not _props.is_empty():
		top_y -= 46.0
	top_y -= _lift
	queue_redraw()


## Включает/выключает сияние (только для объектов с visual.glow).
func set_highlighted(value: bool) -> void:
	if not _glow_enabled:
		return
	_glow_target = 1.0 if value else 0.0
	set_process(true)


func _process(delta: float) -> void:
	_glow_level = move_toward(_glow_level, _glow_target, delta * 4.0)
	_glow_time += delta
	queue_redraw()
	if _glow_target == 0.0 and _glow_level == 0.0:
		set_process(false)


func _draw() -> void:
	match str(_visual.get("type", "")):
		"box":
			_draw_box()
		"emoji", "texture":
			IsoDraw.draw_shadow(self, 18.0)
	if _glow_level > 0.0:
		_draw_glow()


func _draw_glow() -> void:
	var pulse := 0.85 + 0.15 * sin(_glow_time * 4.0)
	var radius := 52.0 * pulse
	for i in 7:
		var t := float(i) / 6.0
		var color := Color(1.0, 0.85, 0.35, 0.11 * _glow_level)
		draw_circle(_glow_center, radius * (1.0 - t * 0.75), color)
	# Яркое ядро — чтобы сияние читалось даже на светлом полу.
	draw_circle(_glow_center, 15.0 * pulse, Color(1.0, 0.95, 0.7, 0.35 * _glow_level))


func _add_emoji(text: String, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := float(font_size) * 1.6
	label.size = Vector2(box, box)
	label.position = Vector2(-box * 0.5, -box * 0.5 - float(font_size) * 0.55 + 4.0 - _lift)
	_glow_center = Vector2(0, -float(font_size) * 0.55 + 4.0 - _lift)
	add_child(label)
	top_y = -float(font_size) * 1.3


func _add_texture(path: String, height: float) -> void:
	if not ResourceLoader.exists(path):
		GameLog.warn("garage", "Текстура не найдена: %s (объект %s), показан запасной эмодзи" % [path, object_id])
		_add_emoji(FALLBACK_EMOJI, 40)
		return
	var texture: Texture2D = load(path)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	var factor := height / float(texture.get_height())
	sprite.scale = Vector2(factor, factor)
	sprite.position = Vector2(-float(texture.get_width()) * factor * 0.5, -height + 2.0)
	add_child(sprite)
	top_y = -height - 4.0


func _draw_box() -> void:
	var half := Vector2(_footprint) * 0.5
	var height := float(_visual.get("height", 24.0))
	var base := Color.html(str(_visual.get("color", "#9c6b43")))
	var lift := Vector2(0, -height)
	var north := IsoProjection.grid_to_screen(Vector2(-half.x, -half.y))
	var east := IsoProjection.grid_to_screen(Vector2(half.x, -half.y))
	var south := IsoProjection.grid_to_screen(Vector2(half.x, half.y))
	var west := IsoProjection.grid_to_screen(Vector2(-half.x, half.y))
	draw_colored_polygon(PackedVector2Array([west, south, south + lift, west + lift]), base.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([south, east, east + lift, south + lift]), base.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([north + lift, east + lift, south + lift, west + lift]), base.lightened(0.1))
	_draw_props(lift)


## Предметы на поверхности стола: сортируем по глубине (x + y), дальние рисуются первыми.
func _sorted_props(raw: Variant) -> Array:
	var result: Array = []
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Array = a["at"]
		var pb: Array = b["at"]
		return float(pa[0]) + float(pa[1]) < float(pb[0]) + float(pb[1]))
	return result


func _draw_props(lift: Vector2) -> void:
	for prop in _props:
		var at: Array = prop["at"]
		var base := IsoProjection.grid_to_screen(Vector2(float(at[0]), float(at[1]))) + lift
		var color := Color.html(str(prop.get("color", "#6fb3d9")))
		match str(prop["type"]):
			"hookah":
				_draw_hookah(base, color)
			"jar":
				_draw_jar(base, color)
			"cup":
				_draw_cup(base, color)
			"coals":
				_draw_coals(base)


static func _ellipse_points(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points


func _ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	draw_colored_polygon(_ellipse_points(center, rx, ry), color)


func _draw_hookah(p: Vector2, color: Color) -> void:
	var metal := Color("#c9ced6")
	var dark_metal := Color("#8b929e")
	_ellipse(p + Vector2(0, 1), 12.0, 5.0, Color(0, 0, 0, 0.25))
	# Колба с водой.
	_ellipse(p + Vector2(0, -10), 10.0, 11.0, color.darkened(0.25))
	_ellipse(p + Vector2(0, -7), 8.0, 8.0, color)
	_ellipse(p + Vector2(-3, -14), 2.5, 4.0, Color(1, 1, 1, 0.35))
	# Горлышко, шахта, тарелка.
	draw_rect(Rect2(p + Vector2(-2.5, -24), Vector2(5, 5)), dark_metal)
	draw_rect(Rect2(p + Vector2(-2.0, -40), Vector2(4, 17)), metal)
	_ellipse(p + Vector2(0, -39), 9.0, 3.5, dark_metal)
	_ellipse(p + Vector2(0, -40), 8.0, 3.0, metal)
	# Чаша с табаком и фольгой, уголь.
	draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -40), p + Vector2(5, -40), p + Vector2(3.5, -47), p + Vector2(-3.5, -47)]), Color("#b5573a"))
	_ellipse(p + Vector2(0, -47), 4.5, 1.8, Color("#d9d9dd"))
	_ellipse(p + Vector2(0, -48), 2.4, 1.0, Color("#ff6a2a"))
	# Шланг: плавная дуга в сторону, мундштук на конце.
	var hose := PackedVector2Array()
	var start := p + Vector2(3, -26)
	var control := p + Vector2(26, -24)
	var finish := p + Vector2(24, -5)
	for i in 11:
		var t := float(i) / 10.0
		hose.append(start.lerp(control, t).lerp(control.lerp(finish, t), t))
	draw_polyline(hose, Color("#3a2f4a"), 2.5, true)
	draw_rect(Rect2(finish + Vector2(-1.5, -1), Vector2(3, 4)), metal)


func _draw_jar(p: Vector2, color: Color) -> void:
	_ellipse(p + Vector2(0, 1), 8.0, 3.2, Color(0, 0, 0, 0.22))
	_ellipse(p + Vector2(0, -1), 6.5, 2.6, color.darkened(0.3))
	draw_rect(Rect2(p + Vector2(-6.5, -13), Vector2(13, 12)), color)
	draw_rect(Rect2(p + Vector2(-6.5, -9), Vector2(13, 4)), Color(1, 1, 1, 0.75))
	_ellipse(p + Vector2(0, -13), 6.5, 2.6, color.lightened(0.25))


func _draw_cup(p: Vector2, color: Color) -> void:
	_ellipse(p + Vector2(0, 1), 6.0, 2.4, Color(0, 0, 0, 0.22))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -12), p + Vector2(5, -12), p + Vector2(3.5, 0), p + Vector2(-3.5, 0)]), Color(0.85, 0.93, 1.0, 0.75))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-4.4, -7), p + Vector2(4.4, -7), p + Vector2(3.5, 0), p + Vector2(-3.5, 0)]), color)
	_ellipse(p + Vector2(0, -12), 5.0, 1.8, Color(1, 1, 1, 0.6))


func _draw_coals(p: Vector2) -> void:
	_ellipse(p + Vector2(0, 1), 12.0, 5.0, Color(0, 0, 0, 0.25))
	_ellipse(p + Vector2(0, -2), 11.0, 4.6, Color("#4a4f58"))
	_ellipse(p + Vector2(0, -3), 9.5, 3.8, Color("#2f3238"))
	for offset in [Vector2(-4, -4), Vector2(1, -5), Vector2(5, -3)]:
		draw_rect(Rect2(p + offset, Vector2(4, 3)), Color("#1f2125"))
		draw_rect(Rect2(p + offset + Vector2(1, 0), Vector2(2, 1)), Color("#ff7a30"))
