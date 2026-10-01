class_name RecipeSystem
extends RefCounted
## Рецепты игрока (M3): оценка, сохранение в GameState, переиспользование, переименование.
##
## Эквивалентные миксы (одинаковые канонические доли и модификаторы) дают один и тот же
## рецепт: повторное приготовление не создаёт дубликат, а увеличивает счётчик использований.

signal recipe_created(recipe_id: String)
signal recipe_updated(recipe_id: String)

## Значение исполнения у рецепта, который ещё ни разу не готовили.
const NO_EXECUTION := -1.0

var catalog: IngredientCatalog
var config: ScoringConfig
var _state: Node


## Возвращает null, если контент (ингредиенты/скоринг) невалиден.
static func create(state: Node) -> RecipeSystem:
	var catalog_value := IngredientCatalog.load_default()
	var config_value := ScoringConfig.load_default(catalog_value)
	return create_with(state, catalog_value, config_value)


static func create_with(state: Node, catalog_value: IngredientCatalog, config_value: ScoringConfig) -> RecipeSystem:
	if not catalog_value.is_valid() or not config_value.is_valid():
		for message in catalog_value.errors + config_value.errors:
			GameLog.error("RecipeSystem", message)
		return null
	var system := RecipeSystem.new()
	system.catalog = catalog_value
	system.config = config_value
	system._state = state
	return system


## Оценка микса без сохранения. {"ok", "error"?, "canonical", "scoring", "auto_name", "existing"}
func evaluate(selection: Dictionary, modifiers: Array) -> Dictionary:
	var portions := 0
	for raw_id in selection:
		portions += roundi(float(selection[raw_id]))
	var canonical := RecipeCanonical.canonicalize(selection, modifiers, catalog, config, portions)
	if not canonical["ok"]:
		return {"ok": false, "error": canonical["error"]}
	var scoring := RecipeScoring.evaluate(canonical, catalog, config)
	var existing: Dictionary = _state.recipes.get(canonical["id"], {})
	return {
		"ok": true,
		"canonical": canonical,
		"scoring": scoring,
		"auto_name": auto_name(canonical, scoring),
		"existing": existing,
	}


## Сохраняет микс в книгу. Если такой рецепт уже есть, ничего не меняется (is_new == false):
## счётчик использований растёт только через record_preparation (приготовление).
## {"ok", "error"?, "is_new", "recipe_id", "recipe", "is_secret", "secret_message"}
func commit(selection: Dictionary, modifiers: Array, custom_name: String = "") -> Dictionary:
	var evaluation := evaluate(selection, modifiers)
	if not evaluation["ok"]:
		return {"ok": false, "error": evaluation["error"]}
	var canonical: Dictionary = evaluation["canonical"]
	var scoring: Dictionary = evaluation["scoring"]
	var recipe_id: String = canonical["id"]
	var trimmed := custom_name.strip_edges()
	var is_new: bool = not _state.recipes.has(recipe_id)
	var recipe: Dictionary
	if is_new:
		recipe = {
			"id": recipe_id,
			"key": canonical["key"],
			"name": evaluation["auto_name"],
			"custom_name": "" if scoring["secret_id"] != "" else trimmed,
			"ingredients": canonical["ingredients"],
			"modifiers": canonical["modifiers"],
			"best_score": scoring["quality"],
			"last_score": scoring["quality"],
			"times_used": 0,
			"best_execution": NO_EXECUTION,
			"last_execution": NO_EXECUTION,
			"created_seq": _state.next_recipe_seq(),
			"secret_id": scoring["secret_id"],
		}
		recipe["last_used_seq"] = recipe["created_seq"]
		_state.recipes[recipe_id] = recipe
	else:
		recipe = _state.recipes[recipe_id]
	if is_new:
		recipe_created.emit(recipe_id)
	return {
		"ok": true,
		"is_new": is_new,
		"recipe_id": recipe_id,
		"recipe": recipe,
		"is_secret": is_new and scoring["secret_id"] != "",
		"secret_message": scoring["secret_message"] if is_new else "",
	}


## Переименование. Пустое имя сбрасывает на автоназвание. Возвращает false, если рецепта нет
## или он секретный (секретные рецепты переименовывать нельзя).
func rename(recipe_id: String, new_name: String) -> bool:
	if not _state.recipes.has(recipe_id) or str(_state.recipes[recipe_id]["secret_id"]) != "":
		return false
	_state.recipes[recipe_id]["custom_name"] = new_name.strip_edges()
	recipe_updated.emit(recipe_id)
	return true


