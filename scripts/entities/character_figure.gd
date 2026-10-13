class_name CharacterFigure
extends Node2D
## Векторный человечек (вид сбоку, смотрит вправо; влево — отражением): идёт, стоит, сидит, делает затяжку.
## Рисуется кодом в стиле остальной графики: капсулы-конечности, плоские цвета, тёмная "дальняя" сторона.

const BODY_SCALE := 0.9
const WALK_FREQUENCY := 11.0
## На сколько (в локальных единицах фигурки) от рта вперёд берётся рука, когда тянет шланг: ручка с мундштуком между рукой и ртом.
const GRIP_REACH := 11.3
## И на сколько ниже рта берётся хват (рука не поднимается к лицу, мундштук идёт ко рту снизу).
const GRIP_DROP := 5.3

const POSE_STAND := "stand"
const POSE_SIT := "sit"

## Ракурс: сбоку (смотрит вправо/влево), лицом к зрителю или спиной.
const VIEW_SIDE := "side"
const VIEW_FRONT := "front"
const VIEW_BACK := "back"

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
## Мундштук на шнурке на шее (кальянный мастер): цвет смолы; piece_hidden — мундштук сейчас вставлен в шланг.
var lanyard := false
var piece_color := Color("#e29a2e")
var piece_hidden := false
## Держит перед собой конец шланга (рука вперёд).
var holding := false

## Жест на месте (idle кальянщика): "scrub", "read", "pat", "think", "drink", "juggle"; "" — нет.
var gesture := ""
var juggle_colors: Array[Color] = [Color("#ff7a1a"), Color("#22b8ff"), Color("#7bd62f")]

var pose: String = POSE_STAND
var moving: bool = false
var puffing: bool = false
var facing_right: bool = true
var view: String = VIEW_SIDE

## Обычный (не друг) гость: в новом виде рисуется безликим оранжевым болванчиком.
var generic := false
var blob_color := VisualStyle.GUEST_BLOB
var _look_saved: Dictionary = {}

var _phase: float = 0.0
var _time: float = 0.0
var _hand_t: float = 0.0
var _gesture_time := 0.0
var _gesture_hands := {true: Vector2.ZERO, false: Vector2.ZERO}
var _last_hand := Vector2.ZERO


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
			figure.lanyard = true
			figure.piece_color = Color("#2fb36b")
			figure.face_seed = 11
		_:
			figure.skin = Color("#f1c27d")
			figure.hair = Color("#5a3a22")
			figure.shirt = Color("#e8833a")
			figure.pants = Color("#33405f")
			figure.shoes = Color("#f2f2f2")
	figure.set_facing(true)
	return figure


## Внешность из описания гостя (look): цвета "#rrggbb" для skin/hair/shirt/pants/shoes/jacket.
func apply_look(look: Dictionary) -> void:
	_look_saved = {}
	for part in look:
		var color := Color.html(str(look[part]))
		match str(part):
			"skin":
				skin = color
			"hair":
				hair = color
			"shirt":
				shirt = color
			"pants":
				pants = color
			"shoes":
				shoes = color
			"jacket":
				jacket = color
	queue_redraw()


func set_facing(right: bool) -> void:
	facing_right = right
	view = VIEW_SIDE
	scale = Vector2(BODY_SCALE if right else -BODY_SCALE, BODY_SCALE)


## Повернуться к точке: screen_delta — вектор на экране от фигуры к цели.
## Больше вертикали — лицом к зрителю (цель ниже) или спиной (выше), иначе боком.
func look_toward(screen_delta: Vector2) -> void:
	if screen_delta.length() < 1.0:
		return
	var right := screen_delta.x > 0.0 if absf(screen_delta.x) > 0.5 else facing_right
	facing_right = right
	scale = Vector2(BODY_SCALE if right else -BODY_SCALE, BODY_SCALE)
	if absf(screen_delta.y) > absf(screen_delta.x) * 0.9:
		view = VIEW_FRONT if screen_delta.y > 0.0 else VIEW_BACK
	else:
		view = VIEW_SIDE


## Ракурс при ходьбе: движение по экрану вверх/вниз (W/S) — спиной/лицом к зрителю, иначе боком по направлению шага.
func walk_toward(screen_delta: Vector2) -> void:
	if screen_delta.length() < 0.001:
		return
	if absf(screen_delta.y) > absf(screen_delta.x) * 1.2:
		view = VIEW_FRONT if screen_delta.y > 0.0 else VIEW_BACK
	else:
		set_facing(screen_delta.x > 0.0)


