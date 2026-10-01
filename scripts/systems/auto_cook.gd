class_name AutoCook
extends RefCounted
## Автопилот кальянщика (затравка под нанятых работников): подбирает микс под заказ гостя и параметры
## приготовления «почти правильно» — с ошибками, чтобы выглядело живо. Чистая логика без UI.
## mistake_chance / noise — «неопытность»: позже их будет задавать уровень навыка работника.

const DEFAULT_MISTAKE_CHANCE := 0.35
const DEFAULT_NOISE := 0.3
## Рецепт из книги годится, если GuestFit не ниже этого значения.
const FIT_MIN_FOR_EXISTING := 65.0


## Подбирает микс под предпочтения заказа: {"selection": {ingredient_id: порции}, "modifiers": [...]}.
## Первый ингредиент — случайный из топ-3 по совпадению со вкусом, второй — лучший по совпадению и сочетанию
## с первым; с шансом noise второй берётся наугад из топ-8 (ошибка новичка). Всего 4 порции.
static func pick_mix(catalog: IngredientCatalog, preferences: Dictionary, rng: RandomNumberGenerator, noise: float = DEFAULT_NOISE, allowed: Array = []) -> Dictionary:
	var ranked := OrderHint.rank(catalog, preferences)
	if not allowed.is_empty():
		# Например, только бесплатные ингредиенты, когда не хватает денег.
		var filtered: Array[String] = []
		for id in ranked:
			if allowed.has(id):
				filtered.append(id)
		ranked = filtered
	if ranked.is_empty():
		return {"selection": {}, "modifiers": []}
	var first := ranked[rng.randi_range(0, mini(2, ranked.size() - 1))]
	var selection := {}
	if ranked.size() < 2:
		selection[first] = 4
		return {"selection": selection, "modifiers": []}
	var second := ""
	if rng.randf() < noise:
		var pool := ranked.slice(0, mini(8, ranked.size()))
		pool.erase(first)
		second = pool[rng.randi_range(0, pool.size() - 1)]
	else:
		var best_value := -INF
		for candidate in ranked.slice(0, mini(5, ranked.size())):
			if candidate == first:
				continue
			var value := OrderHint.fit(catalog, candidate, preferences) + 0.5 * catalog.synergy_between(first, candidate)
			if value > best_value:
				best_value = value
				second = candidate
	var first_portions: int = [2, 2, 3, 1][rng.randi_range(0, 3)]
	selection[first] = first_portions
	selection[second] = 4 - first_portions
	var modifiers: Array = []
	if float(preferences.get("fresh", 0.0)) > 0.0 and rng.randf() < 0.5:
		modifiers.append("ice")
	return {"selection": selection, "modifiers": modifiers}


## Подходящий рецепт из книги: лучший по GuestFit, если он не ниже min_fit (иначе ""), —
## тогда к смесителю идти не нужно, можно сразу забивать.
static func find_fitting_recipe(recipes: Array, catalog: IngredientCatalog, config: ScoringConfig, scoring: SessionScoring, taste: Dictionary, min_fit: float) -> String:
	var best_id := ""
	var best_fit := min_fit
	for recipe in recipes:
		var profile := RecipeScoring.taste_profile({"ingredients": recipe["ingredients"], "modifiers": recipe["modifiers"]}, catalog, config)
		var fit := scoring.guest_fit(profile, taste)
		if fit >= best_fit and (best_id == "" or fit > best_fit):
			best_fit = fit
			best_id = str(recipe["id"])
	return best_id


## Элементы рецепта для чипов над головой: id ингредиентов и "ice" для льда.
static func recipe_items(recipe: Dictionary) -> Array:
	var items: Array = []
	for item in recipe["ingredients"]:
		items.append(str(item["id"]))
	if recipe["modifiers"].has(TasteIcons.ICE_ID):
		items.append(TasteIcons.ICE_ID)
	return items


## Параметры быстрого приготовления {parameter_id: option_id}: оптимальный уровень для рецепта,
## но с шансом mistake_chance на каждый параметр кальянщик ошибается ровно на один уровень.
static func pick_choices(prep: PreparationConfig, recipe: Dictionary, catalog: IngredientCatalog, config: ScoringConfig, rng: RandomNumberGenerator, mistake_chance: float = DEFAULT_MISTAKE_CHANCE) -> Dictionary:
	var features := ExecutionScoring.features(recipe, catalog, config)
	var targets := ExecutionScoring.targets(features, prep)
	var choices := {}
	for entry in prep.parameters:
		var options: Array = entry["options"]
		var level := roundi(float(targets[entry["id"]]))
		if rng.randf() < mistake_chance:
			var step := 1 if rng.randf() < 0.5 else -1
			if level + step < 0 or level + step > options.size() - 1:
				step = -step
			level += step
		choices[entry["id"]] = options[clampi(level, 0, options.size() - 1)]["id"]
	return choices
