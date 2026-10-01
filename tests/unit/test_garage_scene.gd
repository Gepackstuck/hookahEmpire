extends TestCase
## Smoke-тесты сборки сцены гаража и настроек ввода.


func test_input_actions_exist() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "interact"]:
		assert_true(InputMap.has_action(action), "нет input action '%s'" % action)


func test_garage_scene_builds_world() -> void:
	# В --script режиме _ready у нод, добавленных в _initialize, срабатывает только после первого кадра.
	var tree := Engine.get_main_loop() as SceneTree
	var garage: Node = load("res://scenes/garage/Garage.tscn").instantiate()
	tree.root.add_child(garage)
	await tree.process_frame
	var entities := garage.get_node("%Entities")
	# 6 объектов (включая книгу рецептов) + игрок.
	assert_eq(entities.get_child_count(), 13, "ожидалось 12 объектов и игрок")
	var player_found := false
	for child in entities.get_children():
		if child is Player:
			player_found = true
	assert_true(player_found, "игрок не создан")
	tree.root.remove_child(garage)
	garage.free()


func test_friend_can_be_spawned() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var garage: Node = load("res://scenes/garage/Garage.tscn").instantiate()
	tree.root.add_child(garage)
	await tree.process_frame
	var guest := GuestCatalog.load_guest("friend_denis")
	assert_true(garage.spawn_friend(guest, Vector2(0.3, 7.5), Vector2i(1, 7), Vector2i(9, 9), "friend_denis_intro"))
	var entities := garage.get_node("%Entities")
	assert_eq(entities.get_child_count(), 14, "ожидались 12 объектов, игрок и друг")
	tree.root.remove_child(garage)
	garage.free()


func test_dialogue_box_shows_choices_and_reports_pick() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var box: DialogueBox = load("res://scenes/ui/DialogueBox.tscn").instantiate()
	tree.root.add_child(box)
	await tree.process_frame
	var picked: Array[int] = []
	box.choice_selected.connect(func(index: int) -> void: picked.append(index))
	box.open({"s": {"name": "Тест", "portrait": "🙂"}})
	assert_true(box.visible)
	var choices: Array = [{"text": "Один", "next": "x"}, {"text": "Два", "next": "x"}]
	box.show_node({"speaker": "s", "text": "Привет"}, choices)
	assert_eq(box.get_node("%NameLabel").text, "Тест")
	assert_eq(box.get_node("%ChoicesBox").get_child_count(), 0, "кнопки появляются после печати")
	box.finish_typing()
	var buttons := box.get_node("%ChoicesBox").get_children()
	assert_eq(buttons.size(), 2)
	buttons[1].pressed.emit()
	assert_eq(picked, [1])

	box.show_node({"speaker": "s", "text": "Без выбора"}, [])
	box.finish_typing()
	assert_true(box.get_node("%HintLabel").visible, "подсказка 'дальше' для узла без выбора")
	box.close()
	assert_true(not box.visible)
	tree.root.remove_child(box)
	box.free()