## Фактический ракурс: при затяжке и шланге в руке рисуем боком (руки и шланг рассчитаны на профиль).
func effective_view() -> String:
	if puffing or holding or _hand_t > 0.02 or idle_dance or gesture != "":
		return VIEW_SIDE
	return view


## Рот в координатах родителя (для дыма).
func mouth_position() -> Vector2:
	var local := _mouth_local()
	return position + Vector2(local.x * scale.x, local.y * scale.y)


## Насколько рука поднята ко рту (0..1).
func puff_amount() -> float:
	return _hand_t


## Ближняя рука в координатах родителя (куда ложится шланг).
func hand_position() -> Vector2:
	return position + Vector2(_last_hand.x * scale.x, _last_hand.y * scale.y)


func _draw_lanyard(shoulder: Vector2) -> void:
	if not lanyard:
		return
	var chest := shoulder + Vector2(3.5, 13.0)
	var strap := Color("#15151a")
	draw_line(shoulder + Vector2(-1.0, 0.0), chest, strap, 1.4, true)
	draw_line(shoulder + Vector2(5.0, 0.0), chest, strap, 1.4, true)
	draw_circle(chest, 1.3, Color("#cfd4dc"))
	if not piece_hidden:
		HookahArt.draw_mouthpiece(self, chest + Vector2(0.0, 1.0), Vector2.DOWN, piece_color, 0.42)


func _process(delta: float) -> void:
	_time += delta
	_gesture_time += delta
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


## Куда идёт рука при затяжке: хват ручки шланга перед лицом.
func _grip_local() -> Vector2:
	return _mouth_local() + Vector2(GRIP_REACH, GRIP_DROP)


func _limb(a: Vector2, b: Vector2, width: float, color: Color, outline: bool = true) -> void:
	if VisualStyle.modern and outline:
		# Тёмный контур вокруг конечности: фигурки «отлипают» от пола и друг от друга.
		var edge := color.darkened(0.6)
		edge.a = 0.85
		draw_line(a, b, edge, width + 1.6, true)
		draw_circle(a, (width + 1.6) * 0.5, edge)
		draw_circle(b, (width + 1.6) * 0.5, edge)
	draw_line(a, b, color, width, true)
	draw_circle(a, width * 0.5, color)
	draw_circle(b, width * 0.5, color)


func _shoe(foot: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(-3.5, -4.0), foot + Vector2(3.0, -4.0), foot + Vector2(7.5, -1.5),
		foot + Vector2(7.5, 1.0), foot + Vector2(-3.5, 1.0)]), shoes)
	draw_line(foot + Vector2(-3.5, 0.0), foot + Vector2(7.5, 0.0), shoes.darkened(0.45), 1.5)


## Безликий болванчик нового вида.
func _blob() -> bool:
	return generic and VisualStyle.modern


## Подменяет палитру безликого гостя (и возвращает обычную, когда вид переключили обратно).
func _sync_palette() -> void:
	if _blob():
		if _look_saved.is_empty():
			_look_saved = {"skin": skin, "hair": hair, "shirt": shirt, "pants": pants, "shoes": shoes, "jacket": jacket}
		skin = blob_color
		hair = blob_color
		shirt = blob_color
		pants = blob_color.darkened(0.08)
		shoes = blob_color.darkened(0.18)
		jacket = Color(0, 0, 0, 0)
	elif not _look_saved.is_empty():
		skin = _look_saved["skin"]
		hair = _look_saved["hair"]
		shirt = _look_saved["shirt"]
		pants = _look_saved["pants"]
		shoes = _look_saved["shoes"]
		jacket = _look_saved["jacket"]
		_look_saved = {}


