class_name GarageGrid
extends RefCounted
## Логическая сетка гаража: проходимость клеток, столкновения и поиск пути.
##
## Ничего не знает о нодах и графике. Игрок двигается свободно (float-координаты
## в клетках), а NPC позже смогут ходить по тем же данным через find_path().

var size: Vector2i

var _blocked: Dictionary = {} # Vector2i -> true
var _astar: AStarGrid2D = null
var _astar_dirty := true


func _init(grid_size: Vector2i) -> void:
	size = grid_size


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func set_blocked_rect(rect: Rect2i, blocked: bool) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var cell := Vector2i(x, y)
			if blocked:
				_blocked[cell] = true
			else:
				_blocked.erase(cell)
	_astar_dirty = true


func is_cell_walkable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not _blocked.has(cell)


## Можно ли встать квадратным "телом" с центром pos и половиной стороны half_extent.
func can_stand(pos: Vector2, half_extent: float) -> bool:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cell := Vector2i(floori(pos.x + sx * half_extent), floori(pos.y + sy * half_extent))
			if not is_cell_walkable(cell):
				return false
	return true


## Двигает тело на delta с раздельной проверкой осей (скольжение вдоль стен).
func resolve_move(pos: Vector2, delta: Vector2, half_extent: float) -> Vector2:
	var result := pos
	var try_x := Vector2(result.x + delta.x, result.y)
	if can_stand(try_x, half_extent):
		result = try_x
	var try_y := Vector2(result.x, result.y + delta.y)
	if can_stand(try_y, half_extent):
		result = try_y
	return result


## Путь между клетками (центры клеток). Пустой массив, если пути нет.
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not is_cell_walkable(from_cell) or not is_cell_walkable(to_cell):
		return result
	_ensure_astar()
	for cell in _astar.get_id_path(from_cell, to_cell):
		result.append(Vector2(cell) + Vector2(0.5, 0.5))
	return result


func _ensure_astar() -> void:
	if _astar != null and not _astar_dirty:
		return
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for cell in _blocked.keys():
		_astar.set_point_solid(cell, true)
	_astar_dirty = false
