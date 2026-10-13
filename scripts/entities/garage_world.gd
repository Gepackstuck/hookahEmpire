class_name GarageWorld
extends Node2D
## Корень сцены гаража: собирает мир из data-описания и связывает игрока, NPC,
## систему взаимодействий и подсказку. Игровых правил здесь нет.

## Гость сделал затяжку (Main считает их для повторной просьбы).
signal friend_inhaled(guest_id: String)
signal player_inhaled
signal message_requested(text: String)
signal dialogue_requested(dialogue_id: String)
signal action_requested(action_id: String)
signal image_requested(texture_path: String, title: String, description: String)
signal friend_arrived(guest_id: String)
## M12: гость без места дошёл до точки ожидания у входа (отсчёт его терпения запускает Main).
signal waiting_guest_arrived(guest_id: String)

const LAYOUT_PATH := "res://data/garage/garage_main.json"
const PLAYER_SCENE := preload("res://scenes/characters/Player.tscn")
const FRIEND_SCENE := preload("res://scenes/characters/Friend.tscn")
const DOOR_OBJECT_ID := "door_main"
const HOOKAH_OBJECT_ID := "hookah_test"
const HOOKAH_PREP_OBJECT_ID := "hookah_prep"
const SHELF_OBJECT_ID := "shelf_hookah"
const GAZE_RADIUS := 2.6
const SINK_OBJECT_ID := "sink_wash"
## Сколько секунд кальянщик набирает воду в колбу.
const FLASK_FILL_SECONDS := 1.8
const WASH_MIN_SECONDS := 3.0
const WASH_MAX_SECONDS := 5.0
## Где шланг лежит на столе для кальянов (от основания кальяна): в свободном заднем правом углу, между предметами.
const PREP_HOSE_START := Vector2(10.0, 0.0)
const PREP_HOSE_END := Vector2(40.0, 12.0)
const FRIEND_TALK_PROMPT := "Поговорить"
const SIT_CAMERA_ZOOM := 3.0
const FRIEND_TALK_RADIUS := 1.4
## M12: где стоит гость, для которого нет места (по порядку, берётся первая свободная клетка с путём от двери).
const WAIT_CELL_CANDIDATES: Array[Vector2i] = [Vector2i(3, 9), Vector2i(3, 10), Vector2i(2, 9), Vector2i(2, 10), Vector2i(4, 10), Vector2i(3, 11)]

var _grid: GarageGrid = null
var _layout: GarageLayout = null
## M9: мебель (создаётся из Main через setup_furniture).
var _furniture_layer: FurnitureLayer = null
var _interactions := InteractionSystem.new()
var _player: Player = null
var _objects: Dictionary = {} # id -> Node2D (GarageObject или Friend)
var _buddy: Buddy = null # M10: Бэн — друг без заказов, живёт вне _objects
var _emoji_source_id := ""
var _highlighted: GarageObject = null
var _serve_cell := Vector2i(-1, -1)
var _coal_cell := Vector2i(-1, -1)
var _prep_cell := Vector2i(-1, -1)
var _seat_cell := Vector2i(-1, -1)
var _sitting_busy := false
## M12: кальяны в мире. _u — «активный» (тот, что мастер сейчас готовит, несёт или ставит); у каждого кальяна свой шланг и состояние.

## station_id -> подпись сборки места (uid стола, uid стула, прямоугольник стола, клетка стула).
var _extra_signatures: Dictionary = {}
## Место, у стола которого игрок взаимодействовал последним (Main узнаёт, к какому гостю относится действие).
var _last_action_station_id := GuestStation.MAIN_ID
var _last_interacted_id := ""
## Занятые места на диване: ключ места -> guest_id.
var _sofa_taken: Dictionary = {}
var _u: HookahUnit = HookahUnit.new()
var _units: Array[HookahUnit] = []
## Места гостей за столами: id -> GuestStation (s1 из раскладки, s2 из купленных стола и стула).
var _stations: Dictionary = {}
## guest_id -> id места, за которым он сидит.
var _guest_station: Dictionary = {}
## Спутники компании: guest_id -> true (кальян и заказ у них общие с гостем другого места).
var _companions: Dictionary = {}
## Место, за столом которого кальянщик работает сейчас (подаёт, курит).
var _player_station: GuestStation = null
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
	# Порядок отрисовки считаем сами (см. _sort_entities): одного y мало для длинных объектов вроде полки и вывесок.
	_entities.y_sort_enabled = false
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	if not layout.is_valid():
		for message in layout.errors:
			GameLog.error("garage", message)
		return

	_layout = layout
	_grid = GarageGrid.new(layout.size)
	_backdrop.setup(layout.size)
	_serve_cell = layout.hookah_serve_cell
	_prep_cell = layout.hookah_prep_cell
	_coal_cell = layout.hookah_coal_cell
	_seat_cell = layout.player_seat_cell
	var main_station := GuestStation.new()
	main_station.id = GuestStation.MAIN_ID
	main_station.table_id = "table_guest"
	main_station.table_uid = "table_guest"
	main_station.hookah_id = HOOKAH_OBJECT_ID
	main_station.serve_cell = _serve_cell
	main_station.coal_cell = _coal_cell
	main_station.seat_cell = _seat_cell
	_stations[main_station.id] = main_station
	_player_station = main_station
	_build_objects(layout)
	# Стулья гостей непроходимы и пока пустые (в раскладке они не блокируют, чтобы путь гостя и проверки мебели считали клетку свободной).
	# При приходе гостя spawn_friend освобождает его клетку на время расчёта пути, после ухода она блокируется снова.
	for node in _objects.values():
		if node is GarageObject and (node as GarageObject).is_chair():
			_grid.set_blocked_rect(Rect2i(Vector2i((node as GarageObject).sort_rect().position.floor()), Vector2i.ONE), true)
	# Стул игрока непроходим, пока на нём не сидят (иначе сквозь него можно ходить).
	if _seat_cell.x >= 0:
		_grid.set_blocked_rect(Rect2i(_seat_cell, Vector2i.ONE), true)

	_player = PLAYER_SCENE.instantiate() as Player
	_entities.add_child(_player)
	_player.setup(_grid, layout.player_spawn)
	_player.inhale_started.connect(_on_inhale)
	_player.inhale_started.connect(_on_player_inhale)
	_player.inhale_started.connect(func(_duration: float) -> void: _hose_take(_player))
	_units.append(_u)
	_u.hose = _make_hose()
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
	_sort_entities()
	_try_apply_pending_blocks()
	_update_hose(delta)
	_interactions.update_focus(_player.grid_position)
	_update_marker(delta)
	_update_gazes()
	_sync_buddy_hire_rect()
	_update_pointer_hover()


## Порядок отрисовки: сначала по y (как y-sort), затем персонажи переставляются относительно крупных объектов:
## персонаж, стоящий ближе к камере за краем объекта (по x или по y), рисуется поверх него, а стоящий дальше — под ним.
func _sort_entities() -> void:
	var nodes: Array[Node2D] = []
	for child in _entities.get_children():
		if child is Node2D:
			nodes.append(child as Node2D)
	if nodes.size() < 2:
		return
	var order: Dictionary = {}
	for i in nodes.size():
		order[nodes[i]] = i
	nodes.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		if is_equal_approx(a.position.y, b.position.y):
			return int(order[a]) < int(order[b])
		return a.position.y < b.position.y)
	var larges: Array[GarageObject] = []
	var chairs: Array[GarageObject] = []
	var characters: Array[Node2D] = []
	for node in nodes:
		if node is GarageObject:
			if (node as GarageObject).is_sort_large() and node.visible:
				larges.append(node as GarageObject)
			elif (node as GarageObject).is_chair() and node.visible:
				chairs.append(node as GarageObject)
		elif (node is Player and not (node as Player).seated) or (node is Friend and not (node as Friend).is_seated()):
			characters.append(node)
	# Кальян стоит на столе: порядок по y даёт «за столом» для левой половины длинного стола и срезает основание.
	# Кальян, стоящий над столом, рисуется сразу поверх этого стола.
	for node in nodes.duplicate():
		if node is GarageObject and (node as GarageObject).is_hookah() and node.visible:
			var hookah_at := (node as GarageObject).sort_rect().get_center()
			for large in larges:
				if large != node and large.sort_rect().has_point(hookah_at):
					nodes.erase(node)
					nodes.insert(nodes.find(large) + 1, node)
					break
	for character in characters:
		var at: Vector2 = character.get("grid_position")
		for large in larges:
			var rect := large.sort_rect()
			var in_front := at.y >= rect.end.y or at.x >= rect.end.x
			var behind := at.y <= rect.position.y or at.x <= rect.position.x
			if in_front == behind:
				continue
			var ci := nodes.find(character)
			var oi := nodes.find(large)
			if in_front and ci < oi:
				nodes.remove_at(ci)
				nodes.insert(nodes.find(large) + 1, character)
			elif behind and ci > oi:
				nodes.remove_at(ci)
				nodes.insert(nodes.find(large), character)
	# Сидящий (гость или кальянщик) рисуется поверх своего стула (спинка у него за спиной), но под столом.
	for node in nodes.duplicate():
		var is_seated_person := (node is Friend and (node as Friend).is_seated()) or (node is Player and (node as Player).seated)
		if is_seated_person and node is Friend and _guest_routes.get((node as Friend).guest_id, {}).has("sofa_key"):
			# Гость на диване рисуется поверх дивана (иначе левое место «уходит под диван»).
			var sofa_at: Vector2 = node.get("grid_position")
			for large in larges:
				if large.sort_rect().grow(0.3).has_point(sofa_at):
					nodes.erase(node)
					nodes.insert(nodes.find(large) + 1, node)
					break
			continue
		if is_seated_person:
			var at: Vector2 = node.get("grid_position")
			var seat: GarageObject = null
			var best := 1.2
			for chair in chairs:
				var distance := chair.sort_rect().get_center().distance_to(at)
				if distance < best:
					best = distance
					seat = chair
			if seat != null and nodes.find(node) < nodes.find(seat):
				nodes.erase(node)
				nodes.insert(nodes.find(seat) + 1, node)
	for i in nodes.size():
		if nodes[i].get_index() != i:
			_entities.move_child(nodes[i], i)


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


## Свободная камера на время расстановки мебели: begin → pan (смещение мыши в пикселях) → end.
func begin_free_camera() -> void:
	if _player != null:
		_player.begin_free_camera()


