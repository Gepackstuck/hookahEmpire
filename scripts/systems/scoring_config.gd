class_name ScoringConfig
extends RefCounted
## Баланс-параметры скоринга рецептов и секретные рецепты
## (data/config/scoring.json, data/recipes/secret_recipes.json).

const CONFIG_PATH := "res://data/config/scoring.json"
const SECRETS_PATH := "res://data/recipes/secret_recipes.json"

var errors: Array[String] = []

var weight_synergy: float = 0.7
var weight_balance: float = 0.3
var max_ingredients: int = 4
## Сколько "единиц" в полном миксе; доли хранятся в единицах (шаг = 1/total_units).
var total_units: int = 20
## Общий бюджет порций в смесителе (1 ингредиент — до 4 порций, 2 — 1+3 или 2+2 и т.д.).
var max_portions: int = 4
var single_ingredient_synergy: float = 50.0
## Оценка синергии для нейтральной пары (значение матрицы 0); положительные значения тянут к 100, отрицательные — к 0.
var synergy_neutral: float = 50.0
var dimension_names: Dictionary = {}
var conflicts: Array[Dictionary] = []
var conflict_scale: float = 100.0
var intensity_min: float = 0.35
var intensity_max: float = 0.75
var intensity_penalty_per_unit: float = 80.0
var bands: Array[Dictionary] = []
## Секретные рецепты: {id, name, units: {ingredient_id: units}, quality_bonus, discovery_message}.
var secrets: Array[Dictionary] = []


static func load_default(catalog: IngredientCatalog) -> ScoringConfig:
	return load_files(CONFIG_PATH, SECRETS_PATH, catalog)


static func load_files(config_path: String, secrets_path: String, catalog: IngredientCatalog) -> ScoringConfig:
	var config := ScoringConfig.new()
	config._parse(_read(config_path, config.errors))
	config._parse_secrets(_read(secrets_path, config.errors), catalog)
	return config


static func from_dicts(config_data: Dictionary, secrets_data: Dictionary, catalog: IngredientCatalog) -> ScoringConfig:
	var config := ScoringConfig.new()
	config._parse(config_data)
	config._parse_secrets(secrets_data, catalog)
	return config


func is_valid() -> bool:
	return errors.is_empty()


## Описание полосы качества (id, name, min) для оценки 0..100.
func band_for(score: float) -> Dictionary:
	var result: Dictionary = bands[0] if not bands.is_empty() else {}
	for band in bands:
		if score >= float(band["min"]):
			result = band
	return result


## Секретный рецепт, совпадающий с каноническим (по ингредиентам; модификаторы не важны).
func find_secret(canonical_units: Dictionary) -> Dictionary:
	for secret in secrets:
		if secret["units"] == canonical_units:
			return secret
	return {}


