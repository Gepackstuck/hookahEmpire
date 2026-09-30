class_name GuestCatalog
extends RefCounted
## Загрузка описаний гостей/друзей из data/guests/<id>.json.

const DIR := "res://data/guests"


## Возвращает словарь гостя или пустой словарь (ошибка уже залогирована).
static func load_guest(guest_id: String) -> Dictionary:
	var path := "%s/%s.json" % [DIR, guest_id]
	if not FileAccess.file_exists(path):
		GameLog.error("guests", "Нет файла гостя: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		GameLog.error("guests", "%s: не JSON-объект" % path)
		return {}
	for key in ["id", "name", "emoji"]:
		if str(parsed.get(key, "")).is_empty():
			GameLog.error("guests", "%s: не задано поле '%s'" % [path, key])
			return {}
	var faces := str(parsed.get("sprite_faces", "right"))
	if faces != "left" and faces != "right":
		GameLog.error("guests", "%s: sprite_faces должен быть 'left' или 'right'" % path)
		return {}
	var preferences: Variant = parsed.get("preferences", {})
	if not (preferences is Dictionary):
		GameLog.error("guests", "%s: preferences должен быть объектом" % path)
		return {}
	for dimension in preferences:
		if not IngredientCatalog.DIMENSIONS.has(str(dimension)) or not (preferences[dimension] is float or preferences[dimension] is int):
			GameLog.error("guests", "%s: некорректное предпочтение '%s'" % [path, str(dimension)])
			return {}
	var orders: Variant = parsed.get("orders", [])
	if not (orders is Array):
		GameLog.error("guests", "%s: orders должен быть массивом" % path)
		return {}
	for order in orders:
		if not (order is Dictionary) or str(order.get("text", "")).is_empty() or not (order.get("preferences") is Dictionary):
			GameLog.error("guests", "%s: заказ должен иметь text и preferences" % path)
			return {}
		for dimension in order["preferences"]:
			if not IngredientCatalog.DIMENSIONS.has(str(dimension)) or not (order["preferences"][dimension] is float or order["preferences"][dimension] is int):
				GameLog.error("guests", "%s: некорректное предпочтение заказа '%s'" % [path, str(dimension)])
				return {}
	var chance: Variant = parsed.get("smoke_permission_chance", 0.7)
	if not (chance is float or chance is int) or float(chance) < 0.0 or float(chance) > 1.0:
		GameLog.error("guests", "%s: smoke_permission_chance должен быть числом 0..1" % path)
		return {}
	var smoke_dialogue: Variant = parsed.get("smoke_dialogue", {})
	if not (smoke_dialogue is Dictionary):
		GameLog.error("guests", "%s: smoke_dialogue должен быть объектом" % path)
		return {}
	for key in smoke_dialogue:
		if not (smoke_dialogue[key] is Array) or smoke_dialogue[key].is_empty():
			GameLog.error("guests", "%s: smoke_dialogue.%s должен быть непустым массивом строк" % [path, str(key)])
			return {}
	var reactions: Variant = parsed.get("reactions", {})
	if not (reactions is Dictionary):
		GameLog.error("guests", "%s: reactions должен быть объектом" % path)
		return {}
	for emotion_id in reactions:
		if not (reactions[emotion_id] is Array) or reactions[emotion_id].is_empty():
			GameLog.error("guests", "%s: reactions.%s должен быть непустым массивом строк" % [path, str(emotion_id)])
			return {}
	if str(parsed["id"]) != guest_id:
		GameLog.error("guests", "%s: id '%s' не совпадает с именем файла" % [path, str(parsed["id"])])
		return {}
	return parsed


## Случайный заказ гостя: {"id", "text", "preferences"}. Без списка orders — заказ по умолчанию из preferences.
static func roll_order(guest: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var orders: Array = guest.get("orders", [])
	if orders.is_empty():
		return {"id": "default", "text": "Сделай мне кальян на свой вкус.", "preferences": guest.get("preferences", {})}
	return orders[rng.randi_range(0, orders.size() - 1)]


## Реплика гостя о кальяне по id эмоции (реакция по умолчанию, если в данных нет).
static func reaction_text(guest: Dictionary, emotion_id: String, likes: bool, rng: RandomNumberGenerator) -> String:
	var reactions: Dictionary = guest.get("reactions", {})
	var lines: Array = reactions.get(emotion_id, [])
	if lines.is_empty():
		return "Классный кальян, спасибо!" if likes else "Не то… Перезабей, пожалуйста."
	return str(lines[rng.randi_range(0, lines.size() - 1)])


## Разрешит ли гость покурить вместе с ним (случайно, шанс из smoke_permission_chance).
static func roll_smoke_permission(guest: Dictionary, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < float(guest.get("smoke_permission_chance", 0.7))


## Реплика из smoke_dialogue: key = "ask" | "yes" | "no".
static func smoke_line(guest: Dictionary, key: String, rng: RandomNumberGenerator) -> String:
	var dialogue: Dictionary = guest.get("smoke_dialogue", {})
	var lines: Array = dialogue.get(key, [])
	if lines.is_empty():
		match key:
			"ask":
				return "Можно с тобой покурить?"
			"yes":
				return "Конечно, давай!"
			_:
				return "Не сейчас, извини."
	return str(lines[rng.randi_range(0, lines.size() - 1)])
