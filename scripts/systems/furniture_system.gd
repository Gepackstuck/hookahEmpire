class_name FurnitureSystem
extends RefCounted
## M9: каталог мебели, покупка, владение и размещение на сетке гаража, бонус комфорта/атмосферы.
## Чистая логика без нод: графику строит FurnitureLayer, интерфейс — FurnitureScreen.
## Купленная мебель хранится в GameState.furniture: [{"uid", "item", "cell": [x, y], "rotation": 0|1, "placed": bool}].
## Данные — data/config/furniture.json (проверяются при загрузке).

signal changed

const CONFIG_PATH := "res://data/config/furniture.json"
const PLACEMENTS: Array[String] = ["floor", "wall"]
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var errors: Array[String] = []
## id -> {"id", "name", "icon", "price", "size": Vector2i, "rotation_allowed", "category", "placement", "flat", "blocks", "comfort", "atmosphere", "visual"}.
var items: Dictionary = {}
var item_order: Array[String] = []
var bonus_per_point: float = 0.25
var bonus_cap: float = 3.0
## Доля цены, которую возвращает продажа предмета.
var sell_ratio: float = 0.3
var no_build: Array[Rect2i] = []
var required_cells: Array[Vector2i] = []

var room_size := Vector2i.ZERO
## Сколько предметов со «стола» вернулось на склад после последней уборки/перестановки хозяина (для сообщения игроку).
var last_detached: int = 0
var _fixed_rects: Array[Rect2i] = []
var _fixed_blocking: Array[Rect2i] = []
var _state: Object
var _economy: EconomySystem


func _init(state: Object = null, economy: EconomySystem = null) -> void:
	_state = state
	_economy = economy


static func load_default(state: Object, economy: EconomySystem) -> FurnitureSystem:
	var system := FurnitureSystem.new(state, economy)
	if not FileAccess.file_exists(CONFIG_PATH):
		system.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return system
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		system.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return system
	system._parse(parsed)
	return system


static func from_dict(data: Dictionary, state: Object, economy: EconomySystem) -> FurnitureSystem:
	var system := FurnitureSystem.new(state, economy)
	system._parse(data)
	return system


func is_valid() -> bool:
	return errors.is_empty()


func has_item(item_id: String) -> bool:
	return items.has(item_id)


func item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


## Размеры комнаты и занятые клетки: fixed_rects — все объекты гаража (пол и стены), fixed_blocking — те, через которые нельзя ходить.
func set_room(size: Vector2i, fixed_rects: Array[Rect2i], fixed_blocking: Array[Rect2i]) -> void:
	room_size = size
	_fixed_rects = fixed_rects.duplicate()
	_fixed_blocking = fixed_blocking.duplicate()


## То же, но из описания гаража (непроходимые объекты + стул игрока).
func set_room_from_layout(layout: GarageLayout) -> void:
	var all_rects: Array[Rect2i] = []
	var blocking: Array[Rect2i] = []
	for object in layout.objects:
		var rect := Rect2i(object["cell"], object["size"])
		all_rects.append(rect)
		if bool(object["blocks"]):
			blocking.append(rect)
	if layout.player_seat_cell.x >= 0:
		blocking.append(Rect2i(layout.player_seat_cell, Vector2i.ONE))
	set_room(layout.size, all_rects, blocking)


# --- Владение ---------------------------------------------------------------

func entries() -> Array:
	return _state.furniture


func entry_of(uid: String) -> Dictionary:
	for entry in _state.furniture:
		if str(entry["uid"]) == uid:
			return entry
	return {}


func placed_entries() -> Array:
	return _state.furniture.filter(func(entry: Dictionary) -> bool: return bool(entry.get("placed", false)))


func stored_entries() -> Array:
	return _state.furniture.filter(func(entry: Dictionary) -> bool: return not bool(entry.get("placed", false)))


func owned_count(item_id: String = "") -> int:
	var count := 0
	for entry in _state.furniture:
		if item_id == "" or str(entry["item"]) == item_id:
			count += 1
	return count


## Покупка: списывает цену, предмет попадает на «склад» (не расставлен).
func buy(item_id: String) -> Dictionary:
	if not items.has(item_id):
		return {"ok": false, "error": "Такого предмета нет в каталоге"}
	var price := int(items[item_id]["price"])
	if _economy == null or not _economy.spend(price):
		return {"ok": false, "error": "Не хватает денег: нужно %d 💰" % price}
	_state.furniture_seq += 1
	var uid := "f%d" % int(_state.furniture_seq)
	_state.furniture.append({"uid": uid, "item": item_id, "cell": [0, 0], "rotation": 0, "placed": false, "host": ""})
	changed.emit()
	return {"ok": true, "uid": uid}


