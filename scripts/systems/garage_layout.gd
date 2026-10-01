class_name GarageLayout
extends RefCounted
## Загрузка и валидация data-описания гаража (data/garage/*.json).
## Ошибки копятся в errors; is_valid() == false означает, что layout использовать нельзя.

const VISUAL_TYPES := ["emoji", "texture", "box", "table", "chair", "door", "shelf", "neon_sign", "hookah"]
const PROP_TYPES := ["hookah", "jar", "cup", "coals", "tongs", "napkins", "mouthpiece_box"]

var id: String = ""
var size: Vector2i = Vector2i.ZERO
var player_spawn: Vector2 = Vector2.ZERO
## Нормализованные описания объектов. Ключи: id, name, cell (Vector2i), size (Vector2i),
## blocks (bool), anchor (Vector2, клетки), visual (Dictionary), interaction (Dictionary, может быть пустым;
## ключи: prompt, message, player_emoji, action, radius, rect (Rect2 в клетках)).
## Объект может быть hidden (скрыт до показа кодом); interaction.enabled = false отключает взаимодействие.
## visual.top_extra поднимает подсказку выше (px); visual.type "chair" рисует стул. visual может содержать lift (подъём над полом, px) и glow (bool, сияние при приближении).
var objects: Array[Dictionary] = []
## Клетка, куда игрок приносит кальян к столу гостя (необязательна).
var hookah_serve_cell: Vector2i = Vector2i(-1, -1)
## Клетка у стола для кальянов, куда игрок возвращается с кальяном для перезабивки.
var hookah_prep_cell: Vector2i = Vector2i(-1, -1)
## Клетка стула, куда садится игрок, чтобы покурить вместе с гостем.
var player_seat_cell: Vector2i = Vector2i(-1, -1)
var errors: Array[String] = []


static func load_file(path: String) -> GarageLayout:
	var layout := GarageLayout.new()
	if not FileAccess.file_exists(path):
		layout.errors.append("Файл не найден: %s" % path)
		return layout
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		layout.errors.append("Файл %s не содержит JSON-объект" % path)
		return layout
	layout._parse(parsed)
	return layout


static func from_dict(data: Dictionary) -> GarageLayout:
	var layout := GarageLayout.new()
	layout._parse(data)
	return layout


func is_valid() -> bool:
	return errors.is_empty()


