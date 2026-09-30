class_name CharacterFigure
extends Node2D
## Векторный человечек (вид сбоку, смотрит вправо; влево — отражением): идёт, стоит, сидит, делает затяжку.
## Рисуется кодом в стиле остальной графики: капсулы-конечности, плоские цвета, тёмная "дальняя" сторона.

const BODY_SCALE := 0.9
const WALK_FREQUENCY := 11.0

const POSE_STAND := "stand"
const POSE_SIT := "sit"

var skin := Color("#f1c27d")
var hair := Color("#4a3020")
var shirt := Color("#e8833a")
var pants := Color("#33405f")
var shoes := Color("#f2f2f2")
## Пиджак поверх рубашки (прозрачный цвет — без пиджака).
var jacket := Color(0, 0, 0, 0)
var tie := Color(0, 0, 0, 0)
## В покое поднять руку вверх (танцор).
var idle_dance := false

var pose: String = POSE_STAND
var moving: bool = false
var puffing: bool = false
var facing_right: bool = true

var _phase: float = 0.0
var _time: float = 0.0
var _hand_t: float = 0.0


## Готовые образы: "denis" и "player".
static func make(style: String) -> CharacterFigure:
	var figure := CharacterFigure.new()
	match style:
		"player":
			figure.skin = Color("#f3c98b")
			figure.hair = Color("#1f1a1a")
			figure.shirt = Color("#f4f4f4")
			figure.jacket = Color("#26262f")
			figure.tie = Color("#d6403f")
			figure.pants = Color("#1e1e26")
			figure.shoes = Color("#e9e9e9")
		_:
			figure.skin = Color("#f1c27d")
			figure.hair = Color("#5a3a22")
			figure.shirt = Color("#e8833a")
			figure.pants = Color("#33405f")
			figure.shoes = Color("#f2f2f2")
	figure.set_facing(true)
	return figure


func set_facing(right: bool) -> void:
	facing_right = right
	scale = Vector2(BODY_SCALE if right else -BODY_SCALE, BODY_SCALE)


## Рот в координатах родителя (для дыма).
func mouth_position() -> Vector2:
	var local := _mouth_local()
	return position + Vector2(local.x * scale.x, local.y * scale.y)


func _process(delta: float) -> void:
	_time += delta
	if moving and pose == POSE_STAND:
		_phase += delta * WALK_FREQUENCY
	_hand_t = move_toward(_hand_t, 1.0 if puffing else 0.0, delta * 6.0)
	queue_redraw()


func _bob() -> float:
	if pose == POSE_STAND and moving:
		return -absf(sin(_phase)) * 1.6
	return sin(_time * 2.5) * 0.5


func _head_local() -> Vector2:
	if pose == POSE_SIT:
		return Vector2(-2.0, -57.0 + _bob())
	return Vector2(1.0, -52.0 + _bob())


func _mouth_local() -> Vector2:
	return _head_local() + Vector2(7.0, 4.5)


func _limb(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(a, b, color, width, true)
	draw_circle(a, width * 0.5, color)
	draw_circle(b, width * 0.5, color)


func _shoe(foot: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(-3.5, -4.0), foot + Vector2(3.0, -4.0), foot + Vector2(7.5, -1.5),
		foot + Vector2(7.5, 1.0), foot + Vector2(-3.5, 1.0)]), shoes)
	draw_line(foot + Vector2(-3.5, 0.0), foot + Vector2(7.5, 0.0), shoes.darkened(0.45), 1.5)


func _draw() -> void:
	if pose == POSE_SIT:
		_draw_seated()
	else:
		_draw_standing()


func _draw_standing() -> void:
	var bob: float = _bob()
	var hip := Vector2(0.0, -23.0 + bob)
	var shoulder := Vector2(1.0, -43.0 + bob)
	# Ноги: дальняя первой, темнее.
	for near: bool in [false, true]:
		var phase: float = _phase if near else _phase + PI
		var foot := Vector2(1.5 if near else -2.5, 0.0)
		var knee_push: float = 0.0
		if moving:
			foot = Vector2(sin(phase) * 7.5, -maxf(0.0, cos(phase)) * 4.0)
			knee_push = 2.5
		var knee: Vector2 = (hip + foot) * 0.5 + Vector2(knee_push, 0.0)
		var tone: Color = pants if near else pants.darkened(0.3)
		_limb(hip, knee, 7.5, tone)
		_limb(knee, foot + Vector2(0, -2.0), 6.5, tone)
		_shoe(foot)
	_arm(shoulder + Vector2(-2.0, 3.0), false)
	# Торс.
	var torso: Color = jacket if jacket.a > 0.0 else shirt
	_limb(hip, shoulder + Vector2(0, 2.0), 13.5, torso.darkened(0.12))
	_limb(hip + Vector2(1.5, 0), shoulder + Vector2(1.5, 2.0), 10.0, torso)
	draw_line(hip + Vector2(-6.5, -1.0), hip + Vector2(6.5, -1.0), pants.darkened(0.35), 2.0)
	if jacket.a > 0.0:
		draw_colored_polygon(PackedVector2Array([
			shoulder + Vector2(3.0, 2.0), shoulder + Vector2(7.0, 4.0),
			hip + Vector2(5.0, -6.0), hip + Vector2(3.0, -6.0)]), shirt)
		draw_line(shoulder + Vector2(5.0, 4.0), hip + Vector2(4.0, -8.0), tie, 2.2)
	var head: Vector2 = _head_local()
	_limb(shoulder + Vector2(0, 1.0), head + Vector2(0, 5.0), 5.0, skin.darkened(0.08))
	_draw_head(head)
	_arm(shoulder + Vector2(2.5, 3.0), true)