func pan_camera(screen_delta: Vector2) -> void:
	if _player != null:
		_player.pan_camera(screen_delta)


func end_free_camera() -> void:
	if _player != null:
		_player.end_free_camera()


## M9: подключает систему мебели: комната берётся из описания гаража, мебель рисуется в мире и блокирует клетки сетки.
func setup_furniture(system: FurnitureSystem) -> void:
	if _layout == null or _grid == null or system == null:
		return
	system.set_room_from_layout(_layout)
	var rugs := Node2D.new()
	rugs.name = "Rugs"
	add_child(rugs)
	move_child(rugs, _entities.get_index())
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.name = "FurnitureLayer"
	add_child(_furniture_layer)
	_furniture_layer.setup(system, _grid, _entities, rugs)
	_furniture_layer.validator = _furniture_validator


## Облачка и чипы над головами делаем полупрозрачными (например, пока открыто окно мебели).
func set_head_labels_alpha(alpha: float) -> void:
	if _player != null:
		_player.head_labels().modulate.a = alpha
	for node in _objects.values():
		if node is Friend:
			(node as Friend).head_labels().modulate.a = alpha
	if _buddy != null and is_instance_valid(_buddy.friend):
		_buddy.friend.head_labels().modulate.a = alpha


func furniture_layer() -> FurnitureLayer:
	return _furniture_layer


## Нельзя ставить непроходимую мебель туда, где сейчас стоит игрок или гость (иначе они застрянут).
func _furniture_validator(item_id: String, cell: Vector2, rotation: int, _uid: String) -> String:
	var system := _furniture_layer.system
	var data := system.item(item_id)
	if data.is_empty() or not bool(data["blocks"]) or str(data["placement"]) == "wall":
		return ""
	var rect := system.rect_of(item_id, cell, rotation).grow(0.05)
	for body in _character_bodies():
		if rect.intersects(body):
			return "Здесь стоит персонаж"
	return ""


## Прямоугольники (в клетках), которые сейчас занимают игрок и гости.
func _character_bodies() -> Array[Rect2]:
	var bodies: Array[Rect2] = []
	if _player != null:
		var half := Player.HALF_EXTENT + 0.1
		bodies.append(Rect2(_player.grid_position - Vector2(half, half), Vector2(half, half) * 2.0))
	for node in _objects.values():
		if node is Friend:
			var friend_pos: Vector2 = (node as Friend).grid_position
			bodies.append(Rect2(friend_pos - Vector2(0.4, 0.4), Vector2(0.8, 0.8)))
	if _buddy != null and is_instance_valid(_buddy.friend):
		bodies.append(Rect2(_buddy.friend.grid_position - Vector2(0.4, 0.4), Vector2(0.8, 0.8)))
	return bodies


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
		elif kind == "boombox":
			action_requested.emit("toggle_boombox")
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
func spawn_friend(guest: Dictionary, entry_position: Vector2, entry_cell: Vector2i, stand_cell: Vector2i, dialogue_id: String, seat: Dictionary = {}, station_id: String = GuestStation.MAIN_ID, companion_of: String = "") -> bool:
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
	if companion_of != "":
		# Спутник сидит на своём месте, но шланг, кальян и мундштук — гостя с места companion_of.
		_companions[friend.guest_id] = true
		_guest_station[friend.guest_id] = companion_of
		if _stations.has(station_id):
			(_stations[station_id] as GuestStation).companion_id = friend.guest_id
	else:
		_guest_station[friend.guest_id] = station_id
		if _stations.has(station_id):
			(_stations[station_id] as GuestStation).guest_id = friend.guest_id
	_wire_seated_friend(friend)
	friend.arrived.connect(_on_friend_arrived.bind(friend, guest, stand_cell, dialogue_id, seat))
	GameLog.info("garage", "%s заходит в гараж" % str(guest["name"]))
	_enter_through_door(friend, path)
	return true


## Затяжки сидящего гостя: дым, шланг его кальяна и сигнал для Main.
func _wire_seated_friend(friend: Friend) -> void:
	friend.inhale_started.connect(func(duration: float) -> void: _on_inhale(duration, friend))
	# Игрок и гость не тянут кальян одновременно: между их затяжками есть пауза.
	friend.smoke_emitter().partner = _player.smoke_emitter()
	_player.smoke_emitter().partner = friend.smoke_emitter()
	friend.inhale_started.connect(func(_duration: float) -> void: friend_inhaled.emit(friend.guest_id))
	friend.inhale_started.connect(func(_duration: float) -> void: _hose_take(friend))


## M12: гость приходит, а сесть негде: заходит через дверь и стоит у входа (без разговора и заказа), пока Main не отправит его обратно.
func spawn_waiting_guest(guest: Dictionary, entry_position: Vector2, entry_cell: Vector2i) -> bool:
	if _grid == null:
		return false
	var wait_cell := Vector2i(-1, -1)
	var path: Array[Vector2] = []
	# Сначала диван: ждать удобнее сидя (края дивана; центр — место Бэна, на него гости не садятся).
	var sofa_seat: Dictionary = {}
	for seat: Dictionary in _sofa_seats():
		if _sofa_taken.has(seat["key"]):
			continue
		var approach: Vector2i = seat["approach"]
		if not _grid.is_cell_walkable(approach):
			continue
		var sofa_path := _grid.find_path(entry_cell, approach)
		if sofa_path.is_empty():
			continue
		sofa_seat = seat
		wait_cell = approach
		path = sofa_path
		break
	if wait_cell.x < 0:
		for cell in WAIT_CELL_CANDIDATES:
			if not _grid.is_cell_walkable(cell):
				continue
			path = _grid.find_path(entry_cell, cell)
			if not path.is_empty():
				wait_cell = cell
				break
	if wait_cell.x < 0:
		GameLog.error("garage", "spawn_waiting_guest: нет свободной клетки ожидания с путём от двери")
		return false
	path.push_front(entry_position)
	var friend := FRIEND_SCENE.instantiate() as Friend
	_entities.add_child(friend)
	friend.setup(str(guest["id"]), str(guest.get("emoji", "")), entry_position, str(guest.get("sprite_faces", "right")) == "right")
	friend.apply_look(guest.get("look", {}))
	friend.set_meta("waiting_guest", true)
	var route := {"entry_position": entry_position, "entry_cell": entry_cell, "stand_cell": wait_cell, "waiting": true}
	if not sofa_seat.is_empty():
		route["sofa_key"] = sofa_seat["key"]
		route["approach_point"] = Vector2(wait_cell) + Vector2(0.5, 0.5)
		route["seat_point"] = sofa_seat["point"]
		route["face_left"] = sofa_seat["face_left"]
		_sofa_taken[sofa_seat["key"]] = friend.guest_id
	_guest_routes[friend.guest_id] = route
	_objects[friend.guest_id] = friend
	friend.arrived.connect(_on_waiting_guest_arrived.bind(friend, wait_cell), CONNECT_ONE_SHOT)
	GameLog.info("garage", "%s заходит в гараж и ждёт места" % str(guest.get("name", friend.guest_id)))
	_enter_through_door(friend, path)
	return true


func _on_waiting_guest_arrived(friend: Friend, wait_cell: Vector2i) -> void:
	var route: Dictionary = _guest_routes.get(friend.guest_id, {})
	if route.has("sofa_key"):
		waiting_guest_arrived.emit(friend.guest_id)
		_sofa_sit(friend, route)
		return
	# Клетка ожидающего становится непроходимой, как только игрок из неё вышел (как у сидящих гостей).
	_pending_blocks.append(Rect2i(wait_cell, Vector2i.ONE))
	waiting_guest_arrived.emit(friend.guest_id)


## Гость подходит к дивану, делает шаг к своему месту и садится.
func _sofa_sit(friend: Friend, route: Dictionary) -> void:
	var step: Array[Vector2] = [route["seat_point"]]
	friend.walk_path(step)
	await friend.arrived
	if not is_instance_valid(friend) or _guest_routes.get(friend.guest_id, {}).get("sofa_key", "") != route["sofa_key"]:
		return
	await friend.sit_down_animated(bool(route["face_left"]), false)


## Места для ожидающих на диване: два по краям каждого дивана длиной от трёх клеток (центр занят Бэном).
func _sofa_seats() -> Array[Dictionary]:
	var seats: Array[Dictionary] = []
	if _furniture_layer == null or _furniture_layer.system == null:
		return seats
	var system := _furniture_layer.system
	for entry: Dictionary in system.placed_entries():
		if str(entry["item"]) != "couch":
			continue
		var rect := system.entry_rect(entry)
		var along_x := rect.size.x >= rect.size.y
		if maxf(rect.size.x, rect.size.y) < 3.0:
			continue
		var center := rect.get_center()
		for side in [-1, 1]:
			var offset := float(side)
			var point := center + (Vector2(offset, 0.12) if along_x else Vector2(0.12, offset))
			var approach := Vector2i(floori(center.x + offset), ceili(rect.end.y - 0.001)) if along_x else Vector2i(ceili(rect.end.x - 0.001), floori(center.y + offset))
			seats.append({"key": "%s:%d" % [str(entry["uid"]), side], "point": point, "approach": approach, "face_left": along_x})
	return seats


