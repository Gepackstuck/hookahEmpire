class_name PreparationService
extends RefCounted
## Приготовление кальяна: запрос (рецепт + выбор параметров + кто готовит) -> результат.
## Не зависит от UI и от того, кто выбрал параметры: игрок в быстром режиме, игрок в ручном
## режиме (M5) или нанятый кальянщик (идея на будущее) отдают сюда один и тот же запрос.
## Результат уходит в сигнал preparation_completed — его получает окно результата, а в M6 — гость.

signal preparation_completed(result: Dictionary)

const MODE_QUICK := "quick"
const MODE_MANUAL := "manual"

var recipes: RecipeSystem
var config: PreparationConfig


## Возвращает null, если данные приготовления невалидны.
static func create(recipe_system: RecipeSystem) -> PreparationService:
	return create_with(recipe_system, PreparationConfig.load_default())


static func create_with(recipe_system: RecipeSystem, prep_config: PreparationConfig) -> PreparationService:
	if recipe_system == null or not prep_config.is_valid():
		for message in prep_config.errors:
			GameLog.error("preparation", message)
		return null
	var service := PreparationService.new()
	service.recipes = recipe_system
	service.config = prep_config
	return service


func default_choices() -> Dictionary:
	return config.default_choices()


## Оценка приготовления БЕЗ записи: игрок может изменить параметры и пересчитать, пока не «подал» кальян.
## preparer — кто готовит ("player" по умолчанию), mode — как ("quick"); пока только для результата.
func preview(recipe_id: String, choices: Dictionary, preparer: String = "player", mode: String = MODE_QUICK) -> Dictionary:
	var recipe := recipes.get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "error": "Рецепт не найден: %s" % recipe_id}
	var execution := ExecutionScoring.evaluate(recipe, choices, recipes.catalog, recipes.config, config)
	return _build_result(recipe_id, recipe, execution, choices, preparer, mode)


## Ручной режим (M5): уровни параметров {id: float} и дополнительные оценки действий игрока (см. ExecutionScoring.evaluate_levels).
## Без записи результата, как preview.
func preview_manual(recipe_id: String, levels: Dictionary, extras: Dictionary = {}, preparer: String = "player") -> Dictionary:
	var recipe := recipes.get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "error": "Рецепт не найден: %s" % recipe_id}
	var execution := ExecutionScoring.evaluate_levels(recipe, levels, recipes.catalog, recipes.config, config, extras)
	return _build_result(recipe_id, recipe, execution, levels, preparer, MODE_MANUAL)


func _build_result(recipe_id: String, recipe: Dictionary, execution: Dictionary, choices: Dictionary, preparer: String, mode: String) -> Dictionary:
	if not execution["ok"]:
		return {"ok": false, "error": execution["error"]}
	var quality_band := recipes.config.band_for(float(recipe["best_score"]))
	return {
		"ok": true,
		"recipe_id": recipe_id,
		"recipe_name": recipes.display_name(recipe),
		"recipe_quality": float(recipe["best_score"]),
		"recipe_quality_band": str(quality_band.get("name", "")),
		"execution_score": execution["execution_score"],
		"execution_band_id": execution["band_id"],
		"execution_band": execution["band_name"],
		"parameters": execution["parameters"],
		"choices": choices.duplicate(),
		"preparer": preparer,
		"mode": mode,
	}


## Слабое ли исполнение (кнопка «И так сойдет» вместо «Подать кальян»).
func is_weak(result: Dictionary) -> bool:
	return float(result["execution_score"]) < config.serve_weak_below


## Подача: записывает результат в рецепт (+1 к использованиям, исполнение) и сообщает о завершении.
func commit(result: Dictionary) -> bool:
	if not result.get("ok", false) or not recipes.record_preparation(str(result["recipe_id"]), float(result["execution_score"])):
		return false
	preparation_completed.emit(result)
	return true


## preview + commit одним вызовом (для нанятого кальянщика и тестов).
func prepare(recipe_id: String, choices: Dictionary, preparer: String = "player", mode: String = MODE_QUICK) -> Dictionary:
	var result := preview(recipe_id, choices, preparer, mode)
	if result["ok"]:
		commit(result)
	return result
