class_name GarageObject
extends Node2D
## Визуальное представление объекта гаража (стол, кальян, ящик...) по data-описанию.
## Позиция ноды = экранная проекция точки опоры на пол; Y-sort родителя сортирует по ней.

const FALLBACK_EMOJI := "❓"

var object_id: String = ""
## Высота визуала над полом (отрицательная, в экранных пикселях) — для подсказки.
var top_y: float = -48.0
## Дверь: 0 — закрыта, 1 — распахнута.
var _door_open: float = 0.0
var _door_tween: Tween = null
var _sprite: Sprite2D = null
var _sprite_base_scale := Vector2.ONE
var _sprite_size := Vector2.ONE
var _sprite_anchor := Vector2.ZERO # низ-центр спрайта (точка, вокруг которой сплющиваем)
var _squash_tween: Tween = null

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
	visible = not bool(definition.get("hidden", false))
	_lift = float(_visual.get("lift", 0.0))
	_glow_enabled = bool(_visual.get("glow", false))
	set_process(false)
	match str(_visual["type"]):
		"emoji":
			_add_emoji(str(_visual["text"]), int(_visual.get("size", 40)))
		"texture":
			_add_texture(str(_visual["path"]), float(_visual.get("height", 64.0)))
		"box", "table":
			top_y = -float(_visual.get("height", 24.0)) - 6.0
		"chair":
			top_y = -50.0
		"door":
			top_y = -float(_visual.get("height", 76.0)) - 6.0
	_props = _sorted_props(_visual.get("props", []))
	if not _props.is_empty():
		top_y -= 46.0
	top_y -= _lift + float(_visual.get("top_extra", 0.0))
	queue_redraw()


