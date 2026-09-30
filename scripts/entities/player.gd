class_name Player
extends Node2D
## Аватар игрока. Источник истины позиции — grid_position (клетки); нода лишь проецирует её.

const DEFAULT_EMOJI := "🕺"
const SPEED_CELLS_PER_SEC := 4.0
const HALF_EXTENT := 0.25
const MAX_FRAME_DELTA := 0.05
## Куда смотрит исходный эмодзи-спрайт. Если в игре направление перевёрнуто — поменять на false.
const SPRITE_FACES_RIGHT := false

var grid_position: Vector2 = Vector2.ZERO
## Выключается на время диалога.
var input_enabled: bool = true

var _grid: GarageGrid = null

@onready var _avatar: Label = %Avatar
@onready var _camera: Camera2D = %Camera


func setup(grid: GarageGrid, spawn: Vector2) -> void:
	_grid = grid
	_avatar.pivot_offset = _avatar.size * 0.5
	grid_position = spawn
	position = IsoProjection.grid_to_screen(grid_position)
	reset_emoji()


func set_camera_limits(bounds: Rect2i) -> void:
	_camera.limit_left = bounds.position.x
	_camera.limit_top = bounds.position.y
	_camera.limit_right = bounds.end.x
	_camera.limit_bottom = bounds.end.y
	_camera.reset_smoothing()


func set_emoji(text: String) -> void:
	_avatar.text = text


func reset_emoji() -> void:
	_avatar.text = DEFAULT_EMOJI


func _process(delta: float) -> void:
	if _grid == null or not input_enabled:
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		return
	if absf(input.x) > 0.05:
		_face(input.x > 0.0)
	var step := IsoProjection.screen_dir_to_grid_dir(input) * input.length() * SPEED_CELLS_PER_SEC * minf(delta, MAX_FRAME_DELTA)
	grid_position = _grid.resolve_move(grid_position, step, HALF_EXTENT)
	position = IsoProjection.grid_to_screen(grid_position)


func _face(right: bool) -> void:
	_avatar.scale.x = 1.0 if right == SPRITE_FACES_RIGHT else -1.0


func _draw() -> void:
	IsoDraw.draw_shadow(self, 14.0)
