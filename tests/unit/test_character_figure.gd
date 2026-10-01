extends TestCase


func test_mouth_follows_facing_and_pose() -> void:
	var figure := CharacterFigure.make("denis")
	var right := figure.mouth_position()
	figure.set_facing(false)
	var left := figure.mouth_position()
	assert_true(right.x > 0.0 and left.x < 0.0, "рот должен отражаться вместе с разворотом")
	figure.pose = CharacterFigure.POSE_SIT
	figure.set_facing(true)
	assert_true(figure.mouth_position().y < right.y, "сидя голова выше")
	figure.free()


func test_smoke_emitter_puff_signals() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var emitter := SmokeEmitter.new()
	tree.root.add_child(emitter)
	await tree.process_frame
	var events: Array[String] = []
	emitter.inhale_started.connect(func(duration: float) -> void: events.append("in%.1f" % duration))
	emitter.inhale_ended.connect(func() -> void: events.append("out"))
	await emitter.puff(0.1)
	assert_eq(events, ["in0.1", "out"])
	tree.root.remove_child(emitter)
	emitter.free()


func test_hookah_squash_changes_and_restores_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layout := GarageLayout.load_file("res://data/garage/garage_main.json")
	var definition: Dictionary = {}
	for object in layout.objects:
		if object["id"] == "hookah_test":
			definition = object
	var hookah := GarageObject.new()
	tree.root.add_child(hookah)
	hookah.setup(definition)
	assert_true(hookah._hookah_squash == 0.0)
	hookah._apply_squash(1.0)
	assert_true(hookah._hookah_squash > 0.9, "кальян сплющен")
	hookah._apply_squash(0.0)
	assert_true(hookah._hookah_squash == 0.0, "кальян вернулся")
	tree.root.remove_child(hookah)
	hookah.free()


func test_door_opens_and_closes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layout := GarageLayout.load_file("res://data/garage/garage_main.json")
	var door := GarageObject.new()
	tree.root.add_child(door)
	for object in layout.objects:
		if object["id"] == "door_main":
			door.setup(object)
	await tree.process_frame
	await door.set_door_open(true, 0.05)
	assert_true(is_equal_approx(door._door_open, 1.0), "дверь открыта")
	await door.set_door_open(false, 0.05)
	assert_true(is_equal_approx(door._door_open, 0.0), "дверь закрыта")
	tree.root.remove_child(door)
	door.free()


func test_friend_mood_reaction_while_smoking() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var friend: Friend = load("res://scenes/characters/Friend.tscn").instantiate()
	tree.root.add_child(friend)
	await tree.process_frame
	friend.set_smoking(true, "😊")
	friend._puffs_until_mood = 1
	friend._on_inhale_started(1.0)
	assert_true(friend._bubble.visible and friend._bubble.text == "😊", "гость показывает реакцию во время курения")
	friend.set_smoking(false)
	assert_eq(friend._mood_emoji, "")
	tree.root.remove_child(friend)
	friend.free()


func test_player_sits_and_stands_up() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var player: Player = load("res://scenes/characters/Player.tscn").instantiate()
	tree.root.add_child(player)
	await tree.process_frame
	var stood := [false]
	player.stood_up.connect(func() -> void: stood[0] = true)
	player.sit_down()
	assert_true(player.seated)
	player.stand_up()
	assert_true(not player.seated and stood[0], "игрок встал и сообщил об этом")
	tree.root.remove_child(player)
	player.free()
