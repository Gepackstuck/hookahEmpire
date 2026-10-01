class_name GarageWorld
extends Node2D
## Корень сцены гаража: собирает мир из data-описания и связывает игрока, NPC,
## систему взаимодействий и подсказку. Игровых правил здесь нет.

## Гость сделал затяжку (Main считает их для повторной просьбы).
signal friend_inhaled(guest_id: String)
signal message_requested(text: String)
signal dialogue_requested(dialogue_id: String)
signal action_requested(action_id: String)
signal image_requested(texture_path: String, title: String, description: String)
signal friend_arrived(guest_id: String)

const LAYOUT_PATH := "res://data/garage/garage_main.json"
const PLAYER_SCENE := preload("res://scenes/characters/Player.tscn")
const FRIEND_SCENE := preload("res://scenes/characters/Friend.tscn")
const DOOR_OBJECT_ID := "door_main"
const HOOKAH_OBJECT_ID := "hookah_test"
const HOOKAH_PREP_OBJECT_ID := "hookah_prep"
const SHELF_OBJECT_ID := "shelf_hookah"
const GAZE_RADIUS := 2.6
const SINK_OBJECT_ID := "sink_wash"
const WASH_MIN_SECONDS := 3.0
const WASH_MAX_SECONDS := 5.0
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
## guest_id -> {"entry_position", "entry_cell", "stand_cell"}: откуда пришёл гость и где сидит (чтобы уйти тем же путём).
var _guest_routes: Dictionary = {}

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
	_camera_bounds = GarageBackdrop.screen_bounds(layout.size)
	_player.set_camera_limits(_camera_bounds)

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
	_update_gazes()
	_update_pointer_hover()


## Кальянщик, стоя спокойно рядом с севшим гостем, поворачивается к нему (лицом/спиной/боком); иначе — профиль.
func _update_gazes() -> void:
	var partner: Friend = null
	for node in _objects.values():
		if node is Friend and (node as Friend).has_arrived:
			var friend := node as Friend
			if friend.grid_position.distance_to(_player.grid_position) <= GAZE_RADIUS:
				partner = friend
				break
	for node in _objects.values():
		if node is Friend and node != partner and (node as Friend).has_arrived:
			(node as Friend).look_straight()
	if partner != null and _player.is_idle() and not _player.seated and not _player.is_carrying_hookah():
		# Сидящий гость остаётся в профиле (сидит на стуле как обычно); поворачивается только кальянщик.
		partner.look_straight()
		_player.look_toward(partner.position - _player.position)
	elif partner != null:
		partner.look_straight()


## Мышь: предметы с картинками (маски, книги) и свиток подсвечиваются при наведении, клик — смотреть/открыть.
var _camera_bounds := Rect2i()
var _pointer_enabled := true
var _hover_object: GarageObject = null
var _hover_hit: Dictionary = {}


## true — камера ходит за кальянщиком; false — стоит по центру помещения.
func set_camera_follow(follow: bool) -> void:
	if _player != null:
		_player.set_camera_follow(follow, _camera_bounds)


func set_pointer_enabled(value: bool) -> void:
	_pointer_enabled = value
	if not value:
		_clear_hover()


func _clear_hover() -> void:
	if _hover_object != null and is_instance_valid(_hover_object):
		_hover_object.set_hover({})
	_hover_object = null
	_hover_hit = {}
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _update_pointer_hover() -> void:
	if not _pointer_enabled:
		return
	var mouse := get_global_mouse_position()
	var found: GarageObject = null
	var hit: Dictionary = {}
	for node in _objects.values():
		if node is GarageObject and (node as GarageObject).visible:
			var candidate := node as GarageObject
			var result := candidate.hit_test(candidate.to_local(mouse))
			if not result.is_empty():
				found = candidate
				hit = result
				break
	if found != _hover_object and _hover_object != null and is_instance_valid(_hover_object):
		_hover_object.set_hover({})
	_hover_object = found
	_hover_hit = hit
	if found != null:
		found.set_hover(hit)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if _pointer_enabled and _hover_object != null and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var kind := str(_hover_hit.get("kind", ""))
		if kind == "image":
			image_requested.emit(str(_hover_hit["texture"]), str(_hover_hit["title"]), str(_hover_hit.get("description", "")))
		elif kind == "book":
			action_requested.emit("open_recipe_book")
		get_viewport().set_input_as_handled()
		return
	_handle_key_input(event)


