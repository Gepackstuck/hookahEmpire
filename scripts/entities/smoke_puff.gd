class_name SmokePuff
extends Node2D
## Один клуб дыма: поднимается, растёт, бледнеет и сам удаляется.

const LIFETIME := 1.6
const RISE_SPEED := 22.0

var drift_x: float = 0.0

var _age: float = 0.0
var _radius: float = 4.0


func _process(delta: float) -> void:
	_age += delta
	var t := _age / LIFETIME
	if t >= 1.0:
		queue_free()
		return
	position += Vector2(drift_x, -RISE_SPEED) * delta
	_radius = 4.0 + 7.0 * t
	modulate.a = 1.0 - t
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius, Color(0.88, 0.88, 0.94, 0.6))
	draw_circle(Vector2(-_radius * 0.3, -_radius * 0.2), _radius * 0.6, Color(1, 1, 1, 0.35))
