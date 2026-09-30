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