## Ожидающий гость встаёт (с дивана или от двери) и идёт занимать освободившееся место за столом.
func seat_waiting_guest(guest_id: String, station_id: String, companion_of: String = "") -> void:
	var friend := _objects.get(guest_id) as Friend
	var station := _station(station_id)
	if friend == null or station == null or station.guest_id != "" or station.companion_id != "" or not bool(friend.get_meta("waiting_guest", false)):
		return
	var guest := GuestCatalog.load_guest(guest_id)
	if guest.is_empty():
		return
	var route: Dictionary = _guest_routes.get(guest_id, {})
	var stand_cell := station.guest_cell
	if companion_of != "":
		station.companion_id = guest_id
		_companions[guest_id] = true
		_guest_station[guest_id] = companion_of
	else:
		station.guest_id = guest_id
		_guest_station[guest_id] = station_id
	friend.set_meta("waiting_guest", false)
	for connection in friend.arrived.get_connections():
		friend.arrived.disconnect(connection["callable"])
	friend.stand_up()
	if route.has("sofa_key"):
		_sofa_taken.erase(route["sofa_key"])
		var out: Array[Vector2] = [route["approach_point"]]
		var reached := [false]
		friend.arrived.connect(func() -> void: reached[0] = true, CONNECT_ONE_SHOT)
		friend.walk_path(out)
		while not reached[0]:
			await get_tree().process_frame
	else:
		var wait_rect := Rect2i(route.get("stand_cell", Vector2i(-1, -1)), Vector2i.ONE)
		_pending_blocks.erase(wait_rect)
		_grid.set_blocked_rect(wait_rect, false)
	var stand_rect := Rect2i(stand_cell, Vector2i.ONE)
	_pending_blocks.erase(stand_rect)
	_grid.set_blocked_rect(stand_rect, false)
	var path := _grid.find_path(Vector2i(friend.grid_position.floor()), stand_cell)
	_guest_routes[guest_id] = {"entry_position": route.get("entry_position", friend.grid_position), "entry_cell": route.get("entry_cell", stand_cell), "stand_cell": stand_cell}
	_wire_seated_friend(friend)
	friend.arrived.connect(_on_friend_arrived.bind(friend, guest, stand_cell, "", station_seat(station_id)))
	if path.is_empty():
		# Дойти нельзя: гость просто появляется на месте.
		friend.place_at(Vector2(stand_cell) + Vector2(0.5, 0.5))
		friend.arrived.emit.call_deferred()
		return
	friend.walk_path(path)


## Сколько гостей сейчас в гараже (включая идущих и ждущих места).
func guests_present() -> int:
	var count := 0
	for node in _objects.values():
		if node is Friend:
			count += 1
	return count


## id гостей, которые ждут места (стоят у входа).
func waiting_guest_ids() -> Array[String]:
	var ids: Array[String] = []
	for object_id in _objects:
		var node: Variant = _objects[object_id]
		if node is Friend and bool((node as Friend).get_meta("waiting_guest", false)):
			ids.append(str(object_id))
	return ids


## M10: Бэн заходит в гараж (через дверь) и идёт к wait_cell; при through_door = false появляется сразу (загрузка игры).
## Он не входит в _objects: не гость, у него нет заказа и разговора. Возвращает Buddy (поведение запускает вызывающий через start()).
func spawn_buddy(guest: Dictionary, entry_position: Vector2, entry_cell: Vector2i, wait_cell: Vector2i, guide: IntroGuide, through_door: bool = true) -> Buddy:
	if _grid == null or _player == null:
		return null
	if _buddy != null:
		return _buddy
	var friend := FRIEND_SCENE.instantiate() as Friend
	_entities.add_child(friend)
	friend.setup(str(guest["id"]), str(guest.get("emoji", "")), entry_position, false)
	friend.apply_look(guest.get("look", {}))
	var buddy := Buddy.new()
	buddy.name = "Buddy"
	add_child(buddy)
	buddy.setup(friend, _grid, _player, guide)
	for object_id in guide.ben.get("interests", {}):
		var node: Variant = _objects.get(object_id)
		if node is GarageObject:
			buddy.interests[object_id] = {"cell": (node as GarageObject).front_cell(), "position": (node as GarageObject).position}
	_buddy = buddy
	var path := _grid.find_path(entry_cell, wait_cell) if through_door else ([] as Array[Vector2])
	if path.is_empty():
		friend.place_at(Vector2(wait_cell) + Vector2(0.5, 0.5))
		friend.arrived.emit.call_deferred()
	else:
		path.push_front(entry_position)
		_enter_through_door(friend, path)
	GameLog.info("garage", "%s заходит в гараж" % str(guest.get("name", "Бэн")))
	return buddy


func buddy() -> Buddy:
	return _buddy


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


## M7: состояние углей кальяна на столе гостя (0 остыли … 3 сгорели) и эмодзи-индикатор над ним.
func set_hookah_heat(coal_state: int, badge: String, subtle_badge: bool = false, station_id: String = GuestStation.MAIN_ID) -> void:
	var station := _station(station_id)
	if station == null:
		return
	var hookah: Variant = _objects.get(station.hookah_id)
	if hookah is GarageObject:
		(hookah as GarageObject).set_coal_state(coal_state)
		(hookah as GarageObject).set_badge(badge, subtle_badge)


## Кальянщик меняет угли на кальяне гостя: подходит к столу (если стоит далеко), снимает старые, кладёт свежие.
## Корутина: завершается, когда на кальяне свежие угли.
func _service_coals_impl(seconds: float, station_id: String = GuestStation.MAIN_ID) -> void:
	var station := _station(station_id)
	if station == null or _player == null:
		return
	var hookah: Variant = _objects.get(station.hookah_id)
	if not (hookah is GarageObject):
		return
	# Угли меняют со стороны стола, где лежит лоток со свежими углями.
	var work_cell := station.coal_cell if station.coal_cell.x >= 0 and _grid.is_cell_walkable(station.coal_cell) else station.serve_cell
	if work_cell.x >= 0 and Vector2(work_cell).distance_to(_player.grid_position) > 1.2:
		await _walk_to(work_cell)
	_player.face_toward((hookah as GarageObject).position.x)
	await (hookah as GarageObject).play_coal_swap(seconds)


## Видимость работы у объекта (idle): у раковины льётся вода, остальное — только поза/эмодзи над головой.
func set_idle_work(object_id: String, on: bool) -> void:
	if object_id == SINK_OBJECT_ID:
		var sink: Variant = _objects.get(SINK_OBJECT_ID)
		if sink is GarageObject:
			(sink as GarageObject).set_washing(on)


## Прерывает идущую автоматическую ходьбу кальянщика (например, когда у гостя появилось настоящее дело).
func cancel_walk() -> void:
	# Кальянщик занят переносом/мойкой: чужая отмена ходьбы сломала бы это действие.
	if _action_busy:
		return
	if _player != null:
		_player.cancel_auto_walk()


const JUGGLE_COLORS: Array[Color] = [Color("#ff7a1a"), Color("#22b8ff"), Color("#7bd62f"), Color("#ff4f9a"), Color("#b574ff"), Color("#ffd23a")]


## Ждёт seconds секунд; false — если stop() вернул true (появилось настоящее дело).
func _idle_wait(seconds: float, stop: Callable) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		if stop.call():
			return false
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	return not stop.call()


## Действие простоя кальянщика у объекта target (кальянщик уже стоит у него).
## action: wash, gaze, look_mask, look_book, swap, juggle, think, read, pat, drink, stand.
## stop — Callable без аргументов: true, когда надо бросить всё и идти работать. По окончании всё возвращается на место.
func play_idle_action(target: String, action: String, seconds: float, stop: Callable) -> void:
	if _player == null:
		return
	var node: Variant = _objects.get(target)
	match action:
		"wash":
			await _idle_wash(node, seconds, stop, true)
		"gaze":
			await _idle_wash(node, seconds, stop, false)
		"juggle", "drink", "think", "read", "pat":
			var colors: Array = JUGGLE_COLORS.duplicate()
			colors.shuffle()
			_player.set_gesture(action, colors.slice(0, 3))
			await _idle_wait(seconds, stop)
		"look_mask", "look_book":
			await _idle_look(node, action == "look_mask", seconds, stop)
		"swap":
			await _idle_swap(node, seconds, stop)
		_:
			await _idle_wait(seconds, stop)
	_player.clear_gesture()


## Кальянщик пьёт молоко на месте (кнопка 🥛): жест, реплика над головой.
func play_drink(seconds: float, line: String) -> void:
	if _player == null:
		return
	_player.set_gesture("drink")
	say("player", line)
	await get_tree().create_timer(seconds).timeout
	_player.clear_gesture()


func _idle_wash(node: Variant, seconds: float, stop: Callable, scrub: bool) -> void:
	var sink := node as GarageObject
	if sink != null:
		var color := _u.color
		color.a = 1.0
		sink.set_washing(true, color if scrub else Color(0, 0, 0, 0), "flask" if randf() < 0.5 else "hose")
	if scrub:
		_player.set_gesture("scrub")
	await _idle_wait(seconds, stop)
	if sink != null:
		sink.set_washing(false)


## Берёт с полки маску или книгу, рассматривает (покачивает в руках) и кладёт обратно.
func _idle_look(node: Variant, mask: bool, seconds: float, stop: Callable) -> void:
	var shelf := node as GarageObject
	if shelf == null:
		await _idle_wait(seconds, stop)
		return
	var options: Array = []
	for candidate: Dictionary in shelf.image_props():
		if str(candidate["texture"]).contains("mask") == mask:
			options.append(candidate)
	if options.is_empty():
		await _idle_wait(seconds, stop)
		return
	var entry: Dictionary = options.pick_random()
	var index := int(entry["index"])
	var texture := shelf.prop_texture(index)
	if texture == null:
		await _idle_wait(seconds, stop)
		return
	shelf.set_prop_hidden(index, true)
	_player.set_carrying(texture, minf(float(entry["height"]) * 1.4, 36.0))
	_player.set_holding(true)
	var elapsed := 0.0
	while elapsed < seconds and not stop.call():
		_player.set_carried_rotation(sin(elapsed * 1.8) * 0.22)
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	_player.set_carried_rotation(0.0)
	_player.set_carrying(null)
	_player.set_holding(false)
	shelf.set_prop_hidden(index, false)


