class_name Player
extends Node2D
## Аватар игрока. Источник истины позиции — grid_position (клетки); нода лишь проецирует её.

signal auto_walk_finished
## Игрок встал со стула (например, пошёл куда-то после совместного курения).
signal stood_up
## Начало затяжки (для сплющивания кальяна) и её конец.
signal inhale_started(duration: float)
signal inhale_ended

const DEFAULT_EMOJI := "🕺"
const SPEED_CELLS_PER_SEC := 4.0
const HALF_EXTENT := 0.25
const MAX_FRAME_DELTA := 0.05
const DEFAULT_ZOOM := 2.0
const STAND_BUTTON_Y := -112.0

var grid_position: Vector2 = Vector2.ZERO
## Выключается на время диалога.
var input_enabled: bool = true

var _grid: GarageGrid = null
var _smoke: SmokeEmitter
var _figure: CharacterFigure
var _seat_overlay: SeatOverlay = null
var seated: bool = false
var _carry_width: float = 0.0
var _carried: Sprite2D
var _carried_hookah: CarriedHookah
var _stand_button: PanelContainer
var _zoom_tween: Tween = null
var _auto_walker := PathWalker.new()
var _auto_walking: bool = false

@onready var _avatar: Label = %Avatar
@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	_avatar.visible = false
	_figure = CharacterFigure.make("player")
	add_child(_figure)
	_stand_button = _make_stand_button()
	add_child(_stand_button)
	# Кнопка добавлена раньше дыма, поэтому клубы иногда заходят поверх надписи.
	_smoke = SmokeEmitter.new()
	add_child(_smoke)
	_smoke.inhale_started.connect(_on_inhale_started)
	_smoke.inhale_ended.connect(_on_inhale_ended)
	_sync_smoke_position()
	_carried = Sprite2D.new()
	_carried.centered = false
	_carried.visible = false
	add_child(_carried)
	_carried_hookah = CarriedHookah.new()
	_carried_hookah.visible = false
	add_child(_carried_hookah)


## Надпись «E Встать» над головой в стиле остальных подсказок (рамка клавиши + текст), поменьше; клик тоже встаёт.
func _make_stand_button() -> PanelContainer:
	var panel := PanelContainer.new()
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.05, 0.04, 0.03, 0.72)
	panel_box.set_corner_radius_all(6)
	panel_box.content_margin_left = 5.0
	panel_box.content_margin_right = 6.0
	panel_box.content_margin_top = 2.0
	panel_box.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override("panel", panel_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var key_frame := PanelContainer.new()
	var key_box := StyleBoxFlat.new()
	key_box.bg_color = Color(0.2, 0.16, 0.12, 1)
	key_box.border_color = Color(0.96, 0.85, 0.55, 1)
	key_box.set_border_width_all(1)
	key_box.set_corner_radius_all(3)
	key_box.content_margin_left = 4.0
	key_box.content_margin_right = 4.0
	key_box.content_margin_top = 0.0
	key_box.content_margin_bottom = 0.0
	key_frame.add_theme_stylebox_override("panel", key_box)
	key_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key := Label.new()
	key.text = "E"
	key.add_theme_font_size_override("font_size", 9)
	key.add_theme_color_override("font_color", Color(0.98, 0.92, 0.75, 1))
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_frame.add_child(key)
	row.add_child(key_frame)
	var action := Label.new()
	action.text = "Встать"
	action.add_theme_font_size_override("font_size", 9)
	action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(action)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			stand_up())
	panel.visible = false
	return panel


