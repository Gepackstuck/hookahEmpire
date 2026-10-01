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
const HOOKAH_PREP_OBJECT_ID := "hookah_prep"
const SHELF_OBJECT_ID := "shelf_hookah"
## Где шланг лежит на столе для кальянов (от основания кальяна): в свободном заднем правом углу, между предметами.
const PREP_HOSE_START := Vector2(10.0, 0.0)
const PREP_HOSE_END := Vector2(40.0, 12.0)
const FRIEND_TALK_PROMPT := "Поговорить"
const SIT_CAMERA_ZOOM := 3.0
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
## Цвет кальяна, который взяли с полки (его же несут, ставят на стол и подают гостю).
var _hookah_color := Color("#22b8ff")
## Шланг: концы плавно едут к целевым точкам (колбэки возвращают координаты Entities).
var _hose: HoseLine = null
var _hose_start_fn := Callable()
var _hose_end_fn := Callable()
var _hose_aim_fn := Callable()
var _hose_cover_fn := Callable()
var _hose_cover_id := ""
## Начало шланга плавно едет (только когда мастер тянет его к клапану); иначе приклеено к кальяну.
var _hose_start_smooth := false
## Вид ручки шланга текущего кальяна (случайный при выборе кальяна).
var _handle_style := 0
var _hose_holder: Node2D = null
var _hose_at_guest := false
var _warming_up := false
var _guest_piece := Color("#e29a2e")
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
	# Стул игрока непроходим, пока на нём не сидят (иначе сквозь него можно ходить).
	if _seat_cell.x >= 0:
		_grid.set_blocked_rect(Rect2i(_seat_cell, Vector2i.ONE), true)

	_player = PLAYER_SCENE.instantiate() as Player
	_entities.add_child(_player)
	_player.setup(_grid, layout.player_spawn)
	_player.inhale_started.connect(_on_inhale)
	_player.inhale_started.connect(_on_player_inhale)
	_player.inhale_started.connect(func(_duration: float) -> void: _hose_take(_player))
	_hose = HoseLine.new()
	add_child(_hose)
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
	_update_hose(delta)
	_interactions.update_focus(_player.grid_position)
	_update_marker(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _player != null and _player.seated and not _sitting_busy and not _input_locked and event.is_action_pressed("interact"):
		_player.stand_up()
		get_viewport().set_input_as_handled()
		return
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
	# Игрок и гость не тянут кальян одновременно: между их затяжками есть пауза.
	friend.smoke_emitter().partner = _player.smoke_emitter()
	_player.smoke_emitter().partner = friend.smoke_emitter()
	friend.inhale_started.connect(func(_duration: float) -> void: friend_inhaled.emit(friend.guest_id))
	friend.inhale_started.connect(func(_duration: float) -> void: _hose_take(friend))
	_guest_piece = friend.piece_color()
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


## Игрок идёт к полке, берёт случайный кальян (слот пустеет), несёт к столу для кальянов и ставит его.
## Корутина: завершается, когда кальян стоит на столе. Ввод на время переноса блокируется.
func fetch_random_hookah() -> void:
	if _player == null or _grid == null:
		return
	var was_locked := _input_locked
	set_input_locked(true)
	reset_hose()
	_handle_style = randi_range(0, HoseLine.HANDLE_STYLES - 1)
	var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
	var color := Color.html(HookahArt.PALETTE.pick_random())
	if shelf is GarageObject and (shelf as GarageObject).hookah_slot_count() > 0:
		var rack := shelf as GarageObject
		var free := rack.free_hookah_slots()
		if free.is_empty():
			rack.restock_hookahs()
			free = rack.free_hookah_slots()
		var slot: int = free.pick_random()
		await _walk_to(rack.shelf_front_cell(slot))
		await get_tree().create_timer(0.3).timeout
		color = rack.hookah_slot_color(slot)
		rack.take_hookah(slot)
		GameLog.info("garage", "Кальян взят с полки: слот %d, цвет %s" % [slot, color.to_html(false)])
	_hookah_color = color
	_player.set_carrying_hookah(color)
	await get_tree().create_timer(0.2).timeout
	await _walk_to(_prep_cell)
	_player.set_carrying(null)
	await _place_hookah(HOOKAH_PREP_OBJECT_ID)
	set_input_locked(was_locked)


## Цвет текущего кальяна (взятого с полки).
func hookah_color() -> Color:
	return _hookah_color


## Полка заново заставляется кальянами (отладка/сброс).
func restock_shelf() -> void:
	var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
	if shelf is GarageObject:
		(shelf as GarageObject).restock_hookahs()


## Игрок несёт кальян к столу гостя: вставляет шланг в кальян, берёт кальян и конец шланга,
## идёт к точке подачи, ставит кальян на стол гостя и раскуривает.
## Корутина: завершается, когда кальян стоит на столе. Ввод на время переноса блокируется.
func carry_hookah_to_guest_table() -> void:
	if _player == null or _grid == null or not (_objects.get(HOOKAH_OBJECT_ID) is GarageObject):
		return
	var was_locked := _input_locked
	set_input_locked(true)
	await _insert_hose()
	hide_object(HOOKAH_PREP_OBJECT_ID)
	_hose_carried()
	await _walk_carrying(_serve_cell)
	await _place_hookah(HOOKAH_OBJECT_ID)
	_guest_takes_mouthpiece()
	_warming_up = true
	await _warm_up_puffs()
	_warming_up = false
	_hose_release_if_idle()
	set_input_locked(was_locked)


## Игрок забирает кальян со стола гостя вместе со шлангом и несёт к столу для кальянов (перезабивка).
func carry_hookah_to_prep_table() -> void:
	if _player == null or _grid == null or not (_objects.get(HOOKAH_PREP_OBJECT_ID) is GarageObject):
		return
	var was_locked := _input_locked
	set_input_locked(true)
	hide_object(HOOKAH_OBJECT_ID)
	_hose_holder = null
	_hose_at_guest = false
	_hose.piece = _guest_piece
	_player.set_piece_hidden(false)
	_hose_carried()
	await _walk_carrying(_prep_cell)
	await _place_hookah(HOOKAH_PREP_OBJECT_ID)
	set_input_locked(was_locked)


## Ставит кальян нужного цвета на стол (объект появляется с «падением»); шланг ложится рядом
## (на столе для кальянов) или остаётся в руке игрока (на столе гостя).
func _place_hookah(object_id: String) -> void:
	var hookah: Variant = _objects.get(object_id)
	if not (hookah is GarageObject):
		return
	# Кальянщик ставит кальян лицом к столу.
	_player.face_toward((hookah as GarageObject).position.x)
	(hookah as GarageObject).set_hookah_color(_hookah_color)
	_hose.color = _hookah_color
	_hose.handle_style = _handle_style
	if object_id == HOOKAH_PREP_OBJECT_ID:
		_hose.piece = Color(0, 0, 0, 0)
		_hose_loose_on_prep(not _hose.shown)
	else:
		_hose_at_guest = true
		_hose_held_by(_player)
	await (hookah as GarageObject).drop_in()


# --- Шланг ---------------------------------------------------------------------------------

func _object_base(object_id: String) -> Vector2:
	var node: Variant = _objects.get(object_id)
	return (node as GarageObject).hookah_base_position() if node is GarageObject else Vector2.ZERO


func _object_valve(object_id: String) -> Vector2:
	var node: Variant = _objects.get(object_id)
	return (node as GarageObject).hookah_valve_position() if node is GarageObject else Vector2.ZERO


func _hose_use(start_fn: Callable, end_fn: Callable, aim_fn: Callable, lying: bool, snap: bool = false) -> void:
	_hose_start_fn = start_fn
	_hose_end_fn = end_fn
	_hose_aim_fn = aim_fn
	_hose_cover_fn = Callable()
	_hose_cover_id = ""
	_hose_start_smooth = false
	_hose.lying = lying
	_hose.flat = false
	if snap:
		_hose.start = start_fn.call()
		_hose.end = end_fn.call()
	_hose.show_hose(true)


func _update_hose(delta: float) -> void:
	if _hose == null or not _hose.shown or not _hose_start_fn.is_valid():
		return
	var follow := 1.0 - exp(-14.0 * delta)
	_hose.start = _hose.start.lerp(_hose_start_fn.call(), follow) if _hose_start_smooth else _hose_start_fn.call()
	_hose.end = _hose.end.lerp(_hose_end_fn.call(), follow)
	_hose.cover_enabled = _hose_cover_fn.is_valid()
	if _hose.cover_enabled:
		_hose.cover_base = _hose_cover_fn.call()
		_hose.cover_color = _hookah_color
		var cover_node: Variant = _objects.get(_hose_cover_id)
		_hose.cover_squash = (cover_node as GarageObject).hookah_squash() if cover_node is GarageObject else 0.0
	if _hose_aim_fn.is_valid():
		var aim: Vector2 = _hose_aim_fn.call()
		if aim != Vector2.ZERO:
			_hose.piece_dir = aim
	_hose.queue_redraw()


## Мундштук лежит перед лицом горизонтально и смотрит кончиком в рот (назад по взгляду держащего) — никуда не поворачивается.
func _aim_to_mouth(holder: Node2D) -> Vector2:
	return Vector2(-float(holder.call("facing_sign")), -0.47).normalized()


## Конец шланга (основание ручки) у держащего: рука хватает ручку на расстоянии GRIP_OFFSET от шланга,
## при затяжке рука идёт ко рту и кончик мундштука касается губ.
func _holder_end(holder: Node2D) -> Vector2:
	var hand: Vector2 = holder.call("hand_position")
	return hand - _aim_to_mouth(holder) * HoseLine.GRIP_OFFSET


## Шланг лежит петлёй рядом с кальяном на столе для кальянов (оба конца свободны).
func _hose_loose_on_prep(snap: bool) -> void:
	var base := _object_base(HOOKAH_PREP_OBJECT_ID)
	_hose_use(func() -> Vector2: return base + PREP_HOSE_START, func() -> Vector2: return base + PREP_HOSE_END,
		func() -> Vector2: return Vector2(-0.99, 0.1), true, snap)
	_hose.flat = true


## Кальян в руках: клапан едет с кальяном, свободный конец шланга — в руке игрока.
func _hose_carried() -> void:
	_hose_use(func() -> Vector2: return _player.carried_valve_position(), func() -> Vector2: return _holder_end(_player),
		func() -> Vector2: return _aim_to_mouth(_player), false)
	_hose_cover_fn = func() -> Vector2: return _player.carried_base_position()
	_hose_cover_id = "carried"


## Шланг подключён к кальяну на столе гостя, конец у holder (мундштук его собственный).
func _hose_held_by(holder: Node2D) -> void:
	if not _hose_at_guest or _hose_holder == holder:
		return
	_hose_holder = holder
	_set_holders_hold(holder)
	var master := holder == _player
	_hose.piece = _player.piece_color() if master else Color(holder.call("piece_color"))
	_player.set_piece_hidden(master)
	_hose_use(func() -> Vector2: return _object_valve(HOOKAH_OBJECT_ID), func() -> Vector2: return _holder_end(holder),
		func() -> Vector2: return _aim_to_mouth(holder), false)
	_hose_cover_fn = func() -> Vector2: return _object_base(HOOKAH_OBJECT_ID)
	_hose_cover_id = HOOKAH_OBJECT_ID


## Рука с ручкой шланга вперёд только у того, кто держит шланг.
func _set_holders_hold(holder: Node2D) -> void:
	_player.set_holding(holder == _player)
	for node in _objects.values():
		if node is Friend:
			(node as Friend).set_holding(holder == node)


## Кто-то начал затяжку: берёт шланг в руку.
func _hose_take(holder: Node2D) -> void:
	if _hose_at_guest and is_object_visible(HOOKAH_OBJECT_ID):
		_hose_held_by(holder)


## Никто не курит: шланг с мундштуком гостя ложится на стол, мундштук мастера возвращается на шею.
func _hose_release_if_idle() -> void:
	if _hose == null or not _hose_at_guest or _warming_up or _player.is_smoking():
		return
	for node in _objects.values():
		if node is Friend and (node as Friend).is_smoking():
			return
	_hose_holder = null
	_set_holders_hold(null)
	_hose.piece = _guest_piece
	_player.set_piece_hidden(false)
	_hose_use(func() -> Vector2: return _object_valve(HOOKAH_OBJECT_ID), func() -> Vector2: return _object_base(HOOKAH_OBJECT_ID) + Vector2(-17, 3),
		func() -> Vector2: return Vector2(-0.9, 0.3), true)


## Мастер вставляет шланг в кальян: берёт конец со стола, подключает к клапану, надевает свой мундштук с шеи.
func _insert_hose() -> void:
	if _hose == null or not _hose.shown:
		return
	var base := _object_base(HOOKAH_PREP_OBJECT_ID)
	_player.face_toward(base.x)
	_player.set_holding(true)
	_hose_use(func() -> Vector2: return base + PREP_HOSE_START, func() -> Vector2: return _holder_end(_player),
		func() -> Vector2: return _aim_to_mouth(_player), true)
	_hose.flat = true
	await get_tree().create_timer(0.6).timeout
	_hose_use(func() -> Vector2: return _object_valve(HOOKAH_PREP_OBJECT_ID), func() -> Vector2: return _holder_end(_player),
		func() -> Vector2: return _aim_to_mouth(_player), false)
	_hose_cover_fn = func() -> Vector2: return _object_base(HOOKAH_PREP_OBJECT_ID)
	_hose_cover_id = HOOKAH_PREP_OBJECT_ID
	_hose_start_smooth = true
	await get_tree().create_timer(0.7).timeout
	_hose.piece = _player.piece_color()
	_player.set_piece_hidden(true)
	await get_tree().create_timer(0.4).timeout
	_player.set_holding(false)


## Сброс шланга (отладка): кальяна нет — шланга тоже.
func reset_hose() -> void:
	if _hose == null:
		return
	_hose.show_hose(false)
	_hose_holder = null
	_hose_at_guest = false
	_warming_up = false
	_player.set_piece_hidden(false)
	_player.set_holding(false)


## Гость берёт из коробочки случайный мундштук (он пропадает из коробки) — пока мастер раскуривает кальян.
func _guest_takes_mouthpiece() -> void:
	var table: Variant = _objects.get("table_guest")
	if table is GarageObject:
		_guest_piece = (table as GarageObject).take_box_piece()
	for node in _objects.values():
		if node is Friend:
			(node as Friend).set_piece_color(_guest_piece)
	if _hose_at_guest and _hose_holder != null and _hose_holder != _player:
		_hose.piece = _guest_piece


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


func _walk_to(target_cell: Vector2i) -> void:
	if target_cell.x < 0:
		return
	var path := _grid.find_path(Vector2i(_player.grid_position.floor()), target_cell)
	_player.walk_path(path)
	await _player.auto_walk_finished


func _walk_carrying(target_cell: Vector2i) -> void:
	_player.set_carrying_hookah(_hookah_color)
	_player.set_holding(true)
	await _walk_to(target_cell)
	_player.set_carrying(null)
	_player.set_holding(false)


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
		_hose_release_if_idle()


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
	if _seat_cell.x >= 0:
		_grid.set_blocked_rect(Rect2i(_seat_cell, Vector2i.ONE), false)
	var path := _grid.find_path(Vector2i(_player.grid_position.floor()), _seat_cell)
	if not path.is_empty():
		_player.walk_path(path)
		await _player.auto_walk_finished
	_player.sit_down()
	_player.focus_camera(SIT_CAMERA_ZOOM, _sit_focus_offset())
	_prompt.hide_prompt()
	_player.set_smoking(true)
	_sitting_busy = false
	_pending_smoke_message = message
	_puffs_until_message = randi_range(2, 5)


## Камера смещается к середине между игроком и гостем (чтобы оба были в кадре).
func _sit_focus_offset() -> Vector2:
	for node in _objects.values():
		if node is Friend:
			return ((node as Friend).position - _player.position) * 0.5 + Vector2(0, -14)
	return Vector2.ZERO


## Гость делает count затяжек (корутина; ждёт сигналов затяжек именно этого гостя).
func wait_for_friend_puffs(guest_id: String, count: int) -> void:
	if not (_objects.get(guest_id) is Friend):
		return
	var remaining := count
	while remaining > 0:
		var who: String = await friend_inhaled
		if who == guest_id:
			remaining -= 1
	await get_tree().create_timer(1.1).timeout


func _on_player_inhale(_duration: float) -> void:
	if _pending_smoke_message.is_empty() or not _player.seated:
		return
	_puffs_until_message -= 1
	if _puffs_until_message <= 0:
		message_requested.emit(_pending_smoke_message)
		_pending_smoke_message = ""


func _on_player_stood_up() -> void:
	# Стул снова становится непроходимым, как только игрок из него вышел.
	if _seat_cell.x >= 0:
		_pending_blocks.append(Rect2i(_seat_cell, Vector2i.ONE))
	_pending_smoke_message = ""
	_on_focus_changed(_interactions.focus)
	_emoji_source_id = ""
	_player.set_smoking(false)
	_hose_release_if_idle()