func _handle_key_input(event: InputEvent) -> void:
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
	# Клетка стула могла остаться заблокированной после предыдущего гостя.
	var stand_rect := Rect2i(stand_cell, Vector2i.ONE)
	_pending_blocks.erase(stand_rect)
	_grid.set_blocked_rect(stand_rect, false)
	var path := _grid.find_path(entry_cell, stand_cell)
	if path.is_empty():
		GameLog.error("garage", "spawn_friend: нет пути от %s до %s" % [str(entry_cell), str(stand_cell)])
		return false
	path.push_front(entry_position)

	var friend := FRIEND_SCENE.instantiate() as Friend
	_entities.add_child(friend)
	friend.setup(str(guest["id"]), str(guest["emoji"]), entry_position, str(guest.get("sprite_faces", "right")) == "right")
	friend.apply_look(guest.get("look", {}))
	_guest_routes[friend.guest_id] = {"entry_position": entry_position, "entry_cell": entry_cell, "stand_cell": stand_cell}
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


## Реплика над головой персонажа ("player" или id гостя); возвращает длительность показа (0 — некому говорить).
func say(who: String, text: String, emoji: String = "") -> float:
	# Говорит один: облачка собеседников не должны перекрываться.
	if who != "player" and _player != null:
		_player.clear_speech()
	for key in _objects:
		var other: Variant = _objects[key]
		if other is Friend and str(key) != who:
			(other as Friend).clear_speech()
	if who == "player" and _player != null:
		return _player.say(text)
	var node: Variant = _objects.get(who)
	return (node as Friend).say(text, emoji) if node is Friend else 0.0


## Чипы-эмодзи над головой персонажа ("player" или id гостя).
func set_chips(who: String, chips: Array) -> void:
	if who == "player" and _player != null:
		_player.set_chips(chips)
		return
	var node: Variant = _objects.get(who)
	if node is Friend:
		(node as Friend).set_chips(chips)


func clear_chips(who: String) -> void:
	set_chips(who, [])


## Убирает все надписи над головами (выход из режима NPC).
func clear_all_head_labels() -> void:
	if _player != null:
		_player.head_labels().clear_all()
	for node in _objects.values():
		if node is Friend:
			(node as Friend).head_labels().clear_all()


## Видимость работы у объекта (idle): у раковины льётся вода, остальное — только поза/эмодзи над головой.
func set_idle_work(object_id: String, on: bool) -> void:
	if object_id == SINK_OBJECT_ID:
		var sink: Variant = _objects.get(SINK_OBJECT_ID)
		if sink is GarageObject:
			(sink as GarageObject).set_washing(on)


func has_object(object_id: String) -> bool:
	return _objects.get(object_id) is GarageObject


## Игрок идёт к объекту (клетка перед ним) и поворачивается к нему, например к столу смешивания.
func walk_to_object(object_id: String) -> void:
	var node: Variant = _objects.get(object_id)
	if not (node is GarageObject) or _player == null:
		return
	var target := (node as GarageObject).front_cell()
	if _grid.is_cell_walkable(target):
		await _walk_to(target)
	_player.face_toward((node as GarageObject).position.x)


## Идентификатор диалога гостя (для автопилота: «поговорить» без нажатия E).
func friend_dialogue_id(guest_id: String) -> String:
	var data := _interactions.find_by_id(guest_id)
	return data.dialogue_id if data != null else ""


## Игрок подходит к гостю (клетка рядом с его стулом) и поворачивается к нему.
func walk_to_friend(guest_id: String) -> void:
	var node: Variant = _objects.get(guest_id)
	var route: Dictionary = _guest_routes.get(guest_id, {})
	if not (node is Friend) or route.is_empty() or _player == null:
		return
	var stand: Vector2i = route["stand_cell"]
	var player_cell := Vector2i(_player.grid_position.floor())
	# Заказ принимаем у угла стола (там же, где подаём кальян): сбоку от гостя, лицом к нему.
	if _serve_cell.x >= 0 and _grid.is_cell_walkable(_serve_cell) and not _grid.find_path(player_cell, _serve_cell).is_empty():
		await _walk_to(_serve_cell)
		_player.face_toward((node as Friend).position.x)
		return
	# Подходим сбоку от гостя (вдоль стола), а не со спины; со спины — только если сбоку не пройти.
	for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var cell: Vector2i = stand + offset
		if _grid.is_cell_walkable(cell) and not _grid.find_path(player_cell, cell).is_empty():
			await _walk_to(cell)
			break
	_player.face_toward((node as Friend).position.x)