## Меняет два кальяна на полке местами: берёт первый, у второго меняет в руках и ставит второй на место первого.
func _idle_swap(node: Variant, seconds: float, stop: Callable) -> void:
	var shelf := node as GarageObject
	var present: Array = shelf.free_hookah_slots() if shelf != null else []
	if present.size() < 2:
		_player.set_gesture("juggle", JUGGLE_COLORS.slice(0, 3))
		await _idle_wait(seconds, stop)
		return
	present.shuffle()
	var a: int = present[0]
	var b: int = present[1]
	# Чаще берём кальяны подальше друг от друга, чтобы переход был заметен.
	for candidate: int in present:
		if candidate != a and absi(candidate - a) >= 2:
			b = candidate
			break
	var color_a := shelf.hookah_slot_color(a)
	var color_b := shelf.hookah_slot_color(b)
	var stage := 0
	while true:
		await _walk_to(shelf.shelf_front_cell(a))
		if stop.call():
			break
		_player.face_toward(shelf.position.x)
		shelf.take_hookah(a)
		_player.set_carrying_hookah(color_a, 0)
		_player.set_holding(true)
		stage = 1
		if not await _idle_wait(0.7, stop):
			break
		await _walk_to(shelf.shelf_front_cell(b))
		if stop.call():
			break
		shelf.put_hookah(b, color_a)
		_player.set_carrying_hookah(color_b, 0)
		stage = 2
		if not await _idle_wait(0.9, stop):
			break
		await _walk_to(shelf.shelf_front_cell(a))
		if stop.call():
			break
		shelf.put_hookah(a, color_b)
		_player.set_carrying(null)
		_player.set_holding(false)
		stage = 3
		await _idle_wait(0.6, stop)
		break
	# Прервали посередине — возвращаем всё на полку как есть.
	if stage == 1:
		shelf.put_hookah(a, color_a)
	elif stage == 2:
		shelf.put_hookah(a, color_b)
	if stage != 3:
		_player.set_carrying(null)
		_player.set_holding(false)


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
	var serve_cell: Vector2i = _station_for(guest_id).serve_cell
	var player_cell := Vector2i(_player.grid_position.floor())
	# Заказ принимаем у угла стола (там же, где подаём кальян): сбоку от гостя, лицом к нему.
	if serve_cell.x >= 0 and _grid.is_cell_walkable(serve_cell) and not _grid.find_path(player_cell, serve_cell).is_empty():
		await _walk_to(serve_cell)
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
		if node is Friend and not bool((node as Friend).get_meta("waiting_guest", false)):
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
	# Гость уходит — спутник уходит вместе с ним.
	if not _companions.has(guest_id):
		var buddy := companion_at(str(_guest_station.get(guest_id, GuestStation.MAIN_ID)))
		if buddy != "":
			friend_leave(buddy)
	# Приход гостя больше не должен срабатывать на этот путь.
	for connection in friend.arrived.get_connections():
		friend.arrived.disconnect(connection["callable"])
	friend.set_smoking(false)
	friend.stand_up()
	_hose_release_if_idle()
	# С дивана сначала выходим к клетке перед ним (идти по сетке из занятой клетки дивана нельзя).
	if route.has("sofa_key"):
		_sofa_taken.erase(route["sofa_key"])
		var out: Array[Vector2] = [route["approach_point"]]
		var out_done := [false]
		friend.arrived.connect(func() -> void: out_done[0] = true, CONNECT_ONE_SHOT)
		friend.walk_path(out)
		while not out_done[0]:
			await get_tree().process_frame
	var stand_cell: Vector2i = route.get("stand_cell", Vector2i(friend.grid_position.floor()))
	var stand_rect := Rect2i(stand_cell, Vector2i.ONE)
	_pending_blocks.erase(stand_rect)
	_grid.set_blocked_rect(stand_rect, false)
	var exit_position: Vector2 = route.get("entry_position", friend.grid_position)
	var path := _grid.find_path(Vector2i(friend.grid_position.floor()), route.get("entry_cell", stand_cell))
	path.append(exit_position)
	# Пустой стул снова непроходим (иначе сквозь него можно ходить); клетка ожидания у входа остаётся свободной.
	if not bool(route.get("waiting", false)):
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
	var left_station_id := str(_guest_station.get(guest_id, GuestStation.MAIN_ID))
	_guest_station.erase(guest_id)
	if _companions.has(guest_id):
		_companions.erase(guest_id)
		for station: GuestStation in _stations.values():
			if station.companion_id == guest_id:
				station.companion_id = ""
	if _stations.has(left_station_id) and (_stations[left_station_id] as GuestStation).guest_id == guest_id:
		(_stations[left_station_id] as GuestStation).guest_id = ""
	friend.queue_free()
	GameLog.info("garage", "Гость %s ушёл" % guest_id)


# --- Очередь действий кальянщика ---------------------------------------------------------
## Кальянщик один: переносы кальяна, мойка и замена углей идут по очереди (иначе два гостя ломают состояние кальянов — у каждого свой шланг).
var _action_busy := false


## Кальянщик сейчас занят действием с кальяном (перенос, мойка, угли).
func is_action_busy() -> bool:
	return _action_busy


func _lock_action() -> void:
	while _action_busy:
		await get_tree().process_frame
	_action_busy = true


func _unlock_action() -> void:
	_action_busy = false


func fetch_random_hookah() -> void:
	await _lock_action()
	await _fetch_random_hookah_impl()
	_unlock_action()


func carry_hookah_to_guest_table(station_id: String = GuestStation.MAIN_ID) -> void:
	await _lock_action()
	await _carry_hookah_to_guest_table_impl(station_id)
	_unlock_action()


func carry_hookah_to_prep_table(station_id: String = GuestStation.MAIN_ID) -> void:
	await _lock_action()
	await _carry_hookah_to_prep_table_impl(station_id)
	_unlock_action()


func wash_hookah_and_shelve(station_id: String = GuestStation.MAIN_ID) -> void:
	await _lock_action()
	await _wash_hookah_and_shelve_impl(station_id)
	_unlock_action()


## Гости, которые закреплены за местом, но ещё не дошли до него.
func walking_guest_ids() -> Array[String]:
	var result: Array[String] = []
	for station: GuestStation in _stations.values():
		for guest_id in [station.guest_id, station.companion_id]:
			if str(guest_id) == "":
				continue
			var node: Variant = _objects.get(str(guest_id))
			if node is Friend and not (node as Friend).has_arrived:
				result.append(str(guest_id))
	return result


## Страховка от «вечно идущего» гостя: ставит его на место и садит, как будто он дошёл.
func force_seat(guest_id: String) -> bool:
	var node: Variant = _objects.get(guest_id)
	var route: Dictionary = _guest_routes.get(guest_id, {})
	if not (node is Friend) or route.is_empty() or not route.has("stand_cell"):
		return false
	var friend := node as Friend
	var stand: Vector2i = route["stand_cell"]
	friend.visible = true
	friend.stop_walking()
	friend.place_at(Vector2(stand) + Vector2(0.5, 0.5))
	friend.arrived.emit()
	return true


## Места, кальян которых забрал мыть Бэн (кальянщик их не трогает).
var _wash_claims: Dictionary = {}


## Бэн занимает место под мойку; false — кальянщик уже занят действием или место занято.
func claim_wash(station_id: String) -> bool:
	if _action_busy or _wash_claims.has(station_id):
		return false
	_wash_claims[station_id] = true
	return true


func release_wash(station_id: String) -> void:
	_wash_claims.erase(station_id)


## На месте стоит кальян (его нужно убрать, если гостя уже нет).
func station_has_hookah(station_id: String) -> bool:
	var station := _station(station_id)
	return station != null and station.unit != null and is_object_visible(station.hookah_id)


## Бэн убирает кальян брошенного места: забирает со стола, моет в раковине, ставит на полку.
func buddy_wash_hookah(station_id: String) -> void:
	var station := _station(station_id)
	if station == null or not buddy_ready() or not station_has_hookah(station_id):
		return
	var unit := station.unit
	if station.serve_cell.x >= 0 and _grid.is_cell_walkable(station.serve_cell):
		await _buddy.job_walk(station.serve_cell)
	if not buddy_ready() or station.unit != unit or unit == null or not is_object_visible(station.hookah_id):
		return
	_buddy.friend.look_toward(_object_base(station.hookah_id) - _buddy.friend.position)
	await get_tree().create_timer(0.25).timeout
	if station.unit != unit or not is_object_visible(station.hookah_id):
		return
	hide_object(station.hookah_id)
	unit.holder = null
	unit.at_guest = false
	unit.warming_up = false
	unit.station = null
	station.unit = null
	unit.start_fn = Callable()
	if unit.hose != null:
		unit.hose.show_hose(false)
	var color := unit.color
	var sink: Variant = _objects.get(SINK_OBJECT_ID)
	if sink is GarageObject and buddy_ready():
		var basin := sink as GarageObject
		await _buddy.job_walk(basin.front_cell())
		if buddy_ready():
			_buddy.friend.look_toward(basin.position - _buddy.friend.position)
			basin.set_washing(true, color)
			await get_tree().create_timer(randf_range(WASH_MIN_SECONDS, WASH_MAX_SECONDS)).timeout
			basin.set_washing(false)
	var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
	if shelf is GarageObject and buddy_ready():
		var rack := shelf as GarageObject
		var taken := rack.taken_hookah_slots()
		if not taken.is_empty():
			var slot: int = taken.pick_random()
			await _buddy.job_walk(rack.shelf_front_cell(slot))
			await get_tree().create_timer(0.3).timeout
			rack.put_hookah(slot, color)
	_discard_unit(unit)


# --- Бэн-помощник (второй кальянщик) ---

const BUDDY_HIRE_ID := "friend_ben"


## Бэн в гараже, дошёл и может работать.
func buddy_ready() -> bool:
	return _buddy != null and is_instance_valid(_buddy.friend) and _buddy.friend.has_arrived


func buddy_working() -> bool:
	return _buddy != null and _buddy.is_working()


func buddy_begin_job() -> void:
	if _buddy != null:
		await _buddy.begin_job()


func buddy_end_job() -> void:
	if _buddy != null:
		_buddy.end_job()


func buddy_say(text: String, emoji: String = "") -> void:
	if buddy_ready():
		_buddy.friend.say(text, emoji)


func buddy_phone(on: bool) -> void:
	if buddy_ready():
		_buddy.friend.set_phone(on)


func buddy_emotion(emoji: String, seconds: float = 2.5) -> void:
	if buddy_ready():
		_buddy.friend.show_emotion(emoji, seconds)


## Включает/выключает разговор с Бэном (найм): точка взаимодействия ходит за ним.
func set_buddy_hire(on: bool) -> void:
	if _buddy == null:
		return
	var data := _interactions.find_by_id(BUDDY_HIRE_ID)
	if data == null:
		if not on:
			return
		data = InteractableData.new()
		data.id = BUDDY_HIRE_ID
		data.display_name = "Бэн"
		data.prompt = "Поговорить с Бэном"
		data.dialogue_id = "ben_hire"
		data.radius = 1.4
		_interactions.register(data)
	data.enabled = on
	_buddy_hire_on = on
	_sync_buddy_hire_rect()
	_interactions.refocus()


var _buddy_hire_on := false


