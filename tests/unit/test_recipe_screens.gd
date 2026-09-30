extends TestCase
## Smoke-тесты экранов смесителя и книги рецептов.

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _make_system(state: Node) -> RecipeSystem:
	var catalog := IngredientCatalog.load_default()
	var config := ScoringConfig.load_default(catalog)
	return RecipeSystem.create_with(state, catalog, config)


func test_mixer_screen_flow() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var state := GameStateScript.new()
	var system := _make_system(state)
	var screen: MixerScreen = load("res://scenes/ui/MixerScreen.tscn").instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	screen.setup(system)
	await tree.process_frame
	screen.open()
	assert_true(screen.visible)
	var plus: Dictionary = screen._plus
	assert_eq(plus.size(), system.catalog.ingredient_ids().size())
	# Занять 4 слота: остальные кнопки «+» блокируются.
	var ids := system.catalog.ingredient_ids()
	for i in 4:
		(plus[ids[i]] as Button).pressed.emit()
	assert_true((plus[ids[4]] as Button).disabled)
	assert_true((plus[ids[0]] as Button).disabled, "бюджет 4 порции исчерпан")
	(plus[ids[0]] as Button).pressed.emit()
	assert_eq(screen._mix.amount(ids[0]), 1)
	screen._minus[ids[0]].pressed.emit()
	assert_true(not (plus[ids[0]] as Button).disabled)
	(plus[ids[0]] as Button).pressed.emit()
	screen._ice.button_pressed = true
	assert_true(screen._ice.text.contains("❄️"))
	assert_true(screen._composition.text.contains("❄️"))
	screen._on_save_pressed()
	assert_eq(state.recipes.size(), 1)
	screen._on_save_pressed()
	assert_eq(state.recipes.size(), 1, "повторное сохранение не создаёт дубликат")
	for recipe in state.recipes.values():
		assert_eq(recipe["times_used"], 0, "повторное сохранение не увеличивает использования")
	assert_eq(screen._mix.total_portions(), 4, "до закрытия выбор сохраняется")
	var closed := [false]
	screen.closed.connect(func() -> void: closed[0] = true)
	screen.close()
	assert_true(closed[0] and not screen.visible)
	screen.open()
	assert_true(screen._mix.is_empty() and not screen._mix.ice, "после сохранения и закрытия смеситель сброшен")
	assert_true(not screen._ice.button_pressed)
	(screen._plus[ids[0]] as Button).pressed.emit()
	screen.close()
	screen.open()
	assert_eq(screen._mix.total_portions(), 1, "без сохранения выбор не сбрасывается")
	tree.root.remove_child(screen)
	screen.free()
	state.free()


func test_recipe_book_screen_flow() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var state := GameStateScript.new()
	var system := _make_system(state)
	system.commit({"strawberry": 1, "vanilla": 1}, [])
	system.commit({"apple": 4}, [])
	var book: RecipeBookScreen = load("res://scenes/ui/RecipeBookScreen.tscn").instantiate()
	tree.root.add_child(book)
	await tree.process_frame
	book.setup(system)
	await tree.process_frame
	book.open()
	assert_eq(book._list.item_count, 2)
	assert_true(not book._detail.visible and book._list.get_selected_items().is_empty(), "при открытии ничего не выбрано")
	book._on_item_selected(0)
	assert_true(book._detail.visible)
	var secret_index := -1
	for index in book._shown.size():
		if book._shown[index]["secret_id"] != "":
			secret_index = index
	assert_true(secret_index >= 0)
	book._on_item_selected(secret_index)
	assert_true(not book._rename_edit.visible and not book._rename_button.visible, "секретный рецепт нельзя переименовать")
	var normal_index := 1 - secret_index
	book._on_item_selected(normal_index)
	book._list.select(normal_index)
	book.close()
	book.open()
	assert_true(not book._detail.visible and book._list.get_selected_items().is_empty(), "повторное открытие сбрасывает выбор")
	book._on_item_selected(normal_index)
	assert_true(book._rename_edit.visible)
	var requested: Array[String] = []
	book.load_requested.connect(func(recipe_id: String) -> void: requested.append(recipe_id))
	book._load_button.pressed.emit()
	assert_eq(requested.size(), 1)
	book._rename_edit.text = "Мой микс"
	book._on_rename_pressed()
	assert_eq(system.display_name(system.get_recipe(requested[0])), "Мой микс")
	tree.root.remove_child(book)
	book.free()
	state.free()


func test_recipe_book_empty_state() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var state := GameStateScript.new()
	var system := _make_system(state)
	var book: RecipeBookScreen = load("res://scenes/ui/RecipeBookScreen.tscn").instantiate()
	tree.root.add_child(book)
	await tree.process_frame
	book.setup(system)
	await tree.process_frame
	book.open()
	assert_eq(book._list.item_count, 0)
	assert_true(book._empty.visible and not book._detail.visible)
	tree.root.remove_child(book)
	book.free()
	state.free()
