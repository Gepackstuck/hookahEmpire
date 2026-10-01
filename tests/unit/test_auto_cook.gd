extends TestCase
## Автопилот кальянщика: подбор микса под заказ и параметров приготовления (с контролируемыми ошибками).

const GameStateScript := preload("res://scripts/core/game_state.gd")
const MainScript := preload("res://scripts/core/main.gd")


func _system(state: Node) -> RecipeSystem:
	var catalog := IngredientCatalog.load_default()
	return RecipeSystem.create_with(state, catalog, ScoringConfig.load_default(catalog))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _level(entry: Dictionary, option_id: String) -> int:
	var options: Array = entry["options"]
	for i in options.size():
		if options[i]["id"] == option_id:
			return i
	return -1


func test_mix_is_valid_and_matches_order() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var prefs_list := [{"sweet": 1.0, "fruit": 0.5}, {"fresh": 1.0}, {"sour": 1.0, "fresh": 0.4}, {"heavy": 1.0}, {"spicy": 1.0}]
	for prefs in prefs_list:
		var ranked := OrderHint.rank(recipes.catalog, prefs)
		for seed_value in 40:
			var mix := AutoCook.pick_mix(recipes.catalog, prefs, _rng(seed_value), 0.0)
			var total := 0
			for id in mix["selection"]:
				total += int(mix["selection"][id])
				assert_true(recipes.catalog.ingredient_ids().has(id))
			assert_eq(total, 4, "всегда 4 порции")
			var evaluation := recipes.evaluate(mix["selection"], mix["modifiers"])
			assert_true(evaluation["ok"], str(mix))
			var has_top := false
			for id in mix["selection"]:
				if ranked.slice(0, 3).has(id):
					has_top = true
			assert_true(has_top, "в миксе есть ингредиент из топ-3 по вкусу заказа")
	state.free()


func test_mix_noise_makes_it_imperfect_but_valid() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var prefs := {"sweet": 1.0}
	var kinds := {}
	for seed_value in 80:
		var mix := AutoCook.pick_mix(recipes.catalog, prefs, _rng(seed_value), 1.0)
		assert_true(recipes.evaluate(mix["selection"], mix["modifiers"])["ok"])
		kinds[str(mix["selection"])] = true
	assert_true(kinds.size() > 5, "рандом: разные миксы (разных: %d)" % kinds.size())
	state.free()


func test_mix_is_deterministic_for_seed() -> void:
	var catalog := IngredientCatalog.load_default()
	var prefs := {"sweet": 1.0, "fruit": 0.5}
	assert_eq(AutoCook.pick_mix(catalog, prefs, _rng(9)), AutoCook.pick_mix(catalog, prefs, _rng(9)))


func test_choices_without_mistakes_are_optimal() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var prep := PreparationConfig.load_default()
	var recipe: Dictionary = recipes.commit({"strawberry": 2, "vanilla": 2}, [])["recipe"]
	var targets := ExecutionScoring.targets(ExecutionScoring.features(recipe, recipes.catalog, recipes.config), prep)
	var choices := AutoCook.pick_choices(prep, recipe, recipes.catalog, recipes.config, _rng(1), 0.0)
	assert_eq(choices.size(), prep.parameters.size(), "выбраны все параметры")
	for entry in prep.parameters:
		assert_eq(_level(entry, choices[entry["id"]]), roundi(float(targets[entry["id"]])))
	state.free()


func test_choices_with_mistakes_are_off_by_exactly_one_level() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var prep := PreparationConfig.load_default()
	var recipe: Dictionary = recipes.commit({"strawberry": 2, "vanilla": 2}, [])["recipe"]
	var targets := ExecutionScoring.targets(ExecutionScoring.features(recipe, recipes.catalog, recipes.config), prep)
	for seed_value in 20:
		var choices := AutoCook.pick_choices(prep, recipe, recipes.catalog, recipes.config, _rng(seed_value), 1.0)
		for entry in prep.parameters:
			var level := _level(entry, choices[entry["id"]])
			assert_true(level >= 0 and level < entry["options"].size())
			assert_eq(absi(level - roundi(float(targets[entry["id"]]))), 1, "ошибка ровно на уровень (%s)" % entry["id"])
	state.free()


func test_autopilot_result_is_accepted_by_preparation_service() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var service := PreparationService.create_with(recipes, PreparationConfig.load_default())
	var mix := AutoCook.pick_mix(recipes.catalog, {"sweet": 1.0}, _rng(3))
	var recipe_id: String = recipes.commit(mix["selection"], mix["modifiers"])["recipe_id"]
	var recipe := recipes.get_recipe(recipe_id)
	var choices := AutoCook.pick_choices(service.config, recipe, recipes.catalog, recipes.config, _rng(3))
	var result := service.preview(recipe_id, choices)
	assert_true(result["ok"], str(result))
	assert_true(service.commit(result))
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 1)
	state.free()


func test_existing_recipe_is_reused_only_when_it_fits() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var scoring := SessionScoring.load_default()
	var sweet_id: String = recipes.commit({"strawberry": 2, "vanilla": 2}, [])["recipe_id"]
	var sour_id: String = recipes.commit({"lemon": 2, "lime": 2}, [])["recipe_id"]
	var min_fit := AutoCook.FIT_MIN_FOR_EXISTING
	var find := func(taste: Dictionary, book: Array) -> String:
		return AutoCook.find_fitting_recipe(book, recipes.catalog, recipes.config, scoring, taste, min_fit)
	assert_eq(find.call({"preferences": {"sweet": 1.0}}, recipes.all_recipes()), sweet_id)
	assert_eq(find.call({"preferences": {"sour": 1.0}}, recipes.all_recipes()), sour_id)
	assert_eq(find.call({"preferences": {"spicy": 1.0}}, recipes.all_recipes()), "", "острого в книге нет — идти к смесителю")
	assert_eq(find.call({"preferences": {"sweet": 1.0}}, []), "", "пустая книга — идти к смесителю")
	assert_eq(find.call({"preferences": {"sweet": 1.0}, "dislikes": {"creamy": 1.0, "heavy": 1.0}}, [recipes.get_recipe(sour_id)]), "")
	state.free()


func test_recipe_items_for_chips() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var recipe: Dictionary = recipes.commit({"lemon": 2, "lime": 2}, ["ice"])["recipe"]
	var items := AutoCook.recipe_items(recipe)
	assert_true(items.has("lemon") and items.has("lime") and items.has("ice"))
	state.free()


func test_idle_targets_exist_in_layout() -> void:
	var layout := GarageLayout.load_file("res://data/garage/garage_main.json")
	var ids := []
	for object in layout.objects:
		ids.append(str(object["id"]))
	for id in MainScript.IDLE_TARGETS:
		assert_true(ids.has(id), "объект простоя '%s' есть в гараже" % id)
		assert_true(not (MainScript.IDLE_TARGETS[id] as Array).is_empty())
	assert_true(MainScript.IDLE_MIN_SECONDS == 3.0 and MainScript.IDLE_MAX_SECONDS == 6.0)
