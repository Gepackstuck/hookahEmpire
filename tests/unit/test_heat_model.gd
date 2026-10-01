extends TestCase
## M7: жар кальяна (пороги, остывание, затяжки, штрафы, обслуживание углей), конфиг и пересчёт итога со штрафами.


func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(HeatModel.CONFIG_PATH))


func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func test_config_valid_and_rejects_bad() -> void:
	var model := HeatModel.load_default()
	assert_true(model.is_valid(), str(model.errors))
	assert_true(not HeatModel.from_dict({}).is_valid())
	var bad := _data()
	bad["thresholds"] = {"cold_below": 80, "hot_from": 75, "burned_from": 95}
	assert_true(not HeatModel.from_dict(bad).is_valid(), "пороги должны возрастать")
	var bad_lines := _data()
	bad_lines["lines"]["cold"] = []
	assert_true(not HeatModel.from_dict(bad_lines).is_valid(), "реплики не могут быть пустыми")
	var bad_redo := _data()
	bad_redo["redo"]["min_puff"] = 9
	assert_true(not HeatModel.from_dict(bad_redo).is_valid(), "min_puff <= max_puff")


func test_state_thresholds() -> void:
	var model := HeatModel.load_default()
	assert_eq(model.state_for(10.0), HeatModel.STATE_COLD)
	assert_eq(model.state_for(50.0), HeatModel.STATE_NORMAL)
	assert_eq(model.state_for(80.0), HeatModel.STATE_HOT)
	assert_eq(model.state_for(99.0), HeatModel.STATE_BURNED)
	assert_eq(model.state_for(model.cold_below), HeatModel.STATE_NORMAL, "граница холодного включена в норму")
	assert_eq(model.state_for(model.hot_from), HeatModel.STATE_HOT)


func test_heat_cools_over_time_and_puffs_heat_up() -> void:
	var model := HeatModel.load_default()
	var start := model.heat
	model.tick(10.0)
	assert_true(model.heat < start, "со временем остывает")
	var before := model.heat
	model.puff()
	assert_true(_near(model.heat - before, model.puff_gain * model.pace), "затяжка греет на puff_gain * pace")
	model.pace = 2.0
	before = model.heat
	model.puff()
	assert_true(_near(model.heat - before, model.puff_gain * 2.0), "темп усиливает нагрев")


func test_heat_reaches_cold_hot_burned_with_events() -> void:
	var model := HeatModel.load_default()
	var changed := ""
	for i in 400:
		changed = model.tick(1.0)
		if changed != "":
			break
	assert_eq(changed, HeatModel.STATE_COLD, "без затяжек кальян остывает")
	model.begin()
	model.pace = 3.0
	var seen: Array[String] = []
	for i in 80:
		var event := model.puff()
		if event != "":
			seen.append(event)
	assert_true(seen.has(HeatModel.STATE_HOT) and seen.has(HeatModel.STATE_BURNED), "перегрев: hot, затем burned")
	assert_true(model.needs_service())


func test_penalty_accumulates_is_capped_and_burn_is_one_time() -> void:
	var model := HeatModel.load_default()
	model.heat = 80.0
	model.state = HeatModel.STATE_HOT
	model.tick(10.0)
	assert_true(_near(model.penalty, 10.0 * model.penalty_per_second[HeatModel.STATE_HOT] , 0.3), "штраф за жарко по секундам")
	model.begin()
	model.heat = 94.0
	model.pace = 1.0
	model.puff()
	assert_true(model.state == HeatModel.STATE_BURNED)
	assert_true(_near(model.penalty, model.burn_once), "сгорание даёт разовый штраф")
	var after := model.penalty
	model.puff()
	assert_true(_near(model.penalty, after), "разовый штраф не повторяется")
	model.tick(10000.0)
	model.heat = 99.0
	for i in 5:
		model.tick(10000.0)
		model.heat = 99.0
	assert_true(model.penalty <= model.max_heat_penalty + 0.001, "штраф ограничен")


func test_service_resets_heat_and_keeps_penalty() -> void:
	var model := HeatModel.load_default()
	model.heat = 98.0
	model.state = HeatModel.STATE_BURNED
	model.add_penalty(7.0)
	model.service()
	assert_eq(model.state, HeatModel.STATE_NORMAL)
	assert_true(_near(model.heat, model.service_heat))
	assert_true(_near(model.penalty, 7.0), "штраф остаётся")
	assert_true(not model.needs_service())
	model.begin()
	assert_true(_near(model.penalty, 0.0), "новая сессия — штраф обнулён")


func test_npc_pace_in_range_and_lines_exist() -> void:
	var model := HeatModel.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		var pace := model.roll_npc_pace(rng)
		assert_true(pace >= model.pace_npc_min and pace <= model.pace_npc_max)
		var interval := model.roll_pace_interval(rng)
		assert_true(interval >= model.pace_change_min and interval <= model.pace_change_max)
	for key in HeatModel.LINE_KEYS:
		assert_true(model.random_line(key, rng) != "", "есть реплика '%s'" % key)
	assert_eq(model.random_line("nope", rng), "")


func test_rescore_applies_penalties_and_keeps_guest_fields() -> void:
	var scoring := SessionScoring.load_default()
	var verdict := scoring.build_result({"recipe_quality": 80.0, "guest_fit": 80.0, "trend_fit": 80.0, "execution": 80.0})
	verdict["guest_id"] = "friend_denis"
	verdict["recipe_id"] = "r1"
	var revised := scoring.rescore(verdict, 20.0, 5.0)
	assert_true(_near(float(revised["final_score"]), float(verdict["final_score"]) - 25.0, 0.2), "штрафы вычитаются")
	assert_eq(str(revised["guest_id"]), "friend_denis")
	assert_eq(str(revised["recipe_id"]), "r1")
	assert_true(int(revised["payment"]) < int(verdict["payment"]), "оплата падает")
	assert_true(_near(float(revised["heat_penalty"]), 20.0) and _near(float(revised["service_penalty"]), 5.0))
	var floor_case := scoring.rescore(verdict, 100.0, 100.0)
	assert_true(float(floor_case["final_score"]) >= 0.0, "оценка не уходит ниже 0")
