class_name GarageWorld
extends Node2D
## Корень сцены гаража: собирает мир из data-описания и связывает игрока, NPC,
## систему взаимодействий и подсказку. Игровых правил здесь нет.

## Гость сделал затяжку (Main считает их для повторной просьбы).
signal friend_inhaled(guest_id: String)
signal message_requested(text: String)
signal dialogue_requested(dialogue_id: String)
signal action_requested(action_id: String)
signal friend_arrived(guest_id: String)

const LAYOUT_PATH := "res://data/garage/garage_main.json"
const PLAYER_SCENE := preload("res://scenes/characters/Player.tscn")
const FRIEND_SCENE := preload("res://scenes/characters/Friend.tscn")
const DOOR_OBJECT_ID := "door_main"
const HOOKAH_OBJECT_ID := "hookah_test"
const HOOKAH_CARRY_TEXTURE := "res://art/furniture/hookah_test.png"
const FRIEND_TALK_PROMPT := "Поговорить"
const FRIEND_TALK_RADIUS := 1.4

var _grid: GarageGrid = null
var _interactions := InteractionSystem.new()
var _player: Player = null
var _objects: Dictionary = {} # id -> Node2D (GarageObject или Friend)
var _emoji_source_id := ""
var _highlighted: GarageObject = null
var _serve_cell := Vector2i(-1, -1)
var _prep_cell := Vector2i(-1, -1)
var _seat_cell := Vector2i(-1, -1)
var _sitting_busy := false
## Сообщение о вкусе кальяна: показывается после нескольких затяжек игрока.
var _pending_smoke_message := ""
var _puffs_until_message := 0
var _marker: Label = null
var _marker_target_id := ""
var _marker_time := 0.0
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
	_serve_cell = layout.hookah_serve_cell
	_prep_cell = layout.hookah_prep_cell
	_seat_cell = layout.player_seat_cell
	_build_objects(layout)

	_player = PLAYER_SCENE.instantiate() as Player
	_entities.add_child(_player)
	_player.setup(_grid, layout.player_spawn)
	_player.inhale_started.connect(_on_inhale)
	_player.inhale_started.connect(_on_player_inhale)
	_player.stood_up.connect(_on_player_stood_up)
	_player.set_camera_limits(GarageBackdrop.screen_bounds(layout.size))

	_marker = Label.new()
	_marker.text = "⬇️"
	_marker.size = Vector2(24, 24)
	_marker.add_theme_font_size_override("font_size", 17)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.visible = false
	add_child(_marker)

	_interactions.focus_changed.connect(_on_focus_changed)
	_interactions.player_interacted.connect(_on_player_interacted)
	GameLog.info("garage", "Гараж '%s' загружен: %dx%d, объектов: %d" % [layout.id, layout.size.x, layout.size.y, layout.objects.size()])


func _process(delta: float) -> void:
	if _player == null:
		return
	_try_apply_pending_blocks()
	_interactions.update_focus(_player.grid_position)
	_update_marker(delta)


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
func spawn_friend(guest: Dictionary, entry_position: Vector2, entry_cell: Vector2i, stand_cell: Vector2i, dialogue_id: String, seat: Dictionary = {}) -> bool:
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
	friend.inhale_started.connect(_on_inhale)
	friend.inhale_started.connect(func(_duration: float) -> void: friend_inhaled.emit(friend.guest_id))
	friend.arrived.connect(_on_friend_arrived.bind(friend, guest, stand_cell, dialogue_id, seat))
	GameLog.info("garage", "%s заходит в гараж" % str(guest["name"]))
	_enter_through_door(friend, path)
	return true


## Дверь открывается, гость заходит, затем дверь закрывается. Без двери — просто идёт.
func _enter_through_door(friend: Friend, path: Array[Vector2]) -> void:
	var door: Variant = _objects.get(DOOR_OBJECT_ID)
	if not (door is GarageObject):
		friend.walk_path(path)
		return
	friend.visible = false
	await (door as GarageObject).set_door_open(true)
	friend.visible = true
	friend.walk_path(path)
	await get_tree().create_timer(1.3).timeout
	await (door as GarageObject).set_door_open(false, 0.45)