## Записывает приготовление рецепта: +1 к использованиям, последнее/лучшее исполнение (ExecutionScore).
## Качество самого рецепта (best_score/last_score) от приготовления не меняется.
func record_preparation(recipe_id: String, execution_score: float) -> bool:
	if not _state.recipes.has(recipe_id):
		return false
	var recipe: Dictionary = _state.recipes[recipe_id]
	recipe["times_used"] = int(recipe["times_used"]) + 1
	recipe["last_execution"] = execution_score
	recipe["best_execution"] = maxf(float(recipe.get("best_execution", NO_EXECUTION)), execution_score)
	recipe["last_used_seq"] = _state.next_recipe_seq()
	recipe_updated.emit(recipe_id)
	return true


## Записывает итог гостевой сессии: последняя и лучшая итоговая оценка рецепта (FinalScore) и гость.
## Старые записи без этих полей читаются через get() с NO_EXECUTION как "нет результата".
func record_session(recipe_id: String, final_score: float, guest_id: String, payment: int) -> bool:
	if not _state.recipes.has(recipe_id):
		return false
	var recipe: Dictionary = _state.recipes[recipe_id]
	recipe["last_final"] = final_score
	recipe["last_guest"] = guest_id
	recipe["last_payment"] = payment
	recipe["best_final"] = maxf(float(recipe.get("best_final", NO_EXECUTION)), final_score)
	recipe["sessions"] = int(recipe.get("sessions", 0)) + 1
	recipe_updated.emit(recipe_id)
	return true


## M7: итог последней сессии уточнён штрафами (жар, redo) — обновляем «последний результат» без нового сеанса.
func revise_last(recipe_id: String, final_score: float, payment: int) -> void:
	if not _state.recipes.has(recipe_id):
		return
	var recipe: Dictionary = _state.recipes[recipe_id]
	recipe["last_final"] = final_score
	recipe["last_payment"] = payment
	recipe_updated.emit(recipe_id)


## Состав для карточек: "Клубника 50% · Ваниль 50%" (+ "Ледяная нотка ❄️").
func composition_text(recipe: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item in recipe["ingredients"]:
		var percent := int(round(float(item["units"]) / float(config.total_units) * 100.0))
		parts.append("%s %d%%" % [catalog.label(item["id"]), percent])
	if recipe["modifiers"].has("ice"):
		parts.append("Ледяная нотка ❄️")
	return " · ".join(parts)


func get_recipe(recipe_id: String) -> Dictionary:
	return _state.recipes.get(recipe_id, {})


func all_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id in _state.recipes:
		result.append(_state.recipes[recipe_id])
	return result


## Отображаемое имя: своё, если задано, иначе автоназвание.
func display_name(recipe: Dictionary) -> String:
	var custom := str(recipe.get("custom_name", ""))
	return custom if not custom.is_empty() else str(recipe.get("name", ""))


## Автоназвание: два самых крупных ингредиента с эмодзи ("🍎 Яблоко + 🫐 Черника"),
## остальные — только эмодзи в конце ("... + 🍋" или "... + 🍋🍇"); один ингредиент — "Соло: 🍎 Яблоко";
## с модификатором льда в конце добавляется " ❄️".
func auto_name(canonical: Dictionary, scoring: Dictionary) -> String:
	if scoring["secret_name"] != "":
		return scoring["secret_name"]
	var items: Array = canonical["ingredients"].duplicate()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["units"] != b["units"]:
			return a["units"] > b["units"]
		return a["id"] < b["id"])
	var labels: Array[String] = []
	var emojis: Array[String] = []
	for item in items:
		var ingredient := catalog.get_ingredient(item["id"])
		labels.append("%s %s" % [ingredient["emoji"], ingredient["name"]])
		emojis.append(str(ingredient["emoji"]))
	var result: String
	if labels.size() == 1:
		result = "Соло: %s" % labels[0]
	else:
		result = "%s + %s" % [labels[0], labels[1]]
		if labels.size() > 2:
			result += " + " + "".join(emojis.slice(2))
	if canonical["modifiers"].has("ice"):
		result += " ❄️"
	return result


## Ключ сортировки по названию: без эмодзи и знаков, в нижнем регистре.
func sort_key(recipe: Dictionary) -> String:
	var regex := RegEx.create_from_string("[^\\p{L}\\p{N} ]")
	return regex.sub(display_name(recipe), "", true).strip_edges().to_lower()
