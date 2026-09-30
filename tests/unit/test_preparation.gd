extends TestCase
## Тесты M4: конфиг приготовления, расчёт исполнения, PreparationService, окно приготовления.

const GameStateScript := preload("res://scripts/core/game_state.gd")

const GOOD_FOR_LIGHT := {"packing": "loose", "foil": "single", "holes": "many", "coals": "three", "lighting": "normal"}
const GOOD_FOR_HEAVY := {"packing": "dense", "foil": "double", "holes": "few", "coals": "three", "lighting": "normal"}
const BAD_FOR_LIGHT := {"packing": "dense", "foil": "none", "holes": "few", "coals": "four", "lighting": "weak"}


func _setup_system(state: Node) -> Array:
	var catalog := IngredientCatalog.load_default()
	var scoring := ScoringConfig.load_default(catalog)
	var recipes := RecipeSystem.create_with(state, catalog, scoring)
	var prep := PreparationConfig.load_default()
	return [recipes, prep, PreparationService.create_with(recipes, prep)]


func test_preparation_config_valid() -> void:
	var config := PreparationConfig.load_default()
	assert_true(config.is_valid(), str(config.errors))
	assert_eq(config.parameters.size(), 5)
	assert_eq(config.option_level("packing", "dense"), 2)
	assert_eq(config.option_level("packing", "nope"), -1)
	assert_eq(config.default_choices()["packing"], "normal")


func test_preparation_config_rejects_bad_data() -> void:
	GameLog.muted = true
	assert_true(not PreparationConfig.from_dict({}).is_valid())
	var bad := {"parameters": [{"id": "x", "weight": 1.0, "weights": {"nonsense": 1.0}, "options": [{"id": "a", "name": "A"}]}]}
	assert_true(not PreparationConfig.from_dict(bad).is_valid())
	GameLog.muted = false


func test_targets_differ_between_light_and_heavy_recipes() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var prep: PreparationConfig = parts[1]
	var light: Dictionary = recipes.commit({"watermelon": 4}, [])["recipe"]
	var heavy: Dictionary = recipes.commit({"vanilla": 4}, [])["recipe"]
	var light_targets := ExecutionScoring.targets(ExecutionScoring.features(light, recipes.catalog, recipes.config), prep)
	var heavy_targets := ExecutionScoring.targets(ExecutionScoring.features(heavy, recipes.catalog, recipes.config), prep)
	assert_true(heavy_targets["packing"] > light_targets["packing"], "тяжёлый вкус — плотнее упаковка")
	assert_true(heavy_targets["holes"] < light_targets["holes"], "лёгкий вкус — больше отверстий")
	state.free()


func test_good_choices_beat_bad_choices() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var prep: PreparationConfig = parts[1]
	var light: Dictionary = recipes.commit({"watermelon": 4}, [])["recipe"]
	var good := ExecutionScoring.evaluate(light, GOOD_FOR_LIGHT, recipes.catalog, recipes.config, prep)
	var bad := ExecutionScoring.evaluate(light, BAD_FOR_LIGHT, recipes.catalog, recipes.config, prep)
	assert_true(good["ok"] and bad["ok"])
	assert_true(good["execution_score"] > bad["execution_score"] + 30.0, "%s vs %s" % [good["execution_score"], bad["execution_score"]])
	# Те же выборы для тяжёлого рецепта оцениваются иначе: оптимум зависит от рецепта.
	var heavy: Dictionary = recipes.commit({"vanilla": 4}, [])["recipe"]
	var light_choice_for_heavy := ExecutionScoring.evaluate(heavy, GOOD_FOR_LIGHT, recipes.catalog, recipes.config, prep)
	var heavy_choice_for_heavy := ExecutionScoring.evaluate(heavy, GOOD_FOR_HEAVY, recipes.catalog, recipes.config, prep)
	assert_true(heavy_choice_for_heavy["execution_score"] > light_choice_for_heavy["execution_score"])
	state.free()


func test_evaluate_is_deterministic_and_in_range() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var prep: PreparationConfig = parts[1]
	var recipe: Dictionary = recipes.commit({"mango": 2, "strawberry": 2}, ["ice"])["recipe"]
	var first := ExecutionScoring.evaluate(recipe, prep.default_choices(), recipes.catalog, recipes.config, prep)
	var second := ExecutionScoring.evaluate(recipe, prep.default_choices(), recipes.catalog, recipes.config, prep)
	assert_eq(first["execution_score"], second["execution_score"])
	assert_true(first["execution_score"] >= 0.0 and first["execution_score"] <= 100.0)
	assert_eq(first["parameters"].size(), 5)
	state.free()