## Ставит (или переставляет) купленный предмет. Возвращает {"ok", "error"?}.
func place(uid: String, cell: Vector2, rotation: int) -> Dictionary:
	var entry := entry_of(uid)
	if entry.is_empty():
		return {"ok": false, "error": "Такой предмет не куплен"}
	var item_id := str(entry["item"])
	var rot := normalize_rotation(item_id, rotation)
	var info := placement_info(item_id, cell, rot, uid)
	if str(info["problem"]) != "":
		return {"ok": false, "error": str(info["problem"])}
	last_detached = _detach_children(uid)
	entry["cell"] = [cell.x, cell.y]
	entry["rotation"] = rot
	entry["placed"] = true
	entry["host"] = str(info["host"])
	changed.emit()
	return {"ok": true, "detached": last_detached}


## Убирает предмет со стены/пола на склад (деньги не возвращаются).
func remove(uid: String) -> bool:
	var entry := entry_of(uid)
	if entry.is_empty() or not bool(entry.get("placed", false)):
		return false
	last_detached = _detach_children(uid)
	entry["placed"] = false
	entry["host"] = ""
	changed.emit()
	return true


## Сколько денег вернёт продажа предмета (заметно меньше цены покупки).
func sell_price(item_id: String) -> int:
	if not items.has(item_id):
		return 0
	return maxi(1, roundi(float(items[item_id]["price"]) * sell_ratio))


## Продаёт купленный предмет: он исчезает из владения, деньги возвращаются по sell_price. Предметы на нём уходят на склад.
func sell(uid: String) -> Dictionary:
	var entry := entry_of(uid)
	if entry.is_empty():
		return {"ok": false, "error": "Такой предмет не куплен"}
	var item_id := str(entry["item"])
	var price := sell_price(item_id)
	last_detached = _detach_children(uid)
	_state.furniture.erase(entry)
	if _economy != null:
		_economy.earn(price)
	changed.emit()
	return {"ok": true, "price": price, "item": item_id}


# --- Размещение -------------------------------------------------------------

func normalize_rotation(item_id: String, rotation: int) -> int:
	if not items.has(item_id) or not bool(items[item_id]["rotation_allowed"]):
		return 0
	return rotation % 2


func footprint(item_id: String, rotation: int) -> Vector2i:
	var size: Vector2i = items[item_id]["size"]
	return Vector2i(size.y, size.x) if normalize_rotation(item_id, rotation) == 1 else size


## Шаг расстановки мебели — половина клетки (проход персонажей по-прежнему идёт по целым клеткам).
const STEP := 0.5


func rect_of(item_id: String, cell: Vector2, rotation: int) -> Rect2:
	return Rect2(cell, Vector2(footprint(item_id, rotation)))


func entry_cell(entry: Dictionary) -> Vector2:
	return Vector2(float(entry["cell"][0]), float(entry["cell"][1]))


func entry_rect(entry: Dictionary) -> Rect2:
	return rect_of(str(entry["item"]), entry_cell(entry), int(entry["rotation"]))


## Целые клетки сетки, которых касается прямоугольник (для блокировки пути: мебель на половине клетки перекрывает клетку целиком).
func cover_cells(rect: Rect2) -> Rect2i:
	var x0 := floori(rect.position.x + 0.001)
	var y0 := floori(rect.position.y + 0.001)
	var x1 := ceili(rect.end.x - 0.001)
	var y1 := ceili(rect.end.y - 0.001)
	return Rect2i(x0, y0, maxi(x1 - x0, 0), maxi(y1 - y0, 0))


static func _rf(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position), Vector2(rect.size))


