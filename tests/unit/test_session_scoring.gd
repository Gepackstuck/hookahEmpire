extends TestCase
## M6: оценка гостевой сессии (GuestFit, TrendFit, ContextScore, FinalScore, полосы, оплата) на детерминированных входах.

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _system(state: Node) -> RecipeSystem:
	var catalog := IngredientCatalog.load_default()
	return RecipeSystem.create_with(state, catalog, ScoringConfig.load_default(catalog))


func _components(quality: float, fit: float, trend: float, execution: float) -> Dictionary:
	return {"recipe_quality": quality, "guest_fit": fit, "trend_fit": trend, "execution": execution}


func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func test_config_valid_and_rejects_bad() -> void:
	var scoring := SessionScoring.load_default()
	assert_true(scoring.is_valid(), str(scoring.errors))
	assert_true(_near(scoring.weights["recipe_quality"], 0.45) and _near(scoring.weights["guest_fit"], 0.25))
	assert_true(_near(scoring.weights["trend_fit"], 0.15) and _near(scoring.weights["execution"], 0.15))
	assert_true(not SessionScoring.from_dict({}).is_valid())
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SessionScoring.CONFIG_PATH))
	var bad_bands: Dictionary = data.duplicate(true)
	bad_bands["bands"] = [{"min": 50, "id": "a", "emoji": "🙂", "name": "А"}]
	assert_true(not SessionScoring.from_dict(bad_bands).is_valid(), "нужна полоса с min = 0")
	var bad_weights: Dictionary = data.duplicate(true)
	bad_weights["context_weights"]["guest_fit"] = -1
	assert_true(not SessionScoring.from_dict(bad_weights).is_valid())
	var bad_trend: Dictionary = data.duplicate(true)
	bad_trend["trend"]["current"] = "нет_такого"
	assert_true(not SessionScoring.from_dict(bad_trend).is_valid())
	var bad_pay: Dictionary = data.duplicate(true)
	bad_pay["payment"]["exponent"] = 0
	assert_true(not SessionScoring.from_dict(bad_pay).is_valid())


func test_context_and_final_score_formula() -> void:
	var scoring := SessionScoring.load_default()
	# 0.45*80 + 0.25*85 + 0.15*50 + 0.15*85 = 36 + 21.25 + 7.5 + 12.75 = 77.5
	var result := scoring.build_result(_components(80, 85, 50, 85))
	assert_true(_near(result["context_score"], 77.5), str(result))
	assert_true(_near(result["final_score"], 77.5))
	assert_eq(result["band_id"], "like")
	assert_true(result["likes"])
	assert_eq(result["payment"], 205)
	assert_true(_near(scoring.build_result(_components(100, 100, 100, 100))["final_score"], 100.0))
	assert_eq(scoring.build_result(_components(100, 100, 100, 100))["payment"], 300)
	assert_eq(scoring.build_result(_components(0, 0, 0, 0))["payment"], 0)
	assert_eq(scoring.build_result(_components(0, 0, 0, 0))["band_id"], "dislike")


func test_penalties_reduce_and_clamp_final_score() -> void:
	var scoring := SessionScoring.load_default()
	var base := scoring.build_result(_components(80, 85, 50, 85))
	var heated := scoring.build_result(_components(80, 85, 50, 85), 10.0, 0.0)
	assert_true(_near(heated["final_score"], 67.5), str(heated))
	assert_true(heated["final_score"] < base["final_score"])
	var serviced := scoring.build_result(_components(80, 85, 50, 85), 0.0, 5.0)
	assert_true(_near(serviced["final_score"], 72.5))
	assert_true(_near(scoring.build_result(_components(10, 10, 10, 10), 50.0, 50.0)["final_score"], 0.0), "не ниже 0")


func test_band_boundaries_and_reaction_matches_score() -> void:
	var scoring := SessionScoring.load_default()
	var expected := {80.0: "love", 79.9: "like", 65.0: "like", 64.9: "okay", 55.0: "okay", 54.9: "meh", 40.0: "meh", 39.9: "dislike", 0.0: "dislike", 100.0: "love"}
	for score in expected:
		assert_eq(scoring.band_for(score)["id"], expected[score], "оценка %.1f" % score)
	# Реакция гостя всегда соответствует итоговой оценке.
	for value in [0, 12, 39, 41, 57, 66, 79, 81, 95]:
		var result := scoring.build_result(_components(value, value, value, value))
		assert_eq(result["emotion_id"], scoring.band_for(result["final_score"])["id"])
		assert_eq(result["likes"], result["final_score"] >= scoring.likes_min)


func test_payment_is_monotonic_and_rounded() -> void:
	var scoring := SessionScoring.load_default()
	var previous := -1
	for score in range(0, 101, 5):
		var pay := scoring.payment_for(float(score))
		assert_true(pay >= previous, "оплата не убывает (оценка %d)" % score)
		assert_eq(pay % scoring.pay_round_to, 0)
		previous = pay
	assert_true(scoring.payment_for(90.0) > scoring.payment_for(60.0))


