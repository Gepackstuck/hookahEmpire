class_name PathWalker
extends RefCounted
## Ведёт точку по списку путевых точек (в клетках сетки) с постоянной скоростью.
## Не зависит от нод — им пользуются NPC (друзья, позже кальянщик).

var position: Vector2 = Vector2.ZERO
var speed: float = 2.5

var _points: Array[Vector2] = []
var _index := 0


func set_path(points: Array[Vector2], walk_speed: float) -> void:
	_points = points.duplicate()
	speed = walk_speed
	_index = 0


func is_walking() -> bool:
	return _index < _points.size()


## Двигает по пути. Возвращает true только на шаге, на котором путь закончился.
func step(delta: float) -> bool:
	if not is_walking():
		return false
	var remaining := speed * delta
	while remaining > 0.0 and _index < _points.size():
		var to_target := _points[_index] - position
		var distance := to_target.length()
		if distance <= remaining:
			position = _points[_index]
			remaining -= distance
			_index += 1
		else:
			position += to_target / distance * remaining
			remaining = 0.0
	return _index >= _points.size()
