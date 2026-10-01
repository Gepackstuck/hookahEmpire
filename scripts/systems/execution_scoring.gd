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
	var levels := {}
	for entry in prep.parameters:
		var parameter_id: String = entry["id"]
		if not choices.has(parameter_id):
			return {"ok": false, "error": "Не выбран параметр '%s'" % parameter_id}
		var option_id := str(choices[parameter_id])
		var level := prep.option_level(parameter_id, option_id)
		if level < 0:
			return {"ok": false, "error": "Неизвестный вариант '%s' для параметра '%s'" % [option_id, parameter_id]}
		levels[parameter_id] = level
	return evaluate_levels(recipe, levels, catalog, config, prep)


## Множитель итога от подоценки состава (0..100): от MIX_MIN_FACTOR (совсем не тот состав) до 1 (состав достаточно близок).
const MIX_FULL_SCORE := 60.0
const MIX_MIN_FACTOR := 0.2


static func mix_factor(mix_score: float) -> float:
	return MIX_MIN_FACTOR + (1.0 - MIX_MIN_FACTOR) * clampf(mix_score / MIX_FULL_SCORE, 0.0, 1.0)


## Оценка по дробным уровням параметров {parameter_id: float|int} (быстрый режим отдаёт целые, ручной — дробные).
## extras (необязательно): "multipliers" {parameter_id: 0..1} — штраф качества исполнения (например, расстановка углей),
## "labels" {parameter_id: текст} — как показать выбранный уровень, "mix_score" (0..100) и "mix_hint" — подоценка состава.
static func evaluate_levels(recipe: Dictionary, levels: Dictionary, catalog: IngredientCatalog, config: ScoringConfig, prep: PreparationConfig, extras: Dictionary = {}) -> Dictionary:
	var recipe_targets := targets(features(recipe, catalog, config), prep)
	var multipliers: Dictionary = extras.get("multipliers", {})
	var labels: Dictionary = extras.get("labels", {})
	var tolerance_factors: Dictionary = extras.get("tolerance_factors", {})
	var penalty := prep.penalty_per_level * float(extras.get("penalty_factor", 1.0))
	var details: Array[Dictionary] = []
	var weighted := 0.0
	var weight_sum := 0.0
	for entry in prep.parameters:
		var parameter_id: String = entry["id"]
		if not levels.has(parameter_id):
			return {"ok": false, "error": "Нет уровня параметра '%s'" % parameter_id}
		var level_value: Variant = levels[parameter_id]
		var level := float(level_value)
		var target: float = recipe_targets[parameter_id]
		var distance := absf(level - target)
		var tolerance := prep.ok_tolerance * float(tolerance_factors.get(parameter_id, 1.0))
		var score := maxf(0.0, 100.0 - penalty * distance) * float(multipliers.get(parameter_id, 1.0))
		var hint: String = entry["hint_ok"]
		if distance > tolerance:
			hint = entry["hint_high"] if level > target else entry["hint_low"]
		var options: Array = entry["options"]
		var option_name: String = str(labels.get(parameter_id, options[clampi(roundi(level), 0, options.size() - 1)]["name"]))
		weighted += float(entry["weight"]) * score
		weight_sum += float(entry["weight"])
		details.append({
			"id": parameter_id,
			"name": entry["name"],
			"option_id": str(options[clampi(roundi(level), 0, options.size() - 1)]["id"]),
			"option_name": option_name,
			"level": level_value,
			"target": target,
			"score": score,
			"hint": hint,
			"is_ok": distance <= tolerance,
		})
	if extras.has("mix_score"):
		var mix_score := clampf(float(extras["mix_score"]), 0.0, 100.0)
		weighted += prep.manual_mix_weight * mix_score
		weight_sum += prep.manual_mix_weight
		details.append({
			"id": "mix",
			"name": "Состав",
			"option_id": "",
			"option_name": str(labels.get("mix", "")),
			"level": 0,
			"target": 0.0,
			"score": mix_score,
			"hint": str(extras.get("mix_hint", "")),
			"is_ok": mix_score >= 85.0,
		})
	var total := weighted / weight_sum
	if extras.has("mix_score"):
		# Неверный состав нельзя вытянуть идеальной техникой: итог умножается на коэффициент состава.
		total *= mix_factor(float(extras["mix_score"]))
	total = snappedf(total, 0.1)
	var band := config.band_for(total)
	return {
		"ok": true,
		"execution_score": total,
		"band_id": str(band.get("id", "")),
		"band_name": str(band.get("name", "")),
		"parameters": details,
	}
