class_name SmokeEmitter
extends Node2D
## Курение "затяжками": пока active == true, повторяет цикл пауза → затяжка (разной длительности) → выдох дымом.
## Положение эмиттера — "рот" персонажа. Сигналы затяжки нужны, чтобы сплющивать кальян и двигать руку.

signal inhale_started(duration: float)
signal inhale_ended

const STATE_IDLE := 0
const STATE_WAIT := 1
const STATE_INHALE := 2
## Минимальная пауза между затяжками двух людей у одного кальяна.
const GAP_SECONDS := 0.8
## Длительность затяжки: от 1.3 до 2.35 с.
const MIN_PUFF_SECONDS := 1.3
const MAX_PUFF_SECONDS := 2.35

var active: bool = false:
	set(value):
		if value == active:
			return
		active = value
		if value:
			_state = STATE_WAIT
			_timer = 0.15
		else:
			_burst_left = 0
			if _state == STATE_INHALE:
				_end_inhale()
			_state = STATE_IDLE

## Второй курильщик за тем же кальяном: пока он тянет (и короткое время после), этот ждёт своей очереди.
var partner: SmokeEmitter = null
## Идёт ли сейчас затяжка.
var inhaling: bool = false
var last_inhale_end: float = -100.0

## Сколько серий затяжек (1–3 подряд) сделано; нужно для очерёдности.
var bursts_done: int = 0

var _burst_left: int = 0
var _last_duration: float = 1.0
var _partner_bursts_seen: int = -1
var _state: int = STATE_IDLE
var _timer: float = 0.0


func _process(delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _state == STATE_WAIT:
		if partner_busy() or (_burst_left <= 0 and not _my_turn()):
			_timer = 0.15
			return
		if _burst_left <= 0:
			_burst_left = randi_range(1, 3)
		_burst_left -= 1
		var duration := randf_range(MIN_PUFF_SECONDS, MAX_PUFF_SECONDS)
		_state = STATE_INHALE
		_timer = duration
		_last_duration = duration
		_begin_inhale(duration)
	elif _state == STATE_INHALE:
		_state = STATE_WAIT
		if _burst_left > 0:
			_timer = randf_range(0.3, 0.7)
		else:
			_timer = randf_range(1.0, 3.0)
			bursts_done += 1
			_partner_bursts_seen = partner.bursts_done if partner != null and is_instance_valid(partner) else 0
		_end_inhale()
		exhale_for(_last_duration)


## Партнёр тянет кальян сейчас или только что закончил (пауза между затяжками разных людей).
func partner_busy() -> bool:
	if partner == null or not is_instance_valid(partner):
		return false
	return partner.inhaling or partner._burst_left > 0 or _now() - partner.last_inhale_end < GAP_SECONDS


## Очередь: новую серию можно начать, если партнёр не курит или уже успел сделать свою серию после моей.
func _my_turn() -> bool:
	if partner == null or not is_instance_valid(partner) or not partner.active:
		return true
	return partner.bursts_done != _partner_bursts_seen


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _begin_inhale(duration: float) -> void:
	inhaling = true
	inhale_started.emit(duration)


func _end_inhale() -> void:
	inhaling = false
	last_inhale_end = _now()
	inhale_ended.emit()


## Одна короткая затяжка заданной длительности (корутина: завершается после выдоха).
func puff(duration: float) -> void:
	_begin_inhale(duration)
	await get_tree().create_timer(duration).timeout
	_end_inhale()
	exhale_for(duration)


## Выдох после затяжки: чем дольше затяжка, тем больше и гуще дым (0.7 с — несколько клубов, 2.35 с — плотное облако).
func exhale_for(duration: float) -> void:
	var amount := clampf(duration / 1.0, 0.7, 2.6)
	exhale(int(round(1.6 + amount * amount * 1.3)), amount)


## Выдох: несколько клубов дыма.
func exhale(count: int, amount: float = 1.0) -> void:
	for i in count:
		var puff_node := SmokePuff.new()
		puff_node.amount = amount
		# Клубы вылетают вразнобой: разная задержка, направление и скорость, а не столбиком.
		puff_node.delay = randf_range(0.0, 0.07 * float(count))
		puff_node.velocity = Vector2(randf_range(-20.0, 20.0) * sqrt(amount), -randf_range(18.0, 36.0))
		puff_node.position = Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 1.0))
		add_child(puff_node)