## Рука: качается при ходьбе, идёт ко рту при затяжке, у танцора в покое поднята.
func _arm(shoulder: Vector2, near: bool) -> void:
	var sleeve: Color = jacket if jacket.a > 0.0 else shirt
	var tone: Color = sleeve if near else sleeve.darkened(0.3)
	var swing: float = 0.0
	if moving:
		swing = sin(_phase + (PI if near else 0.0)) * 6.5
	var hand: Vector2 = shoulder + Vector2(swing, 16.0 - absf(swing) * 0.25)
	var elbow: Vector2 = shoulder + Vector2(swing * 0.5, 8.5)
	if near:
		if idle_dance and not moving:
			var wave: float = sin(_time * 4.0)
			hand = shoulder + Vector2(8.0 + wave * 1.5, -15.0)
			elbow = shoulder + Vector2(6.0, -5.0)
		if _hand_t > 0.0:
			var mouth: Vector2 = _mouth_local() + Vector2(-2.0, 2.5)
			hand = hand.lerp(mouth, _hand_t)
			elbow = elbow.lerp(shoulder + Vector2(7.0, 6.0), _hand_t)
	_limb(shoulder, elbow, 5.2, tone)
	_limb(elbow, hand, 4.8, tone)
	draw_circle(hand, 2.8, skin if near else skin.darkened(0.2))


func _draw_head(head: Vector2) -> void:
	draw_circle(head + Vector2(-0.8, -1.5), 8.9, hair)
	draw_circle(head + Vector2(-2.6, 0.5), 2.2, skin.darkened(0.12))
	draw_circle(head + Vector2(2.2, 1.6), 7.0, skin)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-3.0, -8.8), head + Vector2(6.0, -7.0), head + Vector2(9.0, -2.6),
		head + Vector2(4.5, -4.6), head + Vector2(0.5, -3.6)]), hair.lightened(0.05))
	draw_circle(head + Vector2(5.6, -0.6), 1.3, Color("#1b1b1b"))
	draw_line(head + Vector2(4.2, -3.0), head + Vector2(7.2, -3.3), hair.darkened(0.3), 1.2)
	draw_circle(head + Vector2(9.0, 1.4), 1.3, skin.darkened(0.06))
	draw_line(head + Vector2(6.0, 4.6), head + Vector2(8.0, 4.4), Color("#8a4b3a"), 1.2)


func _draw_seated() -> void:
	var bob: float = _bob()
	var hip := Vector2(-3.0, -24.0)
	var shoulder := Vector2(-3.0, -46.0 + bob)
	var knee: Vector2 = hip + Vector2(17.0, 8.5)
	var foot: Vector2 = knee + Vector2(3.0, 15.0)
	var far_offset := Vector2(-2.6, 1.3)
	_limb(hip + far_offset, knee + far_offset, 7.5, pants.darkened(0.3))
	_limb(knee + far_offset, foot + far_offset, 6.5, pants.darkened(0.3))
	_shoe(foot + far_offset)
	_seated_arm(shoulder + Vector2(-2.0, 3.0), knee + far_offset + Vector2(-3, -4), false)
	var torso: Color = jacket if jacket.a > 0.0 else shirt
	_limb(hip, shoulder + Vector2(0, 2.0), 13.5, torso.darkened(0.12))
	_limb(hip + Vector2(1.5, 0), shoulder + Vector2(1.5, 2.0), 10.0, torso)
	_limb(hip, knee, 7.5, pants)
	_limb(knee, foot, 6.5, pants)
	_shoe(foot)
	var head: Vector2 = _head_local()
	_limb(shoulder + Vector2(0, 1.0), head + Vector2(0, 5.0), 5.0, skin.darkened(0.08))
	_draw_head(head)
	_seated_arm(shoulder + Vector2(2.5, 3.0), knee + Vector2(-3, -4), true)


func _seated_arm(shoulder: Vector2, rest: Vector2, near: bool) -> void:
	var sleeve: Color = jacket if jacket.a > 0.0 else shirt
	var tone: Color = sleeve if near else sleeve.darkened(0.3)
	var elbow: Vector2 = shoulder.lerp(rest, 0.5) + Vector2(-3.0, 3.0)
	var hand: Vector2 = rest
	if near and _hand_t > 0.0:
		hand = hand.lerp(_mouth_local() + Vector2(-2.0, 2.5), _hand_t)
		elbow = elbow.lerp(shoulder + Vector2(7.0, 6.0), _hand_t)
	_limb(shoulder, elbow, 5.2, tone)
	_limb(elbow, hand, 4.8, tone)
	draw_circle(hand, 2.8, skin if near else skin.darkened(0.2))