## Мягкая тень под ногами; у друзей и кальянщика в новом виде — ещё цветное кольцо (чтобы выделялись среди болванчиков).
func _draw_ground_shadow() -> void:
	if not VisualStyle.modern:
		return
	draw_texture_rect(VisualStyle.soft_disc(), Rect2(-20.0, -6.0, 40.0, 14.0), false, Color(0.1, 0.05, 0.02, 0.5))
	if not generic:
		var ring := shirt if jacket.a <= 0.0 else jacket.lightened(0.25)
		draw_set_transform(Vector2(0.0, 1.0), 0.0, Vector2(1.0, 0.4))
		draw_arc(Vector2.ZERO, 14.5, 0.0, TAU, 28, Color(ring.r, ring.g, ring.b, 0.85), 2.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	_sync_palette()
	_draw_ground_shadow()
	var current := effective_view()
	if current != VIEW_SIDE:
		_draw_front_back(current == VIEW_FRONT)
		return
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
	_limb(hip + Vector2(1.5, 0), shoulder + Vector2(1.5, 2.0), 10.0, torso, false)
	draw_line(hip + Vector2(-6.5, -1.0), hip + Vector2(6.5, -1.0), pants.darkened(0.35), 2.0)
	if jacket.a > 0.0:
		draw_colored_polygon(PackedVector2Array([
			shoulder + Vector2(3.0, 2.0), shoulder + Vector2(7.0, 4.0),
			hip + Vector2(5.0, -6.0), hip + Vector2(3.0, -6.0)]), shirt)
		draw_line(shoulder + Vector2(5.0, 4.0), hip + Vector2(4.0, -8.0), tie, 2.2)
	_draw_lanyard(shoulder)
	var head: Vector2 = _head_local()
	_limb(shoulder + Vector2(0, 1.0), head + Vector2(0, 5.0), 5.0, skin.darkened(0.08))
	_draw_head(head)
	_arm(shoulder + Vector2(2.5, 3.0), true)
	_draw_gesture_extras()


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
		if holding:
			hand = shoulder + Vector2(10.0, 13.0)
			elbow = shoulder + Vector2(5.0, 9.5)
		if _hand_t > 0.0:
			hand = hand.lerp(_grip_local(), _hand_t)
			elbow = elbow.lerp(shoulder + Vector2(7.0, 6.0), _hand_t)
		_last_hand = hand
	if gesture != "" and not moving and not holding and _hand_t < 0.02:
		var g := _gesture_pose(shoulder, near)
		if not g.is_empty():
			hand = g[0]
			elbow = g[1]
			if near:
				_last_hand = hand
		_gesture_hands[near] = hand
	_limb(shoulder, elbow, 5.2, tone)
	_limb(elbow, hand, 4.8, tone)
	draw_circle(hand, 2.8, skin if near else skin.darkened(0.2))


## Включает жест (см. gesture); colors — цвета банок для жонглирования.
func set_gesture(gesture_name: String, colors: Array = []) -> void:
	gesture = gesture_name
	_gesture_time = 0.0
	if not colors.is_empty():
		juggle_colors.clear()
		for c in colors:
			juggle_colors.append(c)


## Насколько поднят стакан ко рту (0..1) в цикле питья.
func _drink_k() -> float:
	var u := fposmod(_gesture_time, 4.0) / 4.0
	return smoothstep(0.0, 1.0, clampf(sin(u * PI) * 2.0, 0.0, 1.0))


## Положение [кисть, локоть] для жеста; пустой массив — рука в обычном положении.
func _gesture_pose(shoulder: Vector2, near: bool) -> Array:
	var t := _gesture_time
	match gesture:
		"scrub":
			if near:
				return [shoulder + Vector2(11.0 + sin(t * 10.0) * 3.0, 9.0 + sin(t * 5.0)), shoulder + Vector2(5.0, 9.0)]
			return [shoulder + Vector2(9.0, 12.0), shoulder + Vector2(4.0, 9.5)]
		"read":
			if near:
				return [shoulder + Vector2(12.0 + sin(t * 1.6) * 5.0, -6.0 + sin(t * 0.8) * 2.5), shoulder + Vector2(6.0, 3.0)]
		"pat":
			if near:
				var swing := sin(t * 11.0)
				return [shoulder + Vector2(11.0 + maxf(0.0, swing) * 2.0, -16.0 + swing * 3.0), shoulder + Vector2(7.0, -4.0)]
		"think":
			if near:
				return [_head_local() + Vector2(6.0, 8.0), shoulder + Vector2(7.0, 6.0)]
		"drink":
			if near:
				var k := _drink_k()
				var rest := shoulder + Vector2(9.0, 12.0)
				var up := _mouth_local() + Vector2(1.0, 5.0)
				return [rest.lerp(up, k), (shoulder + Vector2(5.0, 9.0)).lerp(shoulder + Vector2(8.0, 5.0), k)]
		"juggle":
			var wobble := t * 7.8
			if near:
				return [shoulder + Vector2(10.0 + cos(wobble) * 1.5, 4.0 + sin(wobble) * 2.0), shoulder + Vector2(6.0, 7.0)]
			return [shoulder + Vector2(6.0 - cos(wobble) * 1.5, 5.0 - sin(wobble) * 2.0), shoulder + Vector2(3.0, 8.0)]
	return []


## Предметы жеста: летающие банки (жонглирование) и стакан с водой (питьё).
func _draw_gesture_extras() -> void:
	if gesture == "juggle":
		var center: Vector2 = (_gesture_hands[true] + _gesture_hands[false]) * 0.5
		for k in 3:
			var a := TAU * fposmod(_gesture_time * 0.65 + float(k) / 3.0, 1.0)
			var at := center + Vector2(cos(a) * 8.0, -3.0 - absf(sin(a)) * 22.0)
			draw_set_transform(at, 0.0, Vector2(0.45, 0.45))
			HookahArt.draw_jar(self, Vector2.ZERO, juggle_colors[k % juggle_colors.size()])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif gesture == "drink":
		var hand: Vector2 = _gesture_hands[true]
		var k := _drink_k()
		draw_set_transform(hand + Vector2(1.5, -2.0), k * 1.0, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(-2.6, -4.0), Vector2(2.6, -4.0), Vector2(2.0, 3.0), Vector2(-2.0, 3.0)]), Color(0.85, 0.93, 1.0, 0.8))
		draw_colored_polygon(PackedVector2Array([Vector2(-2.4, -1.0), Vector2(2.4, -1.0), Vector2(2.0, 3.0), Vector2(-2.0, 3.0)]), Color(0.97, 0.96, 0.92, 0.95))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_head(head: Vector2) -> void:
	if _blob():
		draw_circle(head + Vector2(0.0, 0.0), 8.6, skin)
		draw_circle(head + Vector2(-2.4, -2.6), 3.2, skin.lightened(0.14))
		return
	if VisualStyle.modern:
		_draw_head_modern(head)
		return
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


