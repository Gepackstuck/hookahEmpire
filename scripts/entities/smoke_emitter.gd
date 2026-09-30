class_name SmokeEmitter
extends Node2D
## Курение "затяжками": пока active == true, повторяет цикл пауза → затяжка (разной длительности) → выдох дымом.
## Положение эмиттера — "рот" персонажа. Сигналы затяжки нужны, чтобы сплющивать кальян и двигать руку.

signal inhale_started(duration: float)
signal inhale_ended

const STATE_IDLE := 0
const STATE_WAIT := 1
const STATE_INHALE := 2

var active: bool = false:
	set(value):
		if value == active:
			return
		active = value
		if value:
			_state = STATE_WAIT
			_timer = 0.15
		else:
			if _state == STATE_INHALE:
				inhale_ended.emit()
			_state = STATE_IDLE

var _state: int = STATE_IDLE
var _timer: float = 0.0


func _process(delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _state == STATE_WAIT:
		var duration := randf_range(0.7, 2.0)
		_state = STATE_INHALE
		_timer = duration
		inhale_started.emit(duration)
	elif _state == STATE_INHALE:
		_state = STATE_WAIT
		_timer = randf_range(1.0, 3.0)
		inhale_ended.emit()
		exhale(1 + int(randf_range(1.0, 2.5)))


## Одна короткая затяжка заданной длительности (корутина: завершается после выдоха).
func puff(duration: float) -> void:
	inhale_started.emit(duration)
	await get_tree().create_timer(duration).timeout
	inhale_ended.emit()
	exhale(2)


## Выдох: несколько клубов дыма.
func exhale(count: int) -> void:
	for i in count:
		var puff_node := SmokePuff.new()
		puff_node.drift_x = randf_range(-9.0, 9.0)
		puff_node.position = Vector2(randf_range(-2.0, 2.0), randf_range(-3.0, 0.0) - float(i) * 4.0)
		add_child(puff_node)