func test_guest_fit_preferences_and_dislikes() -> void:
	var scoring := SessionScoring.load_default()
	var profile := {"sweet": 0.8, "fruit": 0.4, "sour": 0.5}
	# (1.0*0.8 + 0.5*0.4) / 1.5 = 0.6667
	assert_true(_near(scoring.guest_fit(profile, {"preferences": {"sweet": 1.0, "fruit": 0.5}}), 66.67))
	# Неприятие: 1.0 * 0.5 * 60 = 30 штрафа.
	assert_true(_near(scoring.guest_fit(profile, {"preferences": {"sweet": 1.0, "fruit": 0.5}, "dislikes": {"sour": 1.0}}), 36.67))
	assert_true(_near(scoring.guest_fit(profile, {}), 50.0), "без предпочтений — нейтральная оценка")
	assert_true(_near(scoring.guest_fit(profile, {"preferences": {"sweet": 1.0}, "dislikes": {"sour": 5.0}}), 0.0), "не ниже 0")


func test_trend_fit_placeholder_and_authored_trend() -> void:
	var scoring := SessionScoring.load_default()
	assert_eq(scoring.trend_current, "neutral")
	assert_true(_near(scoring.trend_fit({"sweet": 1.0}), 50.0), "нейтральный тренд не меняет оценку")
	var fresh := {"fresh": 1.0, "fruit": 1.0, "creamy": 0.0, "heavy": 0.0}
	var heavy := {"fresh": 0.0, "fruit": 0.0, "creamy": 1.0, "heavy": 1.0}
	assert_true(scoring.trend_fit(fresh, "fresh_fruit") > 70.0)
	assert_true(scoring.trend_fit(heavy, "fresh_fruit") < 40.0)


func test_same_recipe_two_guests_different_outcomes() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var scoring := SessionScoring.load_default()
	var sweet_lover := {"preferences": {"sweet": 1.0}}
	var sour_lover := {"preferences": {"sour": 1.0, "fresh": 0.4}}
	var sweet: Dictionary = recipes.commit({"strawberry": 2, "vanilla": 2}, [])["recipe"]
	var for_sweet := scoring.evaluate(sweet_lover, sweet, 85.0, recipes.catalog, recipes.config)
	var for_sour := scoring.evaluate(sour_lover, sweet, 85.0, recipes.catalog, recipes.config)
	assert_true(for_sweet["guest_fit"] - for_sour["guest_fit"] > 40.0, "вкусы контрастны: %s / %s" % [for_sweet["guest_fit"], for_sour["guest_fit"]])
	assert_true(for_sweet["final_score"] > for_sour["final_score"])
	assert_true(for_sweet["payment"] > for_sour["payment"])
	# И наоборот: кислый микс нравится кислому гостю больше, чем сладкому.
	var sour: Dictionary = recipes.commit({"lemon": 2, "lime": 2}, [])["recipe"]
	assert_true(scoring.evaluate(sour_lover, sour, 85.0, recipes.catalog, recipes.config)["final_score"] > scoring.evaluate(sweet_lover, sour, 85.0, recipes.catalog, recipes.config)["final_score"])
	state.free()


func test_execution_quality_changes_final_score() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var scoring := SessionScoring.load_default()
	var taste := {"preferences": {"sweet": 1.0}}
	var recipe: Dictionary = recipes.commit({"strawberry": 2, "vanilla": 2}, [])["recipe"]
	var neat := scoring.evaluate(taste, recipe, 90.0, recipes.catalog, recipes.config)
	var sloppy := scoring.evaluate(taste, recipe, 10.0, recipes.catalog, recipes.config)
	assert_true(neat["final_score"] > sloppy["final_score"])
	# Разница ровно вес исполнения * разница оценок (0.15 * 80 = 12).
	assert_true(_near(neat["context_score"] - sloppy["context_score"], 12.0, 0.11), str([neat["context_score"], sloppy["context_score"]]))
	state.free()


func test_recipe_book_records_best_and_last_session() -> void:
	var state := GameStateScript.new()
	var recipes := _system(state)
	var recipe_id: String = recipes.commit({"strawberry": 2, "vanilla": 2}, [])["recipe_id"]
	assert_true(not recipes.record_session("нет_такого", 50.0, "friend_denis", 100))
	assert_true(recipes.record_session(recipe_id, 80.0, "friend_denis", 400))
	assert_true(recipes.record_session(recipe_id, 40.0, "friend_max", 100))
	var recipe := recipes.get_recipe(recipe_id)
	assert_eq(recipe["best_final"], 80.0)
	assert_eq(recipe["last_final"], 40.0)
	assert_eq(recipe["last_guest"], "friend_max")
	assert_eq(recipe["sessions"], 2)
	assert_true(recipes.composition_text(recipe).contains("%"))
	state.free()


func test_summary_breakdown_rows() -> void:
	var scoring := SessionScoring.load_default()
	var verdict := scoring.build_result(_components(80, 85, 50, 85), 4.0, 0.0, {}, "Без тренда")
	var rows := SessionSummaryScreen.breakdown_rows(verdict, scoring.weights)
	assert_eq(rows.size(), 5, "4 компонента + штраф за жар")
	assert_eq(rows[0][0], "Качество рецепта")
	assert_eq(rows[0][2], "×45%")
	assert_eq(rows[4][1], "−4.0")