## Черты лица из зерна (face_seed): причёска, глаза, брови, рот, очки, борода, веснушки — у каждого свои.
var face_seed := 0
var _traits: Dictionary = {}


func _face() -> Dictionary:
	if not _traits.is_empty() and int(_traits["seed"]) == face_seed:
		return _traits
	var rng := RandomNumberGenerator.new()
	rng.seed = face_seed * 2654435761 + 17
	_traits = {
		"seed": face_seed,
		"style": rng.randi_range(0, 5),
		"eye": 1.6 + rng.randf() * 0.9,
		"iris": [Color("#1b1b1b"), Color("#3a2a1a"), Color("#2a5a8a"), Color("#2f7a4a"), Color("#6a3a7a")][rng.randi_range(0, 4)],
		"lashes": rng.randf() < 0.3,
		"brow": 1.0 + rng.randf() * 1.3,
		"tilt": (rng.randf() - 0.5) * 1.6,
		"mouth": rng.randi_range(0, 3),
		"glasses": rng.randf() < 0.25,
		"frame": [Color("#1c1c22"), Color("#c0392b"), Color("#d4a640"), Color("#3a6fb0")][rng.randi_range(0, 3)],
		"beard": rng.randi_range(1, 3) if rng.randf() < 0.2 else 0,
		"freckles": rng.randf() < 0.22,
		"blush": 0.18 + rng.randf() * 0.22,
		"nose": 0.9 + rng.randf() * 0.8,
		"cap": Color.from_hsv(rng.randf(), 0.55, 0.75),
	}
	return _traits


## Волосы и причёска за головой (рисуются до лица): длинные, пучок, кудри, шапка.
func _hair_back_modern(head: Vector2, front: bool) -> void:
	var t := _face()
	var edge := Color(0.12, 0.07, 0.06, 0.9)
	var centre := head + (Vector2(-0.8, -1.5) if not front else Vector2(0.0, -2.0))
	match int(t["style"]):
		1:
			var a := centre + Vector2(-3.0 if not front else -6.0, 2.0)
			var b := centre + Vector2(-5.5 if not front else -6.5, 13.0)
			draw_line(a, b, edge, 9.4, true)
			draw_line(a, b, hair, 7.6, true)
			if front:
				var a2 := centre + Vector2(6.0, 2.0)
				var b2 := centre + Vector2(6.5, 13.0)
				draw_line(a2, b2, edge, 9.4, true)
				draw_line(a2, b2, hair, 7.6, true)
		2:
			var bun := centre + Vector2(-6.5 if not front else 0.0, -8.0 if not front else -9.0)
			draw_circle(bun, 5.0, edge)
			draw_circle(bun, 3.9, hair)
			draw_circle(bun + Vector2(-1.0, -1.0), 1.3, hair.lightened(0.3))
		4:
			for k in 7:
				var angle := -PI + float(k) * PI / 6.0
				var at := centre + Vector2(cos(angle) * 8.6, sin(angle) * 8.2 - 1.0)
				draw_circle(at, 4.4, edge)
			for k in 7:
				var angle := -PI + float(k) * PI / 6.0
				var at := centre + Vector2(cos(angle) * 8.6, sin(angle) * 8.2 - 1.0)
				draw_circle(at, 3.5, hair)


