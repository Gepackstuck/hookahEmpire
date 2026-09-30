class_name RecipeScoring
extends RefCounted
## Расчёт вкусового профиля и базового качества рецепта (M3).
## Чистые функции без UI: RecipeQuality = w_s * Synergy + w_b * Balance (+ бонус секретного рецепта).


## Полный расчёт. canonical — результат RecipeCanonical.canonicalize (ok == true).
static func evaluate(canonical: Dictionary, catalog: IngredientCatalog, config: ScoringConfig) -> Dictionary:
	var profile := taste_profile(canonical, catalog, config)
	var intensity_value := intensity(canonical, catalog, config)
	var synergy_score := synergy(canonical, catalog, config)
	var balance_score := balance(profile, intensity_value, config)
	var secret := {} if canonical.get("secret_blocked", false) else config.find_secret(RecipeCanonical.units_map(canonical))
	var bonus := float(secret.get("quality_bonus", 0.0))
	var quality := clampf(config.weight_synergy * synergy_score + config.weight_balance * balance_score + bonus, 0.0, 100.0)
	quality = snappedf(quality, 0.1)
	var band := config.band_for(quality)
	return {
		"profile": profile,
		"intensity": intensity_value,
		"synergy": synergy_score,
		"balance": balance_score,
		"quality": quality,
		"band_id": str(band.get("id", "")),
		"band_name": str(band.get("name", "")),
		"secret_id": str(secret.get("id", "")),
		"secret_name": str(secret.get("name", "")),
		"secret_message": str(secret.get("discovery_message", "")),
	}


## Взвешенный вкусовой профиль по измерениям (значения 0..1) с учётом модификаторов.
static func taste_profile(canonical: Dictionary, catalog: IngredientCatalog, config: ScoringConfig) -> Dictionary:
	var profile := {}
	for dim in IngredientCatalog.DIMENSIONS:
		profile[dim] = 0.0
	for item in canonical["ingredients"]:
		var share := float(item["units"]) / float(config.total_units)
		var ingredient := catalog.get_ingredient(item["id"])
		for dim in IngredientCatalog.DIMENSIONS:
			profile[dim] += share * float(ingredient[dim])
	for modifier_id in canonical["modifiers"]:
		var delta: Dictionary = catalog.get_modifier(modifier_id)["profile_delta"]
		for dim in delta:
			profile[dim] += float(delta[dim])
	for dim in IngredientCatalog.DIMENSIONS:
		profile[dim] = clampf(profile[dim], 0.0, 1.0)
	return profile


static func intensity(canonical: Dictionary, catalog: IngredientCatalog, config: ScoringConfig) -> float:
	var total := 0.0
	for item in canonical["ingredients"]:
		total += float(item["units"]) / float(config.total_units) * float(catalog.get_ingredient(item["id"])["intensity"])
	return total


## 0..100: среднее по парам, взвешенное долями (p_i * p_j), из матрицы [-1, 1]: 0 -> synergy_neutral, 1 -> 100, -1 -> 0.
## Для одного ингредиента пар нет — берётся нейтральное значение из конфига.
static func synergy(canonical: Dictionary, catalog: IngredientCatalog, config: ScoringConfig) -> float:
	var items: Array = canonical["ingredients"]
	if items.size() < 2:
		return config.single_ingredient_synergy
	var weighted_sum := 0.0
	var weight_total := 0.0
	for i in items.size():
		for j in range(i + 1, items.size()):
			var weight := float(items[i]["units"]) * float(items[j]["units"])
			weighted_sum += weight * catalog.synergy_between(items[i]["id"], items[j]["id"])
			weight_total += weight
	var average := weighted_sum / weight_total
	if average >= 0.0:
		return config.synergy_neutral + (100.0 - config.synergy_neutral) * average
	return config.synergy_neutral + config.synergy_neutral * average


## 0..100: штрафы за конфликтующие вкусы (например, сладкое + кислое) и за слишком слабую/сильную крепость.
static func balance(profile: Dictionary, intensity_value: float, config: ScoringConfig) -> float:
	var penalty := 0.0
	for conflict in config.conflicts:
		penalty += minf(float(profile[conflict["a"]]), float(profile[conflict["b"]])) * float(conflict["weight"]) * config.conflict_scale
	var excess := maxf(intensity_value - config.intensity_max, 0.0) + maxf(config.intensity_min - intensity_value, 0.0)
	penalty += excess * config.intensity_penalty_per_unit
	return clampf(100.0 - penalty, 0.0, 100.0)