## Есть ли в гараже гость (идёт, сидит или ждёт).
func has_friend() -> bool:
	for node in _objects.values():
		if node is Friend:
			return true
	return false


## Гость встаёт со стула, идёт к двери, выходит (дверь открывается и закрывается), стул освобождается.
## Корутина: завершается, когда гость ушёл и убран из гаража.
func friend_leave(guest_id: String) -> void:
	var node: Variant = _objects.get(guest_id)
	if not (node is Friend) or _grid == null:
		return
	var friend := node as Friend
	var route: Dictionary = _guest_routes.get(guest_id, {})
	_interactions.unregister(guest_id)
	# Приход гостя больше не должен срабатывать на этот путь.
	for connection in friend.arrived.get_connections():
		friend.arrived.disconnect(connection["callable"])
	friend.set_smoking(false)
	friend.stand_up()
	_hose_release_if_idle()
	var stand_cell: Vector2i = route.get("stand_cell", Vector2i(friend.grid_position.floor()))
	var stand_rect := Rect2i(stand_cell, Vector2i.ONE)
	_pending_blocks.erase(stand_rect)
	_grid.set_blocked_rect(stand_rect, false)
	var exit_position: Vector2 = route.get("entry_position", friend.grid_position)
	var path := _grid.find_path(Vector2i(friend.grid_position.floor()), route.get("entry_cell", stand_cell))
	path.append(exit_position)
	# Пустой стул снова непроходим (иначе сквозь него можно ходить).
	_pending_blocks.append(stand_rect)
	var done := [false]
	friend.arrived.connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	friend.walk_path(path)
	var door: Variant = _objects.get(DOOR_OBJECT_ID)
	var door_opened := false
	while not done[0]:
		if door is GarageObject and not door_opened and friend.grid_position.distance_to(exit_position) < 3.0:
			door_opened = true
			(door as GarageObject).set_door_open(true)
		await get_tree().process_frame
	friend.visible = false
	if door is GarageObject:
		await (door as GarageObject).set_door_open(false, 0.45)
	_player.smoke_emitter().partner = null
	_objects.erase(guest_id)
	_guest_routes.erase(guest_id)
	friend.queue_free()
	GameLog.info("garage", "Гость %s ушёл" % guest_id)


## Кальянщик убирает кальян после ухода гостя: забирает его со стола гостя вместе со шлангом,
## несёт к раковине, моет колбу и шланг 3–5 секунд (вода, брызги) и ставит обратно на полку.
## Корутина: завершается, когда кальян стоит на полке. Ввод на время уборки блокируется.
func wash_hookah_and_shelve() -> void:
	if _player == null or _grid == null:
		return
	var was_locked := _input_locked
	set_input_locked(true)
	if _player.seated and not _sitting_busy:
		_player.stand_up()
	if is_object_visible(HOOKAH_OBJECT_ID):
		await _walk_to(_serve_cell)
		_player.face_toward(_object_base(HOOKAH_OBJECT_ID).x)
		await get_tree().create_timer(0.25).timeout
		hide_object(HOOKAH_OBJECT_ID)
		_hose_holder = null
		_hose_at_guest = false
		_warming_up = false
		_hose.piece = _guest_piece
		_player.set_piece_hidden(false)
		_hose_carried()
		_player.set_carrying_hookah(_hookah_color)
		_player.set_holding(true)
		var sink: Variant = _objects.get(SINK_OBJECT_ID)
		if sink is GarageObject:
			await _walk_to((sink as GarageObject).front_cell())
			_player.face_toward((sink as GarageObject).position.x)
			# Кальян — в раковине под краном (его качает кальянщик), шланг тянется к клапану.
			var basin := sink as GarageObject
			_player.set_carrying(null)
			_hose_use(func() -> Vector2: return basin.wash_valve_position(), func() -> Vector2: return _holder_end(_player),
				func() -> Vector2: return _aim_to_mouth(_player), false, true)
			basin.set_washing(true, _hookah_color)
			await get_tree().create_timer(randf_range(WASH_MIN_SECONDS, WASH_MAX_SECONDS)).timeout
			basin.set_washing(false)
			_player.set_carrying_hookah(_hookah_color, 0)
			_player.set_holding(true)
			_hose_carried()
		var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
		if shelf is GarageObject:
			var rack := shelf as GarageObject
			var taken := rack.taken_hookah_slots()
			if not taken.is_empty():
				var slot: int = taken.pick_random()
				await _walk_to(rack.shelf_front_cell(slot))
				await get_tree().create_timer(0.3).timeout
				rack.put_hookah(slot, _hookah_color)
		_player.set_carrying(null)
	hide_object(HOOKAH_PREP_OBJECT_ID)
	reset_hose()
	set_input_locked(was_locked)