## Поворачивает расставленный предмет на месте (при необходимости сдвигая, чтобы он помещался).
func rotate_in_place(uid: String) -> Dictionary:
	var entry := entry_of(uid)
	if entry.is_empty() or not bool(entry.get("placed", false)):
		return {"ok": false, "error": "Предмет не стоит в гараже"}
	var item_id := str(entry["item"])
	if not bool(items[item_id]["rotation_allowed"]):
		return {"ok": false, "error": "Этот предмет не поворачивается"}
	var old_rot := int(entry["rotation"])
	var new_rot := (old_rot + 1) % 2
	var cell := entry_cell(entry)
	var old_size := Vector2(footprint(item_id, old_rot))
	var new_size := Vector2(footprint(item_id, new_rot))
	var candidates: Array[Vector2] = []
	if str(items[item_id]["placement"]) == "wall":
		# Картина переезжает на другую стену: пробуем места вдоль неё, начиная с ближайшего к прежнему.
		var preferred := cell.x if old_rot == 0 else cell.y
		var span := (float(room_size.x) - new_size.x) if new_rot == 0 else (float(room_size.y) - new_size.y)
		var positions: Array[float] = []
		for step_index in range(0, maxi(int(span / STEP), 0) + 1):
			positions.append(float(step_index) * STEP)
		positions.sort_custom(func(a: float, b: float) -> bool: return absf(a - preferred) < absf(b - preferred))
		for t in positions:
			candidates.append(Vector2(t, 0.0) if new_rot == 0 else Vector2(0.0, t))
	else:
		candidates.append(cell + (old_size - new_size) * 0.5)
		candidates.append(cell)
		candidates.append(cell + Vector2(old_size.x - new_size.x, 0.0))
		candidates.append(cell + Vector2(0.0, old_size.y - new_size.y))
	var first_error := ""
	for candidate in candidates:
		var problem := check_placement(item_id, candidate, new_rot, uid)
		if problem == "":
			return place(uid, candidate, new_rot)
		if first_error == "":
			first_error = problem
	return {"ok": false, "error": "Не получится повернуть: %s" % first_error}


## {"problem": "" или причина отказа, "host": uid предмета-основания, если предмет ставится сверху (на стол, полку)}.
func placement_info(item_id: String, cell: Vector2, rotation: int, ignore_uid: String = "") -> Dictionary:
	var problem := _placement_problem(item_id, cell, rotation, ignore_uid)
	if problem == "":
		return {"problem": "", "host": ""}
	if items.has(item_id) and bool(items[item_id]["surface_ok"]):
		var host := _find_host(item_id, cell, rotation, ignore_uid)
		if host != "":
			return {"problem": "", "host": host}
	return {"problem": problem, "host": ""}


func check_placement(item_id: String, cell: Vector2, rotation: int, ignore_uid: String = "") -> String:
	return str(placement_info(item_id, cell, rotation, ignore_uid)["problem"])


## Предмет, на котором можно поставить item_id в этой клетке: расставленная мебель с surface_height, свободная сверху.
func _find_host(item_id: String, cell: Vector2, rotation: int, ignore_uid: String) -> String:
	if room_size == Vector2i.ZERO:
		return ""
	var rect := rect_of(item_id, cell, rotation)
	for entry in placed_entries():
		var uid := str(entry["uid"])
		if uid == ignore_uid or str(entry.get("host", "")) != "":
			continue
		var data: Dictionary = items[str(entry["item"])]
		if float(data["surface_height"]) <= 0.0 or str(data["placement"]) != "floor":
			continue
		if not entry_rect(entry).encloses(rect):
			continue
		var occupied := false
		for other in placed_entries():
			if str(other["uid"]) != ignore_uid and str(other.get("host", "")) == uid and entry_rect(other).intersects(rect):
				occupied = true
		if not occupied:
			return uid
	return ""


## Предметы, стоявшие на uid (на столе, полке), возвращаются на склад. Возвращает их число.
func _detach_children(uid: String) -> int:
	var count := 0
	for entry in _state.furniture:
		if str(entry.get("host", "")) == uid and bool(entry.get("placed", false)):
			entry["placed"] = false
			entry["host"] = ""
			count += 1
	return count


## Высота поверхности, на которую поставлен предмет (0 — стоит на полу).
func surface_lift(host_uid: String) -> float:
	if host_uid == "":
		return 0.0
	var host := entry_of(host_uid)
	if host.is_empty():
		return 0.0
	return float(items[str(host["item"])]["surface_height"])


func _placement_problem(item_id: String, cell: Vector2, rotation: int, ignore_uid: String) -> String:
	if not items.has(item_id):
		return "Неизвестный предмет"
	if room_size == Vector2i.ZERO:
		return "Комната не задана"
	var data: Dictionary = items[item_id]
	var rot := normalize_rotation(item_id, rotation)
	var rect := rect_of(item_id, cell, rot)
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > room_size.x or rect.end.y > room_size.y:
		return "За пределами комнаты"
	var is_wall := str(data["placement"]) == "wall"
	if is_wall:
		return _check_wall(rect, rot, ignore_uid)
	for fixed in _fixed_rects:
		if rect.intersects(_rf(fixed)):
			return "Здесь уже стоит предмет гаража"
	for zone in no_build:
		if rect.intersects(_rf(zone)):
			return "Рабочая зона: здесь нельзя ставить мебель"
	var flat := bool(data["flat"])
	for entry in placed_entries():
		if str(entry["uid"]) == ignore_uid or str(entry.get("host", "")) != "":
			continue
		if str(items[str(entry["item"])]["placement"]) == "wall":
			continue
		var other_flat := bool(items[str(entry["item"])]["flat"])
		if flat == other_flat and rect.intersects(entry_rect(entry)):
			return "Место занято другой мебелью"
	if bool(data["blocks"]):
		for required in required_cells:
			if rect.intersects(Rect2(Vector2(required), Vector2.ONE)):
				return "Перекроет важный проход"
		if not _paths_stay_open(rect, ignore_uid):
			return "Перекроет проход к рабочим местам"
	return ""


