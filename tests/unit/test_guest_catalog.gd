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
