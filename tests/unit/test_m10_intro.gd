extends TestCase
## Тесты M10: ворота интро, цель-подсказка, Бэн (данные), подарок-мебель, тайминги, гости Иван/Бэн.

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {"sessions": 0, "ben_here": false, "couch_placed": false, "recipe_count": 0, "coals_replaced": false,
		"furniture_unlocked": false, "extra_furniture_placed": 0, "goal_done": false, "progress_text": "0/3"}
	ctx.merge(overrides, true)
	return ctx


func test_config_valid() -> void:
	var guide := IntroGuide.load_default()
	assert_true(guide.is_valid(), str(guide.errors))
	assert_true(guide.ending_notice.contains("3"), "уведомление про 3 рецепта")


func test_config_rejects_bad_data() -> void:
	var guide := IntroGuide.from_dict({"unlocks": {"quick_after_sessions": -1}, "ben": {}, "guide": {}})
	assert_true(not guide.is_valid())


func test_unlock_thresholds() -> void:
	var guide := IntroGuide.load_default()
	assert_true(not guide.is_quick_unlocked(0))
	assert_true(not guide.is_quick_unlocked(1))
	assert_true(guide.is_quick_unlocked(2))
	assert_true(not guide.is_furniture_unlocked(0))
	assert_true(guide.is_furniture_unlocked(1))


func test_ben_arrives_once_after_first_guest() -> void:
	var guide := IntroGuide.load_default()
	assert_true(not guide.ben_should_arrive(0, false))
	assert_true(guide.ben_should_arrive(1, false))
	assert_true(not guide.ben_should_arrive(2, true), "второй раз Бэн не приходит")


func test_ben_ranges_in_bounds() -> void:
	var guide := IntroGuide.load_default()
	var rng := RandomNumberGenerator.new()
	for key in IntroGuide.BEN_RANGES:
		var range_value: Array = guide.ben[key]
		for i in range(10):
			var value := guide.ben_range(key, rng)
			assert_true(value >= float(range_value[0]) and value <= float(range_value[1]), key)
	assert_true(guide.ben_lines("remind_lines").size() > 0)


func test_guide_step_sequence() -> void:
	var guide := IntroGuide.load_default()
	assert_eq(guide.current_step(_ctx())["id"], "serve_first")
	assert_eq(guide.current_step(_ctx({"sessions": 1, "ben_here": true}))["id"], "place_couch")
	assert_eq(guide.current_step(_ctx({"sessions": 1, "ben_here": true, "couch_placed": true, "furniture_unlocked": true}))["id"], "serve_second")
	var after_second := _ctx({"sessions": 2, "ben_here": true, "couch_placed": true, "furniture_unlocked": true})
	assert_eq(guide.current_step(after_second)["id"], "serve_third")
	after_second["sessions"] = 3
	assert_eq(guide.current_step(after_second)["id"], "recipes")
	after_second["recipe_count"] = 3
	assert_eq(guide.current_step(after_second)["id"], "decorate", "угли без предупреждения шаг не блокируют")
	after_second["heat_warn"] = true
	assert_eq(guide.current_step(after_second)["id"], "heat")
	after_second["coals_replaced"] = true
	assert_eq(guide.current_step(after_second)["id"], "decorate")
	after_second["extra_furniture_placed"] = 1
	var strong := guide.current_step(after_second)
	assert_eq(strong["id"], "strong")
	assert_true(str(strong["text"]).contains("0/3"), "прогресс подставляется в текст")
	after_second["goal_done"] = true
	assert_eq(guide.current_step(after_second)["id"], "done")


func test_guide_skips_inapplicable_steps() -> void:
	var guide := IntroGuide.load_default()
	# Бэна нет и мебель закрыта: шаги «поставь диван» и «обставь гараж» пропускаются.
	var step := guide.current_step(_ctx({"sessions": 3, "recipe_count": 3, "coals_replaced": true}))
	assert_eq(step["id"], "strong")


func test_gift_furniture_cannot_be_sold_and_is_not_counted() -> void:
	var state := GameStateScript.new()
	state.set_money(1000)
	var economy := EconomySystem.load_default(state, IngredientCatalog.load_default())
	var system := FurnitureSystem.load_default(state, economy)
	system.set_room_from_layout(GarageLayout.load_file("res://data/garage/garage_main.json"))
	assert_true(system.has_item("couch"))
	var granted := system.grant_gift("couch")
	assert_true(granted["ok"])
	assert_true(not system.gift_entry("couch").is_empty())
	assert_eq(system.placed_non_gift_count(), 0)
	var sold := system.sell(str(granted["uid"]))
	assert_true(not sold["ok"], "подарок нельзя продать")
	assert_eq(state.money, 1000, "деньги не изменились")
	assert_true(not system.grant_gift("нет_такого")["ok"])
	state.free()


func test_guest_files_for_ivan_and_ben() -> void:
	var ivan := GuestCatalog.load_guest("friend_ivan")
	assert_eq(ivan["name"], "Иван")
	assert_true(ivan["orders"].size() >= 3)
	var ben := GuestCatalog.load_guest("friend_ben")
	assert_eq(ben["name"], "Бэн")
	assert_true(not ben.has("orders") or (ben["orders"] as Array).is_empty(), "у Бэна нет заказов")


func test_ivan_beat_and_dialogues() -> void:
	var beats := StoryBeats.load_file("res://data/story/intro_beats.json")
	assert_true(beats.is_valid(), str(beats.errors))
	var ivan := beats.find_for_progress("friend_02_done")
	assert_eq(ivan["guest"], "friend_ivan")
	assert_eq(ivan["sets_progress"], "friend_03_arrives")
	var library := DialogueLibrary.new()
	library.load_directory("res://data/dialogues")
	assert_true(library.errors.is_empty(), str(library.errors))
	assert_true(library.has_dialogue(ivan["dialogue"]))
	assert_true(library.has_dialogue("ben_couch"))


func test_beat_times_marked_once() -> void:
	var stats := PlaytestStats.new()
	assert_true(stats.mark_beat("session_1", 65.0))
	assert_true(not stats.mark_beat("session_1", 99.0), "повторная отметка игнорируется")
	assert_eq(float(stats.beat_times["session_1"]), 65.0)
	assert_eq(PlaytestStats.format_time(125.0), "2:05")
	assert_true(stats.beat_lines()[0].contains("1:05"))
	stats.reset()
	assert_true(stats.beat_times.is_empty())
