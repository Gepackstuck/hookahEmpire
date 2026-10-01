extends TestCase
## Статистика для ручного тестирования и цикл гостей.

const MainScript := preload("res://scripts/core/main.gd")


func test_stats_record_sessions() -> void:
	var stats := PlaytestStats.new()
	stats.record_session({"guest_id": "friend_denis", "recipe_id": "r1", "final_score": 80.0, "band_id": "good", "payment": 30})
	stats.record_session({"guest_id": "friend_max", "recipe_id": "r2", "final_score": 60.0, "band_id": "ok", "payment": 10})
	assert_eq(stats.sessions, 2)
	assert_true(absf(stats.average_score() - 70.0) < 0.01)
	assert_eq(stats.payment_sum, 40)
	assert_eq(int(stats.guests["friend_denis"]["count"]), 1)
	stats.bump("redo")
	stats.bump("redo", 2)
	assert_eq(stats.count("redo"), 3)
	assert_true(not stats.summary_lines().is_empty())
	stats.reset()
	assert_eq(stats.sessions, 0)
	assert_eq(stats.count("redo"), 0)


func test_guest_loop_returns_to_first_beat() -> void:
	var beats := StoryBeats.load_file("res://data/story/intro_beats.json")
	assert_true(beats.is_valid())
	assert_true(not beats.find_for_progress(MainScript.LOOP_RESTART_PROGRESS).is_empty(), "после круга снова приходит первый гость")
	assert_true(beats.find_for_progress(MainScript.LOOP_END_PROGRESS).is_empty(), "после последнего гостя бита нет — цикл замыкается в Main")
	assert_eq(str(beats.find_for_progress(MainScript.LOOP_RESTART_PROGRESS)["guest"]), "friend_denis")


func test_repeat_visit_progress_returns_to_done() -> void:
	var beats := StoryBeats.load_file("res://data/story/intro_beats.json")
	assert_eq(beats.done_progress_for("friend_denis"), "friend_01_done")
	assert_eq(beats.done_progress_for("friend_max"), "friend_02_done")
	assert_eq(beats.done_progress_for("friend_ivan"), "friend_03_done")
	assert_true(beats.is_in_progress_of("friend_denis", "friend_01_arrives"), "визит без разговора тоже завершается")
	assert_true(beats.is_in_progress_of("friend_denis", "friend_01_intro_done"))
	assert_true(not beats.is_in_progress_of("friend_denis", "friend_02_arrives"))
	assert_eq(beats.done_progress_for("nobody"), "")


func test_orders_do_not_repeat_until_exhausted() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var guest := GuestCatalog.load_guest("friend_denis")
	var total: int = (guest["orders"] as Array).size()
	var used: Array = []
	for i in total:
		var order := GuestCatalog.roll_order(guest, rng, {}, used)
		assert_true(not used.has(str(order["text"])), "заказ %d не повторяет прежние" % i)
		used.append(str(order["text"]))
	var again := GuestCatalog.roll_order(guest, rng, {}, used)
	assert_true(str(again["text"]) != str(used[used.size() - 1]), "после круга — не тот же подряд")


func test_speed_options() -> void:
	assert_true(StatsPanel.SPEEDS.has(1.0), "есть обычная скорость")
	assert_true(StatsPanel.SPEEDS.max() <= 10.0, "выше ×10 кадры слишком крупные")
