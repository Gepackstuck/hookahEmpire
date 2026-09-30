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
var _auto_walker := PathWalker.new()
var _auto_walking: bool = false

@onready var _avatar: Label = %Avatar
@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	_avatar.visible = false
	_figure = CharacterFigure.make("player")
	add_child(_figure)
	_smoke = SmokeEmitter.new()
	add_child(_smoke)
	_smoke.inhale_started.connect(_on_inhale_started)
	_smoke.inhale_ended.connect(_on_inhale_ended)
	_sync_smoke_position()
	_carried = Sprite2D.new()
	_carried.centered = false
	_carried.visible = false
	add_child(_carried)


func _on_inhale_started(duration: float) -> void:
	_figure.puffing = true
	inhale_started.emit(duration)


func _on_inhale_ended() -> void:
	_figure.puffing = false
	inhale_ended.emit()


func _sync_smoke_position() -> void:
	_smoke.position = _figure.mouth_position()


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


func stand_up() -> void:
	if not seated:
		return
	seated = false
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
	if texture == null:
		_carried.visible = false
		return
	_carried.texture = texture
	var factor := height / float(texture.get_height())
	_carried.scale = Vector2(factor, factor)
	_carry_width = float(texture.get_width()) * factor
	_carried.position = Vector2(_carry_side() * 16.0 - _carry_width * 0.5, -height + 4.0)
	_carried.visible = true


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


func _carry_side() -> float:
	return 1.0 if _figure.facing_right else -1.0


func _draw() -> void:
	IsoDraw.draw_shadow(self, 14.0)