func _sync_buddy_hire_rect() -> void:
	if not _buddy_hire_on or _buddy == null or not is_instance_valid(_buddy.friend):
		return
	var data := _interactions.find_by_id(BUDDY_HIRE_ID)
	if data != null:
		data.rect = Rect2(_buddy.friend.grid_position - Vector2(0.5, 0.5), Vector2.ONE)


## Бэн меняет угли у кальяна места: идёт к лотку, меняет угли (анимация кальяна та же, что у кальянщика).
func buddy_service_coals(seconds: float, station_id: String) -> void:
	var station := _station(station_id)
	if station == null or not buddy_ready():
		return
	var hookah: Variant = _objects.get(station.hookah_id)
	if not (hookah is GarageObject):
		return
	var work_cell := station.coal_cell if station.coal_cell.x >= 0 and _grid.is_cell_walkable(station.coal_cell) else station.serve_cell
	if work_cell.x >= 0 and _grid.is_cell_walkable(work_cell):
		await _buddy.job_walk(work_cell)
	if not buddy_ready():
		return
	_buddy.friend.look_toward((hookah as GarageObject).position - _buddy.friend.position)
	await (hookah as GarageObject).play_coal_swap(seconds)


## Расстояние от стола для кальянов до места гостя (чем дальше, тем охотнее кальян готовит Бэн).
func serve_distance_from_prep(station_id: String) -> float:
	var station := _station(station_id)
	if station == null or station.serve_cell.x < 0 or _prep_cell.x < 0:
		return 0.0
	return Vector2(station.serve_cell).distance_to(Vector2(_prep_cell))


## Бэн готовит кальян целиком по упрощённой схеме: берёт с полки, наливает колбу, забивает и ставит гостю.
## Возвращает true, если кальян стоит на столе гостя. Кальянщика не блокирует (у Бэна свой кальян-юнит).
func buddy_serve_hookah(station_id: String) -> bool:
	var station := _station(station_id)
	if station == null or not buddy_ready() or station.unit != null or not (_objects.get(station.hookah_id) is GarageObject):
		return false
	var color := Color.html(HookahArt.PALETTE.pick_random())
	var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
	if shelf is GarageObject and (shelf as GarageObject).hookah_slot_count() > 0:
		var rack := shelf as GarageObject
		var free := rack.free_hookah_slots()
		if free.is_empty():
			rack.restock_hookahs()
			free = rack.free_hookah_slots()
		if not free.is_empty():
			var slot: int = free.pick_random()
			await _buddy.job_walk(rack.shelf_front_cell(slot))
			if not buddy_ready():
				return false
			await get_tree().create_timer(0.3).timeout
			color = rack.hookah_slot_color(slot)
			rack.take_hookah(slot)
	var sink: Variant = _objects.get(SINK_OBJECT_ID)
	if sink is GarageObject and buddy_ready():
		var basin := sink as GarageObject
		await _buddy.job_walk(basin.front_cell())
		if buddy_ready():
			_buddy.friend.look_toward(basin.position - _buddy.friend.position)
			basin.set_washing(true, Color(0, 0, 0, 0), "flask")
			await get_tree().create_timer(FLASK_FILL_SECONDS).timeout
			basin.set_washing(false)
	var prep: Variant = _objects.get(HOOKAH_PREP_OBJECT_ID)
	if prep is GarageObject and _prep_cell.x >= 0 and buddy_ready():
		await _buddy.job_walk(_prep_cell)
		if buddy_ready():
			_buddy.friend.look_toward((prep as GarageObject).position - _buddy.friend.position)
			await get_tree().create_timer(2.2).timeout
	if not buddy_ready() or station.unit != null:
		return false
	if station.serve_cell.x >= 0 and _grid.is_cell_walkable(station.serve_cell):
		await _buddy.job_walk(station.serve_cell)
	if not buddy_ready() or station.unit != null:
		return false
	var hookah := _objects.get(station.hookah_id) as GarageObject
	# Синхронно подменяем активный юнит (кальянщик может нести свой), чтобы не ломать его шланг.
	var previous := _u
	var unit := _new_unit()
	unit.color = color
	unit.handle_style = randi_range(0, HoseLine.HANDLE_STYLES - 1)
	unit.hose.color = color
	unit.hose.handle_style = unit.handle_style
	station.unit = unit
	unit.station = station
	unit.at_guest = true
	_u = unit
	_guest_takes_mouthpiece(station)
	_u = previous
	_buddy.friend.look_toward(hookah.position - _buddy.friend.position)
	hookah.set_hookah_color(color)
	hookah.set_hookah_top(2)
	await hookah.drop_in()
	_hose_release_if_idle(station)
	return true


## Бэн идёт к коробке мундштуков, в которой их меньше всего.
func buddy_walk_to_mouthpiece_box() -> void:
	if not buddy_ready():
		return
	var table: GarageObject = null
	for candidate in _box_tables():
		if table == null or candidate.box_piece_count() < table.box_piece_count():
			table = candidate
	if table == null:
		return
	var box := table.mouthpiece_box_grid_position()
	if box.x < 0.0:
		return
	var base := Vector2i(box.floor())
	var best := Vector2i(-1, -1)
	var best_dist := INF
	var here := _buddy.friend.grid_position
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i.ZERO]:
		var cell := base + offset
		if not _grid.is_cell_walkable(cell):
			continue
		var dist := Vector2(cell).distance_to(here)
		if dist < best_dist:
			best_dist = dist
			best = cell
	if best.x >= 0:
		await _buddy.job_walk(best)
	if buddy_ready():
		_buddy.friend.look_toward(table.position - _buddy.friend.position)


func service_coals(seconds: float, station_id: String = GuestStation.MAIN_ID) -> void:
	await _lock_action()
	await _service_coals_impl(seconds, station_id)
	_unlock_action()


## Кальянщик убирает кальян после ухода гостя: забирает его со стола гостя вместе со шлангом,
## несёт к раковине, моет колбу и шланг 3–5 секунд (вода, брызги) и ставит обратно на полку.
## Корутина: завершается, когда кальян стоит на полке. Ввод на время уборки блокируется.
func _wash_hookah_and_shelve_impl(station_id: String = GuestStation.MAIN_ID) -> void:
	if _player == null or _grid == null:
		return
	var station := _station(station_id)
	if station == null:
		return
	var was_locked := _input_locked
	set_input_locked(true)
	if _player.seated and not _sitting_busy:
		_player.stand_up()
	var unit := station.unit
	if unit != null and is_object_visible(station.hookah_id) and not _wash_claims.has(station_id):
		var previous := _u
		_u = unit
		await _walk_to(station.serve_cell)
		_player.face_toward(_object_base(station.hookah_id).x)
		await get_tree().create_timer(0.25).timeout
		hide_object(station.hookah_id)
		_u.holder = null
		_u.at_guest = false
		_u.warming_up = false
		_u.station = null
		station.unit = null
		_u.hose.piece = _u.guest_piece
		_player.set_piece_hidden(false)
		_hose_carried()
		_player.set_carrying_hookah(_u.color)
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
			basin.set_washing(true, _u.color)
			await get_tree().create_timer(randf_range(WASH_MIN_SECONDS, WASH_MAX_SECONDS)).timeout
			basin.set_washing(false)
			_player.set_carrying_hookah(_u.color, 0)
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
				rack.put_hookah(slot, _u.color)
		_player.set_carrying(null)
		reset_hose()
		_discard_unit(unit)
		_u = previous
	set_input_locked(was_locked)


## true — в коробке у стола гостя меньше min_count мундштуков.
func mouthpieces_low(min_count: int = 2) -> bool:
	for table in _box_tables():
		if table.box_piece_count() < min_count:
			return true
	return false


## Столы гостей с коробкой мундштуков (у каждого стола своя коробка).
func _box_tables() -> Array[GarageObject]:
	var tables: Array[GarageObject] = []
	for station: GuestStation in _stations.values():
		var table: Variant = _objects.get(station.table_id)
		if table is GarageObject and (table as GarageObject).mouthpiece_box_grid_position().x >= 0.0 and not tables.has(table):
			tables.append(table as GarageObject)
	return tables


## Сколько мундштуков сейчас в коробках на всех столах гостей.
func mouthpiece_count() -> int:
	var total := 0
	for table in _box_tables():
		total += table.box_piece_count()
	return total


## Кальянщик подходит вплотную к коробке с мундштуками (клетка рядом, поворот к столу): к той, где их меньше всего.
func walk_to_mouthpiece_box() -> void:
	var table: GarageObject = null
	for candidate in _box_tables():
		if table == null or candidate.box_piece_count() < table.box_piece_count():
			table = candidate
	if table == null or _player == null or _grid == null:
		return
	var box := table.mouthpiece_box_grid_position()
	if box.x < 0.0:
		return
	var base := Vector2i(box.floor())
	var best := Vector2i(-1, -1)
	var best_dist := INF
	var here := _player.grid_position
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i.ZERO]:
		var cell := base + offset
		if not _grid.is_cell_walkable(cell):
			continue
		var dist := Vector2(cell).distance_to(here)
		if dist < best_dist:
			best_dist = dist
			best = cell
	if best.x >= 0:
		await _walk_to(best)
	_player.face_toward(table.position.x)


## Докладывает мундштуки во все коробки на столах гостей, где их меньше min_count. true — докладывал.
func top_up_mouthpieces(min_count: int = 2) -> bool:
	var topped := false
	for table in _box_tables():
		if table.top_up_box(min_count):
			topped = true
	return topped


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
func _fetch_random_hookah_impl() -> void:
	if _player == null or _grid == null:
		return
	var was_locked := _input_locked
	set_input_locked(true)
	reset_hose()
	_u.handle_style = randi_range(0, HoseLine.HANDLE_STYLES - 1)
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
	_u.color = color
	_player.set_carrying_hookah(color)
	await get_tree().create_timer(0.2).timeout
	await _fill_flask_at_sink()
	await _walk_to(_prep_cell)
	_player.set_carrying(null)
	await _place_hookah(HOOKAH_PREP_OBJECT_ID)
	set_input_locked(was_locked)


## Перед забивкой кальянщик набирает колбу водой в раковине (кальян в руках, вода течёт из крана).
func _fill_flask_at_sink() -> void:
	var sink: Variant = _objects.get(SINK_OBJECT_ID)
	if not (sink is GarageObject) or _player == null or _grid == null:
		return
	var basin := sink as GarageObject
	await _walk_to(basin.front_cell())
	_player.face_toward(basin.position.x)
	basin.set_washing(true, Color(0, 0, 0, 0), "flask")
	await get_tree().create_timer(FLASK_FILL_SECONDS * 0.5).timeout
	# Колба наполнилась: вода видна в кальяне, который кальянщик держит в руках.
	_player.set_carrying_hookah(_u.color, HookahArt.TOP_WATERED)
	await get_tree().create_timer(FLASK_FILL_SECONDS * 0.5).timeout
	basin.set_washing(false)