func can_place(item_id: String, cell: Vector2, rotation: int, ignore_uid: String = "") -> bool:
	return check_placement(item_id, cell, rotation, ignore_uid) == ""


func _check_wall(rect: Rect2, rotation: int, ignore_uid: String) -> String:
	if rotation == 0 and rect.position.y != 0:
		return "Картину можно повесить только на стену"
	if rotation == 1 and rect.position.x != 0:
		return "Картину можно повесить только на стену"
	for fixed in _fixed_rects:
		if rect.intersects(_rf(fixed)):
			return "Стена занята"
	for entry in placed_entries():
		if str(entry["uid"]) == ignore_uid or str(items[str(entry["item"])]["placement"]) != "wall":
			continue
		if rect.intersects(entry_rect(entry)):
			return "Стена занята другой картиной"
	return ""


## Все required_cells остаются свободными и достижимы друг из друга (4-связность, с запасом по сравнению с реальной ходьбой).
func _paths_stay_open(extra: Rect2, ignore_uid: String) -> bool:
	if required_cells.is_empty():
		return true
	var blocked: Dictionary = {}
	for rect in _fixed_blocking:
		_mark(blocked, _rf(rect))
	for entry in placed_entries():
		if str(entry["uid"]) == ignore_uid or str(entry.get("host", "")) != "":
			continue
		var data: Dictionary = items[str(entry["item"])]
		if bool(data["blocks"]) and str(data["placement"]) != "wall":
			_mark(blocked, entry_rect(entry))
	_mark(blocked, extra)
	for cell in required_cells:
		if blocked.has(cell):
			return false
	var seen: Dictionary = {required_cells[0]: true}
	var queue: Array[Vector2i] = [required_cells[0]]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for direction in DIRECTIONS:
			var next := current + direction
			if seen.has(next) or blocked.has(next):
				continue
			if next.x < 0 or next.y < 0 or next.x >= room_size.x or next.y >= room_size.y:
				continue
			seen[next] = true
			queue.append(next)
	for cell in required_cells:
		if not seen.has(cell):
			return false
	return true


func _mark(blocked: Dictionary, float_rect: Rect2) -> void:
	var rect := cover_cells(float_rect)
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			blocked[Vector2i(x, y)] = true


## Свободна ли база комнаты (без мебели) — все required_cells достижимы. Используется в тестах и при старте.
func base_layout_connected() -> bool:
	return _paths_stay_open(Rect2(), "")


# --- Бонусы -----------------------------------------------------------------

## {"comfort", "atmosphere", "points", "bonus", "placed"}: суммы по расставленной мебели и итоговый бонус к баллу.
func totals() -> Dictionary:
	var comfort := 0
	var atmosphere := 0
	var count := 0
	for entry in placed_entries():
		var data: Dictionary = items.get(str(entry["item"]), {})
		if data.is_empty():
			continue
		comfort += int(data["comfort"])
		atmosphere += int(data["atmosphere"])
		count += 1
	var points := comfort + atmosphere
	var bonus := snappedf(minf(bonus_cap, float(points) * bonus_per_point), 0.1)
	return {"comfort": comfort, "atmosphere": atmosphere, "points": points, "bonus": bonus, "placed": count}


func score_bonus() -> float:
	return float(totals()["bonus"])


# --- Графика ----------------------------------------------------------------

## Описание объекта для GarageObject.setup: id — uid предмета.
func object_definition(entry: Dictionary) -> Dictionary:
	var item_id := str(entry["item"])
	var cell := entry_cell(entry)
	return definition_for(item_id, cell, int(entry["rotation"]), str(entry["uid"]), surface_lift(str(entry.get("host", ""))))


func definition_for(item_id: String, cell: Vector2, rotation: int, object_id: String, lift: float = 0.0) -> Dictionary:
	var data: Dictionary = items[item_id]
	var rot := normalize_rotation(item_id, rotation)
	var size := footprint(item_id, rot)
	var visual: Dictionary = (data["visual"] as Dictionary).duplicate(true)
	if str(visual.get("type", "")) == "chair":
		visual["facing"] = "y" if rot == 1 else "x"
	visual["rotation"] = rot
	if lift > 0.0:
		visual["lift"] = lift
	return {
		"id": object_id,
		"name": str(data["name"]),
		"cell": cell,
		"size": size,
		"anchor": Vector2(cell) + Vector2(size) * 0.5,
		"blocks": bool(data["blocks"]) and lift <= 0.0,
		"visual": visual,
		"interaction": {},
	}