func test_evaluate_rejects_invalid_choices() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var prep: PreparationConfig = parts[1]
	var recipe: Dictionary = recipes.commit({"mango": 4}, [])["recipe"]
	var incomplete := prep.default_choices()
	incomplete.erase("foil")
	assert_true(not ExecutionScoring.evaluate(recipe, incomplete, recipes.catalog, recipes.config, prep)["ok"])
	var wrong := prep.default_choices()
	wrong["foil"] = "golden"
	assert_true(not ExecutionScoring.evaluate(recipe, wrong, recipes.catalog, recipes.config, prep)["ok"])
	state.free()


func test_service_prepare_records_and_emits() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var service: PreparationService = parts[2]
	var recipe_id: String = recipes.commit({"watermelon": 4}, [])["recipe_id"]
	var received: Array[Dictionary] = []
	service.preparation_completed.connect(func(result: Dictionary) -> void: received.append(result))
	var first := service.prepare(recipe_id, BAD_FOR_LIGHT)
	var second := service.prepare(recipe_id, GOOD_FOR_LIGHT, "hired_master")
	assert_true(first["ok"] and second["ok"])
	assert_true(first["execution_score"] != second["execution_score"], "разные параметры — разные оценки")
	assert_eq(received.size(), 2)
	assert_eq(second["preparer"], "hired_master")
	var recipe := recipes.get_recipe(recipe_id)
	assert_eq(recipe["times_used"], 2)
	assert_eq(recipe["best_execution"], second["execution_score"])
	assert_eq(recipe["last_execution"], second["execution_score"])
	assert_true(not service.prepare("missing", GOOD_FOR_LIGHT)["ok"])
	assert_true(not service.prepare(recipe_id, {"packing": "loose"})["ok"])
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 2, "неудачный запрос ничего не записывает")
	state.free()


func test_service_rejects_invalid_config() -> void:
	GameLog.muted = true
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	assert_true(PreparationService.create_with(parts[0], PreparationConfig.from_dict({})) == null)
	GameLog.muted = false
	state.free()


func test_preparation_screen_flow() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var service: PreparationService = parts[2]
	var screen: PreparationScreen = load("res://scenes/ui/PreparationScreen.tscn").instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	screen.setup(service)
	await tree.process_frame
	screen.open()
	assert_true(screen._empty.visible and not screen._form.visible, "без рецептов — пустое состояние")
	screen.close()
	var recipe_id: String = recipes.commit({"watermelon": 4}, [])["recipe_id"]
	screen.open()
	assert_true(screen._form.visible and not screen._empty.visible)
	assert_eq(screen._recipe_ids.size(), 1)
	for parameter_id in GOOD_FOR_LIGHT:
		(screen._option_buttons[parameter_id][GOOD_FOR_LIGHT[parameter_id]] as Button).pressed.emit()
	var results: Array[Dictionary] = []
	screen.prepared.connect(func(result: Dictionary) -> void: results.append(result))
	screen._on_prepare_pressed()
	assert_eq(results.size(), 0, "пока кальян не подан, ничего не записывается")
	assert_true(screen._result_box.visible and not screen._form.visible)
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 0)
	assert_true(screen._serve_button.text.contains("Подать"), "хорошие параметры — «Подать кальян»")
	screen._on_serve_pressed()
	assert_eq(results.size(), 1)
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 1)
	assert_true(not screen.visible, "подача закрывает окно")
	screen.open()
	for parameter_id in BAD_FOR_LIGHT:
		(screen._option_buttons[parameter_id][BAD_FOR_LIGHT[parameter_id]] as Button).pressed.emit()
	screen._on_prepare_pressed()
	assert_true(screen._serve_button.text.contains("сойдет"), "слабое исполнение — «И так сойдет»")
	screen.close()
	tree.root.remove_child(screen)
	screen.free()
	state.free()


func test_preview_does_not_record_and_commit_does() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var service: PreparationService = parts[2]
	var recipe_id: String = recipes.commit({"watermelon": 4}, [])["recipe_id"]
	var good := service.preview(recipe_id, GOOD_FOR_LIGHT)
	var bad := service.preview(recipe_id, BAD_FOR_LIGHT)
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 0)
	assert_true(not service.is_weak(good) and service.is_weak(bad))
	assert_true(service.commit(good))
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 1)
	assert_true(not service.commit({"ok": false}))
	state.free()
