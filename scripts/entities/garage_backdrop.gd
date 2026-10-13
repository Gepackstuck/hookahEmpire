class_name GarageBackdrop
extends Node2D
## Заглушка пола и двух задних стен гаража (рисуется кодом, без арта).

const WALL_HEIGHT := 110.0
const BASEBOARD_HEIGHT := 14.0
const FLOOR_COLORS := [Color(0.56, 0.52, 0.47), Color(0.51, 0.47, 0.43)]
const WALL_LEFT_COLOR := Color(0.72, 0.74, 0.76)
const WALL_RIGHT_COLOR := Color(0.63, 0.65, 0.68)
const BASEBOARD_COLOR := Color(0.36, 0.34, 0.33)
const OUTLINE_COLOR := Color(0.2, 0.18, 0.17)

var _size := Vector2i(1, 1)


func setup(grid_size: Vector2i) -> void:
	_size = grid_size
	queue_redraw()


## Границы комнаты в экранных координатах мира (для лимитов камеры).
static func screen_bounds(grid_size: Vector2i, margin: float = 24.0) -> Rect2i:
	var left := -float(grid_size.y) * IsoProjection.CELL_W * 0.5 - margin
	var right := float(grid_size.x) * IsoProjection.CELL_W * 0.5 + margin
	var top := -WALL_HEIGHT - margin
	var bottom := float(grid_size.x + grid_size.y) * IsoProjection.CELL_H * 0.5 + margin
	return Rect2i(Vector2i(floori(left), floori(top)), Vector2i(ceili(right - left), ceili(bottom - top)))


func _draw() -> void:
	if VisualStyle.modern:
		_draw_modern()
		return
	var up := Vector2(0, -WALL_HEIGHT)
	var base_up := Vector2(0, -BASEBOARD_HEIGHT)
	var origin := IsoProjection.grid_to_screen(Vector2.ZERO)
	var left_end := IsoProjection.grid_to_screen(Vector2(0, _size.y))
	var right_end := IsoProjection.grid_to_screen(Vector2(_size.x, 0))

	# Левая стена (вдоль оси Y сетки) и правая (вдоль оси X).
	draw_colored_polygon(PackedVector2Array([origin, left_end, left_end + up, origin + up]), WALL_LEFT_COLOR)
	draw_colored_polygon(PackedVector2Array([origin, right_end, right_end + up, origin + up]), WALL_RIGHT_COLOR)
	draw_colored_polygon(PackedVector2Array([origin, left_end, left_end + base_up, origin + base_up]), BASEBOARD_COLOR)
	draw_colored_polygon(PackedVector2Array([origin, right_end, right_end + base_up, origin + base_up]), BASEBOARD_COLOR)
	draw_polyline(PackedVector2Array([left_end + up, origin + up, right_end + up]), OUTLINE_COLOR, 2.0)
	draw_line(origin, origin + up, OUTLINE_COLOR, 2.0)

	# Пол в шахматку.
	for x in _size.x:
		for y in _size.y:
			var corners := PackedVector2Array([
				IsoProjection.grid_to_screen(Vector2(x, y)),
				IsoProjection.grid_to_screen(Vector2(x + 1, y)),
				IsoProjection.grid_to_screen(Vector2(x + 1, y + 1)),
				IsoProjection.grid_to_screen(Vector2(x, y + 1)),
			])
			draw_colored_polygon(corners, FLOOR_COLORS[(x + y) % 2])
	draw_polyline(PackedVector2Array([left_end, IsoProjection.grid_to_screen(Vector2(_size)), right_end]), OUTLINE_COLOR, 2.0)


# --- Новый вид: тёплый деревянный пол, стены с панелью, мягкий свет ---

const M_WALL_LEFT := Color("#6f4a55")
const M_WALL_RIGHT := Color("#7d5560")
const M_PANEL_LEFT := Color("#4d3138")
const M_PANEL_RIGHT := Color("#5a3a41")
const M_PANEL_HEIGHT := 40.0
const M_TRIM := Color("#d9b27a")
const M_FLOOR_A := Color("#a8693a")
const M_FLOOR_B := Color("#9a5d33")
const M_OUTLINE := Color("#2a1a1f")


