extends TestCase
## Тесты M5: перевод действий игрока в уровни, оценка состава, аккуратный и небрежный прогон, экран мини-игры.

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _setup_system(state: Node) -> Array:
	var catalog := IngredientCatalog.load_default()
	var scoring := ScoringConfig.load_default(catalog)
	var recipes := RecipeSystem.create_with(state, catalog, scoring)
	var prep := PreparationConfig.load_default()
	return [recipes, prep, PreparationService.create_with(recipes, prep)]


func _careful_run(manual: ManualPreparation, recipe: Dictionary, recipes: RecipeSystem, prep: PreparationConfig) -> void:
	var targets := ExecutionScoring.targets(ExecutionScoring.features(recipe, recipes.catalog, recipes.config), prep)
	for item in recipe["ingredients"]:
		for i in int(round(float(item["units"]) / float(recipes.config.total_units) * float(prep.manual_portions))):
			manual.add_portion(str(item["id"]))
	manual.fill = manual.hint_target("pack", targets)
	manual.tension = manual.hint_target("foil", targets)
	var hole_count := int(round(manual.hint_target("holes", targets)))
	for i in hole_count:
		manual.add_hole(Vector2.from_angle(TAU * float(i) / float(maxi(hole_count, 1))) * 0.6)
	var coal_count := int(round(manual.hint_target("coals", targets)))
	for i in coal_count:
		manual.add_coal(Vector2.from_angle(TAU * float(i) / float(maxi(coal_count, 1))) * prep.manual_coal_ring)
	manual.heat_seconds = manual.hint_target("light", targets)


func test_manual_config_loaded() -> void:
	var prep := PreparationConfig.load_default()
	assert_true(prep.is_valid(), str(prep.errors))
	assert_eq(prep.manual_portions, 4)
	assert_true(prep.manual_mix_weight > 0.0)


func test_actions_map_to_levels() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	assert_eq(manual.packing_level(), 0.0)
	manual.pack(100.0)
	assert_eq(manual.fill, 1.0)
	assert_eq(manual.packing_level(), 2.0)
	manual.set_tension(2.0)
	assert_eq(manual.tension, 1.0, "натяжение ограничено")
	for i in 20:
		manual.add_hole(_hole_spot(i))
	assert_eq(manual.holes.size(), manual.config.manual_holes_max, "дырок не больше максимума")
	assert_true(not manual.add_hole(Vector2(2.0, 0.0)), "вне чаши нельзя")
	manual.light(1.0)
	assert_eq(manual.heat_seconds, 0.0, "без углей на плитке розжиг ничего не делает")
	assert_true(manual.add_stove_coal(Vector2(0.5, 0.0)))
	manual.light(manual.config.manual_light_burn_seconds + 0.5)
	assert_true(manual.is_burnt(), "слишком долгий розжиг подпаливает")
	assert_true(manual.collect_stove_coal(0))
	assert_eq(manual.hot_coals, 1)
	assert_true(manual.add_coal(Vector2(0.3, 0.0)))
	assert_eq(manual.hot_coals, 0, "уголь ушёл из ведёрка на чашу")
	assert_true(manual.remove_coal(0))
	assert_eq(manual.hot_coals, 1, "уголь с чаши вернулся в ведёрко")
	manual.add_coal(Vector2(0.3, 0.0))
	manual.reset_step("light")
	assert_eq(manual.coals.size(), 0)
	assert_eq(manual.hot_coals, 0)
	assert_eq(manual.heat_seconds, 0.0)


func test_coal_total_limit() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	for i in manual.config.manual_max_coals:
		assert_true(manual.add_stove_coal(Vector2(0.1 * float(i), 0.0)))
	assert_true(not manual.add_stove_coal(Vector2(0.0, 0.5)), "больше углей, чем положено, нет")
	assert_eq(ManualPreparation.STEPS.find("light") + 1, ManualPreparation.STEPS.find("coals"), "сначала розжиг, потом выкладка на чашу")


func test_portion_limit_and_mix_score() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	for i in 4:
		assert_true(manual.add_portion("strawberry"))
	assert_true(not manual.add_portion("mint"), "чаша полна")
	var recipe := {"ingredients": [{"id": "strawberry", "units": 10}, {"id": "mint", "units": 10}]}
	assert_eq(ManualPreparation.mix_score(recipe, {"strawberry": 2, "mint": 2}, 20), 100.0)
	assert_true(ManualPreparation.mix_score(recipe, {"strawberry": 4}, 20) < 60.0)
	assert_true(ManualPreparation.mix_score(recipe, {"apple": 4}, 20) < 5.0, "совсем другой состав")
	assert_eq(ManualPreparation.mix_score(recipe, {}, 20), 0.0)


