class_name Friend
extends Node2D
## Друг-NPC: идёт по заданному пути и сообщает о приходе. Позиция в клетках — grid_position.

signal arrived

const SPEED_CELLS_PER_SEC := 2.5
const MAX_FRAME_DELTA := 0.05

var guest_id: String = ""
var grid_position: Vector2 = Vector2.ZERO
## Высота визуала над полом (для подсказки), как у GarageObject.
var top_y: float = -56.0

var _walker := PathWalker.new()
var _sprite_faces_right := true

@onready var _avatar: Label = %Avatar


func setup(id: String, emoji: String, start_position: Vector2, sprite_faces_right: bool = true) -> void:
	_sprite_faces_right = sprite_faces_right
	_avatar.pivot_offset = _avatar.size * 0.5
	guest_id = id
	name = "Friend_%s" % id
	_avatar.text = emoji
	_walker.position = start_position
	_sync_position()


func walk_path(path: Array[Vector2]) -> void:
	_walker.set_path(path, SPEED_CELLS_PER_SEC)


func _process(delta: float) -> void:
	if not _walker.is_walking():
		return
	var finished := _walker.step(minf(delta, MAX_FRAME_DELTA))
	_sync_position()
	if finished:
		arrived.emit()


func _sync_position() -> void:
	grid_position = _walker.position
	var new_position := IsoProjection.grid_to_screen(grid_position)
	var dx := new_position.x - position.x
	if absf(dx) > 0.01 and _avatar != null:
		_avatar.scale.x = 1.0 if (dx > 0.0) == _sprite_faces_right else -1.0
	position = new_position


func _draw() -> void:
	IsoDraw.draw_shadow(self, 14.0)
