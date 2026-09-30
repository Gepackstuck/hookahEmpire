extends TestCase


func test_loads_denis() -> void:
	var guest := GuestCatalog.load_guest("friend_denis")
	assert_eq(guest["name"], "Денис")
	assert_true(not str(guest["emoji"]).is_empty())


func test_missing_guest_returns_empty() -> void:
	GameLog.muted = true
	assert_eq(GuestCatalog.load_guest("нет_такого"), {})
	GameLog.muted = false


func test_denis_sprite_faces_left() -> void:
	var guest := GuestCatalog.load_guest("friend_denis")
	assert_eq(guest.get("sprite_faces", "right"), "left")


func test_denis_has_sweet_preference() -> void:
	var guest := GuestCatalog.load_guest("friend_denis")
	assert_eq(guest["preferences"]["sweet"], 1.0)


func test_orders_are_valid_and_rolled() -> void:
	var guest := GuestCatalog.load_guest("friend_denis")
	assert_true(guest["orders"].size() >= 3, "нужно несколько вариантов заказа")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 60:
		var order := GuestCatalog.roll_order(guest, rng)
		assert_true(not str(order["text"]).is_empty())
		seen[order["id"]] = true
	assert_true(seen.size() >= 3, "заказы должны различаться")


func test_reactions_exist_for_every_emotion() -> void:
	var guest := GuestCatalog.load_guest("friend_denis")
	var rng := RandomNumberGenerator.new()
	for emotion_id in ["love", "like", "okay", "meh", "dislike"]:
		assert_true(guest["reactions"].has(emotion_id), "нет реплик для %s" % emotion_id)
		assert_true(not GuestCatalog.reaction_text(guest, emotion_id, true, rng).is_empty())
	assert_true(not GuestCatalog.reaction_text(guest, "нет_такой", false, rng).is_empty())


func test_smoke_permission_is_random_and_lines_exist() -> void:
	var guest := GuestCatalog.load_guest("friend_denis")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var yes := 0
	for i in 200:
		if GuestCatalog.roll_smoke_permission(guest, rng):
			yes += 1
	assert_true(yes > 60 and yes < 140, "разрешает и отказывает случайно (разрешил %d из 200)" % yes)
	for key in ["ask", "yes", "no"]:
		assert_true(not GuestCatalog.smoke_line(guest, key, rng).is_empty())
