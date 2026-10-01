extends TestCase
## Уборка после гостя: раковина, возврат кальяна на полку, пополнение коробки с мундштуками.

const LAYOUT_PATH := "res://data/garage/garage_main.json"


func _make(object_id: String) -> GarageObject:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var node := GarageObject.new()
	for object in layout.objects:
		if object["id"] == object_id:
			(Engine.get_main_loop() as SceneTree).root.add_child(node)
			node.setup(object)
	return node


func _drop(node: GarageObject) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(node)
	node.free()


func test_sink_is_next_to_mixing_table_and_reachable() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	assert_true(layout.is_valid(), str(layout.errors))
	var sink: Dictionary = {}
	var table: Dictionary = {}
	for object in layout.objects:
		if object["id"] == GarageWorld.SINK_OBJECT_ID:
			sink = object
		elif object["id"] == "table_test":
			table = object
	assert_true(not sink.is_empty(), "раковина есть в гараже")
	assert_true(sink["blocks"])
	# Рядом со столом для рецептов: клетки раковины вплотную к столу.
	var sink_rect := Rect2i(sink["cell"], sink["size"]).grow(1)
	assert_true(sink_rect.intersects(Rect2i(table["cell"], table["size"])), "раковина рядом со столом смешивания")
	var grid := GarageGrid.new(layout.size)
	for object in layout.objects:
		if object["blocks"]:
			grid.set_blocked_rect(Rect2i(object["cell"], object["size"]), true)
	var node := _make(GarageWorld.SINK_OBJECT_ID)
	var front := node.front_cell()
	assert_true(grid.is_cell_walkable(front), "перед раковиной можно встать: %s" % str(front))
	assert_true(not grid.find_path(Vector2i(layout.player_spawn.floor()), front).is_empty(), "до раковины можно дойти")
	_drop(node)


func test_sink_washing_toggles() -> void:
	var sink := _make(GarageWorld.SINK_OBJECT_ID)
	assert_true(not sink.is_washing())
	sink.set_washing(true, Color("#22b8ff"))
	assert_true(sink.is_washing())
	assert_true(sink.wash_valve_position().distance_to(sink.position) < 80.0, "клапан кальяна в раковине рядом с ней")
	sink.set_washing(false)
	assert_true(not sink.is_washing())
	_drop(sink)


func test_wash_time_is_three_to_five_seconds() -> void:
	assert_eq(GarageWorld.WASH_MIN_SECONDS, 3.0)
	assert_eq(GarageWorld.WASH_MAX_SECONDS, 5.0)


func test_hookah_returns_to_the_shelf_slot() -> void:
	var shelf := _make("shelf_hookah")
	assert_eq(shelf.taken_hookah_slots().size(), 0)
	shelf.take_hookah(0)
	shelf.take_hookah(2)
	assert_eq(shelf.taken_hookah_slots(), [0, 2] as Array[int])
	var color := Color("#ff00aa")
	shelf.put_hookah(2, color)
	assert_true(not shelf.is_hookah_slot_taken(2))
	assert_eq(shelf.hookah_slot_color(2), color)
	assert_eq(shelf.taken_hookah_slots(), [0] as Array[int])
	_drop(shelf)


func test_box_is_topped_up_only_when_below_two() -> void:
	var table := _make("table_guest")
	assert_eq(table.box_piece_count(), 2, "изначально в коробке 2 мундштука")
	assert_true(not table.top_up_box(2), "осталось ровно 2 — не докладываем")
	table.take_box_piece()
	assert_eq(table.box_piece_count(), 1)
	assert_true(table.top_up_box(2), "меньше 2 — докладываем")
	assert_eq(table.box_piece_count(), GarageObject.BOX_PIECE_COUNT)
	_drop(table)


