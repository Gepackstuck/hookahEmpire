class_name IsoProjection
extends RefCounted
## Изометрическая проекция логической сетки гаража на экран.
##
## Логика игры живёт в координатах сетки (клетки, float). Ось X сетки идёт на экране
## вправо-вниз, ось Y — влево-вниз. Клетка (0,0) — верхний угол комнаты.

const CELL_W := 64.0
const CELL_H := 32.0


static func grid_to_screen(grid_pos: Vector2) -> Vector2:
	return Vector2(
		(grid_pos.x - grid_pos.y) * CELL_W * 0.5,
		(grid_pos.x + grid_pos.y) * CELL_H * 0.5
	)


static func screen_to_grid(screen_pos: Vector2) -> Vector2:
	var diff := screen_pos.x / (CELL_W * 0.5) # gx - gy
	var sum := screen_pos.y / (CELL_H * 0.5) # gx + gy
	return Vector2((sum + diff) * 0.5, (sum - diff) * 0.5)


## Экранное направление ввода (вверх = (0,-1)) -> единичное направление в сетке.
## Все 8 направлений двигают игрока с одной и той же скоростью в клетках/сек.
static func screen_dir_to_grid_dir(screen_dir: Vector2) -> Vector2:
	if screen_dir == Vector2.ZERO:
		return Vector2.ZERO
	return Vector2(screen_dir.x + screen_dir.y, screen_dir.y - screen_dir.x).normalized()
