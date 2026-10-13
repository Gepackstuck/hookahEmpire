class_name Buddy
extends Node
## M10: Бэн — друг без заказов. Сидит на своём диване (если игрок его поставил), листает телефон, шутит,
## иногда встаёт и бродит по гаражу, порой подходит постоять рядом с игроком (но не ближе min_distance).
## Пока диван не поставлен, Бэн ходит по гаражу и время от времени напоминает его поставить.
## Вся логика — корутина _run с прерыванием при смене дивана; тайминги берутся из IntroGuide (игровое время).

signal reminded(line: String)
signal sat_down
signal stood_up

var friend: Friend = null

var _grid: GarageGrid = null
var _player: Player = null
var _guide: IntroGuide = null
var _rng := RandomNumberGenerator.new()
var _room_size := Vector2i.ZERO
var _running := false
var _interrupt := false
var _couch := Rect2()
var _has_couch := false
var _seated := false
var _approach := Vector2.ZERO
## Объекты гаража, которые Бэн «изучает»: id -> {"cell": Vector2i (клетка перед объектом), "position": Vector2 (экранная точка объекта)}.
var interests: Dictionary = {}
var _last_interest := ""
## Основной цикл (диван/прогулки) ещё выполняется.
var _loop_alive := false
## Бэн сейчас работает помощником кальянщика: обычное поведение приостановлено.
var _job := false


func setup(buddy_friend: Friend, grid: GarageGrid, player: Player, guide: IntroGuide) -> void:
	friend = buddy_friend
	_grid = grid
	_player = player
	_guide = guide
	_room_size = grid.size
	_rng.randomize()


func is_seated() -> bool:
	return _seated


func has_couch() -> bool:
	return _has_couch


## Включает поведение (после прихода). Повторный вызов ничего не делает.
func start() -> void:
	if _running:
		return
	_running = true
	_run()


func stop() -> void:
	_running = false
	_interrupt = true


## Диван поставлен или перемещён: rect — занимаемые клетки (float), along_x — диван длинной стороной вдоль оси X.
func set_couch(rect: Rect2, along_x: bool) -> void:
	if _has_couch and _couch == rect and _couch_along_x == along_x:
		return
	_couch = rect
	_has_couch = true
	_couch_along_x = along_x
	_interrupt = true


func clear_couch() -> void:
	if not _has_couch:
		return
	_has_couch = false
	_interrupt = true


var _couch_along_x := true


## Занять место на диване без ходьбы (загрузка игры): сразу садится.
func sit_immediately() -> void:
	if not _has_couch or friend == null:
		return
	friend.place_at(_seat_point())
	friend.sit(" ", _face_left(), 0.0, false)
	_seated = true


# --- Основной цикл ---------------------------------------------------------------------------

func _run() -> void:
	_loop_alive = true
	await _run_loop()
	_loop_alive = false


func _run_loop() -> void:
	while _running and is_instance_valid(friend):
		_interrupt = false
		if not _has_couch:
			await _without_couch()
			continue
		if not _seated:
			await _go_sit()
			if _interrupt or not _running:
				continue
		await _sit_session()
		if not _running:
			break
		await _stand_up()
		# После дивана — небольшой обход: 1–3 места подряд (стол, кальяны, полка, вывеска...).
		var trips := _rng.randi_range(1, 3)
		while trips > 0 and _has_couch and not _interrupt and _running:
			await _wander_trip()
			trips -= 1


## Дивана нет: гуляем, изредка напоминаем.
func _without_couch() -> void:
	await _sleep(_guide.ben_range("remind_seconds", _rng))
	if _interrupt or not _running or _has_couch:
		return
	var lines := _guide.ben_lines("remind_lines")
	var line := str(lines[_rng.randi() % lines.size()])
	friend.say(line)
	friend.show_emotion("🛋️", 3.0)
	reminded.emit(line)
	await _wander_trip(false)


func _go_sit() -> void:
	var approach_cell := _pick_approach_cell()
	if approach_cell.x < 0:
		await _sleep(2.0)
		return
	_unstick()
	if not await _walk_to_cell(approach_cell):
		await _sleep(2.0)
		return
	if _interrupt or not _running or not _has_couch:
		return
	_approach = Vector2(approach_cell) + Vector2(0.5, 0.5)
	var step: Array[Vector2] = [_seat_point()]
	friend.walk_path(step)
	await friend.arrived
	if _interrupt or not _running:
		return
	await friend.sit_down_animated(_face_left(), false)
	_seated = true
	sat_down.emit()


