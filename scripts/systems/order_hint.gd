class_name OrderHint
extends RefCounted
## Подсказка для тестов/первого раза: какие ингредиенты лучше всего подходят под вкус заказа.


## Подсказка-строка для UI. Без rng — детерминированно (лучшие по совпадению); с rng — первый ингредиент
## случайный из топ-3, второй подбирается по совпадению и сочетанию с первым, чтобы подсказки не повторялись.
static func suggest(catalog: IngredientCatalog, preferences: Dictionary, count: int = 2, rng: RandomNumberGenerator = null) -> String:
	var ranked := rank(catalog, preferences)
	var picked: Array[String] = []
	if rng != null and ranked.size() >= 3 and count >= 2:
		var first := ranked[rng.randi_range(0, mini(2, ranked.size() - 1))]
		picked.append(first)
		var best := ""
		var best_value := -INF
		for candidate in ranked.slice(0, mini(5, ranked.size())):
			if candidate == first:
				continue
			var value := fit(catalog, candidate, preferences) + 0.5 * catalog.synergy_between(first, candidate)
			if value > best_value:
				best_value = value
				best = candidate
		if best != "":
			picked.append(best)
	else:
		for index in mini(count, ranked.size()):
			picked.append(ranked[index])
	var names: Array[String] = []
	for ingredient_id in picked:
		names.append(catalog.label(ingredient_id))
	if names.is_empty():
		return "смешай что захочешь"
	return "попробуй %s" % " + ".join(names)


## Совпадение вкусового профиля ингредиента с предпочтениями.
static func fit(catalog: IngredientCatalog, ingredient_id: String, preferences: Dictionary) -> float:
	var item := catalog.get_ingredient(ingredient_id)
	var total := 0.0
	for dimension in preferences:
		total += float(preferences[dimension]) * float(item.get(dimension, 0.0))
	return total


## Id ингредиентов по убыванию совпадения с предпочтениями (при равенстве — порядок файла).
static func rank(catalog: IngredientCatalog, preferences: Dictionary) -> Array[String]:
	var scored: Array = []
	for ingredient_id in catalog.ingredient_ids():
		scored.append([fit(catalog, ingredient_id, preferences), scored.size(), ingredient_id])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var result: Array[String] = []
	for entry in scored:
		result.append(str(entry[2]))
	return result