## Лицо: глаз(а) с бликами и ресницами, брови, нос, рот, румянец, веснушки, очки, борода.
func _face_details_side(head: Vector2) -> void:
	var t := _face()
	var eye_c := head + Vector2(5.4, -0.4)
	var size: float = float(t["eye"])
	draw_circle(eye_c, size + 0.2, Color(0.97, 0.97, 0.97))
	draw_circle(eye_c + Vector2(0.5, 0.1), size * 0.62, t["iris"])
	draw_circle(eye_c + Vector2(0.5, 0.1), size * 0.3, Color("#101010"))
	draw_circle(eye_c + Vector2(0.9, -0.5), 0.5, Color(1, 1, 1))
	if bool(t["lashes"]):
		draw_line(eye_c + Vector2(1.0, -size), eye_c + Vector2(2.6, -size - 1.2), Color("#1b1b1b"), 1.0, true)
	var tilt: float = float(t["tilt"])
	draw_line(head + Vector2(3.6, -3.2 - tilt), head + Vector2(7.2, -3.5 + tilt), hair.darkened(0.35), float(t["brow"]), true)
	draw_circle(head + Vector2(4.0, 3.0), 1.9, Color(1.0, 0.45, 0.45, float(t["blush"])))
	if bool(t["freckles"]):
		for dot: Vector2 in [Vector2(3.4, 2.2), Vector2(5.0, 3.0), Vector2(4.2, 4.0)]:
			draw_circle(head + dot, 0.45, skin.darkened(0.35))
	draw_circle(head + Vector2(8.6 + (float(t["nose"]) - 1.0), 1.4), 1.3 * float(t["nose"]), skin.darkened(0.06))
	var mouth_c := head + Vector2(6.6, 3.8)
	match int(t["mouth"]):
		0:
			draw_arc(mouth_c, 2.0, 0.3, 2.3, 6, Color("#8a4b3a"), 1.1, true)
		1:
			draw_line(mouth_c + Vector2(-1.4, 0.0), mouth_c + Vector2(1.8, -0.2), Color("#8a4b3a"), 1.1, true)
		2:
			draw_circle(mouth_c, 1.3, Color("#7a2f2a"))
		_:
			draw_arc(mouth_c + Vector2(0.4, 0.6), 1.8, 0.0, 2.4, 6, Color("#8a4b3a"), 1.1, true)
			draw_circle(mouth_c + Vector2(-1.4, 0.4), 0.5, Color("#8a4b3a"))
	var beard := int(t["beard"])
	if beard > 0:
		var tone := hair.darkened(0.1)
		if beard == 1:
			draw_line(mouth_c + Vector2(-1.5, -1.4), mouth_c + Vector2(2.4, -1.2), tone, 1.6, true)
		elif beard == 2:
			draw_arc(head + Vector2(3.0, 2.0), 6.4, 0.5, 2.5, 10, tone, 2.2, true)
		else:
			draw_circle(mouth_c + Vector2(0.4, 2.6), 1.9, tone)
	if bool(t["glasses"]):
		var frame: Color = t["frame"]
		draw_arc(eye_c + Vector2(0.4, 0.0), size + 1.7, 0.0, TAU, 14, frame, 1.2, true)
		draw_line(eye_c + Vector2(-size - 1.0, -0.3), head + Vector2(-3.5, -0.8), frame, 1.0, true)
	_hair_front_modern(head, false)


## Чёлка/шапка поверх лба.
func _hair_front_modern(head: Vector2, front: bool) -> void:
	var t := _face()
	match int(t["style"]):
		3:
			pass
		5:
			var cap: Color = t["cap"]
			var centre := head + Vector2(-0.8, -3.2)
			draw_arc(centre, 9.0, PI, TAU, 14, cap, 5.0, true)
			draw_line(centre + Vector2(-9.0, 0.5), centre + Vector2(10.5 if not front else 9.0, 0.5), cap.darkened(0.25), 2.2, true)


## Новый вид: голова с контуром, глянцем на волосах и индивидуальными чертами лица.
func _draw_head_modern(head: Vector2) -> void:
	var edge := Color(0.12, 0.07, 0.06, 0.9)
	var style := int(_face()["style"])
	_hair_back_modern(head, false)
	draw_circle(head + Vector2(-0.8, -1.5), 10.1, edge)
	draw_circle(head + Vector2(2.2, 1.6), 8.2, edge)
	var hair_tone := hair.lerp(skin, 0.5) if style == 3 else hair
	draw_circle(head + Vector2(-0.8, -1.5), 8.9 if style != 3 else 8.4, hair_tone)
	draw_circle(head + Vector2(-2.6, 0.5), 2.2, skin.darkened(0.12))
	draw_circle(head + Vector2(2.2, 1.6), 7.0, skin)
	if style != 3:
		draw_colored_polygon(PackedVector2Array([
			head + Vector2(-3.0, -8.8), head + Vector2(6.0, -7.0), head + Vector2(9.0, -2.6),
			head + Vector2(4.5, -4.6), head + Vector2(0.5, -3.6)]), hair.lightened(0.05))
	draw_arc(head + Vector2(-0.8, -1.5), 6.6, -2.7, -1.3, 8, hair_tone.lightened(0.35), 1.6, true)
	_face_details_side(head)


