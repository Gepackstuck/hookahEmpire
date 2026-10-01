extends TestCase
## M6: гости сессии — второй гость со случайным контрастным вкусом, внешность, прощание.


func test_max_loads_and_differs_visually() -> void:
	var max_guest := GuestCatalog.load_guest("friend_max")
	var denis := GuestCatalog.load_guest("friend_denis")
	assert_eq(max_guest["name"], "Макс")
	assert_true(max_guest.has("random_taste"))
	assert_true(max_guest["look"]["hair"] != "#5a3a22", "цвет волос должен отличаться от Дениса")
	assert_true(max_guest["look"]["shirt"] != "#e8833a", "одежда должна отличаться от Дениса")
	assert_true(not denis.has("random_taste"))


func test_random_taste_is_contrasting_and_random() -> void:
	var guest := GuestCatalog.load_guest("friend_max")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var avoid := {"sweet": 1.0, "fruit": 0.5}
	var primaries := {}
	var with_dislike := 0
	for i in 200:
		var order := GuestCatalog.roll_order(guest, rng, avoid)
		assert_true(not str(order["text"]).is_empty())
		var preferences: Dictionary = order["preferences"]
		assert_true(not preferences.is_empty())
		for dimension in preferences:
			assert_true(not avoid.has(dimension), "вкус Макса пересёкся с вкусом предыдущего гостя: %s" % dimension)
			assert_true(IngredientCatalog.DIMENSIONS.has(dimension))
		primaries[order["id"]] = true
		if order.has("dislikes"):
			with_dislike += 1
			for dimension in order["dislikes"]:
				assert_true(avoid.has(dimension) and not preferences.has(dimension))
	assert_true(primaries.size() >= 4, "вкус должен быть случайным (разных: %d)" % primaries.size())
	assert_true(with_dislike > 0 and with_dislike < 200, "неприятие появляется иногда")


func test_random_taste_is_deterministic_for_seed() -> void:
	var guest := GuestCatalog.load_guest("friend_max")
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 5
	second.seed = 5
	assert_eq(GuestCatalog.roll_order(guest, first, {"sweet": 1.0}), GuestCatalog.roll_order(guest, second, {"sweet": 1.0}))


func test_random_taste_without_avoid_still_works() -> void:
	var guest := GuestCatalog.load_guest("friend_max")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var order := GuestCatalog.roll_order(guest, rng)
	assert_true(not order["preferences"].is_empty())
	assert_true(not order.has("dislikes"))


func test_farewell_lines_contain_payment() -> void:
	var rng := RandomNumberGenerator.new()
	for guest_id in ["friend_denis", "friend_max"]:
		var guest := GuestCatalog.load_guest(guest_id)
		for emotion_id in ["love", "like", "okay", "meh", "dislike"]:
			assert_true(guest["farewell"].has(emotion_id), "%s: нет прощания для %s" % [guest_id, emotion_id])
			assert_true(guest["reactions"].has(emotion_id))
			var line := GuestCatalog.farewell_text(guest, emotion_id, true, 345, rng)
			assert_true(line.contains("345"), line)
			assert_true(not line.contains("{pay}"))
	assert_true(GuestCatalog.farewell_text({}, "x", false, 50, rng).contains("50"))


func test_guest_reactions_do_not_ask_to_redo() -> void:
	# M6: перезабивки нет — гость не просит «перезабить».
	var denis := GuestCatalog.load_guest("friend_denis")
	for emotion_id in denis["reactions"]:
		for line in denis["reactions"][emotion_id]:
			assert_true(not str(line).to_lower().contains("перезаб"), str(line))


func test_second_beat_follows_first_guest() -> void:
	var beats := StoryBeats.load_file("res://data/story/intro_beats.json")
	assert_true(beats.is_valid(), str(beats.errors))
	var first := beats.find_for_progress("intro_start")
	var second := beats.find_for_progress("friend_01_done")
	assert_eq(second["guest"], "friend_max")
	assert_true(second["delay"] > 0.0, "между гостями есть пауза")
	assert_eq(second["stand_cell"], first["stand_cell"], "Макс садится на тот же стул")
	var library := DialogueLibrary.new()
	library.load_directory("res://data/dialogues")
	assert_true(library.has_dialogue(second["dialogue"]))
	assert_eq(beats.find_for_progress("friend_02_done"), {}, "после Макса гостей нет")


func test_figure_look_applies_colors() -> void:
	var figure := CharacterFigure.make("denis")
	figure.apply_look({"hair": "#112233", "shirt": "#445566"})
	assert_eq(figure.hair, Color("#112233"))
	assert_eq(figure.shirt, Color("#445566"))
	figure.free()
