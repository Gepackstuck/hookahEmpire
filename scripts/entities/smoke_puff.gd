class_name SmokePuff
extends Node2D
## Клуб дыма: мягкое облачко из нескольких пересекающихся "долей", которое расплывается вширь,
## дрейфует в случайную сторону, покачивается, бледнеет и само удаляется.

const LIFETIME := 1.8

## Размер и плотность клуба (растут с длиной затяжки): 1.0 — обычный.
var amount: float = 1.0
## Начальная скорость (px/с); задаёт эмиттер, если нужно, иначе берётся случайная.
var velocity: Vector2 = Vector2.ZERO
## Задержка появления, чтобы клубы из одного выдоха не вылетали одновременно.
var delay: float = 0.0

var _age: float = 0.0
var _lifetime: float = LIFETIME
var _sway_phase: float = 0.0
var _spin: float = 0.0
## Доли облачка: x, y — смещение в долях радиуса, z — относительный радиус.
var _lobes: Array[Vector3] = []
var _radius: float = 4.0


func _ready() -> void:
	_lifetime = LIFETIME * (0.8 + 0.25 * amount)
	_sway_phase = randf() * TAU
	_spin = randf_range(-0.4, 0.4)
	rotation = randf() * TAU
	if velocity == Vector2.ZERO:
		velocity = Vector2(randf_range(-18.0, 18.0), -randf_range(14.0, 30.0))
	for i in randi_range(4, 6):
		var angle := randf() * TAU
		var dist := randf_range(0.2, 0.85)
		_lobes.append(Vector3(cos(angle) * dist, sin(angle) * dist * 0.8, randf_range(0.45, 0.8)))
	visible = delay <= 0.0


func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		if delay > 0.0:
			return
		visible = true
	_age += delta
	var t := _age / _lifetime
	if t >= 1.0:
		queue_free()
		return
	# Скорость затухает, плюс лёгкое покачивание из стороны в сторону.
	velocity *= maxf(0.0, 1.0 - 1.05 * delta)
	var sway := sin(_age * 2.2 + _sway_phase) * 5.0 * (0.4 + t)
	position += (velocity + Vector2(sway, -8.0)) * delta
	rotation += _spin * delta
	_radius = (3.5 + 10.0 * sqrt(t)) * (0.75 + 0.3 * amount)
	modulate.a = 1.0 - t * t
	queue_redraw()


func _draw() -> void:
	var base_alpha := clampf(0.16 + 0.05 * amount, 0.0, 0.4)
	for lobe in _lobes:
		draw_circle(Vector2(lobe.x, lobe.y) * _radius, lobe.z * _radius, Color(0.88, 0.88, 0.94, base_alpha))
	# Светлая сердцевина даёт объём.
	draw_circle(Vector2(-_radius * 0.15, -_radius * 0.15), _radius * 0.45, Color(1, 1, 1, base_alpha * 0.8))