## true — в коробке у стола гостя меньше min_count мундштуков.
func mouthpieces_low(min_count: int = 2) -> bool:
	var table: Variant = _objects.get("table_guest")
	return table is GarageObject and (table as GarageObject).box_piece_count() < min_count


## Кальянщик подходит вплотную к коробке с мундштуками (клетка рядом, поворот к столу гостя).
func walk_to_mouthpiece_box() -> void:
	var table: Variant = _objects.get("table_guest")
	if not (table is GarageObject) or _player == null or _grid == null:
		return
	var box := (table as GarageObject).mouthpiece_box_grid_position()
	if box.x < 0.0:
		return
	var base := Vector2i(box.floor())
	var best := Vector2i(-1, -1)
	var best_dist := INF
	var here := _player.grid_position
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, -1)]:
		var cell := base + offset
		if not _grid.is_cell_walkable(cell):
			continue
		var dist := Vector2(cell).distance_to(here)
		if dist < best_dist:
			best_dist = dist
			best = cell
	if best.x >= 0:
		await _walk_to(best)
	_player.face_toward((table as GarageObject).position.x)


## Докладывает мундштуки в коробку у стола гостя, если их там меньше min_count. true — докладывал.
func top_up_mouthpieces(min_count: int = 2) -> bool:
	var table: Variant = _objects.get("table_guest")
	return table is GarageObject and (table as GarageObject).top_up_box(min_count)


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
	var prep: Variant = _objects.get(HOOKAH_PREP_OBJECT_ID)
	if prep is GarageObject:
		_player.face_toward((prep as GarageObject).position.x)
		# Сначала угли на чашу, затем чаша на кальян, и только потом шланг.
		await (prep as GarageObject).play_pack_sequence()
	await _insert_hose()
	# Шланг вставлен: 2–3 затяжки у стола для кальянов, и только потом несём к гостю.
	await _warm_up_puffs(2, 3)
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
	(hookah as GarageObject).set_hookah_top(0 if object_id == HOOKAH_PREP_OBJECT_ID else 2)
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
		_hose.cover_top = (cover_node as GarageObject).hookah_top() if cover_node is GarageObject else 0
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


## Раскурка кальянщиком: min_puffs–max_puffs коротких тяжек.
func _warm_up_puffs(min_puffs: int = 2, max_puffs: int = 4) -> void:
	var puffs := randi_range(min_puffs, max_puffs)
	for i in puffs:
		await _player.puff(randf_range(0.5, 1.3))
		await get_tree().create_timer(randf_range(0.2, 0.5)).timeout


## Кальян на столе сплющивается на время затяжки (курит игрок или гость).
func _on_inhale(duration: float) -> void:
	var hookah: Variant = _objects.get(HOOKAH_OBJECT_ID)
	if hookah is GarageObject and (hookah as GarageObject).visible:
		(hookah as GarageObject).squash(duration)
	var prep: Variant = _objects.get(HOOKAH_PREP_OBJECT_ID)
	if prep is GarageObject and (prep as GarageObject).visible and (prep as GarageObject).hookah_top() >= 1:
		(prep as GarageObject).squash(duration)


func _walk_to(target_cell: Vector2i) -> void:
	if target_cell.x < 0:
		return
	var path := _grid.find_path(Vector2i(_player.grid_position.floor()), target_cell)
	_player.walk_path(path)
	await _player.auto_walk_finished


func _walk_carrying(target_cell: Vector2i, top: int = 2) -> void:
	_player.set_carrying_hookah(_hookah_color, top)
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