func test_mixing_table_front_cell_is_reachable() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var grid := GarageGrid.new(layout.size)
	for object in layout.objects:
		if object["blocks"]:
			grid.set_blocked_rect(Rect2i(object["cell"], object["size"]), true)
	var table := _make("table_test")
	var front := table.front_cell()
	assert_true(grid.is_cell_walkable(front), "перед столом смешивания можно встать: %s" % str(front))
	assert_true(not grid.find_path(Vector2i(layout.player_spawn.floor()), front).is_empty())
	_drop(table)


func test_packed_hookah_top_state_and_pack_sequence() -> void:
	var prep := _make("hookah_prep")
	assert_eq(prep.hookah_top(), 0, "кальян на столе — без чаши и углей")
	prep.set_hookah_top(2)
	assert_eq(prep.hookah_top(), 2)
	prep.set_hookah_top(0)
	assert_eq(prep.hookah_top(), 0)
	_drop(prep)


func test_mouthpiece_box_position_is_known() -> void:
	var table := _make("table_guest")
	assert_true(table.mouthpiece_box_grid_position().x >= 0.0, "у стола гостя есть коробка с мундштуками")
	_drop(table)


func test_head_labels_emoji_in_frame() -> void:
	var labels := HeadLabels.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(labels)
	var seconds := labels.say("Огонь", -1.0, "😍")
	assert_true(seconds > 0.0)
	assert_true(labels.is_speaking())
	assert_eq(labels._speech_emoji.text, "😍")
	assert_true(labels._speech_emoji.visible)
	labels.say("Без эмодзи")
	assert_true(not labels._speech_emoji.visible)
	(Engine.get_main_loop() as SceneTree).root.remove_child(labels)
	labels.free()


func test_character_view_front_back_side() -> void:
	var figure := CharacterFigure.make("denis")
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_SIDE)
	figure.look_toward(Vector2(10, 60))
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_FRONT, "цель ниже — лицом к зрителю")
	figure.look_toward(Vector2(10, -60))
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_BACK, "цель выше — спиной")
	figure.look_toward(Vector2(-60, 10))
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_SIDE)
	assert_true(not figure.facing_right)
	figure.look_toward(Vector2(0, 60))
	figure.holding = true
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_SIDE, "со шлангом в руке — профиль")
	figure.holding = false
	figure.set_facing(true)
	assert_eq(figure.view, CharacterFigure.VIEW_SIDE)
	figure.free()


func test_walking_vertically_shows_front_and_back() -> void:
	var figure := CharacterFigure.make("denis")
	figure.moving = true
	figure.walk_toward(Vector2(0, 1))
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_FRONT, "вниз (S) — лицом")
	figure.walk_toward(Vector2(0, -1))
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_BACK, "вверх (W) — спиной")
	figure.walk_toward(Vector2(1, 0.5))
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_SIDE)
	assert_true(figure.facing_right)
	figure.walk_toward(Vector2(-1, 0.5))
	assert_true(not figure.facing_right)
	figure.free()


func test_player_camera_follow_toggle() -> void:
	var scene := load("res://scenes/characters/Player.tscn") as PackedScene
	var player := scene.instantiate() as Player
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	assert_true(player.is_camera_following(), "по умолчанию камера следует за игроком")
	player.set_camera_follow(false, Rect2i(0, 0, 800, 600))
	assert_true(not player.is_camera_following())
	player.set_camera_follow(true, Rect2i(0, 0, 800, 600))
	assert_true(player.is_camera_following())
	(Engine.get_main_loop() as SceneTree).root.remove_child(player)
	player.free()


func test_figure_gestures_force_profile() -> void:
	var figure := CharacterFigure.make("player")
	figure.look_toward(Vector2(0, 60))
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_FRONT)
	for gesture_name in ["scrub", "read", "pat", "think", "drink", "juggle"]:
		figure.set_gesture(gesture_name)
		assert_eq(figure.effective_view(), CharacterFigure.VIEW_SIDE, "жест '%s' — в профиль" % gesture_name)
		assert_true(not figure._gesture_pose(Vector2(1, -43), true).is_empty())
	figure.gesture = ""
	assert_eq(figure.effective_view(), CharacterFigure.VIEW_FRONT)
	figure.free()