func _sit_session() -> void:
	var total := _guide.ben_range("sit_seconds", _rng)
	var elapsed := 0.0
	while elapsed < total and _running and not _interrupt:
		var chunk := _rng.randf_range(5.0, 12.0)
		var roll := _rng.randf()
		if roll < 0.6:
			friend.set_phone(true)
			var phone_time := _guide.ben_range("phone_seconds", _rng)
			await _sleep(phone_time * 0.5)
			if not _interrupt and _rng.randf() < 0.6:
				friend.show_emotion(["😂", "💀", "😍"][_rng.randi() % 3], 2.0)
			await _sleep(phone_time * 0.5)
			friend.set_phone(false)
			elapsed += phone_time
		elif roll < 0.85:
			var lines := _guide.ben_lines("chill_lines")
			friend.say(str(lines[_rng.randi() % lines.size()]))
		else:
			friend.show_emotion("😎", 2.5)
		await _sleep(chunk)
		elapsed += chunk


func _stand_up() -> void:
	if not _seated:
		return
	friend.set_phone(false)
	await friend.stand_up_animated()
	_seated = false
	stood_up.emit()
	# Выходим из дивана к клетке перед ним (идти по сетке из занятой клетки нельзя).
	var out: Array[Vector2] = [_approach]
	friend.walk_path(out)
	await friend.arrived
	_unstick()


## Прогулка: к случайной клетке (иногда — постоять рядом с игроком, но не вплотную), немного постоять.
func _wander_trip(play_phone: bool = true) -> void:
	if _rng.randf() < float(_guide.ben.get("visit_chance", 0.0)) and await _visit_interest():
		return
	var together := _rng.randf() < float(_guide.ben.get("together_chance", 0.4))
	var cell := _pick_wander_cell(together)
	if cell.x < 0:
		await _sleep(2.0)
		return
	if not await _walk_to_cell(cell):
		return
	if _interrupt or not _running:
		return
	var linger := _guide.ben_range("linger_seconds", _rng)
	if play_phone and _rng.randf() < 0.4:
		friend.set_phone(true)
		await _sleep(linger)
		friend.set_phone(false)
	else:
		if _rng.randf() < 0.5:
			friend.show_emotion("🙂", 2.0)
		await _sleep(linger)