## Цвет текущего кальяна (взятого с полки).
func hookah_color() -> Color:
	return _u.color


## Полка заново заставляется кальянами (отладка/сброс).
## Докупленные кальяны на полке (нижний ряд).
func set_shelf_extra(count: int) -> void:
	var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
	if shelf is GarageObject:
		(shelf as GarageObject).set_extra_hookahs(count)


func shelf_hookah_total() -> int:
	var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
	return (shelf as GarageObject).hookah_slot_count() if shelf is GarageObject else 0


func restock_shelf() -> void:
	var shelf: Variant = _objects.get(SHELF_OBJECT_ID)
	if shelf is GarageObject:
		(shelf as GarageObject).restock_hookahs()


## Игрок несёт кальян к столу гостя: вставляет шланг в кальян, берёт кальян и конец шланга,
## идёт к точке подачи, ставит кальян на стол гостя и раскуривает.
## Корутина: завершается, когда кальян стоит на столе. Ввод на время переноса блокируется.
func _carry_hookah_to_guest_table_impl(station_id: String = GuestStation.MAIN_ID) -> void:
	var station := _station(station_id)
	if station == null or _player == null or _grid == null or not (_objects.get(station.hookah_id) is GarageObject):
		return
	var was_locked := _input_locked
	set_input_locked(true)
	_player_station = station
	# Кальянщик может быть где угодно (например, у стола смешивания после перезабивки): сначала идёт к столу для кальянов.
	if _prep_cell.x >= 0 and Vector2(_prep_cell).distance_to(_player.grid_position) > 1.2:
		await _walk_to(_prep_cell)
	var prep: Variant = _objects.get(HOOKAH_PREP_OBJECT_ID)
	if prep is GarageObject:
		_player.face_toward((prep as GarageObject).position.x)
		# Сначала угли на чашу, затем чаша на кальян, и только потом шланг.
		await (prep as GarageObject).play_pack_sequence()
	await _insert_hose()
	# Шланг вставлен: 2–3 затяжки у стола для кальянов, и только потом несём к гостю.
	await _warm_up_puffs(4, 6, 0.9, 1.8)
	hide_object(HOOKAH_PREP_OBJECT_ID)
	_hose_carried()
	var serve_target := _reachable_serve(station)
	await _walk_carrying(serve_target)
	GameLog.info("garage", "Кальян для места %s подан из клетки %s" % [station.id, str(serve_target)])
	await _place_hookah(station.hookah_id, station)
	_guest_takes_mouthpiece(station)
	_u.warming_up = true
	await _warm_up_puffs()
	_u.warming_up = false
	_hose_release_if_idle(station)
	# Кальян остался у гостя (station.unit); для следующей забивки берём новый.
	_u = _new_unit()
	set_input_locked(was_locked)


## Игрок забирает кальян со стола гостя вместе со шлангом и несёт к столу для кальянов (перезабивка).
func _carry_hookah_to_prep_table_impl(station_id: String = GuestStation.MAIN_ID) -> void:
	var station := _station(station_id)
	if station == null or station.unit == null or _player == null or _grid == null or not (_objects.get(HOOKAH_PREP_OBJECT_ID) is GarageObject):
		return
	if _u.hose != null and _u.hose.shown:
		GameLog.error("garage", "carry_hookah_to_prep_table: стол для кальянов занят другим кальяном")
		return
	var was_locked := _input_locked
	set_input_locked(true)
	_player_station = station
	# Сначала идём к столу гостя за кальяном — кальян не телепортируется, шланг не тянется через гараж.
	if station.serve_cell.x >= 0 and Vector2(station.serve_cell).distance_to(_player.grid_position) > 1.2:
		await _walk_to(station.serve_cell)
	var guest_hookah: Variant = _objects.get(station.hookah_id)
	if guest_hookah is GarageObject:
		_player.face_toward((guest_hookah as GarageObject).position.x)
	hide_object(station.hookah_id)
	# Кальян гостя становится «активным» (его несут к столу для кальянов).
	var unit := station.unit
	station.unit = null
	unit.station = null
	_discard_unit(_u)
	_u = unit
	_u.holder = null
	_u.at_guest = false
	_u.hose.piece = _u.guest_piece
	_player.set_piece_hidden(false)
	_hose_carried()
	await _walk_carrying(_prep_cell)
	await _place_hookah(HOOKAH_PREP_OBJECT_ID)
	set_input_locked(was_locked)


## Ставит кальян нужного цвета на стол (объект появляется с «падением»); шланг ложится рядом
## (на столе для кальянов) или остаётся в руке игрока (на столе гостя, station != null).
func _place_hookah(object_id: String, station: GuestStation = null) -> void:
	var hookah: Variant = _objects.get(object_id)
	if not (hookah is GarageObject):
		return
	# Кальянщик ставит кальян лицом к столу.
	_player.face_toward((hookah as GarageObject).position.x)
	(hookah as GarageObject).set_hookah_color(_u.color)
	(hookah as GarageObject).set_hookah_top(HookahArt.TOP_WATERED if station == null else 2)
	_u.hose.color = _u.color
	_u.hose.handle_style = _u.handle_style
	if station == null:
		_u.hose.piece = Color(0, 0, 0, 0)
		_hose_loose_on_prep(not _u.hose.shown)
	else:
		if station.unit != null and station.unit != _u:
			_discard_unit(station.unit)
		station.unit = _u
		_u.station = station
		_u.at_guest = true
		_hose_held_by(_player)
	await (hookah as GarageObject).drop_in()


# --- Шланг ---------------------------------------------------------------------------------

func _object_base(object_id: String) -> Vector2:
	var node: Variant = _objects.get(object_id)
	return (node as GarageObject).hookah_base_position() if node is GarageObject else Vector2.ZERO


func _object_valve(object_id: String) -> Vector2:
	var node: Variant = _objects.get(object_id)
	return (node as GarageObject).hookah_valve_position() if node is GarageObject else Vector2.ZERO


## Место по id (null — такого места сейчас нет, например второй стол ещё не собран).
func _station(station_id: String) -> GuestStation:
	return _stations.get(station_id) as GuestStation


## Место, за которым сидит гость (по умолчанию основное).
func _station_for(guest_id: String) -> GuestStation:
	return _station(str(_guest_station.get(guest_id, GuestStation.MAIN_ID)))


## id места гостя (чтобы Main мог убрать кальян после его ухода).
func station_id_of(guest_id: String) -> String:
	return str(_guest_station.get(guest_id, GuestStation.MAIN_ID))


## Место того, кто держит/тянет шланг: гость — его место, игрок — место, где он сейчас работает.
func _station_of_table(table_id: String) -> GuestStation:
	for station: GuestStation in _stations.values():
		if station.table_id == table_id:
			return station
	return null


func _station_of_holder(holder: Node2D) -> GuestStation:
	if holder is Friend:
		return _station_for((holder as Friend).guest_id)
	return _player_station


# --- M12: второе место гостя (стол и стул из мебели) ---------------------------------------

## Собирает или убирает дополнительные места (s2, s3) по купленным и поставленным малым столам и стульям вплотную к ним.
## У стола может быть до двух стульев — два места со своими кальянами. Пока за местом сидит гость или стоит кальян, оно не убирается.
func refresh_extra_station() -> void:
	if _furniture_layer == null or _furniture_layer.system == null or _grid == null or _player == null:
		return
	var seats := _furniture_layer.system.find_guest_stations()
	var wanted: Dictionary = {}
	for seat: Dictionary in seats:
		wanted[_station_signature(seat)] = seat
	for station_id in GuestStation.EXTRA_IDS:
		var existing := _station(station_id)
		if existing == null:
			continue
		var signature := str(_extra_signatures.get(station_id, ""))
		var table_alive: bool = _furniture_layer.node_of(signature.split("|")[0]) != null
		if wanted.has(signature) and table_alive:
			wanted.erase(signature)
			continue
		if table_alive and (existing.guest_id != "" or existing.companion_id != "" or existing.unit != null):
			continue
		_teardown_extra_station(station_id)
	for signature in wanted:
		var free_id := ""
		for station_id in GuestStation.EXTRA_IDS:
			if _station(station_id) == null:
				free_id = station_id
				break
		if free_id == "":
			break
		_build_extra_station(free_id, wanted[signature], str(signature))
	_ensure_main_second_seat()


## Второе место за главным столом (стул кальянщика): собирается один раз, когда мир готов.
func _ensure_main_second_seat() -> void:
	if _station(GuestStation.MAIN2_ID) != null or _seat_cell.x < 0 or _player == null:
		return
	var table_node := _objects.get("table_guest") as GarageObject
	if table_node == null:
		return
	var trect := table_node.sort_rect()
	_build_extra_station(GuestStation.MAIN2_ID, {
		"main": true, "table_uid": "table_guest", "chair_uid": "main_chair", "table_rect": trect,
		"chair_cell": _seat_cell, "side": "north",
	}, "main")


## Стул кальянщика свободен для гостя: на нём не сидит игрок и не идёт посадка.
func seat_cell_free() -> bool:
	if _player == null or _player.seated or _sitting_busy:
		return false
	var s4 := _station(GuestStation.MAIN2_ID)
	return s4 == null or s4.guest_id == ""


func _station_signature(seat: Dictionary) -> String:
	return "%s|%s|%s|%s" % [str(seat["table_uid"]), str(seat["chair_uid"]), str(seat["table_rect"]), str(seat["chair_cell"])]


