class_name RecipeBookQuery
extends RefCounted
## Фильтрация и сортировка рецептов для книги рецептов (чистая логика, без UI).

const SORT_BEST := "best"
const SORT_RECENT := "recent"
const SORT_NAME := "name"


## ingredient_id == "" — без фильтра. name_of — Callable(recipe) -> String для режима SORT_NAME.
static func filter_sort(recipes: Array, ingredient_id: String, sort_mode: String, name_of: Callable = Callable()) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in recipes:
		if ingredient_id.is_empty() or _contains(recipe, ingredient_id):
			result.append(recipe)
	match sort_mode:
		SORT_RECENT:
			result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if a["last_used_seq"] != b["last_used_seq"]:
					return a["last_used_seq"] > b["last_used_seq"]
				return str(a["id"]) < str(b["id"]))
		SORT_NAME:
			result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var na := str(name_of.call(a)) if name_of.is_valid() else str(a["name"])
				var nb := str(name_of.call(b)) if name_of.is_valid() else str(b["name"])
				if na != nb:
					return na.naturalnocasecmp_to(nb) < 0
				return str(a["id"]) < str(b["id"]))
		_:
			result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if not is_equal_approx(float(a["best_score"]), float(b["best_score"])):
					return float(a["best_score"]) > float(b["best_score"])
				return str(a["id"]) < str(b["id"]))
	return result


static func _contains(recipe: Dictionary, ingredient_id: String) -> bool:
	for item in recipe["ingredients"]:
		if item["id"] == ingredient_id:
			return true
	return false
