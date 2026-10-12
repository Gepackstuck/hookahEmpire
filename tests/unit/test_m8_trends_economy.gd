extends TestCase
## Тесты M8: тренды, экономика, цель MVP.

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _trends() -> TrendSystem:
	var scoring := SessionScoring.load_default()
	return TrendSystem.load_default(scoring)


func test_trend_config_valid() -> void:
	var trends := _trends()
	assert_true(trends.is_valid(), str(trends.errors))
	assert_true(trends.rotation.size() >= 2)
	assert_eq(trends.current_id, "fresh_fruit")


func test_trend_changes_after_n_visits() -> void:
	var trends := _trends()
	var n := trends.duration_sessions
	for i in n - 1:
		assert_true(not trends.advance_visit(), "тренд не меняется раньше срока")
	assert_true(trends.advance_visit(), "на N-м визите тренд меняется")
	assert_eq(trends.current_id, "sweet_cream")
	assert_eq(trends.visits_left, n)
	assert_eq(trends.changes, 1)


func test_trend_rotation_wraps() -> void:
	var trends := _trends()
	for i in trends.rotation.size():
		trends.set_trend(trends.next_id())
	assert_eq(trends.current_id, trends.rotation[0])


func test_trend_validation_errors() -> void:
	var scoring := SessionScoring.load_default()
	var bad := TrendSystem.from_dict({"start": "fresh_fruit", "duration_sessions": 3, "rotation": ["fresh_fruit"]}, scoring)
	assert_true(not bad.is_valid())
	var unknown := TrendSystem.from_dict({"start": "fresh_fruit", "duration_sessions": 3, "rotation": ["fresh_fruit", "no_such_trend"]}, scoring)
	assert_true(not unknown.is_valid())
	var wrong_start := TrendSystem.from_dict({"start": "neutral", "duration_sessions": 3, "rotation": ["fresh_fruit", "sweet_cream"]}, scoring)
	assert_true(not wrong_start.is_valid())


func test_trend_changes_trend_fit_of_same_recipe() -> void:
	var trends := _trends()
	var fresh_profile := {"fresh": 1.0, "fruit": 1.0}
	var fit_fresh := trends.trend_fit(fresh_profile, "fresh_fruit")
	var fit_spicy := trends.trend_fit(fresh_profile, "spicy_heavy")
	assert_true(fit_fresh > fit_spicy + 10.0, "один рецепт по-разному ложится в разные тренды")
	trends.set_trend("spicy_heavy")
	assert_eq(trends.trend_fit(fresh_profile), fit_spicy)


func test_economy_earn_spend() -> void:
	var state := GameStateScript.new()
	var catalog := IngredientCatalog.load_default()
	var economy := EconomySystem.load_default(state, catalog)
	assert_true(economy.is_valid(), str(economy.errors))
	assert_true(economy.grant_start_money())
	assert_true(not economy.grant_start_money(), "стартовые деньги выдаются один раз")
	assert_eq(economy.balance(), economy.start_money)
	economy.earn(50)
	assert_eq(economy.balance(), economy.start_money + 50)
	assert_true(not economy.spend(economy.balance() + 1))
	assert_true(economy.spend(20))
	assert_eq(economy.spent_total, 20)
	state.free()


func test_economy_recipe_cost_and_free_ingredients() -> void:
	var state := GameStateScript.new()
	var catalog := IngredientCatalog.load_default()
	var economy := EconomySystem.load_default(state, catalog)
	var total := 20
	var free_recipe := {"ingredients": [{"id": economy.free_ingredients[0], "units": 20}], "modifiers": []}
	assert_eq(economy.recipe_cost(free_recipe, total), 0)
	var paid_id := ""
	for id in catalog.ingredient_ids():
		if not economy.is_free(id) and float(catalog.get_ingredient(id).get("cost", 0)) > 0.0:
			paid_id = id
			break
	assert_true(paid_id != "", "в каталоге есть платный ингредиент")
	var paid_recipe := {"ingredients": [{"id": paid_id, "units": 20}], "modifiers": []}
	assert_true(economy.recipe_cost(paid_recipe, total) > 0)
	state.set_money(0)
	assert_true(not economy.can_afford_recipe(paid_recipe, total), "платный рецепт недоступен без денег")
	assert_true(economy.can_afford_recipe(free_recipe, total), "бесплатный доступен всегда")
	state.free()


