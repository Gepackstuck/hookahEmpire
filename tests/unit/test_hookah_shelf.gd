extends TestCase
## Полка с кальянами: слоты, случайные цвета, снятие кальяна.

const LAYOUT_PATH := "res://data/garage/garage_main.json"


func _make_shelf() -> GarageObject:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var shelf := GarageObject.new()
	for object in layout.objects:
		if object["id"] == "shelf_hookah":
			(Engine.get_main_loop() as SceneTree).root.add_child(shelf)
			shelf.setup(object)
	return shelf


func _drop(shelf: GarageObject) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(shelf)
	shelf.free()


func test_shelf_has_three_hookahs() -> void:
	var shelf := _make_shelf()
	assert_eq(shelf.hookah_slot_count(), 3)
	assert_eq(shelf.free_hookah_slots().size(), 3)
	assert_eq(shelf.hookah_slot_color(0), Color("#22b8ff"))
	assert_eq(shelf.hookah_slot_color(1), Color("#ff7a1a"))
	assert_eq(shelf.hookah_slot_color(2), Color("#7bd62f"))
	shelf.restock_hookahs()
	assert_eq(shelf.hookah_slot_color(0), Color("#22b8ff"), "цвета на полке всегда одинаковые")
	_drop(shelf)


func test_take_hookah_empties_only_that_slot() -> void:
	var shelf := _make_shelf()
	var color := shelf.hookah_slot_color(1)
	shelf.take_hookah(1)
	assert_true(shelf.is_hookah_slot_taken(1))
	assert_eq(shelf.free_hookah_slots().size(), 2)
	assert_true(not shelf.free_hookah_slots().has(1))
	assert_eq(color, Color("#ff7a1a"))
	shelf.restock_hookahs()
	assert_eq(shelf.free_hookah_slots().size(), 3, "после пополнения все слоты заняты")
	_drop(shelf)


func test_shelf_front_cell_is_walkable_row_in_front() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var grid := GarageGrid.new(layout.size)
	var rect := Rect2i()
	for object in layout.objects:
		if object["blocks"]:
			grid.set_blocked_rect(Rect2i(object["cell"], object["size"]), true)
		if object["id"] == "shelf_hookah":
			rect = Rect2i(object["cell"], object["size"])
	var shelf := _make_shelf()
	for i in shelf.hookah_slot_count():
		var cell := shelf.shelf_front_cell(i)
		assert_eq(cell.y, rect.position.y + rect.size.y, "стоит прямо перед полкой")
		assert_true(cell.x >= rect.position.x and cell.x < rect.position.x + rect.size.x, "напротив слота")
		assert_true(grid.is_cell_walkable(cell), "клетка перед полкой проходима")
	_drop(shelf)


func test_random_colors_have_no_equal_neighbours() -> void:
	for attempt in 20:
		var colors := HookahArt.random_colors(25)
		assert_eq(colors.size(), 25)
		for i in range(1, colors.size()):
			assert_true(colors[i] != colors[i - 1], "соседние цвета различаются")


func test_hookah_object_color_can_be_set() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var hookah := GarageObject.new()
	for object in layout.objects:
		if object["id"] == "hookah_prep":
			(Engine.get_main_loop() as SceneTree).root.add_child(hookah)
			hookah.setup(object)
	hookah.set_hookah_color(Color("#ff3b6b"))
	assert_eq(hookah.hookah_color(), Color("#ff3b6b"))
	(Engine.get_main_loop() as SceneTree).root.remove_child(hookah)
	hookah.free()


func test_mouthpiece_box_gives_random_pieces_and_empties() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var table := GarageObject.new()
	for object in layout.objects:
		if object["id"] == "table_guest":
			(Engine.get_main_loop() as SceneTree).root.add_child(table)
			table.setup(object)
	assert_eq(table.box_piece_count(), 2, "в коробке изначально 2 мундштука")
	var color := table.take_box_piece()
	assert_true(color.a > 0.0)
	assert_eq(table.box_piece_count(), 1, "мундштук пропал из коробки")
	table.take_box_piece()
	assert_eq(table.box_piece_count(), 0)
	table.take_box_piece()
	assert_true(table.box_piece_count() > 0, "пустая коробка пополняется")
	table.restock_box()
	assert_eq(table.box_piece_count(), GarageObject.BOX_PIECE_COUNT)
	table.restock_box(3)
	assert_eq(table.box_piece_count(), 3)
	(Engine.get_main_loop() as SceneTree).root.remove_child(table)
	table.free()


func test_mouthpiece_pick_order_is_not_left_to_right() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var table := GarageObject.new()
	for object in layout.objects:
		if object["id"] == "table_guest":
			(Engine.get_main_loop() as SceneTree).root.add_child(table)
			table.setup(object)
	var sequential_runs := 0
	for attempt in 30:
		table.restock_box()
		var first_slot := -1
		var before := table._box_pieces.duplicate()
		var color := table.take_box_piece()
		for i in before.size():
			if before[i] == color:
				first_slot = i
		if first_slot == 0:
			sequential_runs += 1
	assert_true(sequential_runs < 20, "первый мундштук берётся не всегда крайний левый")
	(Engine.get_main_loop() as SceneTree).root.remove_child(table)
	table.free()