# --- Разбор конфигурации ----------------------------------------------------

func _parse(data: Dictionary) -> void:
	var bonus: Variant = data.get("bonus", {})
	if bonus is Dictionary:
		var per_point: Variant = bonus.get("per_point", bonus_per_point)
		var cap: Variant = bonus.get("cap", bonus_cap)
		if not (per_point is int or per_point is float) or float(per_point) < 0.0:
			errors.append("furniture: bonus.per_point должен быть числом >= 0")
		else:
			bonus_per_point = float(per_point)
		if not (cap is int or cap is float) or float(cap) < 0.0:
			errors.append("furniture: bonus.cap должен быть числом >= 0")
		else:
			bonus_cap = float(cap)
	var ratio: Variant = data.get("sell_ratio", sell_ratio)
	if not (ratio is int or ratio is float) or float(ratio) < 0.0 or float(ratio) > 1.0:
		errors.append("furniture: sell_ratio должен быть числом 0..1")
	else:
		sell_ratio = float(ratio)
	_parse_room(data.get("room", {}))
	var raw_items: Variant = data.get("items")
	if not (raw_items is Array) or raw_items.is_empty():
		errors.append("furniture: items должен быть непустым массивом")
		return
	for entry in raw_items:
		_parse_item(entry)


func _parse_room(raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	for rect in raw.get("no_build", []):
		if rect is Array and rect.size() == 4 and _all_numbers(rect):
			no_build.append(Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])))
		else:
			errors.append("furniture: room.no_build — массив [x, y, w, h]")
	for cell in raw.get("required_cells", []):
		if cell is Array and cell.size() == 2 and _all_numbers(cell):
			required_cells.append(Vector2i(int(cell[0]), int(cell[1])))
		else:
			errors.append("furniture: room.required_cells — массив [x, y]")


func _parse_item(entry: Variant) -> void:
	if not (entry is Dictionary):
		errors.append("furniture: предмет должен быть объектом")
		return
	var id := str(entry.get("id", ""))
	if id.is_empty():
		errors.append("furniture: у предмета нет id")
		return
	if items.has(id):
		errors.append("furniture: id '%s' повторяется" % id)
		return
	var label := "предмет '%s'" % id
	var price: Variant = entry.get("price")
	if not (price is int or price is float) or int(price) < 0:
		errors.append("furniture: %s: price должен быть числом >= 0" % label)
		return
	var grid_size: Variant = entry.get("grid_size")
	if not (grid_size is Array) or grid_size.size() != 2 or not _all_numbers(grid_size) or int(grid_size[0]) < 1 or int(grid_size[1]) < 1:
		errors.append("furniture: %s: grid_size должен быть [x, y] >= 1" % label)
		return
	var placement := str(entry.get("placement", "floor"))
	if not PLACEMENTS.has(placement):
		errors.append("furniture: %s: placement должен быть floor или wall" % label)
		return
	var visual: Variant = entry.get("visual")
	if not (visual is Dictionary) or str((visual as Dictionary).get("type", "")).is_empty():
		errors.append("furniture: %s: нет visual.type" % label)
		return
	for key in ["comfort", "atmosphere"]:
		var value: Variant = entry.get(key, 0)
		if not (value is int or value is float) or float(value) < 0.0:
			errors.append("furniture: %s: %s должен быть числом >= 0" % [label, key])
			return
	items[id] = {
		"id": id,
		"name": str(entry.get("name", id)),
		"price": int(price),
		"size": Vector2i(int(grid_size[0]), int(grid_size[1])),
		"rotation_allowed": bool(entry.get("rotation_allowed", false)),
		"category": str(entry.get("category", "decor")),
		"icon": str(entry.get("icon", "")),
		"placement": placement,
		"flat": bool(entry.get("flat", false)),
		"surface_height": float(entry.get("surface_height", 0.0)),
		"surface_ok": bool(entry.get("surface_ok", false)),
		"blocks": bool(entry.get("blocks", true)),
		"comfort": int(entry.get("comfort", 0)),
		"atmosphere": int(entry.get("atmosphere", 0)),
		"visual": visual,
	}
	item_order.append(id)


func _all_numbers(values: Array) -> bool:
	for value in values:
		if not (value is int or value is float):
			return false
	return true