## Меняет подсказку/действие/позу игрока у объекта "на лету" (например, стол с кальяном:
## «Приготовить» -> «Покурить» / «Перезабить»).
func configure_interaction(object_id: String, prompt: String, action: String, player_emoji: String = "", message: String = "", enabled: bool = true) -> void:
	var data := _interactions.find_by_id(object_id)
	if data == null:
		GameLog.error("garage", "configure_interaction: нет объекта '%s'" % object_id)
		return
	data.prompt = prompt
	data.action = action
	data.player_emoji = player_emoji
	data.message = message
	data.enabled = enabled
	if _player != null:
		_interactions.update_focus(_player.grid_position)
	_interactions.refocus()


## Подсказка-стрелка ⬇ над объектом или другом ("" — скрыть), покачивается.
func set_marker(object_id: String) -> void:
	_marker_target_id = object_id
	_marker.visible = _objects.has(object_id)


func hide_object(object_id: String) -> void:
	var node: Variant = _objects.get(object_id)
	if node is CanvasItem:
		(node as CanvasItem).visible = false


func is_object_visible(object_id: String) -> bool:
	var node: Variant = _objects.get(object_id)
	return node is CanvasItem and (node as CanvasItem).visible


## Игрок несёт кальян к столу гостя: идёт к точке подачи с кальяном в руках, ставит его на стол.
## Корутина: завершается, когда кальян стоит на столе. Ввод на время переноса блокируется.
func carry_hookah_to_guest_table() -> void:
	var hookah: Variant = _objects.get(HOOKAH_OBJECT_ID)
	if _player == null or _grid == null or not (hookah is GarageObject):
		return
	var was_locked := _input_locked
	set_input_locked(true)
	(hookah as GarageObject).visible = false
	await _walk_carrying(_serve_cell)
	await (hookah as GarageObject).drop_in()
	await _warm_up_puffs()
	set_input_locked(was_locked)


## Игрок забирает кальян со стола гостя и несёт к столу для кальянов (перезабивка).
func carry_hookah_to_prep_table() -> void:
	var hookah: Variant = _objects.get(HOOKAH_OBJECT_ID)
	if _player == null or _grid == null or not (hookah is GarageObject):
		return
	var was_locked := _input_locked
	set_input_locked(true)
	(hookah as GarageObject).visible = false
	await _walk_carrying(_prep_cell)
	set_input_locked(was_locked)


## Небольшая раскурка перед подачей: 2–5 коротких тяжек.
func _warm_up_puffs() -> void:
	var puffs := randi_range(2, 5)
	for i in puffs:
		await _player.puff(randf_range(0.5, 1.3))
		await get_tree().create_timer(randf_range(0.2, 0.5)).timeout


## Кальян на столе сплющивается на время затяжки (курит игрок или гость).
func _on_inhale(duration: float) -> void:
	var hookah: Variant = _objects.get(HOOKAH_OBJECT_ID)
	if hookah is GarageObject and (hookah as GarageObject).visible:
		(hookah as GarageObject).squash(duration)


func _walk_carrying(target_cell: Vector2i) -> void:
	if target_cell.x < 0:
		return
	var start_cell := Vector2i(_player.grid_position.floor())
	var path := _grid.find_path(start_cell, target_cell)
	if ResourceLoader.exists(HOOKAH_CARRY_TEXTURE):
		_player.set_carrying(load(HOOKAH_CARRY_TEXTURE))
	_player.walk_path(path)
	await _player.auto_walk_finished
	_player.set_carrying(null)


## id первого друга, который уже дошёл до своей точки ("" — никого нет).
func ready_friend_id() -> String:
	for object_id in _objects:
		var node: Node2D = _objects[object_id]
		if node is Friend and (node as Friend).has_arrived:
			return str(object_id)
	return ""