func _parse(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	if id.is_empty():
		errors.append("layout: не задан id")

	var size_value: Variant = DataUtil.vec2(data.get("size"))
	if size_value == null or size_value.x < 1 or size_value.y < 1:
		errors.append("layout: size должен быть [ширина, высота] >= 1")
		return
	size = Vector2i(size_value)

	var spawn_value: Variant = DataUtil.vec2(data.get("player_spawn"))
	if spawn_value == null:
		errors.append("layout: player_spawn должен быть [x, y]")
	else:
		player_spawn = spawn_value
		if player_spawn.x < 0 or player_spawn.y < 0 or player_spawn.x >= size.x or player_spawn.y >= size.y:
			errors.append("layout: player_spawn вне границ гаража")

	if data.has("hookah_serve_cell"):
		var serve_value: Variant = DataUtil.vec2(data["hookah_serve_cell"])
		if serve_value == null or serve_value.x < 0 or serve_value.y < 0 or serve_value.x >= size.x or serve_value.y >= size.y:
			errors.append("layout: hookah_serve_cell должен быть [x, y] внутри гаража")
		else:
			hookah_serve_cell = Vector2i(serve_value)

	if data.has("hookah_prep_cell"):
		var prep_value: Variant = DataUtil.vec2(data["hookah_prep_cell"])
		if prep_value == null or prep_value.x < 0 or prep_value.y < 0 or prep_value.x >= size.x or prep_value.y >= size.y:
			errors.append("layout: hookah_prep_cell должен быть [x, y] внутри гаража")
		else:
			hookah_prep_cell = Vector2i(prep_value)

	if data.has("player_seat_cell"):
		var seat_value: Variant = DataUtil.vec2(data["player_seat_cell"])
		if seat_value == null or seat_value.x < 0 or seat_value.y < 0 or seat_value.x >= size.x or seat_value.y >= size.y:
			errors.append("layout: player_seat_cell должен быть [x, y] внутри гаража")
		else:
			player_seat_cell = Vector2i(seat_value)

	var raw_objects: Variant = data.get("objects", [])
	if not (raw_objects is Array):
		errors.append("layout: objects должен быть массивом")
		return
	var seen_ids := {}
	var blocking_rects: Array[Rect2i] = []
	for index in raw_objects.size():
		var entry: Variant = raw_objects[index]
		var object := _parse_object(entry, index, seen_ids)
		if object.is_empty():
			continue
		objects.append(object)
		if object["blocks"]:
			var rect := Rect2i(object["cell"], object["size"])
			for other in blocking_rects:
				if rect.intersects(other):
					errors.append("объект '%s': пересекается с другим непроходимым объектом" % object["id"])
					break
			blocking_rects.append(rect)
			if Rect2i(Vector2i(player_spawn.floor()), Vector2i.ONE).intersects(rect):
				errors.append("объект '%s': блокирует клетку появления игрока" % object["id"])
	if hookah_serve_cell.x >= 0:
		for rect in blocking_rects:
			if rect.has_point(hookah_serve_cell):
				errors.append("layout: hookah_serve_cell находится внутри непроходимого объекта")
				break
	if player_seat_cell.x >= 0:
		for rect in blocking_rects:
			if rect.has_point(player_seat_cell):
				errors.append("layout: player_seat_cell находится внутри непроходимого объекта")
				break
	if hookah_prep_cell.x >= 0:
		for rect in blocking_rects:
			if rect.has_point(hookah_prep_cell):
				errors.append("layout: hookah_prep_cell находится внутри непроходимого объекта")
				break


func _parse_object(entry: Variant, index: int, seen_ids: Dictionary) -> Dictionary:
	var label := "объект #%d" % index
	if not (entry is Dictionary):
		errors.append("%s: должен быть объектом JSON" % label)
		return {}
	var object_id := str(entry.get("id", ""))
	if object_id.is_empty():
		errors.append("%s: не задан id" % label)
		return {}
	label = "объект '%s'" % object_id
	if seen_ids.has(object_id):
		errors.append("%s: id повторяется" % label)
		return {}
	seen_ids[object_id] = true

	var cell_value: Variant = DataUtil.vec2(entry.get("cell"))
	var size_value: Variant = DataUtil.vec2(entry.get("size", [1, 1]))
	if cell_value == null or size_value == null or size_value.x < 1 or size_value.y < 1:
		errors.append("%s: cell и size должны быть [x, y] (size >= 1)" % label)
		return {}
	var cell := Vector2i(cell_value)
	var obj_size := Vector2i(size_value)
	if not Rect2i(Vector2i.ZERO, size).encloses(Rect2i(cell, obj_size)):
		errors.append("%s: выходит за границы гаража" % label)
		return {}

	var visual: Variant = entry.get("visual")
	if not (visual is Dictionary) or not VISUAL_TYPES.has(str(visual.get("type", ""))):
		errors.append("%s: visual.type должен быть одним из %s" % [label, str(VISUAL_TYPES)])
		return {}
	match str(visual["type"]):
		"emoji":
			if str(visual.get("text", "")).is_empty():
				errors.append("%s: у emoji-визуала нет text" % label)
				return {}
		"texture":
			if str(visual.get("path", "")).is_empty():
				errors.append("%s: у texture-визуала нет path" % label)
				return {}

	if str(visual["type"]) == "neon_sign":
		var lines: Variant = visual.get("lines")
		if not (lines is Array) or lines.is_empty():
			errors.append("%s: у neon_sign должен быть непустой массив lines" % label)
			return {}
		if visual.has("wall") and not ["left", "right"].has(str(visual["wall"])):
			errors.append("%s: neon_sign.wall должен быть left или right" % label)
			return {}
		for line in lines:
			if not (line is Dictionary) or str(line.get("text", "")).is_empty() or not Color.html_is_valid(str(line.get("color", "#ffffff"))):
				errors.append("%s: каждая строка neon_sign — {text, color, size?, blink?}" % label)
				return {}

	if visual.has("hookah_slots"):
		var slots_error := _validate_hookah_slots(visual["hookah_slots"])
		if not slots_error.is_empty():
			errors.append("%s: visual.hookah_slots: %s" % [label, slots_error])
			return {}

	if visual.has("props"):
		var props_error := _validate_props(visual["props"])
		if not props_error.is_empty():
			errors.append("%s: visual.props: %s" % [label, props_error])
			return {}

	var anchor := Vector2(cell) + Vector2(obj_size) * 0.5
	if entry.has("anchor"):
		var anchor_value: Variant = DataUtil.vec2(entry["anchor"])
		if anchor_value == null:
			errors.append("%s: anchor должен быть [x, y]" % label)
			return {}
		anchor = anchor_value

	var interaction := {}
	if entry.has("interaction"):
		var raw: Variant = entry["interaction"]
		if not (raw is Dictionary):
			errors.append("%s: interaction должен быть объектом" % label)
			return {}
		interaction = {
			"prompt": str(raw.get("prompt", "Взаимодействовать")),
			"message": str(raw.get("message", "")),
			"player_emoji": str(raw.get("player_emoji", "")),
			"action": str(raw.get("action", "")),
			"enabled": bool(raw.get("enabled", true)),
			"radius": float(raw.get("radius", 1.0)),
			"rect": Rect2(cell, obj_size),
		}
		if raw.has("rect"):
			var rect_raw: Variant = raw["rect"]
			if not (rect_raw is Array) or rect_raw.size() != 4 or rect_raw.any(func(v: Variant) -> bool: return not (v is float or v is int)):
				errors.append("%s: interaction.rect должен быть [x, y, ширина, высота]" % label)
				return {}
			var rect := Rect2(float(rect_raw[0]), float(rect_raw[1]), float(rect_raw[2]), float(rect_raw[3]))
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				errors.append("%s: interaction.rect должен иметь положительный размер" % label)
				return {}
			interaction["rect"] = rect

	return {
		"id": object_id,
		"name": str(entry.get("name", object_id)),
		"cell": cell,
		"size": obj_size,
		"blocks": bool(entry.get("blocks", false)),
		"hidden": bool(entry.get("hidden", false)),
		"anchor": anchor,
		"visual": visual,
		"interaction": interaction,
	}



## Слоты кальянов на полке: {"rows": [{"z": px}], "count": N на ряд, "span": ширина ряда в клетках, "palette": ["#rrggbb"] (необязательно)}.
func _validate_hookah_slots(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "должен быть объектом"
	var rows: Variant = raw.get("rows")
	if not (rows is Array) or rows.is_empty():
		return "rows должен быть непустым массивом {z}"
	for row in rows:
		if not (row is Dictionary) or not (row.get("z") is float or row.get("z") is int):
			return "каждый ряд — {z: число}"
	if not (raw.get("count") is float or raw.get("count") is int) or int(raw["count"]) < 1:
		return "count должен быть числом >= 1"
	if not (raw.get("span") is float or raw.get("span") is int) or float(raw["span"]) <= 0.0:
		return "span должен быть положительным числом"
	for color in raw.get("palette", []):
		if not Color.html_is_valid(str(color)):
			return "некорректный цвет в palette"
	return ""


## Предметы на поверхности объекта: [{"type": "hookah|jar|cup|coals|tongs|napkins|mouthpiece_box", "at": [x, y], "color": "#rrggbb"}],
## at — смещение от центра объекта в клетках.
func _validate_props(raw: Variant) -> String:
	if not (raw is Array):
		return "должен быть массивом"
	for entry in raw:
		if not (entry is Dictionary) or not PROP_TYPES.has(str(entry.get("type", ""))):
			return "type должен быть одним из %s" % str(PROP_TYPES)
		var at: Variant = entry.get("at")
		if not (at is Array) or at.size() != 2 or not (at[0] is float or at[0] is int) or not (at[1] is float or at[1] is int):
			return "at должен быть [x, y]"
		if entry.has("color") and not Color.html_is_valid(str(entry["color"])):
			return "некорректный color"
		if entry.has("z") and not (entry["z"] is float or entry["z"] is int):
			return "z должен быть числом (высота над основанием, px)"
	return ""
