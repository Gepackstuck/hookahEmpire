class_name GarageLighting
extends Node2D
## Новый вид: приглушённый общий свет и источники — неон с отражением на полу, лампы над столами, торшеры.
## Два слоя: затемнение (обычное смешивание) и свечение (аддитивное смешивание поверх).

const DIM_COLOR := Color(0.07, 0.03, 0.11, 0.15)
## Общая сила пятен света на полу: чуть ниже — не пересвечено, но живое (подбирается на глаз).
const FLOOR_LIGHT_K := 0.72
const FLOOR_REFLECTION_CELLS := 5.0
const REFLECTION_ROWS := 6

var _bounds := Rect2(-1200, -400, 2800, 1400)
var _size := Vector2i(16, 16)
## Свет на полу и стенах лежит под предметами и персонажами (между фоном и Entities); ореолы ламп — поверх.
var _floor: Node2D
var _glow: Node2D
var _time := 0.0
var _disc_texture: GradientTexture2D
var _cache: Array = []
var _skip := false


func _additive() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material


## Готовая радиальная текстура мягкого пятна: яркость плавно падает от центра к краю. Каждое пятно — один вызов отрисовки.
func _make_disc() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture


func setup(grid_size: Vector2i) -> void:
	_size = grid_size
	var rect := GarageBackdrop.screen_bounds(grid_size, 200.0)
	_bounds = Rect2(rect)
	z_index = 1
	_disc_texture = _make_disc()
	_glow = Node2D.new()
	_glow.material = _additive()
	_glow.draw.connect(_draw_halos)
	add_child(_glow)
	_floor = Node2D.new()
	_floor.name = "FloorLight"
	_floor.material = _additive()
	_floor.draw.connect(_draw_floor)
	var world := get_parent()
	world.add_child(_floor)
	var backdrop := world.get_node_or_null("Backdrop")
	world.move_child(_floor, (backdrop.get_index() + 1) if backdrop != null else 0)
	visible = VisualStyle.modern
	_floor.visible = visible
	queue_redraw()


func _process(delta: float) -> void:
	var was_visible := visible
	visible = VisualStyle.modern
	if _floor != null:
		_floor.visible = visible
	if not visible:
		return
	if not was_visible:
		queue_redraw()
	_time += delta
	# Освещение обновляем через кадр: глаз разницы не видит, а сборка источников и перерисовка дорогие.
	_skip = not _skip
	if _skip:
		return
	# Источники собираем один раз за кадр (а не отдельно для каждого слоя).
	_cache = _sources()
	_glow.queue_redraw()
	_floor.queue_redraw()


## Затемнение: рисуется один раз, а не каждый кадр.
func _draw() -> void:
	draw_rect(_bounds, DIM_COLOR)


func _sources() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("garage_objects"):
		if node is GarageObject:
			result.append_array((node as GarageObject).light_sources())
	return result


## Мягкое пятно света одним вызовом: radius — по горизонтали, flatten — сплющивание (0.5 — круг на полу в изометрии).
func _disc(canvas: Node2D, center: Vector2, radius: float, color: Color, flatten: float = 0.5) -> void:
	var shown := color
	if canvas == _floor:
		shown.a *= FLOOR_LIGHT_K
	canvas.draw_texture_rect(_disc_texture, Rect2(center - Vector2(radius, radius * flatten), Vector2(radius * 2.0, radius * 2.0 * flatten)), false, shown)