func friend_react(guest_id: String, emoji: String) -> void:
	var node: Variant = _objects.get(guest_id)
	if node is Friend:
		(node as Friend).show_emotion(emoji)


## mood_emoji — реакция, которую гость время от времени показывает, пока курит.
func set_friend_smoking(guest_id: String, on: bool, mood_emoji: String = "") -> void:
	var node: Variant = _objects.get(guest_id)
	if node is Friend:
		(node as Friend).set_smoking(on, mood_emoji)


func _update_marker(delta: float) -> void:
	if _marker_target_id.is_empty() or not _marker.visible:
		return
	var target: Variant = _objects.get(_marker_target_id)
	if not (target is Node2D) or not (target as CanvasItem).visible:
		return
	_marker_time += delta
	var node := target as Node2D
	var bob := sin(_marker_time * 5.0) * 3.0
	_marker.position = node.position + Vector2(-12.0, float(node.get("top_y")) - 14.0 + bob)


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
			data.enabled = interaction["enabled"]
			data.radius = interaction["radius"]
			data.rect = interaction["rect"]
			_interactions.register(data)


func _on_friend_arrived(friend: Friend, guest: Dictionary, stand_cell: Vector2i, dialogue_id: String, seat: Dictionary) -> void:
	friend.has_arrived = true
	friend_arrived.emit(friend.guest_id)
	if not seat.is_empty():
		friend.sit(str(seat["emoji"]), str(seat["facing"]) == "left", float(seat.get("lift", 0.0)))
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
	if data == null or _input_locked or _player.seated:
		_prompt.hide_prompt()
	else:
		var object: Node2D = _objects[data.id]
		_prompt.show_for(data.prompt, object.position + Vector2(0, float(object.get("top_y")) - 10.0))
	# Поза "курю" действует, пока игрок рядом с тем же объектом (сидя за столом — пока не встанет).
	if _emoji_source_id != "" and not _player.seated and not _sitting_busy and (data == null or data.id != _emoji_source_id):
		_emoji_source_id = ""
		_player.reset_emoji()
		_player.set_smoking(false)


func _on_player_interacted(interactable_id: String) -> void:
	var data := _interactions.find_by_id(interactable_id)
	if data == null or _player.seated:
		return
	if not data.dialogue_id.is_empty():
		dialogue_requested.emit(data.dialogue_id)
		return
	var sits_to_smoke := data.action == "smoke_hookah" and _seat_cell.x >= 0
	# Сообщение о курении показываем после нескольких затяжек, когда игрок уже сидит у гостя.
	if not data.message.is_empty() and not sits_to_smoke:
		message_requested.emit(data.message)
	if not data.action.is_empty():
		action_requested.emit(data.action)
	if sits_to_smoke:
		_sit_and_smoke(interactable_id, data.message)
	elif not data.player_emoji.is_empty():
		_emoji_source_id = interactable_id
		_player.set_head_emoji(data.player_emoji)
		_player.set_smoking(true)


## Игрок идёт к своему стулу, садится за стол гостя и курит, пока не встанет.
func _sit_and_smoke(source_id: String, message: String) -> void:
	if _sitting_busy or _player.seated:
		return
	_sitting_busy = true
	_emoji_source_id = source_id
	var path := _grid.find_path(Vector2i(_player.grid_position.floor()), _seat_cell)
	if not path.is_empty():
		_player.walk_path(path)
		await _player.auto_walk_finished
	_player.sit_down()
	_prompt.hide_prompt()
	_player.set_smoking(true)
	_sitting_busy = false
	_pending_smoke_message = message
	_puffs_until_message = randi_range(2, 5)


func _on_player_inhale(_duration: float) -> void:
	if _pending_smoke_message.is_empty() or not _player.seated:
		return
	_puffs_until_message -= 1
	if _puffs_until_message <= 0:
		message_requested.emit(_pending_smoke_message)
		_pending_smoke_message = ""


func _on_player_stood_up() -> void:
	_pending_smoke_message = ""
	_on_focus_changed(_interactions.focus)
	_emoji_source_id = ""
	_player.set_smoking(false)