## Камера приближается к столу (focus — смещение от игрока в экранных px).
func focus_camera(zoom_value: float, focus: Vector2) -> void:
	if _zoom_tween != null:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_property(_camera, "zoom", Vector2(zoom_value, zoom_value), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(_camera, "offset", focus, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func reset_camera() -> void:
	if _zoom_tween != null:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_property(_camera, "zoom", Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(_camera, "offset", Vector2.ZERO, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_inhale_started(duration: float) -> void:
	_figure.puffing = true
	inhale_started.emit(duration)


func _on_inhale_ended() -> void:
	_figure.puffing = false
	inhale_ended.emit()


func _sync_smoke_position() -> void:
	_smoke.position = _figure.mouth_position()


func smoke_emitter() -> SmokeEmitter:
	return _smoke


## Дым изо рта (игрок курит кальян).
func set_smoking(on: bool) -> void:
	_smoke.active = on


## Садится на стул, смотрящий вдоль +y (то есть влево-вниз на экране): поза «сидит» и передняя часть сиденья.
func sit_down() -> void:
	seated = true
	_figure.pose = CharacterFigure.POSE_SIT
	_figure.moving = false
	_figure.set_facing(false)
	if _seat_overlay == null:
		_seat_overlay = SeatOverlay.new()
		_seat_overlay.scale.x = -1.0
		add_child(_seat_overlay)
		move_child(_seat_overlay, _figure.get_index() + 1)
	_seat_overlay.visible = true
	_stand_button.reset_size()
	_stand_button.position = Vector2(-_stand_button.size.x * 0.5, STAND_BUTTON_Y)
	_stand_button.visible = true


func stand_up() -> void:
	if not seated:
		return
	seated = false
	_stand_button.visible = false
	reset_camera()
	_figure.pose = CharacterFigure.POSE_STAND
	if _seat_overlay != null:
		_seat_overlay.visible = false
	stood_up.emit()


## Одна затяжка заданной длительности (корутина).
func puff(duration: float) -> void:
	await _smoke.puff(duration)


func setup(grid: GarageGrid, spawn: Vector2) -> void:
	_grid = grid
	grid_position = spawn
	position = IsoProjection.grid_to_screen(grid_position)
	reset_emoji()


func set_camera_limits(bounds: Rect2i) -> void:
	_camera.limit_left = bounds.position.x
	_camera.limit_top = bounds.position.y
	_camera.limit_right = bounds.end.x
	_camera.limit_bottom = bounds.end.y
	_camera.reset_smoothing()


## Эмодзи поверх головы больше не рисуется: курение видно по руке у рта и дыму.
func set_head_emoji(_text: String) -> void:
	pass


func reset_emoji() -> void:
	pass


## Показывает/прячет предмет в руках (например, кальян, который несут к столу).
func set_carrying(texture: Texture2D, height: float = 44.0) -> void:
	_carried_hookah.visible = false
	if texture == null:
		_carried.visible = false
		return
	_carried.texture = texture
	var factor := height / float(texture.get_height())
	_carried.scale = Vector2(factor, factor)
	_carry_width = float(texture.get_width()) * factor
	_carried.position = Vector2(_carry_side() * 16.0 - _carry_width * 0.5, -height + 4.0)
	_carried.visible = true


## Несёт в руках векторный кальян цвета color (null-значение не нужно: чтобы убрать — set_carrying(null)).
func set_carrying_hookah(color: Color) -> void:
	_carried.visible = false
	_carried_hookah.color = color
	_carried_hookah.position = Vector2(_carry_side() * 17.0, -2.0)
	_carried_hookah.visible = true
	_carried_hookah.queue_redraw()


## Клапан кальяна в руках (в координатах родителя Player).
func carried_base_position() -> Vector2:
	return position + _carried_hookah.position


func carried_valve_position() -> Vector2:
	return position + _carried_hookah.position + HookahArt.VALVE * HookahArt.SCALE


## Ближняя рука и рот в координатах родителя (для шланга).
func hand_position() -> Vector2:
	return position + _figure.hand_position()


func mouth_position() -> Vector2:
	return position + _figure.mouth_position()


## Рука вперёд: держит конец шланга.
func set_holding(value: bool) -> void:
	_figure.holding = value


## Мундштук с шеи вставлен в шланг (на груди его нет).
func set_piece_hidden(value: bool) -> void:
	_figure.piece_hidden = value


func piece_color() -> Color:
	return _figure.piece_color


## +1 — смотрит вправо, -1 — влево; доля затяжки (0 — рука внизу, 1 — у рта).
func facing_sign() -> float:
	return 1.0 if _figure.facing_right else -1.0


func puff_amount() -> float:
	return _figure.puff_amount()


func face_toward(screen_x: float) -> void:
	_face(screen_x > position.x)


func is_smoking() -> bool:
	return _smoke.active


func is_carrying_hookah() -> bool:
	return _carried_hookah.visible


## Автоматическая ходьба по пути (центры клеток), игнорирует ввод. По окончании — auto_walk_finished.
func walk_path(path: Array[Vector2], speed: float = SPEED_CELLS_PER_SEC) -> void:
	if path.is_empty():
		call_deferred("emit_signal", "auto_walk_finished")
		return
	stand_up()
	_auto_walker.position = grid_position
	_auto_walker.set_path(path, speed)
	_auto_walking = true


func _process(delta: float) -> void:
	_figure.moving = false
	_process_movement(delta)
	_sync_smoke_position()


func _process_movement(delta: float) -> void:
	if _auto_walking:
		_figure.moving = true
		var previous_x := position.x
		var finished := _auto_walker.step(minf(delta, MAX_FRAME_DELTA))
		grid_position = _auto_walker.position
		position = IsoProjection.grid_to_screen(grid_position)
		var dx := position.x - previous_x
		if absf(dx) > 0.01:
			_face(dx > 0.0)
		if finished:
			_auto_walking = false
			auto_walk_finished.emit()
		return
	if _grid == null or not input_enabled:
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		return
	if seated:
		stand_up()
	_figure.moving = true
	if absf(input.x) > 0.05:
		_face(input.x > 0.0)
	var step := IsoProjection.screen_dir_to_grid_dir(input) * input.length() * SPEED_CELLS_PER_SEC * minf(delta, MAX_FRAME_DELTA)
	grid_position = _grid.resolve_move(grid_position, step, HALF_EXTENT)
	position = IsoProjection.grid_to_screen(grid_position)


func _face(right: bool) -> void:
	_figure.set_facing(right)
	_carried.position.x = _carry_side() * 16.0 - _carry_width * 0.5
	_carried_hookah.position.x = _carry_side() * 17.0


func _carry_side() -> float:
	return 1.0 if _figure.facing_right else -1.0


func _draw() -> void:
	IsoDraw.draw_shadow(self, 14.0)