static func _read(path: String, errs: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		errs.append("Файл не найден: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		errs.append("%s: не JSON-объект" % path)
		return {}
	return parsed


func _parse(data: Dictionary) -> void:
	if data.is_empty():
		return
	var weights: Variant = data.get("weights")
	if weights is Dictionary and _is_number(weights.get("synergy")) and _is_number(weights.get("balance")):
		weight_synergy = float(weights["synergy"])
		weight_balance = float(weights["balance"])
	else:
		errors.append("scoring: weights должен содержать числа synergy и balance")
	max_ingredients = int(data.get("max_ingredients", max_ingredients))
	total_units = int(data.get("total_units", total_units))
	max_portions = int(data.get("max_portions", max_portions))
	if max_portions < max_ingredients:
		errors.append("scoring: max_portions должен быть >= max_ingredients")
	if max_ingredients < 1 or total_units < max_ingredients:
		errors.append("scoring: max_ingredients >= 1 и total_units >= max_ingredients")
	single_ingredient_synergy = float(data.get("single_ingredient_synergy", single_ingredient_synergy))
	synergy_neutral = float(data.get("synergy_neutral", synergy_neutral))
	if synergy_neutral <= 0.0 or synergy_neutral >= 100.0:
		errors.append("scoring: synergy_neutral должен быть между 0 и 100")

	var names: Variant = data.get("dimension_names")
	if names is Dictionary:
		dimension_names = names
	for dim in IngredientCatalog.DIMENSIONS:
		if not dimension_names.has(dim):
			errors.append("scoring: нет названия для вкусового измерения '%s'" % dim)

	var balance: Variant = data.get("balance")
	if not (balance is Dictionary):
		errors.append("scoring: нет секции balance")
	else:
		conflict_scale = float(balance.get("conflict_scale", conflict_scale))
		intensity_min = float(balance.get("intensity_min", intensity_min))
		intensity_max = float(balance.get("intensity_max", intensity_max))
		intensity_penalty_per_unit = float(balance.get("intensity_penalty_per_unit", intensity_penalty_per_unit))
		var raw_conflicts: Variant = balance.get("conflicts", [])
		if raw_conflicts is Array:
			for entry in raw_conflicts:
				if entry is Dictionary and IngredientCatalog.DIMENSIONS.has(str(entry.get("a", ""))) \
						and IngredientCatalog.DIMENSIONS.has(str(entry.get("b", ""))) and _is_number(entry.get("weight")):
					conflicts.append({"a": str(entry["a"]), "b": str(entry["b"]), "weight": float(entry["weight"])})
				else:
					errors.append("scoring: некорректный conflict %s" % str(entry))

	var raw_bands: Variant = data.get("bands")
	if raw_bands is Array and not raw_bands.is_empty():
		for entry in raw_bands:
			if entry is Dictionary and _is_number(entry.get("min")) and not str(entry.get("name", "")).is_empty():
				bands.append({"min": float(entry["min"]), "id": str(entry.get("id", "")), "name": str(entry["name"])})
			else:
				errors.append("scoring: некорректная полоса качества %s" % str(entry))
		bands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["min"] < y["min"])
	else:
		errors.append("scoring: bands должен быть непустым массивом")


func _parse_secrets(data: Dictionary, catalog: IngredientCatalog) -> void:
	var raw: Variant = data.get("secret_recipes", [])
	if not (raw is Array):
		errors.append("secret_recipes: нужен массив")
		return
	var seen := {}
	for entry in raw:
		var label := "секретный рецепт '%s'" % str(entry.get("id", "?") if entry is Dictionary else "?")
		if not (entry is Dictionary) or str(entry.get("id", "")).is_empty() or str(entry.get("name", "")).is_empty():
			errors.append("%s: нужны id и name" % label)
			continue
		if seen.has(entry["id"]):
			errors.append("%s: id повторяется" % label)
			continue
		seen[entry["id"]] = true
		var ingredients: Variant = entry.get("ingredients")
		if not (ingredients is Dictionary) or ingredients.is_empty():
			errors.append("%s: ingredients должен быть непустым объектом {id: доля}" % label)
			continue
		var units := {}
		var total := 0
		var valid := true
		for ingredient_id in ingredients:
			var proportion: Variant = ingredients[ingredient_id]
			if not catalog.has_ingredient(str(ingredient_id)) or not _is_number(proportion):
				errors.append("%s: неизвестный ингредиент или доля '%s'" % [label, str(ingredient_id)])
				valid = false
				break
			var unit_count := roundi(float(proportion) * total_units)
			if unit_count < 1 or not is_equal_approx(float(unit_count), float(proportion) * total_units):
				errors.append("%s: доля %s не кратна шагу 1/%d" % [label, str(ingredient_id), total_units])
				valid = false
				break
			units[str(ingredient_id)] = unit_count
			total += unit_count
		if not valid:
			continue
		if total != total_units:
			errors.append("%s: доли должны давать в сумме 1.0" % label)
			continue
		secrets.append({
			"id": str(entry["id"]),
			"name": str(entry["name"]),
			"units": units,
			"quality_bonus": float(entry.get("quality_bonus", 0.0)),
			"discovery_message": str(entry.get("discovery_message", "")),
		})


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
