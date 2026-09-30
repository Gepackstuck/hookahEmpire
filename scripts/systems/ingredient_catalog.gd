class_name IngredientCatalog
extends RefCounted
## Каталог ингредиентов, модификаторов и матрица сочетаний (data/ingredients/*.json).
## Ошибки загрузки копятся в errors; is_valid() == false — каталогом пользоваться нельзя.

const DIMENSIONS: Array[String] = ["sweet", "fresh", "sour", "fruit", "creamy", "spicy", "heavy"]
const INGREDIENTS_PATH := "res://data/ingredients/ingredients.json"
const MODIFIERS_PATH := "res://data/ingredients/modifiers.json"
const SYNERGY_PATH := "res://data/ingredients/synergy.json"

var errors: Array[String] = []

var _ingredients: Dictionary = {} # id -> Dictionary
var _order: Array[String] = []
var _modifiers: Dictionary = {}
var _modifier_order: Array[String] = []
var _synergy: Dictionary = {} # "a|b" (a < b) -> float


static func load_default() -> IngredientCatalog:
	return load_files(INGREDIENTS_PATH, MODIFIERS_PATH, SYNERGY_PATH)


static func load_files(ingredients_path: String, modifiers_path: String, synergy_path: String) -> IngredientCatalog:
	var catalog := IngredientCatalog.new()
	catalog._load_ingredients(_read_json(ingredients_path, catalog.errors))
	catalog._load_modifiers(_read_json(modifiers_path, catalog.errors))
	catalog._load_synergy(_read_json(synergy_path, catalog.errors))
	return catalog


## Для тестов: сборка из уже разобранных словарей.
static func from_dicts(ingredients: Dictionary, modifiers: Dictionary, synergy: Dictionary) -> IngredientCatalog:
	var catalog := IngredientCatalog.new()
	catalog._load_ingredients(ingredients)
	catalog._load_modifiers(modifiers)
	catalog._load_synergy(synergy)
	return catalog


func is_valid() -> bool:
	return errors.is_empty()


func has_ingredient(ingredient_id: String) -> bool:
	return _ingredients.has(ingredient_id)


func get_ingredient(ingredient_id: String) -> Dictionary:
	return _ingredients.get(ingredient_id, {})


## Id ингредиентов в порядке файла.
func ingredient_ids() -> Array[String]:
	return _order


func has_modifier(modifier_id: String) -> bool:
	return _modifiers.has(modifier_id)


func get_modifier(modifier_id: String) -> Dictionary:
	return _modifiers.get(modifier_id, {})


func modifier_ids() -> Array[String]:
	return _modifier_order


## Симметричное значение сочетания [-1, 1]; неизвестная пара нейтральна (0).
func synergy_between(a: String, b: String) -> float:
	return float(_synergy.get(_pair_key(a, b), 0.0))


## Название с эмодзи для UI: "🍓 Клубника".
func label(ingredient_id: String) -> String:
	var item: Dictionary = _ingredients.get(ingredient_id, _modifiers.get(ingredient_id, {}))
	if item.is_empty():
		return ingredient_id
	return "%s %s" % [item["emoji"], item["name"]]