func test_coal_placement_quality() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	manual.add_coal(Vector2(0.5, 0.0))
	manual.add_coal(Vector2(-0.5, 0.0))
	manual.add_coal(Vector2(0.0, 0.5))
	manual.add_coal(Vector2(0.0, -0.5))
	var ring_quality := manual.coal_placement_quality()
	manual.reset_step("coals")
	for i in 4:
		manual.add_coal(Vector2(0.02 * float(i), 0.0))
	assert_true(ring_quality > manual.coal_placement_quality() + 0.3, "кольцо лучше, чем куча в центре")


func test_careful_run_beats_rushed_run() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var prep: PreparationConfig = parts[1]
	var service: PreparationService = parts[2]
	var recipe_id: String = recipes.commit({"watermelon": 2, "strawberry": 2}, [])["recipe_id"]
	var recipe := recipes.get_recipe(recipe_id)
	var careful := ManualPreparation.new(prep)
	_careful_run(careful, recipe, recipes, prep)
	var rushed := ManualPreparation.new(prep)
	rushed.add_portion("apple")
	rushed.add_portion("apple")
	rushed.add_portion("apple")
	rushed.add_portion("apple")
	rushed.add_coal(Vector2(0.01, 0.0))
	var good := service.preview_manual(recipe_id, careful.levels(), careful.extras(recipe, recipes.config.total_units))
	var bad := service.preview_manual(recipe_id, rushed.levels(), rushed.extras(recipe, recipes.config.total_units))
	assert_true(good["ok"] and bad["ok"], "%s %s" % [str(good), str(bad)])
	assert_eq(good["mode"], "manual")
	assert_true(good["execution_score"] > bad["execution_score"] + 30.0, "аккуратный %s против небрежного %s" % [good["execution_score"], bad["execution_score"]])
	assert_true(not service.is_weak(good) and service.is_weak(bad))
	# В результате есть подоценки: 5 параметров + состав, минимум 3 из них различаются.
	assert_eq(good["parameters"].size(), 6)
	var differing := 0
	for i in good["parameters"].size():
		if not is_equal_approx(float(good["parameters"][i]["score"]), float(bad["parameters"][i]["score"])):
			differing += 1
	assert_true(differing >= 3, "действия должны влиять минимум на 3 подоценки (влияют на %d)" % differing)
	# Превью ничего не записывает, подача записывает.
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 0)
	assert_true(service.commit(good))
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 1)
	state.free()


func test_quick_evaluation_unchanged_by_levels_refactor() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var prep: PreparationConfig = parts[1]
	var recipe: Dictionary = recipes.commit({"watermelon": 4}, [])["recipe"]
	var by_choices := ExecutionScoring.evaluate(recipe, {"packing": "loose", "foil": "single", "holes": "many", "coals": "three", "lighting": "normal"}, recipes.catalog, recipes.config, prep)
	var by_levels := ExecutionScoring.evaluate_levels(recipe, {"packing": 0, "foil": 1, "holes": 2, "coals": 1, "lighting": 1}, recipes.catalog, recipes.config, prep)
	assert_eq(by_choices["execution_score"], by_levels["execution_score"])
	assert_eq(by_choices["parameters"].size(), 5, "в быстром режиме подоценки состава нет")
	state.free()