## Лицом к зрителю, новый вид.
func _draw_front_modern(head: Vector2) -> void:
	var t := _face()
	var edge := Color(0.12, 0.07, 0.06, 0.9)
	var style := int(t["style"])
	_hair_back_modern(head, true)
	var hair_tone := hair.lerp(skin, 0.5) if style == 3 else hair
	draw_circle(head + Vector2(0.0, -2.0), 9.9, edge)
	draw_circle(head + Vector2(0.0, -2.0), 8.6 if style != 3 else 8.2, hair_tone)
	draw_circle(head + Vector2(0.0, 1.0), 7.3, skin)
	if style != 3:
		draw_colored_polygon(PackedVector2Array([
			head + Vector2(-7.4, -2.0), head + Vector2(-3.0, -7.6), head + Vector2(3.0, -7.6),
			head + Vector2(7.4, -2.0), head + Vector2(3.0, -4.4), head + Vector2(-3.0, -4.4)]), hair.lightened(0.05))
	draw_circle(head + Vector2(-8.0, 1.0), 1.7, skin.darkened(0.06))
	draw_circle(head + Vector2(8.0, 1.0), 1.7, skin.darkened(0.06))
	var size: float = float(t["eye"]) * 0.85
	var tilt: float = float(t["tilt"])
	for side: float in [-1.0, 1.0]:
		var eye_c := head + Vector2(2.9 * side, 0.1)
		draw_circle(eye_c, size + 0.2, Color(0.97, 0.97, 0.97))
		draw_circle(eye_c + Vector2(0.0, 0.2), size * 0.62, t["iris"])
		draw_circle(eye_c + Vector2(0.0, 0.2), size * 0.3, Color("#101010"))
		draw_circle(eye_c + Vector2(0.4, -0.3), 0.45, Color(1, 1, 1))
		draw_line(head + Vector2(2.0 * side, -2.6 + tilt * side * 0.5), head + Vector2(4.4 * side, -2.6 - tilt * side * 0.5), hair.darkened(0.35), float(t["brow"]), true)
		draw_circle(head + Vector2(4.8 * side, 3.0), 1.6, Color(1.0, 0.45, 0.45, float(t["blush"])))
		if bool(t["lashes"]):
			draw_line(eye_c + Vector2(side * size, -size * 0.6), eye_c + Vector2(side * (size + 1.4), -size - 0.8), Color("#1b1b1b"), 1.0, true)
	if bool(t["freckles"]):
		for dot: Vector2 in [Vector2(-3.8, 2.8), Vector2(-2.6, 3.6), Vector2(3.8, 2.8), Vector2(2.6, 3.6), Vector2(0.0, 2.2)]:
			draw_circle(head + dot, 0.45, skin.darkened(0.35))
	draw_circle(head + Vector2(0.0, 2.0), 1.0 * float(t["nose"]), skin.darkened(0.1))
	var mouth_c := head + Vector2(0.0, 4.2)
	match int(t["mouth"]):
		0:
			draw_arc(mouth_c - Vector2(0, 0.6), 2.2, 0.35, 2.8, 6, Color("#8a4b3a"), 1.1, true)
		1:
			draw_line(mouth_c + Vector2(-1.8, 0.0), mouth_c + Vector2(1.8, 0.0), Color("#8a4b3a"), 1.1, true)
		2:
			draw_circle(mouth_c, 1.4, Color("#7a2f2a"))
		_:
			draw_arc(mouth_c + Vector2(0.5, 0.0), 2.0, 0.2, 2.6, 6, Color("#8a4b3a"), 1.1, true)
	var beard := int(t["beard"])
	if beard > 0:
		var tone := hair.darkened(0.1)
		if beard == 1:
			draw_line(head + Vector2(-2.6, 3.0), head + Vector2(2.6, 3.0), tone, 1.6, true)
		elif beard == 2:
			draw_arc(head + Vector2(0.0, 1.5), 6.4, 0.3, PI - 0.3, 12, tone, 2.4, true)
		else:
			draw_circle(head + Vector2(0.0, 6.4), 2.1, tone)
	if bool(t["glasses"]):
		var frame: Color = t["frame"]
		for side: float in [-1.0, 1.0]:
			draw_arc(head + Vector2(2.9 * side, 0.1), size + 1.7, 0.0, TAU, 14, frame, 1.2, true)
		draw_line(head + Vector2(-1.2, 0.0), head + Vector2(1.2, 0.0), frame, 1.0, true)
	_hair_front_modern(head, true)


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
	_limb(hip + Vector2(1.5, 0), shoulder + Vector2(1.5, 2.0), 10.0, torso, false)
	_limb(hip, knee, 7.5, pants)
	_limb(knee, foot, 6.5, pants)
	_shoe(foot)
	_draw_lanyard(shoulder)
	var head: Vector2 = _head_local()
	_limb(shoulder + Vector2(0, 1.0), head + Vector2(0, 5.0), 5.0, skin.darkened(0.08))
	_draw_head(head)
	_seated_arm(shoulder + Vector2(2.5, 3.0), knee + Vector2(-3, -4), true)


