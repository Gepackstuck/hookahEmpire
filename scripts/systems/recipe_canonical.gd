class_name RecipeCanonical
extends RefCounted
## Приведение микса к канонической форме и генерация стабильного id рецепта.
##
## Вход — "сырые" веса ингредиентов (например, значения ползунков) и список модификаторов.
## Выход — доли в целых единицах (сумма = config.total_units), отсортированные по id:
## эквивалентные миксы (2:1:1 и 4:2:2) дают один и тот же key/id.


## Возвращает {"ok": true, "ingredients": [{"id", "units"}], "modifiers": [...], "key", "id"}
## или {"ok": false, "error": "..."}.
##
## portions — общее число порций в смесителе (-1 — неизвестно). Секретный рецепт требует полного
## бюджета порций (config.max_portions): при меньшем числе порций микс — обычный рецепт
## (secret_blocked), с другим key/id, чтобы не совпадать с секретным.
static func canonicalize(selection: Dictionary, modifiers: Array, catalog: IngredientCatalog, config: ScoringConfig, portions: int = -1) -> Dictionary:
	var weights := {}
	for raw_id in selection:
		var weight := float(selection[raw_id])
		if weight <= 0.0:
			continue
		if not catalog.has_ingredient(str(raw_id)):
			return _fail("Неизвестный ингредиент: %s" % str(raw_id))
		weights[str(raw_id)] = weight
	var mods: Array[String] = []
	for raw_modifier in modifiers:
		var modifier_id := str(raw_modifier)
		if not catalog.has_modifier(modifier_id):
			return _fail("Неизвестный модификатор: %s" % modifier_id)
		if not mods.has(modifier_id):
			mods.append(modifier_id)
	mods.sort()
	if weights.is_empty():
		return _fail("Микс пуст")

	var units := _distribute(weights, config.total_units)
	if units.is_empty():
		return _fail("Не удалось распределить доли")
	if units.size() > config.max_ingredients:
		return _fail("Слишком много ингредиентов: %d (максимум %d)" % [units.size(), config.max_ingredients])

	var ids: Array = units.keys()
	ids.sort()
	var ingredients: Array[Dictionary] = []
	var parts: PackedStringArray = []
	for ingredient_id in ids:
		ingredients.append({"id": ingredient_id, "units": units[ingredient_id]})
		parts.append("%s:%d" % [ingredient_id, units[ingredient_id]])
	var key := "|".join(parts)
	if not mods.is_empty():
		key += ";" + "+".join(mods)
	var secret_blocked := false
	if portions >= 0 and portions < config.max_portions and not config.find_secret(units).is_empty():
		secret_blocked = true
		key += "#partial"
	return {
		"secret_blocked": secret_blocked,
		"ok": true,
		"ingredients": ingredients,
		"modifiers": mods,
		"key": key,
		"id": "r_" + key.md5_text().substr(0, 10),
	}


## Публичная обёртка над распределением долей: {id: вес} -> {id: целые единицы, сумма total}.
static func distribute_units(weights: Dictionary, total: int) -> Dictionary:
	return _distribute(weights, total)


## Словарь {ingredient_id: units} из канонической формы.
static func units_map(canonical: Dictionary) -> Dictionary:
	var result := {}
	for item in canonical["ingredients"]:
		result[item["id"]] = item["units"]
	return result


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}


## Метод наибольших остатков: целые единицы с суммой total. Ингредиенты, у которых
## получилось 0 единиц (слишком малая доля), отбрасываются, и распределение пересчитывается.
static func _distribute(weights: Dictionary, total: int) -> Dictionary:
	var current := weights.duplicate()
	while not current.is_empty():
		var sum := 0.0
		for id in current:
			sum += float(current[id])
		var ids: Array = current.keys()
		ids.sort()
		var floors := {}
		var remainders: Array[Dictionary] = []
		var assigned := 0
		for id in ids:
			var exact: float = float(current[id]) / sum * float(total)
			var whole := floori(exact + 1e-9)
			floors[id] = whole
			assigned += whole
			remainders.append({"id": id, "frac": maxf(exact - float(whole), 0.0)})
		remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(a["frac"], b["frac"]):
				return a["frac"] > b["frac"]
			return a["id"] < b["id"])
		for i in range(total - assigned):
			floors[remainders[i]["id"]] += 1
		var zeros: Array = []
		for id in ids:
			if floors[id] == 0:
				zeros.append(id)
		if zeros.is_empty():
			return floors
		for id in zeros:
			current.erase(id)
	return {}