func test_manual_screen_full_flow_and_repeatable() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var service: PreparationService = parts[2]
	var recipe_id: String = recipes.commit({"watermelon": 4}, [])["recipe_id"]
	var screen := ManualPreparationScreen.new()
	tree.root.add_child(screen)
	screen.setup(service)
	await tree.process_frame
	var served: Array = []
	screen.served.connect(func(result: Dictionary) -> void: served.append(result))
	for run in 2:
		screen.open(recipe_id, run == 0)
		assert_true(screen.visible)
		assert_eq(screen.current_step(), "mix")
		assert_true(screen._next_button.disabled, "пока не набраны порции, дальше нельзя")
		for i in 4:
			screen._on_token_clicked("watermelon")
		assert_true(not screen._next_button.disabled)
		screen._on_next_pressed()
		assert_eq(screen.current_step(), "pack")
		assert_true(not screen._bowl.gauge_info().is_empty(), "у набивки есть шкала")
		screen._manual.pack(1.0)
		screen._on_next_pressed()
		screen._manual.set_tension(0.5)
		screen._on_next_pressed()
		for i in 6:
			screen._manual.add_hole(Vector2.from_angle(float(i)) * 0.5)
		screen._on_next_pressed()
		assert_eq(screen.current_step(), "light")
		assert_true(screen._next_button.disabled, "без разогретых углей в ведёрке дальше нельзя")
		for i in 3:
			# Щипцы: свежий уголь из ведёрка кладётся в произвольную точку плитки.
			var drop_at: Vector2 = screen._bowl.center_point() + Vector2.from_angle(float(i) * TAU / 3.0) * 85.0
			assert_true(screen._bowl._can_drop_data(drop_at, {"kind": "coal"}))
			screen._bowl._drop_data(drop_at, {"kind": "coal"})
		assert_eq(screen._manual.stove_coals.size(), 3)
		assert_true(screen._next_button.disabled)
		screen._manual.light(2.0)
		# Горячие угли переносятся с плитки в ведёрко.
		while not screen._manual.stove_coals.is_empty():
			screen._manual.collect_stove_coal(0)
		assert_eq(screen._manual.hot_coals, 3)
		screen._on_next_pressed()
		assert_eq(screen.current_step(), "coals")
		assert_true(screen._next_button.disabled, "пока угли в ведёрке, готовить нельзя")
		for i in 3:
			var drop_at: Vector2 = screen._bowl.center_point() + Vector2.from_angle(float(i) * TAU / 3.0) * 85.0
			assert_true(screen._bowl._can_drop_data(drop_at, {"kind": "hot_coal"}))
			screen._bowl._drop_data(drop_at, {"kind": "hot_coal"})
		assert_eq(screen._manual.coals.size(), 3)
		assert_eq(screen._manual.hot_coals, 0)
		screen._process(0.0)
		assert_true(not screen._next_button.disabled)
		screen._on_next_pressed()
		assert_true(screen._result_box.visible, "после розжига показан результат")
		assert_true(not screen._pending_result.is_empty())
		screen.close()
	# Закрытие без подачи ничего не записало; подача записывает и сообщает наверх.
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 0)
	screen.open(recipe_id, false)
	for i in 4:
		screen._on_token_clicked("watermelon")
	for i in ManualPreparation.STEPS.size():
		screen._on_next_pressed()
	screen._on_serve_pressed()
	assert_eq(served.size(), 1)
	assert_eq(recipes.get_recipe(recipe_id)["times_used"], 1)
	assert_true(not screen.visible)
	tree.root.remove_child(screen)
	screen.free()
	state.free()


func test_sfx_streams_exist() -> void:
	var sfx := ManualSfx.new()
	for sound in ["drop", "pack", "foil", "hole", "coal", "light", "done", "bad"]:
		var stream := sfx.stream_for(sound)
		assert_true(stream != null and stream.data.size() > 100, "звук %s" % sound)
	assert_true(sfx.stream_for("нет_такого") == null)
	sfx.free()


func test_holes_level_uses_min_and_max() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	assert_eq(manual.config.manual_holes_min, 6)
	assert_eq(manual.config.manual_holes_max, 10)
	assert_eq(manual.holes_level(), 0.0, "меньше минимума — уровень «мало»")
	for i in 4:
		manual.add_hole(_hole_spot(i))
	assert_eq(manual.holes_level(), 0.0)
	for i in 4:
		manual.add_hole(_hole_spot(4 + i))
	assert_true(is_equal_approx(manual.holes_level(), 1.0), "8 отверстий — середина")
	for i in 10:
		manual.add_hole(_hole_spot(8 + i))
	assert_eq(manual.holes.size(), 10)
	assert_eq(manual.holes_level(), 2.0)


func test_portions_stay_in_their_slots() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	assert_eq(manual.slots.size(), 4)
	assert_true(manual.add_portion("mint", 2))
	assert_eq(manual.slots[2], "mint", "порция лежит в том кружке, куда её положили")
	assert_true(not manual.add_portion("apple", 2), "кружок занят")
	assert_true(manual.add_portion("apple"), "без номера — в первый свободный")
	assert_eq(manual.slots[0], "apple")
	assert_true(manual.remove_portion(2))
	assert_eq(manual.slots[2], "")
	assert_true(not manual.remove_portion(2), "кружок уже пуст")
	assert_eq(manual.total_portions(), 1)
	manual.reset_step("mix")
	assert_eq(manual.total_portions(), 0)
	assert_eq(manual.slots.size(), 4)


func test_wrong_mix_ruins_the_result() -> void:
	var state := GameStateScript.new()
	var parts := _setup_system(state)
	var recipes: RecipeSystem = parts[0]
	var prep: PreparationConfig = parts[1]
	var recipe := {"ingredients": [{"id": "strawberry", "units": 10}, {"id": "watermelon", "units": 10}], "modifiers": []}
	var levels := {"packing": 1, "foil": 1, "holes": 1, "coals": 1, "lighting": 1}
	var right := ExecutionScoring.evaluate_levels(recipe, levels, recipes.catalog, recipes.config, prep, {"mix_score": 100.0})
	var wrong := ExecutionScoring.evaluate_levels(recipe, levels, recipes.catalog, recipes.config, prep, {"mix_score": 0.0})
	assert_true(float(wrong["execution_score"]) < float(right["execution_score"]) * 0.5, "не тот состав: %s против %s" % [wrong["execution_score"], right["execution_score"]])
	assert_eq(ExecutionScoring.mix_factor(100.0), 1.0)
	state.free()