func test_economy_coal_charge_never_blocks() -> void:
	var state := GameStateScript.new()
	var economy := EconomySystem.load_default(state, IngredientCatalog.load_default())
	assert_true(economy.coal_cost > 0)
	state.set_money(economy.coal_cost + 5)
	assert_eq(economy.charge_coals(), economy.coal_cost)
	assert_eq(economy.charge_coals(), 5, "списывается остаток, не больше баланса")
	assert_eq(economy.charge_coals(), 0)
	state.free()


func test_economy_mouthpiece_charge() -> void:
	var state := GameStateScript.new()
	var economy := EconomySystem.load_default(state, IngredientCatalog.load_default())
	assert_true(economy.mouthpiece_cost > 0)
	state.set_money(economy.mouthpiece_cost * 2 + 3)
	assert_eq(economy.charge_mouthpieces(2), economy.mouthpiece_cost * 2)
	assert_eq(economy.charge_mouthpieces(5), 3, "списывается остаток, не больше баланса")
	assert_eq(economy.charge_mouthpieces(0), 0)
	state.free()


func test_economy_reputation_clamped() -> void:
	var state := GameStateScript.new()
	var economy := EconomySystem.load_default(state, IngredientCatalog.load_default())
	assert_eq(economy.add_reputation(1000), economy.reputation_max)
	assert_eq(economy.add_reputation(-1000), economy.reputation_min)
	state.free()


func test_goal_strong_from_one_good_score() -> void:
	var goal := ProgressionGoal.load_default()
	assert_true(goal.is_valid(), str(goal.errors))
	assert_eq(goal.strong_score, 75.0)
	assert_eq(goal.required_trends, 1)
	var recipe := {"id": "r1"}
	assert_true(not goal.record(recipe, "", 65.0), "ниже порога 75 не засчитывается")
	assert_true(goal.record(recipe, "", 78.0), "без трендов хватает одной оценки 75+")
	assert_true(goal.is_strong(recipe))
	assert_true(not goal.record(recipe, "fresh_fruit", 90.0), "рецепт уже сильный")


func test_goal_needs_two_trends_when_configured() -> void:
	var goal := ProgressionGoal.from_dict({"strong_score": 75, "required_trends": 2, "goal_recipes": 3, "ending_dialogue": "mvp_ending"})
	var recipe := {"id": "r1"}
	assert_true(not goal.record(recipe, "fresh_fruit", 90.0), "один тренд — ещё не сильный")
	assert_true(not goal.record(recipe, "fresh_fruit", 90.0), "тот же тренд не считается повторно")
	assert_true(not goal.record(recipe, "sour_zing", 60.0), "низкая оценка не засчитывается")
	assert_true(goal.record(recipe, "sour_zing", 80.0), "второй тренд делает рецепт сильным")
	assert_true(goal.is_strong(recipe))


func test_goal_counts_strong_recipes() -> void:
	var goal := ProgressionGoal.load_default()
	assert_eq(goal.goal_recipes, 2)
	var recipes := {"weak": {"strong_trends": []}}
	assert_eq(goal.strong_count(recipes), 0)
	assert_true(not goal.is_complete(recipes))
	assert_eq(goal.progress_text(recipes), "0/2")
	recipes["r0"] = {"strong_trends": ["base"]}
	assert_eq(goal.strong_count(recipes), 1)
	assert_true(not goal.is_complete(recipes))
	recipes["r1"] = {"strong_trends": ["base"]}
	assert_true(goal.is_complete(recipes))
	assert_eq(goal.progress_text(recipes), "2/2")


func test_mvp_ending_dialogue_valid() -> void:
	var library := DialogueLibrary.new()
	library.load_directory("res://data/dialogues")
	assert_true(library.errors.is_empty(), str(library.errors))
	assert_true(library.has_dialogue(ProgressionGoal.load_default().ending_dialogue))


func test_status_hud_format() -> void:
	var text := StatusHud.format_lines(150, 5, "Свежие фрукты", 2, "1/3", false)
	assert_true(text.contains("150") and text.contains("1/3") and text.contains("Свежие фрукты"))