## Свет на полу и стенах (под предметами и людьми): пятна ламп и столов, цветные потолочные пятна, неон.
func _draw_floor() -> void:
	for spot: Array in [[0.28, 0.32, Color(1.0, 0.62, 0.3)], [0.72, 0.7, Color(0.95, 0.4, 0.7)], [0.3, 0.78, Color(0.3, 0.75, 0.85)]]:
		var at := IsoProjection.grid_to_screen(Vector2(_size) * Vector2(float(spot[0]), float(spot[1])))
		var tint: Color = spot[2]
		_disc(_floor, at, 190.0, Color(tint.r, tint.g, tint.b, 0.16))
	for source: Dictionary in _cache:
		match str(source["kind"]):
			"lamp":
				var lamp_tint: Color = source["color"]
				_disc(_floor, source["pos"] + Vector2(0, 2), 190.0, Color(lamp_tint.r, lamp_tint.g, lamp_tint.b, 0.4))
			"table":
				var warm: Color = source["color"]
				_disc(_floor, source["pos"] + Vector2(0, 8), 170.0, Color(warm.r, warm.g, warm.b, 0.34))
			"shelf":
				var shelf_tint: Color = source["color"]
				_disc(_floor, source["pos"], 120.0, Color(shelf_tint.r, shelf_tint.g, shelf_tint.b, 0.16))
			"hookah":
				var glow_k: float = float(source["coal"]) * (0.5 + float(source["puff"]))
				_disc(_floor, source["pos"] + Vector2(0, 52), 60.0, Color(1.0, 0.6, 0.3, 0.14 * glow_k))
			"window":
				var win_r: float = float(source["radius"])
				var win_pos: Vector2 = source["pos"]
				for k in 3:
					var d := float(k)
					_disc(_floor, win_pos + Vector2(60.0, 30.0) * (1.0 + d * 1.3), win_r * (1.0 + 0.35 * d), Color(0.5, 0.62, 1.0, 0.24 - 0.05 * d))
			"neon":
				_draw_neon(source)


## Ореолы в воздухе (поверх предметов): лампочки над столами, абажур торшера, уголь кальяна.
func _draw_halos() -> void:
	for source: Dictionary in _cache:
		match str(source["kind"]):
			"lamp":
				var lamp_tint: Color = source["color"]
				_disc(_glow, source["pos"] + Vector2(0, -74), 34.0, Color(lamp_tint.r, lamp_tint.g, lamp_tint.b, 0.22), 1.0)
			"hookah":
				var puff: float = float(source["puff"])
				var coal: float = float(source["coal"])
				# Только уголь: всегда умеренно светится, при затяжке вспыхивает ярче.
				_disc(_glow, source["pos"] + Vector2(0, -6), 18.0 + 8.0 * puff, Color(1.0, 0.5, 0.18, (0.28 + 0.4 * puff) * coal), 1.0)


## Неон: свечение на стене вокруг вывески и широкое размытое отражение на полу перед ней.
## Отражение — мягкие пятна без линий и многоугольников (они давали полосы).
func _draw_neon(source: Dictionary) -> void:
	var intensity: float = float(source["intensity"])
	var corners: PackedVector2Array = source["corners"]
	var color_a: Color = source["color_a"]
	var color_b: Color = source["color_b"]
	var mix := color_a.lerp(color_b, 0.5)
	var center := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
	for scale_factor in [1.08, 1.22, 1.42]:
		var poly := PackedVector2Array()
		for corner in corners:
			poly.append(center + (corner - center) * scale_factor)
		_floor.draw_colored_polygon(poly, Color(mix.r, mix.g, mix.b, 0.06 * intensity))
	var base: Vector2 = source["base"]
	var along: Vector2 = source["along"]
	var inward: Vector2 = source["inward"]
	var width: float = float(source["width"])
	var wobble := 0.92 + 0.08 * sin(_time * 2.0)
	# Отражение на полу — только мягкие пятна (без многоугольников и линий, чтобы не было полос).
	for row in 2:
		var depth := 0.8 + 2.0 * float(row)
		var fade := 1.0 - 0.3 * float(row)
		for k in 4:
			var s := (float(k) + 0.5) / 4.0
			var tint := color_a.lerp(color_b, s)
			var at: Vector2 = base + along * width * s + inward * depth
			_disc(_floor, at, 170.0 + 50.0 * float(row), Color(tint.r, tint.g, tint.b, 0.2 * fade * intensity * wobble))
	_disc(_floor, center, 170.0, Color(mix.r, mix.g, mix.b, 0.1 * intensity), 0.9)


func _reflection_alpha(t: float) -> float:
	return 0.55 * pow(1.0 - t, 1.8)


static func fract_hash(value: int) -> float:
	return fposmod(sin(float(value) * 12.9898) * 43758.5453, 1.0)