func _build_extra_station(station_id: String, seat: Dictionary, signature: String) -> void:
	var system := _furniture_layer.system
	var is_main := bool(seat.get("main", false))
	var table_node: GarageObject = _objects.get("table_guest") as GarageObject if is_main else _furniture_layer.node_of(str(seat["table_uid"]))
	if table_node == null:
		return
	var trect: Rect2 = seat["table_rect"]
	var chair_cell: Vector2i = seat["chair_cell"]
	var cover := Rect2i(Vector2i(trect.position.floor()), Vector2i(trect.size.ceil())) if is_main else system.cover_cells(trect)
	var player_cell := Vector2i(_player.grid_position.floor())
	# Клетки, которые нельзя брать как клетку подачи: стулья этого стола и подача других мест.
	var blocked_cells: Array[Vector2i] = []
	for other: Dictionary in system.find_guest_stations():
		blocked_cells.append(other["chair_cell"])
	for other_station: GuestStation in _stations.values():
		blocked_cells.append(other_station.serve_cell)
		blocked_cells.append(other_station.coal_cell)
		blocked_cells.append(other_station.guest_cell)
	blocked_cells.append(_seat_cell)
	for node in _objects.values():
		if node is GarageObject and (node as GarageObject).is_chair():
			blocked_cells.append(Vector2i((node as GarageObject).sort_rect().position.floor()))
	var serve := Vector2i(-1, -1)
	var best := INF
	for x in range(cover.position.x - 1, cover.end.x + 1):
		for y in range(cover.position.y - 1, cover.end.y + 1):
			var cell := Vector2i(x, y)
			if cover.has_point(cell) or blocked_cells.has(cell):
				continue
			var beside_x := cell.x >= cover.position.x and cell.x < cover.end.x
			var beside_y := cell.y >= cover.position.y and cell.y < cover.end.y
			if not (beside_x or beside_y):
				continue
			if not _grid.is_cell_walkable(cell):
				continue
			if cell != player_cell and _grid.find_path(player_cell, cell).is_empty():
				continue
			var d := Vector2(cell).distance_to(Vector2(player_cell))
			if d < best:
				best = d
				serve = cell
	if serve.x < 0:
		return
	# К стулу гостя должен быть подход хотя бы с одной стороны.
	var chair_reachable := false
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var near: Vector2i = chair_cell + offset
		if _grid.is_cell_walkable(near) and (near == player_cell or not _grid.find_path(player_cell, near).is_empty()):
			chair_reachable = true
			break
	if not chair_reachable:
		return

	var hookah_id := "hookah_%s" % station_id
	var table_object_id := "table_%s" % station_id
	var lift := 26.0 if is_main else float(system.item("small_table").get("surface_height", 26.0))
	var center := trect.get_center()
	# Кальян стоит на своей стороне стола (ближе к своему гостю), чтобы два кальяна на одном столе не слипались.
	var toward := Vector2(chair_cell) + Vector2(0.5, 0.5) - center
	var anchor := center + (toward.normalized() * 0.2 if toward.length() > 0.01 else Vector2.ZERO) + Vector2(0, 0.05)
	# Порядок отрисовки идёт по x + y: кальян должен стоять «не дальше» центра стола, иначе стол рисуется поверх него
	# и кальян «проваливается» под столешницу.
	var depth_shift := (anchor.x + anchor.y) - (center.x + center.y)
	if depth_shift < 0.12:
		anchor += Vector2.ONE * ((0.12 - depth_shift) * 0.5)
	var hookah := GarageObject.new()
	_entities.add_child(hookah)
	hookah.setup({
		"id": hookah_id, "name": "Кальян", "cell": Vector2i(center.floor()), "size": Vector2i.ONE,
		"anchor": anchor, "blocks": false, "hidden": true, "interaction": {},
		"visual": {"type": "hookah", "color": "#22b8ff", "lift": lift},
	})
	_objects[hookah_id] = hookah
	_objects[table_object_id] = table_node

	var data := InteractableData.new()
	data.id = table_object_id
	data.display_name = "Стол гостя"
	data.prompt = ""
	data.enabled = false
	data.radius = 0.6
	data.rect = Rect2(Vector2(serve), Vector2.ONE)
	_interactions.register(data)

	var station := GuestStation.new()
	station.id = station_id
	station.table_id = table_object_id
	station.table_uid = str(seat["table_uid"])
	station.hookah_id = hookah_id
	station.serve_cell = serve
	station.coal_cell = serve
	station.guest_cell = chair_cell
	# Гость смотрит на стол: стул справа или сверху от стола — влево, слева или снизу — вправо.
	station.seat_faces_left = str(seat["side"]) == "east" or str(seat["side"]) == "north"
	_stations[station.id] = station
	_extra_signatures[station_id] = signature
	GameLog.info("garage", "Место %s готово: стул %s, подача из %s" % [station_id, str(chair_cell), str(serve)])


func _teardown_extra_station(station_id: String) -> void:
	var station := _station(station_id)
	if station != null and station.unit != null:
		_discard_unit(station.unit)
		station.unit = null
	_stations.erase(station_id)
	_interactions.unregister("table_%s" % station_id)
	_objects.erase("table_%s" % station_id)
	var hookah: Variant = _objects.get("hookah_%s" % station_id)
	if hookah is Node:
		(hookah as Node).queue_free()
	_objects.erase("hookah_%s" % station_id)
	if _player_station == station:
		_player_station = _stations[GuestStation.MAIN_ID]
	_extra_signatures.erase(station_id)


## Есть ли готовое место с таким id (s2 появляется после покупки и расстановки стола со стулом).
func has_station(station_id: String) -> bool:
	return _stations.has(station_id)


## Клетка стула гостя за местом.
func station_guest_cell(station_id: String) -> Vector2i:
	var station := _station(station_id)
	return station.guest_cell if station != null and station.guest_cell.x >= 0 else Vector2i(-1, -1)


## Поза гостя за дополнительным местом (как seat в битах истории).
func station_seat(station_id: String) -> Dictionary:
	var station := _station(station_id)
	var left := station != null and station.seat_faces_left
	return {"emoji": "🧘‍♂️", "facing": "left" if left else "right", "lift": 10}


## id объекта (стол или гость), с которым игрок взаимодействовал в последний раз.
func last_interacted_id() -> String:
	return _last_interacted_id


## id места, у стола которого игрок взаимодействовал в последний раз (для Main).
func last_action_station_id() -> String:
	return _last_action_station_id


## Гость, закреплённый за местом (идёт, сидит или уходит), "" — свободно.
func station_guest_id(station_id: String) -> String:
	var station := _station(station_id)
	return station.guest_id if station != null else ""


## Гость места, который уже дошёл и сел ("" — никого нет или ещё идёт).
func station_ready_guest(station_id: String) -> String:
	var guest_id := station_guest_id(station_id)
	if guest_id == "":
		return ""
	var node: Variant = _objects.get(guest_id)
	return guest_id if node is Friend and (node as Friend).has_arrived else ""


## Гость с таким id сейчас в гараже (идёт, сидит, ждёт места или уходит).
func has_guest(guest_id: String) -> bool:
	return _objects.get(guest_id) is Friend


## id объекта-стола места ("" — места нет).
func station_table_id(station_id: String) -> String:
	var station := _station(station_id)
	return station.table_id if station != null else ""


## Уникальный id стола, за которым стоит место (у двух мест одного стола он совпадает).
func station_table_uid(station_id: String) -> String:
	var station := _station(station_id)
	return station.table_uid if station != null else ""


## Место, где кальянщик работает сейчас (по нему определяется, чей это кальян при затяжке игрока).
func player_station_id() -> String:
	return _player_station.id if _player_station != null else GuestStation.MAIN_ID


## Место занято гостем (идущим или сидящим) или на столе стоит кальян.
func station_busy(station_id: String) -> bool:
	var station := _station(station_id)
	return station != null and (station.guest_id != "" or station.companion_id != "" or station.unit != null)


## Место придержано под спутника, который ещё не зашёл (чтобы туда не посадили другого гостя).
func reserve_station(station_id: String) -> void:
	var station := _station(station_id)
	if station != null and station.companion_id == "" and station.guest_id == "":
		station.companion_id = "pending"


func release_station(station_id: String) -> void:
	var station := _station(station_id)
	if station != null and station.companion_id == "pending":
		station.companion_id = ""


## Гость — спутник компании (у него нет своего заказа и кальяна).
func is_companion(guest_id: String) -> bool:
	return _companions.has(guest_id)


## Спутник гостя, сидящего на месте station_id ("" — гость пришёл один).
func companion_at(station_id: String) -> String:
	for guest_id in _companions:
		if str(_guest_station.get(guest_id, "")) == station_id and _objects.get(guest_id) is Friend:
			return str(guest_id)
	return ""


## Спутник уже дошёл и сел.
func companion_ready(station_id: String) -> String:
	var guest_id := companion_at(station_id)
	var node: Variant = _objects.get(guest_id)
	return guest_id if node is Friend and (node as Friend).has_arrived else ""


func _new_unit() -> HookahUnit:
	var unit := HookahUnit.new()
	unit.hose = _make_hose()
	_units.append(unit)
	return unit


## Кальян больше не нужен (убран на полку): убираем его и линию шланга.
func _discard_unit(unit: HookahUnit) -> void:
	if unit == null:
		return
	_units.erase(unit)
	if unit.hose != null:
		unit.hose.queue_free()
		unit.hose = null


func _make_hose() -> HoseLine:
	var hose := HoseLine.new()
	add_child(hose)
	return hose


func _hose_use(start_fn: Callable, end_fn: Callable, aim_fn: Callable, lying: bool, snap: bool = false) -> void:
	_u.start_fn = start_fn
	_u.end_fn = end_fn
	_u.aim_fn = aim_fn
	_u.cover_fn = Callable()
	_u.cover_id = ""
	_u.start_smooth = false
	_u.hose.lying = lying
	_u.hose.flat = false
	if snap:
		_u.hose.start = start_fn.call()
		_u.hose.end = end_fn.call()
	_u.hose.show_hose(true)


func _update_hose(delta: float) -> void:
	for unit in _units:
		_update_unit_hose(unit, delta)


func _update_unit_hose(unit: HookahUnit, delta: float) -> void:
	if unit.hose == null or not unit.hose.shown or not unit.start_fn.is_valid():
		return
	var follow := 1.0 - exp(-14.0 * delta)
	unit.hose.start = unit.hose.start.lerp(unit.start_fn.call(), follow) if unit.start_smooth else unit.start_fn.call()
	unit.hose.end = unit.hose.end.lerp(unit.end_fn.call(), follow)
	unit.hose.cover_enabled = unit.cover_fn.is_valid()
	if unit.hose.cover_enabled:
		unit.hose.cover_base = unit.cover_fn.call()
		unit.hose.cover_color = unit.color
		var cover_node: Variant = _objects.get(unit.cover_id)
		unit.hose.cover_squash = (cover_node as GarageObject).hookah_squash() if cover_node is GarageObject else 0.0
		unit.hose.cover_top = (cover_node as GarageObject).hookah_top() if cover_node is GarageObject else 0
		unit.hose.cover_heat_state = (cover_node as GarageObject).coal_state() if cover_node is GarageObject else 1
	if unit.aim_fn.is_valid():
		var aim: Vector2 = unit.aim_fn.call()
		if aim != Vector2.ZERO:
			unit.hose.piece_dir = aim
	unit.hose.queue_redraw()


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
	_u.hose.flat = true


