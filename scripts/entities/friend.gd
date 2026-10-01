class_name Friend
extends Node2D
## Друг-NPC: идёт по заданному пути и сообщает о приходе. Позиция в клетках — grid_position.
## Рисуется векторным человечком (CharacterFigure): ходьба, сидение на стуле, затяжки.

signal arrived
## Начало затяжки (кальян сплющивается) и её конец.
signal inhale_started(duration: float)
signal inhale_ended

const SPEED_CELLS_PER_SEC := 3.5
const MAX_FRAME_DELTA := 0.05
const SEAT_COLOR := Color("#8a5a3c")
const SEATED_HEAD_OFFSET := 14.0
const BUBBLE_Y := -112.0

var guest_id: String = ""
var grid_position: Vector2 = Vector2.ZERO
## Высота визуала над полом (для подсказки и стрелки).
var top_y: float = -92.0

var _walker := PathWalker.new()
var _figure: CharacterFigure
var _smoke: SmokeEmitter
var _bubble: Label
var _bubble_tween: Tween
var _seat_front: SeatOverlay
## Пока гость курит, время от времени показывает свою реакцию.
var _mood_emoji: String = ""
var _puffs_until_mood: int = 0
## Дошёл до своей точки (и сел, если задана поза).
var has_arrived: bool = false
var _head: HeadLabels


func _ready() -> void:
	_figure = CharacterFigure.make("denis")
	add_child(_figure)
	_smoke = SmokeEmitter.new()
	add_child(_smoke)
	_smoke.inhale_started.connect(_on_inhale_started)
	_smoke.inhale_ended.connect(_on_inhale_ended)
	_bubble = Label.new()
	_bubble.size = Vector2(28, 28)
	_bubble.position = Vector2(-14, BUBBLE_Y)
	_bubble.pivot_offset = _bubble.size * 0.5
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble.add_theme_font_size_override("font_size", 19)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	add_child(_bubble)
	_head = HeadLabels.new()
	add_child(_head)
	_sync_smoke_position()


func setup(id: String, _emoji: String, start_position: Vector2, _sprite_faces_right: bool = true) -> void:
	guest_id = id
	name = "Friend_%s" % id
	_walker.position = start_position
	_sync_position()


## Внешность гостя из data/guests (look).
func apply_look(look: Dictionary) -> void:
	_figure.apply_look(look)


func walk_path(path: Array[Vector2]) -> void:
	_walker.set_path(path, SPEED_CELLS_PER_SEC)
	_figure.moving = true


## Друг дошёл и сел на стул: поза "сидит", передняя часть сиденья рисуется поверх ног.
func sit(_emoji: String, face_left: bool, _lift: float = 0.0) -> void:
	has_arrived = true
	_figure.moving = false
	_figure.pose = CharacterFigure.POSE_SIT
	_figure.set_facing(not face_left)
	_head.position.y = SEATED_HEAD_OFFSET
	if _seat_front == null:
		_seat_front = SeatOverlay.new()
		_seat_front.color = SEAT_COLOR
		add_child(_seat_front)
		move_child(_bubble, get_child_count() - 1)
	_sync_smoke_position()


## Гость встаёт со стула (уходит): поза "стоит", сиденье больше не рисуется поверх ног.
func stand_up() -> void:
	has_arrived = false
	_figure.pose = CharacterFigure.POSE_STAND
	_figure.holding = false
	_head.position.y = 0.0
	if _seat_front != null:
		_seat_front.visible = false
	_sync_smoke_position()


func _on_inhale_started(duration: float) -> void:
	if not _mood_emoji.is_empty():
		_puffs_until_mood -= 1
		if _puffs_until_mood <= 0:
			_puffs_until_mood = randi_range(6, 15)
			show_emotion(_mood_emoji, 2.5)
	_figure.puffing = true
	inhale_started.emit(duration)


func _on_inhale_ended() -> void:
	_figure.puffing = false
	inhale_ended.emit()


func _sync_smoke_position() -> void:
	_smoke.position = _figure.mouth_position()


## Реплика над головой (режим NPC); возвращает длительность показа.
func say(text: String, emoji: String = "") -> float:
	return _head.say(text, -1.0, emoji)


func clear_speech() -> void:
	_head.clear_speech()


func set_chips(chips: Array) -> void:
	_head.set_chips(chips)


func clear_chips() -> void:
	_head.clear_chips()


func head_labels() -> HeadLabels:
	return _head


func hand_position() -> Vector2:
	return position + _figure.hand_position()


func mouth_position() -> Vector2:
	return position + _figure.mouth_position()


func look_toward(screen_delta: Vector2) -> void:
	_figure.look_toward(screen_delta)


func look_straight() -> void:
	_figure.view = CharacterFigure.VIEW_SIDE


func facing_sign() -> float:
	return 1.0 if _figure.facing_right else -1.0


func puff_amount() -> float:
	return _figure.puff_amount()


func set_holding(value: bool) -> void:
	_figure.holding = value


func set_piece_color(color: Color) -> void:
	_figure.piece_color = color


func piece_color() -> Color:
	return _figure.piece_color


func is_smoking() -> bool:
	return _smoke.active


func smoke_emitter() -> SmokeEmitter:
	return _smoke


## Курит кальян затяжками (друг курит кальян).
func set_smoking(on: bool, mood_emoji: String = "") -> void:
	_smoke.active = on
	_mood_emoji = mood_emoji if on else ""
	_puffs_until_mood = randi_range(6, 15)


## Эмоция над головой: появляется с "отскоком", держится и гаснет.
func show_emotion(emoji: String, hold_seconds: float = 3.5) -> void:
	if _bubble_tween != null:
		_bubble_tween.kill()
	_bubble.text = emoji
	_bubble.visible = true
	_bubble.modulate.a = 1.0
	_bubble.scale = Vector2(0.3, 0.3)
	_bubble_tween = create_tween()
	_bubble_tween.tween_property(_bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_interval(hold_seconds)
	_bubble_tween.tween_property(_bubble, "modulate:a", 0.0, 0.5)
	_bubble_tween.tween_callback(func() -> void: _bubble.visible = false)


func _process(delta: float) -> void:
	_sync_smoke_position()
	if not _walker.is_walking():
		return
	var finished := _walker.step(minf(delta, MAX_FRAME_DELTA * maxf(Engine.time_scale, 1.0)))
	_sync_position()
	if finished:
		_figure.moving = false
		arrived.emit()


func _sync_position() -> void:
	grid_position = _walker.position
	var new_position := IsoProjection.grid_to_screen(grid_position)
	var step := new_position - position
	if step.length() > 0.01 and _figure != null and not has_arrived:
		_figure.walk_toward(step)
	position = new_position


func _draw() -> void:
	IsoDraw.draw_shadow(self, 14.0)