## Подходит к случайному объекту гаража (стол, кальян, полка, вывеска...), разглядывает его и комментирует. false — идти некуда.
func _visit_interest() -> bool:
	var data: Dictionary = _guide.ben.get("interests", {})
	var ids: Array = interests.keys()
	ids.shuffle()
	var player_pos := _player.grid_position if _player != null else Vector2(-100, -100)
	for id in ids:
		if str(id) == _last_interest or not data.has(id):
			continue
		var info: Dictionary = interests[id]
		var cell: Vector2i = info["cell"]
		if not _grid.is_cell_walkable(cell) or (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(player_pos) < 1.6:
			continue
		if cell != _current_cell() and _grid.find_path(_current_cell(), cell).is_empty():
			continue
		if not await _walk_to_cell(cell):
			continue
		if _interrupt or not _running:
			return true
		_last_interest = str(id)
		friend.look_toward((info["position"] as Vector2) - friend.position)
		var entry: Dictionary = data[id]
		var emojis: Array = entry.get("emojis", ["🙂"])
		var lines: Array = entry.get("lines", [])
		var duration := _guide.ben_range("linger_seconds", _rng)
		friend.show_emotion(str(emojis[_rng.randi() % emojis.size()]), 2.5)
		await _sleep(duration * 0.4)
		if not _interrupt and not lines.is_empty() and _rng.randf() < 0.7:
			friend.say(str(lines[_rng.randi() % lines.size()]))
		elif not _interrupt:
			friend.show_emotion(str(emojis[_rng.randi() % emojis.size()]), 2.0)
		await _sleep(duration * 0.6)
		friend.look_straight()
		return true
	return false


# --- Вспомогательные --------------------------------------------------------------------------

func _sleep(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and _running and not _interrupt:
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25


func _current_cell() -> Vector2i:
	return Vector2i(friend.grid_position.floor())


func _walk_to_cell(cell: Vector2i) -> bool:
	var path := _grid.find_path(_current_cell(), cell)
	if path.is_empty():
		return false
	friend.walk_path(path)
	await friend.arrived
	return true


func _face_left() -> bool:
	return _couch_along_x


## Точка сиденья: центр дивана, чуть сдвинутый «вперёд» (чтобы Бэн рисовался поверх спинки).
func _seat_point() -> Vector2:
	var center := _couch.get_center()
	return center + (Vector2(0.0, 0.12) if _couch_along_x else Vector2(0.12, 0.0))


## Клетка перед диваном (с «лицевой» стороны), до которой можно дойти.
func _pick_approach_cell() -> Vector2i:
	if not _has_couch:
		return Vector2i(-1, -1)
	var center := _couch.get_center()
	var candidates: Array[Vector2i] = []
	if _couch_along_x:
		var front := ceili(_couch.end.y - 0.001)
		for dx in [0, -1, 1]:
			candidates.append(Vector2i(floori(center.x) + dx, front))
	else:
		var front_x := ceili(_couch.end.x - 0.001)
		for dy in [0, -1, 1]:
			candidates.append(Vector2i(front_x, floori(center.y) + dy))
	# Запасные подходы: с других сторон.
	candidates.append(Vector2i(floori(center.x), floori(_couch.position.y) - 1))
	candidates.append(Vector2i(floori(_couch.position.x) - 1, floori(center.y)))
	candidates.append(Vector2i(ceili(_couch.end.x - 0.001), floori(center.y)))
	candidates.append(Vector2i(floori(center.x), ceili(_couch.end.y - 0.001)))
	var from := _current_cell()
	for cell in candidates:
		if _grid.is_cell_walkable(cell) and (cell == from or not _grid.find_path(from, cell).is_empty()):
			return cell
	return Vector2i(-1, -1)


## Клетка для прогулки: достижимая, не ближе min_distance к игроку; together — в 2–3.5 клетках от него.
func _pick_wander_cell(together: bool) -> Vector2i:
	var min_distance := float(_guide.ben.get("min_distance", 2.0))
	var player_pos := _player.grid_position if _player != null else Vector2(-100, -100)
	var from := _current_cell()
	var options: Array[Vector2i] = []
	for x in range(_room_size.x):
		for y in range(_room_size.y):
			var cell := Vector2i(x, y)
			if not _grid.is_cell_walkable(cell):
				continue
			var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(player_pos)
			if distance < min_distance:
				continue
			if together and distance > min_distance + 1.5:
				continue
			options.append(cell)
	options.shuffle()
	for cell in options:
		if cell == from or not _grid.find_path(from, cell).is_empty():
			return cell
	return Vector2i(-1, -1)


## Если Бэн оказался в занятой клетке (например, диван поставили поверх), выводим его в ближайшую свободную.
func _unstick() -> void:
	var cell := _current_cell()
	if _grid.is_cell_walkable(cell):
		return
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := cell + Vector2i(dx, dy)
				if _grid.is_cell_walkable(candidate):
					friend.place_at(Vector2(candidate) + Vector2(0.5, 0.5))
					return


# --- Работа помощником кальянщика ---------------------------------------------------------------

func is_working() -> bool:
	return _job


## Бэн бросает свои дела (встаёт с дивана) и готов выполнять работу. Корутина.
func begin_job() -> void:
	if _job:
		return
	_job = true
	stop()
	while _loop_alive and is_instance_valid(friend):
		await get_tree().process_frame
	if not is_instance_valid(friend):
		return
	friend.set_phone(false)
	await _stand_up()
	_unstick()


## Идёт в клетку (корутина); false — дойти нельзя.
func job_walk(cell: Vector2i) -> bool:
	if not is_instance_valid(friend):
		return false
	if _current_cell() == cell:
		return true
	return await _walk_to_cell(cell)


## Работа закончена: Бэн возвращается к обычному поведению (идёт на диван).
func end_job() -> void:
	if not _job:
		return
	_job = false
	if is_instance_valid(friend):
		friend.look_straight()
		start()


func current_cell() -> Vector2i:
	return _current_cell()
