class_name ExecutionScoring
extends RefCounted
## ExecutionScore быстрого приготовления (M4): чистые функции без UI и без случайности.
## Для рецепта считаются "оптимальные" уровни параметров; чем дальше выбор от оптимума, тем ниже оценка.


## Признаки рецепта: вкусовой профиль, intensity и средняя чувствительность к жару.
static func features(recipe: Dictionary, catalog: IngredientCatalog, config: ScoringConfig) -> Dictionary:
	var shape := {"ingredients": recipe["ingredients"], "modifiers": recipe["modifiers"]}
	var result := RecipeScoring.taste_profile(shape, catalog, config)
	result["intensity"] = RecipeScoring.intensity(shape, catalog, config)
	var heat := 0.0
	for item in recipe["ingredients"]:
		heat += float(item["units"]) / float(config.total_units) * float(catalog.get_ingredient(item["id"])["heat_sensitivity"])
	result["heat_sensitivity"] = heat
	return result


## Оптимальный (дробный) уровень каждого параметра: {parameter_id: float в 0..N-1}.
static func targets(recipe_features: Dictionary, prep: PreparationConfig) -> Dictionary:
	var result := {}
	for entry in prep.parameters:
		var target: float = entry["base"]
		for feature in entry["weights"]:
			target += float(entry["weights"][feature]) * float(recipe_features.get(feature, 0.0))
		result[entry["id"]] = clampf(target, 0.0, float(entry["options"].size() - 1))
	return result


## choices: {parameter_id: option_id} — обязаны быть выбраны все параметры.
## Возвращает {"ok", "error"?, "execution_score", "band_id", "band_name", "parameters": [...]}.
static func evaluate(recipe: Dictionary, choices: Dictionary, catalog: IngredientCatalog, config: ScoringConfig, prep: PreparationConfig) -> Dictionary:
	var recipe_targets := targets(features(recipe, catalog, config), prep)
	var details: Array[Dictionary] = []
	var weighted := 0.0
	var weight_sum := 0.0
	for entry in prep.parameters:
		var parameter_id: String = entry["id"]
		if not choices.has(parameter_id):
			return {"ok": false, "error": "Не выбран параметр '%s'" % parameter_id}
		var option_id := str(choices[parameter_id])
		var level := prep.option_level(parameter_id, option_id)
		if level < 0:
			return {"ok": false, "error": "Неизвестный вариант '%s' для параметра '%s'" % [option_id, parameter_id]}
		var target: float = recipe_targets[parameter_id]
		var distance := absf(float(level) - target)
		var score := maxf(0.0, 100.0 - prep.penalty_per_level * distance)
		var hint: String = entry["hint_ok"]
		if distance > prep.ok_tolerance:
			hint = entry["hint_high"] if float(level) > target else entry["hint_low"]
		weighted += float(entry["weight"]) * score
		weight_sum += float(entry["weight"])
		details.append({
			"id": parameter_id,
			"name": entry["name"],
			"option_id": option_id,
			"option_name": entry["options"][level]["name"],
			"level": level,
			"target": target,
			"score": score,
			"hint": hint,
			"is_ok": distance <= prep.ok_tolerance,
		})
	var total := snappedf(weighted / weight_sum, 0.1)
	var band := config.band_for(total)
	return {
		"ok": true,
		"execution_score": total,
		"band_id": str(band.get("id", "")),
		"band_name": str(band.get("name", "")),
		"parameters": details,
	}