func _draw_modern() -> void:
	var up := Vector2(0, -WALL_HEIGHT)
	var panel_up := Vector2(0, -M_PANEL_HEIGHT)
	var origin := IsoProjection.grid_to_screen(Vector2.ZERO)
	var left_end := IsoProjection.grid_to_screen(Vector2(0, _size.y))
	var right_end := IsoProjection.grid_to_screen(Vector2(_size.x, 0))
	# Стены: светлый верх, тёмная панель снизу, золотистый молдинг между ними.
	draw_colored_polygon(PackedVector2Array([origin, left_end, left_end + up, origin + up]), M_WALL_LEFT)
	draw_colored_polygon(PackedVector2Array([origin, right_end, right_end + up, origin + up]), M_WALL_RIGHT)
	draw_colored_polygon(PackedVector2Array([origin, left_end, left_end + panel_up, origin + panel_up]), M_PANEL_LEFT)
	draw_colored_polygon(PackedVector2Array([origin, right_end, right_end + panel_up, origin + panel_up]), M_PANEL_RIGHT)
	draw_line(left_end + panel_up, origin + panel_up, M_TRIM, 3.0)
	draw_line(origin + panel_up, right_end + panel_up, M_TRIM, 3.0)
	# Вертикальные стыки панелей.
	for index in range(1, _size.y):
		var at := IsoProjection.grid_to_screen(Vector2(0, index))
		draw_line(at, at + panel_up, M_PANEL_LEFT.darkened(0.25), 1.2)
	for index in range(1, _size.x):
		var at := IsoProjection.grid_to_screen(Vector2(index, 0))
		draw_line(at, at + panel_up, M_PANEL_RIGHT.darkened(0.25), 1.2)
	draw_polyline(PackedVector2Array([left_end + up, origin + up, right_end + up]), M_OUTLINE, 3.0)
	draw_line(origin, origin + up, M_OUTLINE, 3.0)
	# Пол: тёплые доски, чередование тона по клеткам и тонкие стыки.
	for x in _size.x:
		for y in _size.y:
			var a := IsoProjection.grid_to_screen(Vector2(x, y))
			var b := IsoProjection.grid_to_screen(Vector2(x + 1, y))
			var c := IsoProjection.grid_to_screen(Vector2(x + 1, y + 1))
			var d := IsoProjection.grid_to_screen(Vector2(x, y + 1))
			var tone := M_FLOOR_A if (x + y) % 2 == 0 else M_FLOOR_B
			var jitter := float((x * 7 + y * 13) % 5) * 0.012
			draw_colored_polygon(PackedVector2Array([a, b, c, d]), tone.lightened(jitter))
			draw_line(a.lerp(d, 0.5), b.lerp(c, 0.5), tone.darkened(0.14), 1.0)
	# Мягкая тень у стен (имитация скользящего света): полосы убывающей прозрачности вдоль обеих стен.
	for step in 5:
		var near := float(step) * 0.45
		var far := near + 0.45
		var alpha := 0.20 - 0.04 * float(step)
		var shade := Color(0.08, 0.03, 0.02, alpha)
		# Вдоль левой стены (x = 0) и вдоль правой (y = 0).
		draw_colored_polygon(PackedVector2Array([
			IsoProjection.grid_to_screen(Vector2(near, 0)), IsoProjection.grid_to_screen(Vector2(near, _size.y)),
			IsoProjection.grid_to_screen(Vector2(far, _size.y)), IsoProjection.grid_to_screen(Vector2(far, 0))]), shade)
		draw_colored_polygon(PackedVector2Array([
			IsoProjection.grid_to_screen(Vector2(0, near)), IsoProjection.grid_to_screen(Vector2(_size.x, near)),
			IsoProjection.grid_to_screen(Vector2(_size.x, far)), IsoProjection.grid_to_screen(Vector2(0, far))]), shade)
	# Тёплые пятна света от ламп: мягкие эллипсы в центре комнаты.
	var center := IsoProjection.grid_to_screen(Vector2(_size) * 0.5)
	for ring in 6:
		var k := float(ring) / 5.0
		draw_set_transform(center, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 40.0 + (1.0 - k) * 150.0, Color(1.0, 0.85, 0.5, 0.025 + 0.012 * k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_polyline(PackedVector2Array([left_end, IsoProjection.grid_to_screen(Vector2(_size)), right_end]), M_OUTLINE, 3.0)
