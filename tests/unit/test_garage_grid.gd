extends TestCase

const HALF := 0.25


func _make_grid() -> GarageGrid:
	var grid := GarageGrid.new(Vector2i(10, 8))
	grid.set_blocked_rect(Rect2i(4, 2, 2, 1), true) # стол 2x1
	return grid


func test_bounds_and_blocked_cells() -> void:
	var grid := _make_grid()
	assert_true(grid.is_cell_walkable(Vector2i(0, 0)))
	assert_true(not grid.is_cell_walkable(Vector2i(-1, 0)))
	assert_true(not grid.is_cell_walkable(Vector2i(10, 0)))
	assert_true(not grid.is_cell_walkable(Vector2i(4, 2)))
	assert_true(not grid.is_cell_walkable(Vector2i(5, 2)))
	assert_true(grid.is_cell_walkable(Vector2i(6, 2)))


func test_cannot_walk_into_blocked_object() -> void:
	var grid := _make_grid()
	var pos := Vector2(4.5, 4.5)
	for i in 100:
		pos = grid.resolve_move(pos, Vector2(0, -0.1), HALF)
	assert_true(pos.y >= 3.0 + HALF - 0.001, "игрок прошёл в стол: %s" % str(pos))
	assert_true(grid.can_stand(pos, HALF))


func test_slides_along_wall() -> void:
	var grid := _make_grid()
	var pos := Vector2(4.5, 3.3) # прижат к низу стола
	var moved := grid.resolve_move(pos, Vector2(0.2, -0.2), HALF)
	assert_true(moved.x > pos.x, "должен скользить вдоль стола по X")
	assert_true(is_equal_approx(moved.y, pos.y), "по Y упираться")


func test_room_walls_stop_player() -> void:
	var grid := _make_grid()
	var pos := Vector2(0.5, 0.5)
	for i in 50:
		pos = grid.resolve_move(pos, Vector2(-0.1, -0.1), HALF)
	assert_true(pos.x >= HALF - 0.001 and pos.y >= HALF - 0.001, "вышел за стены: %s" % str(pos))


func test_find_path_goes_around_obstacle() -> void:
	var grid := _make_grid()
	var path := grid.find_path(Vector2i(4, 0), Vector2i(4, 4))
	assert_true(not path.is_empty(), "путь должен существовать")
	for point in path:
		assert_true(grid.is_cell_walkable(Vector2i(point.floor())), "путь идёт через непроходимую клетку %s" % str(point))
	assert_eq(Vector2i(path[path.size() - 1].floor()), Vector2i(4, 4))


func test_find_path_unreachable_or_blocked() -> void:
	var grid := _make_grid()
	assert_true(grid.find_path(Vector2i(0, 0), Vector2i(4, 2)).is_empty(), "цель внутри стола")
	grid.set_blocked_rect(Rect2i(0, 4, 10, 1), true) # стена через всю комнату
	assert_true(grid.find_path(Vector2i(0, 0), Vector2i(0, 6)).is_empty(), "путь перекрыт")
