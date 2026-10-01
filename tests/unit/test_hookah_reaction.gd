extends TestCase
## Тесты состояния кальяна на столе и действий гостя в гараже.

func test_hookah_station_states() -> void:
	var station := HookahStation.new()
	assert_eq(station.prompt(), "Приготовить кальян")
	assert_eq(station.action(), "open_preparation")
	assert_true(station.can_prepare() and not station.can_smoke())
	station.apply_result({"recipe_id": "r"}, {"likes": false, "guest_id": "friend_denis"})
	assert_eq(station.state, HookahStation.STATE_DISLIKED)
	assert_true(not station.can_prepare(), "M6: перезабить недовольному гостю нельзя")
	assert_true(not station.guest_smokes() and not station.can_smoke())
	station.apply_result({"recipe_id": "r"}, {"likes": true, "guest_id": "friend_denis"})
	assert_eq(station.state, HookahStation.STATE_LIKED)
	assert_eq(station.prompt(), "Покурить")
	assert_eq(station.action(), "smoke_hookah")
	assert_true(station.guest_smokes() and station.can_smoke() and not station.can_prepare())
	assert_eq(station.player_emoji(), "😶‍🌫️")
	station.reset()
	assert_eq(station.state, HookahStation.STATE_EMPTY)
	station.apply_result({"recipe_id": "r"}, {})
	assert_eq(station.state, HookahStation.STATE_PREPARED)
	assert_true(station.can_smoke() and not station.guest_smokes() and not station.can_prepare())


func test_garage_configure_interaction_and_friend_effects() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var garage: Node = load("res://scenes/garage/Garage.tscn").instantiate()
	tree.root.add_child(garage)
	await tree.process_frame
	garage.configure_interaction("table_hookah", "Покурить", "smoke_hookah", "😶‍🌫️", "Тянется.")
	var data: InteractableData = garage._interactions.find_by_id("table_hookah")
	assert_eq(data.prompt, "Покурить")
	assert_eq(data.action, "smoke_hookah")
	assert_eq(data.player_emoji, "😶‍🌫️")
	assert_eq(garage.ready_friend_id(), "")
	var guest := GuestCatalog.load_guest("friend_denis")
	assert_true(garage.spawn_friend(guest, Vector2(0.3, 7.5), Vector2i(1, 7), Vector2i(17, 7), "friend_denis_intro", {"emoji": "🧘‍♂️", "facing": "left"}))
	var friend: Friend = garage._objects["friend_denis"]
	friend.arrived.emit()
	assert_eq(garage.ready_friend_id(), "friend_denis")
	garage.friend_react("friend_denis", "😍")
	assert_true(friend._bubble.visible and friend._bubble.text == "😍")
	garage.set_friend_smoking("friend_denis", true)
	assert_true(friend._smoke.active)
	garage.set_friend_smoking("friend_denis", false)
	assert_true(not friend._smoke.active)
	tree.root.remove_child(garage)
	garage.free()
