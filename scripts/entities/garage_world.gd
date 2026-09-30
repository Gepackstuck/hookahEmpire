class_name GarageWorld
extends Node2D
## Корень сцены гаража: собирает мир из data-описания и связывает игрока, NPC,
## систему взаимодействий и подсказку. Игровых правил здесь нет.

signal message_requested(text: String)
signal dialogue_requested(dialogue_id: String)
signal action_requested(action_id: String)

const LAYOUT_PATH := "res://data/garage/garage_main.json"
const PLAYER_SCENE := preload("res://scenes/characters/Player.tscn")
const FRIEND_SCENE := preload("res://scenes/characters/Friend.tscn")
const FRIEND_TALK_PROMPT := "Поговорить"
const FRIEND_TALK_RADIUS := 1.4

var _grid: GarageGrid = null
var _interactions := InteractionSystem.new()
var _player: Player = null
var _objects: Dictionary = {} # id -> Node2D (GarageObject или Friend)
var _emoji_source_id := ""
var _highlighted: GarageObject = null
var _input_locked := false
var _pending_blocks: Array[Rect2i] = [] # клетки, которые займут NPC, когда игрок выйдет из них

@onready var _backdrop: GarageBackdrop = %Backdrop
@onready var _entities: Node2D = %Entities
@onready var _prompt: InteractionPrompt = %InteractionPrompt


func _ready() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	if not layout.is_valid():
		for message in layout.errors:
			GameLog.error("garage", message)
		return

	_grid = GarageGrid.new(layout.size)
	_backdrop.setup(layout.size)
	_build_objects(layout)

	_player = PLAYER_SCENE.instantiate() as Player
	_entities.add_child(_player)
	_player.setup(_grid, layout.player_spawn)
	_player.set_camera_limits(GarageBackdrop.screen_bounds(layout.size))

	_interactions.focus_changed.connect(_on_focus_changed)
	_interactions.player_interacted.connect(_on_player_interacted)
	GameLog.info("garage", "Гараж '%s' загружен: %dx%d, объектов: %d" % [layout.id, layout.size.x, layout.size.y, layout.objects.size()])


func _process(_delta: float) -> void:
	if _player == null:
		return
	_try_apply_pending_blocks()
	_interactions.update_focus(_player.grid_position)


func _unhandled_input(event: InputEvent) -> void:
	if _player != null and not _input_locked and event.is_action_pressed("interact"):
		if _interactions.interact():
			get_viewport().set_input_as_handled()


## Блокирует ходьбу и взаимодействие (на время диалога).
func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	if _player != null:
		_player.input_enabled = not locked
	if locked:
		_prompt.hide_prompt()
	else:
		_interactions.refocus()


## Друг заходит в гараж у entry_position, идёт к stand_cell и становится собеседником.
func spawn_friend(guest: Dictionary, entry_position: Vector2, entry_cell: Vector2i, stand_cell: Vector2i, dialogue_id: String) -> bool:
	if _grid == null:
		GameLog.error("garage", "spawn_friend: гараж не загружен")
		return false
	var path := _grid.find_path(entry_cell, stand_cell)
	if path.is_empty():
		GameLog.error("garage", "spawn_friend: нет пути от %s до %s" % [str(entry_cell), str(stand_cell)])
		return false
	path.push_front(entry_position)

	var friend := FRIEND_SCENE.instantiate() as Friend
	_entities.add_child(friend)
	friend.setup(str(guest["id"]), str(guest["emoji"]), entry_position, str(guest.get("sprite_faces", "right")) == "right")
	_objects[friend.guest_id] = friend
	friend.arrived.connect(_on_friend_arrived.bind(guest, stand_cell, dialogue_id))
	friend.walk_path(path)
	GameLog.info("garage", "%s заходит в гараж" % str(guest["name"]))
	return true


func _build_objects(layout: GarageLayout) -> void:
	for definition in layout.objects:
		var object := GarageObject.new()
		_entities.add_child(object)
		object.setup(definition)
		_objects[definition["id"]] = object

		var footprint := Rect2i(definition["cell"], definition["size"])
		if definition["blocks"]:
			_grid.set_blocked_rect(footprint, true)

		var interaction: Dictionary = definition["interaction"]
		if not interaction.is_empty():
			var data := InteractableData.new()
			data.id = definition["id"]
			data.display_name = definition["name"]
			data.prompt = interaction["prompt"]
			data.message = interaction["message"]
			data.player_emoji = interaction["player_emoji"]
			data.action = interaction["action"]
			data.radius = interaction["radius"]
			data.rect = interaction["rect"]
			_interactions.register(data)


func _on_friend_arrived(guest: Dictionary, stand_cell: Vector2i, dialogue_id: String) -> void:
	_pending_blocks.append(Rect2i(stand_cell, Vector2i.ONE))
	var data := InteractableData.new()
	data.id = str(guest["id"])
	data.display_name = str(guest["name"])
	data.prompt = FRIEND_TALK_PROMPT
	data.dialogue_id = dialogue_id
	data.radius = FRIEND_TALK_RADIUS
	data.rect = Rect2(Vector2(stand_cell), Vector2.ONE)
	_interactions.register(data)
	GameLog.info("garage", "%s дошёл и ждёт разговора" % data.display_name)


## Клетка друга становится непроходимой, как только игрок из неё вышел (иначе он застрянет).
func _try_apply_pending_blocks() -> void:
	if _pending_blocks.is_empty():
		return
	var half := Player.HALF_EXTENT
	var player_box := Rect2(_player.grid_position - Vector2(half, half), Vector2(half, half) * 2.0)
	for rect in _pending_blocks.duplicate():
		if not player_box.intersects(Rect2(rect)):
			_grid.set_blocked_rect(rect, true)
			_pending_blocks.erase(rect)


func _on_focus_changed(data: InteractableData) -> void:
	if _highlighted != null:
		_highlighted.set_highlighted(false)
		_highlighted = null
	if data != null and _objects.get(data.id) is GarageObject:
		_highlighted = _objects[data.id]
		_highlighted.set_highlighted(true)
	if data == null or _input_locked:
		_prompt.hide_prompt()
	else:
		var object: Node2D = _objects[data.id]
		_prompt.show_for(data.prompt, object.position + Vector2(0, float(object.get("top_y")) - 10.0))
	# Поза "курю" действует, пока игрок рядом с тем же объектом.
	if _emoji_source_id != "" and (data == null or data.id != _emoji_source_id):
		_emoji_source_id = ""
		_player.reset_emoji()


func _on_player_interacted(interactable_id: String) -> void:
	var data := _interactions.find_by_id(interactable_id)
	if data == null:
		return
	if not data.dialogue_id.is_empty():
		dialogue_requested.emit(data.dialogue_id)
		return
	if not data.message.is_empty():
		message_requested.emit(data.message)
	if not data.action.is_empty():
		action_requested.emit(data.action)
	if not data.player_emoji.is_empty():
		_emoji_source_id = interactable_id
		_player.set_emoji(data.player_emoji)