static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func _read_json(path: String, errs: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		errs.append("Файл не найден: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		errs.append("%s: не JSON-объект" % path)
		return {}
	return parsed


func _load_ingredients(data: Dictionary) -> void:
	var raw: Variant = data.get("ingredients")
	if not (raw is Array) or raw.is_empty():
		errors.append("ingredients: нужен непустой массив")
		return
	for index in raw.size():
		var entry: Variant = raw[index]
		var item := _parse_ingredient(entry, index)
		if item.is_empty():
			continue
		if _ingredients.has(item["id"]) or _modifiers.has(item["id"]):
			errors.append("ингредиент '%s': id повторяется" % item["id"])
			continue
		_ingredients[item["id"]] = item
		_order.append(item["id"])


func _parse_ingredient(entry: Variant, index: int) -> Dictionary:
	var label := "ингредиент #%d" % index
	if not (entry is Dictionary):
		errors.append("%s: должен быть объектом" % label)
		return {}
	var item_id := str(entry.get("id", ""))
	for key in ["id", "name", "emoji"]:
		if str(entry.get(key, "")).is_empty():
			errors.append("%s: не задано поле '%s'" % [label, key])
			return {}
	label = "ингредиент '%s'" % item_id
	var item := {
		"id": item_id,
		"name": str(entry["name"]),
		"emoji": str(entry["emoji"]),
		"cost": int(entry.get("cost", 0)),
		"unlock_condition": str(entry.get("unlock_condition", "always")),
		"trend_tags": entry.get("trend_tags", []),
	}
	for key in DIMENSIONS + ["intensity"]:
		var value: Variant = entry.get(key)
		if not (value is int or value is float) or value < 0.0 or value > 1.0:
			errors.append("%s: поле '%s' должно быть числом 0..1" % [label, key])
			return {}
		item[key] = float(value)
	var heat: Variant = entry.get("heat_sensitivity", 0.5)
	item["heat_sensitivity"] = float(heat) if (heat is int or heat is float) else 0.5
	if int(item["cost"]) < 0:
		errors.append("%s: cost не может быть отрицательным" % label)
		return {}
	return item


func _load_modifiers(data: Dictionary) -> void:
	var raw: Variant = data.get("modifiers")
	if not (raw is Array):
		errors.append("modifiers: нужен массив")
		return
	for index in raw.size():
		var entry: Variant = raw[index]
		if not (entry is Dictionary):
			errors.append("модификатор #%d: должен быть объектом" % index)
			continue
		var item_id := str(entry.get("id", ""))
		if item_id.is_empty() or str(entry.get("name", "")).is_empty() or str(entry.get("emoji", "")).is_empty():
			errors.append("модификатор #%d: нужны id, name, emoji" % index)
			continue
		if _modifiers.has(item_id) or _ingredients.has(item_id):
			errors.append("модификатор '%s': id повторяется" % item_id)
			continue
		var delta: Variant = entry.get("profile_delta", {})
		var clean := {}
		var valid := delta is Dictionary
		if valid:
			for dim in delta:
				var value: Variant = delta[dim]
				if not DIMENSIONS.has(str(dim)) or not (value is int or value is float) or absf(float(value)) > 1.0:
					errors.append("модификатор '%s': profile_delta.%s некорректен" % [item_id, str(dim)])
					valid = false
					break
				clean[str(dim)] = float(value)
		else:
			errors.append("модификатор '%s': profile_delta должен быть объектом" % item_id)
		if not valid:
			continue
		_modifiers[item_id] = {
			"id": item_id,
			"name": str(entry["name"]),
			"emoji": str(entry["emoji"]),
			"cost": int(entry.get("cost", 0)),
			"profile_delta": clean,
		}
		_modifier_order.append(item_id)


func _load_synergy(data: Dictionary) -> void:
	var raw: Variant = data.get("pairs")
	if not (raw is Array):
		errors.append("synergy: pairs должен быть массивом")
		return
	for index in raw.size():
		var entry: Variant = raw[index]
		var label := "сочетание #%d" % index
		if not (entry is Dictionary):
			errors.append("%s: должно быть объектом" % label)
			continue
		var a := str(entry.get("a", ""))
		var b := str(entry.get("b", ""))
		var value: Variant = entry.get("value")
		if a == b or not _ingredients.has(a) or not _ingredients.has(b):
			errors.append("%s: нужны два разных существующих ингредиента (%s, %s)" % [label, a, b])
			continue
		if not (value is int or value is float) or absf(float(value)) > 1.0:
			errors.append("%s (%s, %s): value должно быть числом -1..1" % [label, a, b])
			continue
		var key := _pair_key(a, b)
		if _synergy.has(key):
			errors.append("%s: пара %s + %s уже задана" % [label, a, b])
			continue
		_synergy[key] = float(value)