## Кальян в руках: клапан едет с кальяном, свободный конец шланга — в руке игрока.
func _hose_carried() -> void:
	_hose_use(func() -> Vector2: return _player.carried_valve_position(), func() -> Vector2: return _holder_end(_player),
		func() -> Vector2: return _aim_to_mouth(_player), false)
	_u.cover_fn = func() -> Vector2: return _player.carried_base_position()
	_u.cover_id = "carried"


## Шланг подключён к кальяну на столе гостя, конец у holder (мундштук его собственный).
func _hose_held_by(holder: Node2D) -> void:
	if _u.station == null or not _u.at_guest or _u.holder == holder:
		return
	var previous := _u.holder
	_u.holder = holder
	_set_holders_hold(holder, previous)
	var master := holder == _player
	_u.hose.piece = _player.piece_color() if master else Color(holder.call("piece_color"))
	if master or previous == _player:
		_player.set_piece_hidden(master)
	var hookah_id := _u.station.hookah_id
	_hose_use(func() -> Vector2: return _object_valve(hookah_id), func() -> Vector2: return _holder_end(holder),
		func() -> Vector2: return _aim_to_mouth(holder), false)
	_u.cover_fn = func() -> Vector2: return _object_base(hookah_id)
	_u.cover_id = hookah_id


## Рука с ручкой шланга вперёд только у того, кто держит шланг (трогаем только прежнего и нового держателя —
## другие гости и кальянщик с другим кальяном остаются как были).
func _set_holders_hold(holder: Node2D, previous: Node2D = null) -> void:
	if holder == _player or previous == _player:
		_player.set_holding(holder == _player)
	for node in _objects.values():
		if node is Friend and (node == holder or node == previous):
			(node as Friend).set_holding(holder == node)


## Кто-то начал затяжку: берёт шланг своего кальяна в руку.
func _hose_take(holder: Node2D) -> void:
	var station := _station_of_holder(holder)
	if station == null or station.unit == null:
		return
	# Кальянщик берёт шланг гостевого кальяна только рядом с ним (или сидя за столом): иначе затяжка у стола для кальянов
	# «утаскивала» шланг чужого кальяна с клиентского стола.
	if holder == _player and not _player.seated and Vector2(station.serve_cell).distance_to(_player.grid_position) > 2.5:
		return
	var previous := _u
	_u = station.unit
	if _u.at_guest and is_object_visible(station.hookah_id):
		_hose_held_by(holder)
	_u = previous


## Никто не курит у кальяна: шланг с мундштуком гостя ложится на стол, мундштук мастера возвращается на шею.
## only — только для этого места (null — для всех).
func _hose_release_if_idle(only: GuestStation = null) -> void:
	for station: GuestStation in _stations.values():
		if only != null and station != only:
			continue
		var unit := station.unit
		if unit == null or unit.hose == null or not unit.at_guest or unit.warming_up:
			continue
		if _player.is_smoking() and station == _player_station:
			continue
		var someone_smokes := false
		for node in _objects.values():
			if node is Friend and (node as Friend).is_smoking() and str(_guest_station.get((node as Friend).guest_id, GuestStation.MAIN_ID)) == station.id:
				someone_smokes = true
				break
		if someone_smokes:
			continue
		var previous := _u
		_u = unit
		var holder := _u.holder
		_u.holder = null
		_set_holders_hold(null, holder)
		_u.hose.piece = _u.guest_piece
		if holder == _player:
			_player.set_piece_hidden(false)
		var hookah_id := station.hookah_id
		_hose_use(func() -> Vector2: return _object_valve(hookah_id), func() -> Vector2: return _object_base(hookah_id) + Vector2(-17, 3),
			func() -> Vector2: return Vector2(-0.9, 0.3), true)
		_u = previous


## Мастер вставляет шланг в кальян: берёт конец со стола, подключает к клапану, надевает свой мундштук с шеи.
func _insert_hose() -> void:
	if _u.hose == null or not _u.hose.shown:
		return
	var base := _object_base(HOOKAH_PREP_OBJECT_ID)
	_player.face_toward(base.x)
	_player.set_holding(true)
	_hose_use(func() -> Vector2: return base + PREP_HOSE_START, func() -> Vector2: return _holder_end(_player),
		func() -> Vector2: return _aim_to_mouth(_player), true)
	_u.hose.flat = true
	await get_tree().create_timer(0.6).timeout
	_hose_use(func() -> Vector2: return _object_valve(HOOKAH_PREP_OBJECT_ID), func() -> Vector2: return _holder_end(_player),
		func() -> Vector2: return _aim_to_mouth(_player), false)
	_u.cover_fn = func() -> Vector2: return _object_base(HOOKAH_PREP_OBJECT_ID)
	_u.cover_id = HOOKAH_PREP_OBJECT_ID
	_u.start_smooth = true
	await get_tree().create_timer(0.7).timeout
	_u.hose.piece = _player.piece_color()
	_player.set_piece_hidden(true)
	await get_tree().create_timer(0.4).timeout
	_player.set_holding(false)


## Сброс шланга (отладка): кальяна нет — шланга тоже.
func reset_hose() -> void:
	if _u.hose == null:
		return
	_u.hose.show_hose(false)
	_u.holder = null
	_u.at_guest = false
	_u.warming_up = false
	_player.set_piece_hidden(false)
	_player.set_holding(false)
	# Кальяны на столах гостей, которые уже убрали (отладка), забываем.
	for station: GuestStation in _stations.values():
		if station.unit != null and not is_object_visible(station.hookah_id):
			var stale := station.unit
			station.unit = null
			stale.station = null
			if stale != _u:
				_discard_unit(stale)


## Гость берёт из коробочки случайный мундштук (он пропадает из коробки) — пока мастер раскуривает кальян.
## Вызывается, пока кальян гостя — «активный» (_u).
func _guest_takes_mouthpiece(station: GuestStation) -> void:
	var table: Variant = _objects.get(station.table_id)
	var piece := _u.guest_piece
	if table is GarageObject:
		piece = (table as GarageObject).take_box_piece()
	_u.guest_piece = piece
	for node in _objects.values():
		if node is Friend and str(_guest_station.get((node as Friend).guest_id, GuestStation.MAIN_ID)) == station.id:
			(node as Friend).set_piece_color(piece)
	if _u.at_guest and _u.holder != null and _u.holder != _player:
		_u.hose.piece = piece


## Раскурка кальянщиком: min_puffs–max_puffs коротких тяжек.
func _warm_up_puffs(min_puffs: int = 2, max_puffs: int = 4, min_len: float = 0.5, max_len: float = 1.3) -> void:
	var puffs := randi_range(min_puffs, max_puffs)
	for i in puffs:
		await _player.puff(randf_range(min_len, max_len))
		await get_tree().create_timer(randf_range(0.2, 0.5)).timeout


## Кальян на столе сплющивается на время затяжки (курит игрок или гость).
func _on_inhale(duration: float, source: Node2D = null) -> void:
	var station := _station_of_holder(source) if source != null else _player_station
	if station != null:
		var hookah: Variant = _objects.get(station.hookah_id)
		if hookah is GarageObject and (hookah as GarageObject).visible:
			(hookah as GarageObject).squash(duration)
	if source == null:
		var prep: Variant = _objects.get(HOOKAH_PREP_OBJECT_ID)
		if prep is GarageObject and (prep as GarageObject).visible and (prep as GarageObject).hookah_top() >= 1:
			(prep as GarageObject).squash(duration)


func _walk_to(target_cell: Vector2i) -> void:
	if target_cell.x < 0:
		return
	var path := _grid.find_path(Vector2i(_player.grid_position.floor()), target_cell)
	_player.walk_path(path)
	await _player.auto_walk_finished


## Клетка, откуда можно подать кальян месту: своя клетка подачи, а если до неё не дойти — ближайшая достижимая рядом.
func _reachable_serve(station: GuestStation) -> Vector2i:
	var origin := Vector2i(_player.grid_position.floor())
	var serve := station.serve_cell
	if _grid.is_cell_walkable(serve) and (serve == origin or not _grid.find_path(origin, serve).is_empty()):
		return serve
	GameLog.error("garage", "Клетка подачи %s места %s недоступна — ищу соседнюю" % [str(serve), station.id])
	var best := serve
	var best_distance := INF
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var cell := serve + Vector2i(dx, dy)
			if cell == serve or cell == station.guest_cell or not _grid.is_cell_walkable(cell):
				continue
			if cell != origin and _grid.find_path(origin, cell).is_empty():
				continue
			var distance := Vector2(cell).distance_to(Vector2(serve))
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


func _walk_carrying(target_cell: Vector2i, top: int = 2) -> void:
	_player.set_carrying_hookah(_u.color, top)
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
	if _companions.has(friend.guest_id):
		return
	var data := InteractableData.new()
	data.id = str(guest["id"])
	data.display_name = str(guest["name"])
	data.prompt = FRIEND_TALK_PROMPT
	# Гость без диалога (второй гость за столом): подойти и принять заказ.
	if dialogue_id.is_empty():
		data.prompt = "Принять заказ"
		data.action = "take_order"
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
	_last_interacted_id = interactable_id
	if not data.dialogue_id.is_empty():
		dialogue_requested.emit(data.dialogue_id)
		return
	var data_station := _station_of_table(interactable_id)
	if data_station != null:
		_last_action_station_id = data_station.id
		_player_station = data_station
	var sits_to_smoke := data.action == "smoke_hookah" and data_station != null and data_station.can_player_sit() and seat_cell_free()
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
	_player_station = _stations[GuestStation.MAIN_ID]
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
		if node is Friend and not bool((node as Friend).get_meta("waiting_guest", false)):
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
	player_inhaled.emit()
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