func test_stove_warms_up_heats_and_cools() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	manual.toggle_stove()
	assert_true(not manual.stove_on, "без углей на плитке её не включить")
	assert_true(manual.add_stove_coal(Vector2(0.3, 0.0)))
	assert_true(manual.add_stove_coal(Vector2(-0.3, 0.0)))
	manual.tick_stove(1.0)
	assert_eq(manual.heat_seconds, 0.0, "выключенная плитка не греет")
	manual.toggle_stove()
	assert_true(manual.stove_on)
	manual.tick_stove(manual.config.manual_coil_warmup_seconds * 0.5)
	assert_true(manual.coil_temp < 1.0)
	assert_eq(manual.heat_seconds, 0.0, "пока спираль греется, угли не греются")
	manual.tick_stove(manual.config.manual_coil_warmup_seconds)
	assert_eq(manual.coil_temp, 1.0)
	manual.tick_stove(3.0)
	assert_true(manual.heat_seconds > 0.0, "потом угли греются")
	assert_true(manual.heat_seconds < 3.0 * 1.0, "греются медленнее, чем секунды на часах")
	manual.toggle_stove()
	var hot := manual.heat_seconds
	manual.tick_stove(2.0)
	assert_true(manual.heat_seconds < hot and manual.heat_seconds > hot * 0.6, "остывание медленное")
	manual.collect_stove_coal(0)
	var fixed := manual.heat_seconds
	manual.tick_stove(5.0)
	assert_eq(manual.heat_seconds, fixed, "после снятия первого угля температура зафиксирована")


func test_manual_is_stricter_than_quick() -> void:
	var prep := PreparationConfig.load_default()
	assert_true(prep.manual_tolerance_factor < 1.0 and prep.manual_penalty_factor > 1.0)


## Точки для отверстий на двух кольцах — достаточно далеко друг от друга.
func _hole_spot(index: int) -> Vector2:
	var ring := 0.35 if index % 2 == 0 else 0.75
	return Vector2.from_angle(float(index) * 0.9) * ring


func test_holes_keep_distance() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	assert_true(manual.add_hole(Vector2(0.2, 0.2)))
	assert_true(not manual.add_hole(Vector2(0.2, 0.2)), "в то же место нельзя")
	assert_true(not manual.add_hole(Vector2(0.2 + ManualPreparation.HOLE_MIN_DISTANCE * 0.5, 0.2)), "вплотную нельзя")
	assert_true(manual.add_hole(Vector2(0.2 + ManualPreparation.HOLE_MIN_DISTANCE * 1.5, 0.2)))


func test_early_coal_removal_does_not_block_heating() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	manual.add_stove_coal(Vector2(0.3, 0.0))
	manual.add_stove_coal(Vector2(-0.3, 0.0))
	manual.lock_temperature()
	assert_true(not manual.temperature_locked, "пока не прогрелись, температура не фиксируется")
	manual.collect_stove_coal(0)
	assert_true(not manual.temperature_locked)
	manual.toggle_stove()
	manual.tick_stove(10.0)
	assert_true(manual.heat_seconds >= ManualPreparation.MIN_HEAT_SECONDS, "оставшийся уголь греется")
	assert_true(manual.has_action("light"))
	assert_true(not manual.has_action("coals"))


func test_stove_coals_locked_while_stove_is_on() -> void:
	var manual := ManualPreparation.new(PreparationConfig.load_default())
	assert_true(manual.can_place_cold_coal())
	manual.add_stove_coal(Vector2(0.3, 0.0))
	manual.toggle_stove()
	assert_true(not manual.can_place_cold_coal(), "на включённую плитку класть нельзя")
	assert_true(not manual.can_take_stove_coal(), "с включённой плитки снимать нельзя")
	assert_true(not manual.collect_stove_coal(0), "уголь остался на плитке")
	assert_eq(manual.stove_coals.size(), 1)
	manual.tick_stove(manual.config.manual_coil_warmup_seconds + 3.0)
	assert_true(not manual.temperature_locked, "температура не фиксируется, пока плитка включена")
	manual.toggle_stove()
	assert_true(not manual.can_place_cold_coal(), "угли уже грелись — новые холодные не кладём")
	assert_true(manual.can_take_stove_coal())
	assert_true(manual.collect_stove_coal(0))
	assert_true(manual.temperature_locked)
