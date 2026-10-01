class_name GuestCatalog
extends RefCounted
## Загрузка описаний гостей/друзей из data/guests/<id>.json.

const DIR := "res://data/guests"
## Детали внешности, которые можно задать в look (цвета "#rrggbb").
const LOOK_PARTS: Array[String] = ["skin", "hair", "shirt", "pants", "shoes", "jacket"]


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
	var farewell: Variant = parsed.get("farewell", {})
	if not (farewell is Dictionary):
		GameLog.error("guests", "%s: farewell должен быть объектом" % path)
		return {}
	for emotion_id in farewell:
		if not (farewell[emotion_id] is Array) or farewell[emotion_id].is_empty():
			GameLog.error("guests", "%s: farewell.%s должен быть непустым массивом строк" % [path, str(emotion_id)])
			return {}
	var look: Variant = parsed.get("look", {})
	if not (look is Dictionary):
		GameLog.error("guests", "%s: look должен быть объектом" % path)
		return {}
	for part in look:
		if not LOOK_PARTS.has(str(part)) or not Color.html_is_valid(str(look[part])):
			GameLog.error("guests", "%s: некорректная деталь внешности '%s'" % [path, str(part)])
			return {}
	var dislikes: Variant = parsed.get("dislikes", {})
	if not (dislikes is Dictionary):
		GameLog.error("guests", "%s: dislikes должен быть объектом" % path)
		return {}
	for dimension in dislikes:
		if not IngredientCatalog.DIMENSIONS.has(str(dimension)) or not (dislikes[dimension] is float or dislikes[dimension] is int):
			GameLog.error("guests", "%s: некорректное неприятие '%s'" % [path, str(dimension)])
			return {}
	if parsed.has("random_taste") and not _valid_random_taste(parsed["random_taste"], path):
		return {}
	if str(parsed["id"]) != guest_id:
		GameLog.error("guests", "%s: id '%s' не совпадает с именем файла" % [path, str(parsed["id"])])
		return {}
	return parsed


## Случайный заказ гостя: {"id", "text", "preferences", "dislikes"?}. Без списка orders — заказ по умолчанию из
## preferences. Гость с random_taste каждый раз придумывает вкус заново и старается отличаться от avoid
## (предпочтения предыдущего гостя {dim: вес}).
static func roll_order(guest: Dictionary, rng: RandomNumberGenerator, avoid: Dictionary = {}) -> Dictionary:
	if guest.has("random_taste"):
		return _random_order(guest["random_taste"], rng, avoid)
	var orders: Array = guest.get("orders", [])
	if orders.is_empty():
		return {"id": "default", "text": "Сделай мне кальян на свой вкус.", "preferences": guest.get("preferences", {})}
	return orders[rng.randi_range(0, orders.size() - 1)]


## Случайный контрастный вкус: основное измерение и (случайно) второе — не из avoid;
## неприятие — одно из измерений avoid (то, что любил предыдущий гость).
static func _random_order(config: Dictionary, rng: RandomNumberGenerator, avoid: Dictionary) -> Dictionary:
	var avoided: Array[String] = []
	for dimension in avoid:
		if float(avoid[dimension]) > 0.0 and IngredientCatalog.DIMENSIONS.has(str(dimension)):
			avoided.append(str(dimension))
	var candidates: Array[String] = []
	for dimension in IngredientCatalog.DIMENSIONS:
		if not avoided.has(dimension):
			candidates.append(dimension)
	if candidates.is_empty():
		for dimension in IngredientCatalog.DIMENSIONS:
			candidates.append(dimension)
	var primary: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	candidates.erase(primary)
	var preferences := {primary: 1.0}
	var text := str(config["phrases"][primary])
	if not candidates.is_empty() and rng.randf() < float(config.get("secondary_chance", 0.6)):
		var secondary: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		candidates.erase(secondary)
		preferences[secondary] = float(config.get("secondary_weight", 0.5))
		text += " " + str(config["also_phrases"][secondary])
	var order := {"id": "random_%s" % primary, "text": text, "preferences": preferences}
	if not avoided.is_empty() and rng.randf() < float(config.get("dislike_chance", 0.5)):
		var disliked := avoided[rng.randi_range(0, avoided.size() - 1)]
		if not preferences.has(disliked):
			order["dislikes"] = {disliked: float(config.get("dislike_weight", 0.8))}
			text += " " + str(config["dislike_phrases"][disliked])
			order["text"] = text
	return order


static func _valid_random_taste(config: Variant, path: String) -> bool:
	if not (config is Dictionary):
		GameLog.error("guests", "%s: random_taste должен быть объектом" % path)
		return false
	for key in ["phrases", "also_phrases", "dislike_phrases"]:
		var map: Variant = config.get(key)
		if not (map is Dictionary):
			GameLog.error("guests", "%s: random_taste.%s должен быть объектом" % [path, key])
			return false
		for dimension in IngredientCatalog.DIMENSIONS:
			if str(map.get(dimension, "")).is_empty():
				GameLog.error("guests", "%s: random_taste.%s: нет фразы для '%s'" % [path, key, dimension])
				return false
	return true


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


## Прощальная реплика гостя по id эмоции; {pay} заменяется суммой оплаты.
static func farewell_text(guest: Dictionary, emotion_id: String, likes: bool, payment: int, rng: RandomNumberGenerator) -> String:
	var farewells: Dictionary = guest.get("farewell", {})
	var lines: Array = farewells.get(emotion_id, [])
	var text := "Спасибо, бывай! Вот твои %d ₽." % payment
	if likes:
		text = "Классно посидели! Держи %d ₽, до встречи." % payment
	if not lines.is_empty():
		text = str(lines[rng.randi_range(0, lines.size() - 1)]).replace("{pay}", str(payment))
	return text