func _seated_arm(shoulder: Vector2, rest: Vector2, near: bool) -> void:
	var sleeve: Color = jacket if jacket.a > 0.0 else shirt
	var tone: Color = sleeve if near else sleeve.darkened(0.3)
	var elbow: Vector2 = shoulder.lerp(rest, 0.5) + Vector2(-3.0, 3.0)
	var hand: Vector2 = rest
	if near and holding:
		hand = shoulder + Vector2(10.0, 13.0)
		elbow = shoulder + Vector2(5.0, 9.5)
	if near and _hand_t > 0.0:
		hand = hand.lerp(_grip_local(), _hand_t)
		elbow = elbow.lerp(shoulder + Vector2(7.0, 6.0), _hand_t)
	if near:
		_last_hand = hand
	_limb(shoulder, elbow, 5.2, tone)
	_limb(elbow, hand, 4.8, tone)
	draw_circle(hand, 2.8, skin if near else skin.darkened(0.2))


## Ракурс «лицом» / «спиной»: симметричная фигура. Положение рта/руки для шланга и дыма — как в профиле
## (в этих ракурсах человек не курит и не держит шланг).
func _draw_front_back(front: bool) -> void:
	var seated := pose == POSE_SIT
	var bob: float = _bob()
	var hip := Vector2(0.0, -24.0 if seated else -23.0 + bob)
	var shoulder := Vector2(0.0, -46.0 + bob if seated else -43.0 + bob)
	var torso: Color = jacket if jacket.a > 0.0 else shirt
	# Ноги.
	for side: float in [-1.0, 1.0]:
		var top := hip + Vector2(3.6 * side, 0.0)
		if seated:
			var knee := top + Vector2(0.8 * side, 11.0)
			var foot := knee + Vector2(0.0, 12.0)
			_limb(top, knee, 7.5, pants)
			draw_circle(knee, 4.4, pants.lightened(0.06))
			_limb(knee, foot, 6.3, pants.darkened(0.12))
			_front_shoe(foot, front)
		else:
			var foot := Vector2(3.6 * side, 0.0)
			if moving:
				# Шаг: поднятая нога по очереди, лёгкое смещение вглубь.
				var leg_phase := _phase + (PI if side > 0.0 else 0.0)
				foot.y = -maxf(0.0, sin(leg_phase)) * 4.0 + cos(leg_phase) * 1.2
			_limb(top, foot + Vector2(0, -2.0), 6.8, pants)
			_front_shoe(foot, front)
	# Руки вдоль тела (за торсом).
	var sleeve: Color = jacket if jacket.a > 0.0 else shirt
	for side: float in [-1.0, 1.0]:
		var sh := shoulder + Vector2(7.2 * side, 3.0)
		var hand := sh + Vector2(1.6 * side, 15.0)
		if seated:
			hand = sh + Vector2(1.0 * side, 14.0)
		elif moving:
			# Руки качаются противоходом ногам.
			hand.y += sin(_phase + (0.0 if side > 0.0 else PI)) * 3.5
		_limb(sh, sh.lerp(hand, 0.5) + Vector2(0.6 * side, 0.0), 5.2, sleeve.darkened(0.1))
		_limb(sh.lerp(hand, 0.5), hand, 4.8, sleeve.darkened(0.1))
		draw_circle(hand, 2.8, skin)
	# Торс.
	_limb(hip, shoulder + Vector2(0, 2.0), 15.0, torso.darkened(0.08))
	_limb(hip, shoulder + Vector2(0, 2.0), 12.0, torso, false)
	draw_line(hip + Vector2(-7.0, -1.0), hip + Vector2(7.0, -1.0), pants.darkened(0.35), 2.0)
	var head := _head_local()
	head.x = 0.0
	if front:
		if jacket.a > 0.0:
			draw_colored_polygon(PackedVector2Array([
				shoulder + Vector2(-2.6, 3.5), shoulder + Vector2(2.6, 3.5), hip + Vector2(0.0, -4.0)]), shirt)
			draw_line(shoulder + Vector2(0.0, 5.0), hip + Vector2(0.0, -6.0), tie, 2.2)
		if lanyard:
			var chest := shoulder + Vector2(0.0, 11.0)
			var strap := Color("#15151a")
			draw_line(shoulder + Vector2(-3.0, 2.0), chest, strap, 1.3, true)
			draw_line(shoulder + Vector2(3.0, 2.0), chest, strap, 1.3, true)
			draw_circle(chest, 1.3, Color("#cfd4dc"))
			if not piece_hidden:
				HookahArt.draw_mouthpiece(self, chest + Vector2(0.0, 1.0), Vector2.DOWN, piece_color, 0.42)
	else:
		if jacket.a > 0.0:
			draw_line(shoulder + Vector2(0.0, 3.0), hip + Vector2(0.0, -5.0), jacket.darkened(0.25), 1.2)
		if lanyard:
			draw_line(shoulder + Vector2(-3.0, 0.0), shoulder + Vector2(3.0, 0.0), Color("#15151a"), 1.3, true)
	_limb(shoulder + Vector2(0, 1.0), head + Vector2(0, 5.0), 5.0, skin.darkened(0.08))
	if _blob():
		draw_circle(head, 8.6, skin)
		draw_circle(head + Vector2(-2.4, -2.6), 3.2, skin.lightened(0.14))
	elif front and VisualStyle.modern:
		_draw_front_modern(head)
	elif front:
		draw_circle(head + Vector2(0.0, -2.0), 8.6, hair)
		draw_circle(head + Vector2(0.0, 1.0), 7.3, skin)
		draw_colored_polygon(PackedVector2Array([
			head + Vector2(-7.4, -2.0), head + Vector2(-3.0, -7.6), head + Vector2(3.0, -7.6),
			head + Vector2(7.4, -2.0), head + Vector2(3.0, -4.4), head + Vector2(-3.0, -4.4)]), hair.lightened(0.05))
		draw_circle(head + Vector2(-8.0, 1.0), 1.7, skin.darkened(0.06))
		draw_circle(head + Vector2(8.0, 1.0), 1.7, skin.darkened(0.06))
		if VisualStyle.modern:
			for eye_x: float in [-2.9, 2.9]:
				draw_circle(head + Vector2(eye_x, 0.1), 1.9, Color(0.97, 0.97, 0.97))
				draw_circle(head + Vector2(eye_x, 0.3), 1.2, Color("#1b1b1b"))
				draw_circle(head + Vector2(eye_x + 0.4, -0.3), 0.45, Color(1, 1, 1))
			draw_circle(head + Vector2(-4.8, 3.0), 1.6, Color(1.0, 0.45, 0.45, 0.3))
			draw_circle(head + Vector2(4.8, 3.0), 1.6, Color(1.0, 0.45, 0.45, 0.3))
			draw_arc(head + Vector2(0.0, 3.4), 2.2, 0.35, 2.8, 6, Color("#8a4b3a"), 1.1, true)
		else:
			draw_circle(head + Vector2(-2.8, 0.2), 1.2, Color("#1b1b1b"))
			draw_circle(head + Vector2(2.8, 0.2), 1.2, Color("#1b1b1b"))
			draw_line(head + Vector2(-1.8, 4.6), head + Vector2(1.8, 4.6), Color("#8a4b3a"), 1.2)
	else:
		if VisualStyle.modern:
			_hair_back_modern(head, true)
		draw_circle(head + Vector2(0.0, -0.5), 8.9, hair)
		draw_circle(head + Vector2(-8.0, 2.0), 1.6, skin.darkened(0.06))
		draw_circle(head + Vector2(8.0, 2.0), 1.6, skin.darkened(0.06))
		draw_arc(head + Vector2(0.0, -0.5), 6.0, 0.4, 2.7, 10, hair.lightened(0.12), 1.0)


func _front_shoe(foot: Vector2, front: bool) -> void:
	var toe := 1.5 if front else -0.5
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(-3.8, -3.5), foot + Vector2(3.8, -3.5), foot + Vector2(4.2, toe + 1.5),
		foot + Vector2(-4.2, toe + 1.5)]), shoes)
	draw_line(foot + Vector2(-4.2, toe + 1.2), foot + Vector2(4.2, toe + 1.2), shoes.darkened(0.45), 1.4)
