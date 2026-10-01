class_name ProgressionGoal
extends RefCounted
## M8: цель MVP — N «сильных» рецептов. Рецепт сильный, если итоговая оценка не ниже strong_score
## получена минимум под required_trends разными трендами (запись recipe["strong_trends"]).
## Чистая логика без UI; состояние хранится в записях рецептов GameState.

const CONFIG_PATH := "res://data/config/progression.json"
const DONE_FLAG := "mvp_goal_done"
const ENDING_SEEN_FLAG := "mvp_ending_seen"

var errors: Array[String] = []
var strong_score: float = 75.0
var required_trends: int = 2
var goal_recipes: int = 3
var ending_dialogue: String = "mvp_ending"


static func load_default() -> ProgressionGoal:
	var goal := ProgressionGoal.new()
	if not FileAccess.file_exists(CONFIG_PATH):
		goal.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return goal
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		goal.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return goal
	goal._parse(parsed)
	return goal


static func from_dict(data: Dictionary) -> ProgressionGoal:
	var goal := ProgressionGoal.new()
	goal._parse(data)
	return goal


func is_valid() -> bool:
	return errors.is_empty()


## Фиксирует итог сессии: если оценка достаточна, тренд записывается в strong_trends рецепта.
## Возвращает true, если рецепт только что стал сильным.
func record(recipe: Dictionary, trend_id: String, final_score: float) -> bool:
	if trend_id.is_empty() or final_score < strong_score:
		return false
	var was_strong := is_strong(recipe)
	var trends: Array = recipe.get("strong_trends", [])
	if not trends.has(trend_id):
		trends.append(trend_id)
	recipe["strong_trends"] = trends
	return not was_strong and is_strong(recipe)


func is_strong(recipe: Dictionary) -> bool:
	return (recipe.get("strong_trends", []) as Array).size() >= required_trends


## Сколько рецептов в книге сильные (recipes — словарь id -> запись, как в GameState).
func strong_count(recipes: Dictionary) -> int:
	var count := 0
	for id in recipes:
		if is_strong(recipes[id]):
			count += 1
	return count


func is_complete(recipes: Dictionary) -> bool:
	return strong_count(recipes) >= goal_recipes


func progress_text(recipes: Dictionary) -> String:
	return "%d/%d" % [mini(strong_count(recipes), goal_recipes), goal_recipes]


func _parse(data: Dictionary) -> void:
	var score: Variant = data.get("strong_score", strong_score)
	if not (score is int or score is float) or float(score) < 0.0 or float(score) > 100.0:
		errors.append("progression: strong_score должен быть числом 0..100")
	else:
		strong_score = float(score)
	var trends: Variant = data.get("required_trends", required_trends)
	if not (trends is int or trends is float) or int(trends) < 1:
		errors.append("progression: required_trends должен быть числом >= 1")
	else:
		required_trends = int(trends)
	var recipes: Variant = data.get("goal_recipes", goal_recipes)
	if not (recipes is int or recipes is float) or int(recipes) < 1:
		errors.append("progression: goal_recipes должен быть числом >= 1")
	else:
		goal_recipes = int(recipes)
	ending_dialogue = str(data.get("ending_dialogue", ending_dialogue))