## Появление предмета с "падением" на поверхность (например, кальян, который поставили на стол).
func drop_in() -> void:
	var final_y := position.y
	position.y = final_y - 30.0
	modulate.a = 0.0
	visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property(self, "position:y", final_y, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await tween.finished


## Открывает/закрывает дверь с анимацией (корутина: завершается, когда движение закончено).
func set_door_open(open: bool, duration: float = 0.35) -> void:
	if _door_tween != null:
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.tween_method(_apply_door_open, _door_open, 1.0 if open else 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _door_tween.finished


func _apply_door_open(amount: float) -> void:
	_door_open = amount
	queue_redraw()


## Кальян "сплющивается" на затяжку: приседает примерно на 6% и возвращается, когда затяжка закончилась.
func squash(duration: float) -> void:
	if _sprite == null:
		return
	if _squash_tween != null:
		_squash_tween.kill()
	_squash_tween = create_tween()
	_squash_tween.tween_method(_apply_squash, 0.0, 1.0, 0.12).set_ease(Tween.EASE_OUT)
	_squash_tween.tween_interval(maxf(duration - 0.12, 0.0))
	_squash_tween.tween_method(_apply_squash, 1.0, 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_squash(amount: float) -> void:
	var stretch := Vector2(1.0 + 0.04 * amount, 1.0 - 0.06 * amount)
	var new_scale := _sprite_base_scale * stretch
	_sprite.scale = new_scale
	_sprite.position = _sprite_anchor - Vector2(_sprite_size.x * new_scale.x * 0.5, _sprite_size.y * new_scale.y)


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
		"table":
			_draw_table()
		"chair":
			_draw_chair()
		"door":
			_draw_door()
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
	sprite.position = Vector2(-float(texture.get_width()) * factor * 0.5, -height + 2.0 - _lift)
	add_child(sprite)
	_sprite = sprite
	_sprite_base_scale = sprite.scale
	_sprite_size = Vector2(texture.get_width(), texture.get_height())
	_sprite_anchor = sprite.position + Vector2(_sprite_size.x * factor * 0.5, _sprite_size.y * factor)
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


## Стол: тень, четыре ножки, царга (рамка под столешницей), столешница с толщиной, досками и светлой кромкой.
func _draw_table() -> void:
	var half := Vector2(_footprint) * 0.5
	var height := float(_visual.get("height", 26.0))
	var base := Color.html(str(_visual.get("color", "#9c6b43")))
	var thickness := 6.0
	var under := height - thickness
	# Мягкая тень на полу.
	var pad := 0.12
	draw_colored_polygon(PackedVector2Array([
		IsoProjection.grid_to_screen(Vector2(-half.x - pad, -half.y - pad)),
		IsoProjection.grid_to_screen(Vector2(half.x + pad, -half.y - pad)),
		IsoProjection.grid_to_screen(Vector2(half.x + pad, half.y + pad)),
		IsoProjection.grid_to_screen(Vector2(-half.x - pad, half.y + pad))]), Color(0, 0, 0, 0.18))
	# Ножки (дальние первыми).
	var leg_color := base.darkened(0.5)
	var inset := 0.14
	var leg := 0.09
	var xs: Array[float] = [-half.x + inset, half.x - inset - leg]
	var ys: Array[float] = [-half.y + inset, half.y - inset - leg]
	_draw_iso_box(Vector2(xs[0], ys[0]), Vector2(xs[0] + leg, ys[0] + leg), 0.0, under, leg_color)
	_draw_iso_box(Vector2(xs[0], ys[1]), Vector2(xs[0] + leg, ys[1] + leg), 0.0, under, leg_color)
	_draw_iso_box(Vector2(xs[1], ys[0]), Vector2(xs[1] + leg, ys[0] + leg), 0.0, under, leg_color)
	_draw_iso_box(Vector2(xs[1], ys[1]), Vector2(xs[1] + leg, ys[1] + leg), 0.0, under, leg_color)
	# Царга.
	_draw_iso_box(Vector2(-half.x + 0.2, -half.y + 0.2), Vector2(half.x - 0.2, half.y - 0.2), under - 7.0, under, base.darkened(0.3))
	# Столешница.
	_draw_iso_box(Vector2(-half.x, -half.y), Vector2(half.x, half.y), under, height, base)
	var top := Vector2(0, -height)
	# Доски вдоль длинной стороны.
	var seams := maxi(int(round(half.y * 2.0)) * 2, 2)
	var plank := base.darkened(0.22)
	plank.a = 0.55
	for i in range(1, seams):
		var y := -half.y + float(i) * (half.y * 2.0 / float(seams))
		draw_line(IsoProjection.grid_to_screen(Vector2(-half.x + 0.04, y)) + top, IsoProjection.grid_to_screen(Vector2(half.x - 0.04, y)) + top, plank, 1.0)
	# Светлая кромка столешницы.
	var rim := base.lightened(0.35)
	var n := IsoProjection.grid_to_screen(Vector2(-half.x, -half.y)) + top
	var e := IsoProjection.grid_to_screen(Vector2(half.x, -half.y)) + top
	var so := IsoProjection.grid_to_screen(Vector2(half.x, half.y)) + top
	var w := IsoProjection.grid_to_screen(Vector2(-half.x, half.y)) + top
	draw_polyline(PackedVector2Array([w, so, e]), rim, 1.5)
	draw_polyline(PackedVector2Array([n, w]), rim.darkened(0.15), 1.0)
	_draw_props(top)


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


## Параллелепипед по координатам клеток относительно центра объекта (min/max) и высотам z0..z1 (px).
func _draw_iso_box(min_c: Vector2, max_c: Vector2, z0: float, z1: float, color: Color) -> void:
	var north := IsoProjection.grid_to_screen(Vector2(min_c.x, min_c.y))
	var east := IsoProjection.grid_to_screen(Vector2(max_c.x, min_c.y))
	var south := IsoProjection.grid_to_screen(Vector2(max_c.x, max_c.y))
	var west := IsoProjection.grid_to_screen(Vector2(min_c.x, max_c.y))
	var low := Vector2(0, -z0)
	var high := Vector2(0, -z1)
	draw_colored_polygon(PackedVector2Array([west + low, south + low, south + high, west + high]), color.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([south + low, east + low, east + high, south + high]), color.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([north + high, east + high, south + high, west + high]), color.lightened(0.1))


## Дверь в стене x = 0: тёмный проём, косяк и полотно, которое поворачивается в комнату (петли со стороны -y).
func _draw_door() -> void:
	var height := float(_visual.get("height", 76.0))
	var base := Color.html(str(_visual.get("color", "#8a5a3c")))
	var half_width := 0.42
	var up := Vector2(0, -height)
	var hinge := Vector2(0.0, -half_width + 0.04)
	var length := half_width * 2.0 - 0.08
	# Проём: тёмная улица за дверью.
	var a := IsoProjection.grid_to_screen(Vector2(0.0, -half_width))
	var b := IsoProjection.grid_to_screen(Vector2(0.0, half_width))
	draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), Color("#14141b"))
	if _door_open > 0.05:
		# Полоска дневного света на полу у открытой двери.
		draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(18, 9), a + Vector2(18, 9)]), Color(1.0, 0.95, 0.75, 0.25 * _door_open))
	# Полотно.
	var angle := _door_open * 1.35
	var free := hinge + Vector2(length * sin(angle), length * cos(angle))
	var hinge_s := IsoProjection.grid_to_screen(hinge)
	var free_s := IsoProjection.grid_to_screen(free)
	var shade := 1.0 - 0.35 * _door_open
	var leaf := base.darkened(0.25 + 0.2 * _door_open)
	draw_colored_polygon(PackedVector2Array([hinge_s, free_s, free_s + up * 0.96, hinge_s + up * 0.96]), leaf)
	# Филёнки на полотне.
	var panel := base.darkened(0.45 + 0.1 * _door_open)
	for z_range: Vector2 in [Vector2(8.0, 34.0), Vector2(40.0, 66.0)]:
		var p0 := hinge_s.lerp(free_s, 0.14)
		var p1 := hinge_s.lerp(free_s, 0.86)
		draw_colored_polygon(PackedVector2Array([
			p0 + Vector2(0, -z_range.x), p1 + Vector2(0, -z_range.x), p1 + Vector2(0, -z_range.y), p0 + Vector2(0, -z_range.y)]), panel)
	# Ручка.
	draw_circle(hinge_s.lerp(free_s, 0.88) + Vector2(0, -38.0), 2.6, Color("#e3c25a").darkened(1.0 - shade))
	# Косяк и притолока.
	var frame := Color("#5b3c25")
	draw_line(a, a + up, frame, 4.0)
	draw_line(b, b + up, frame, 4.0)
	draw_line(a + up, b + up, frame, 5.0)
	draw_line(a + up + Vector2(0, 2), b + up + Vector2(0, 2), frame.lightened(0.2), 1.5)


## Стул: четыре ножки, сиденье и спинка со стороны -x (человек сидит лицом к +x, то есть к зрителю).
func _draw_chair() -> void:
	var color := Color.html(str(_visual.get("color", "#8a5a3c")))
	IsoDraw.draw_shadow(self, 20.0)
	var leg := 0.07
	for corner in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
		_chair_box(corner - Vector2(leg, leg), corner + Vector2(leg, leg), 0.0, 14.0, color.darkened(0.15))
	_chair_box(Vector2(-0.36, -0.36), Vector2(0.36, 0.36), 14.0, 20.0, color)
	_chair_box(Vector2(-0.38, -0.36), Vector2(-0.26, 0.36), 20.0, 48.0, color.lightened(0.05))


## Стул смотрит вдоль x (спинка со стороны -x) или вдоль y (visual.facing = "y": спинка со стороны -y).
func _chair_box(min_c: Vector2, max_c: Vector2, z0: float, z1: float, color: Color) -> void:
	if str(_visual.get("facing", "x")) == "y":
		_draw_iso_box(Vector2(min_c.y, min_c.x), Vector2(max_c.y, max_c.x), z0, z1, color)
	else:
		_draw_iso_box(min_c, max_c, z0, z1, color)
