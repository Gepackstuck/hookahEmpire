extends TestCase


func _path(points: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		result.append(point)
	return result


func test_walks_at_constant_speed_and_arrives() -> void:
	var walker := PathWalker.new()
	walker.position = Vector2.ZERO
	walker.set_path(_path([Vector2(4, 0)]), 2.0)
	assert_true(walker.is_walking())
	assert_true(not walker.step(1.0))
	assert_true(walker.position.is_equal_approx(Vector2(2, 0)))
	assert_true(walker.step(1.5), "должен прийти и сообщить")
	assert_true(walker.position.is_equal_approx(Vector2(4, 0)))
	assert_true(not walker.is_walking())
	assert_true(not walker.step(1.0), "после прихода шаги ничего не делают")


func test_turns_corners_within_one_step() -> void:
	var walker := PathWalker.new()
	walker.set_path(_path([Vector2(1, 0), Vector2(1, 1)]), 1.0)
	assert_true(not walker.step(1.5), "путь ещё не закончен")
	assert_true(walker.position.is_equal_approx(Vector2(1, 0.5)), "повернул за угол в рамках одного шага: %s" % str(walker.position))
	assert_true(walker.step(1.0))
	assert_true(walker.position.is_equal_approx(Vector2(1, 1)))


func test_empty_path_does_not_walk() -> void:
	var walker := PathWalker.new()
	walker.set_path(_path([]), 2.0)
	assert_true(not walker.is_walking())
	assert_true(not walker.step(1.0))


func test_walks_real_grid_path_around_obstacle() -> void:
	var grid := GarageGrid.new(Vector2i(10, 8))
	grid.set_blocked_rect(Rect2i(4, 2, 2, 1), true)
	var walker := PathWalker.new()
	var path := grid.find_path(Vector2i(4, 0), Vector2i(4, 4))
	walker.position = path[0]
	walker.set_path(path, 3.0)
	var guard := 0
	while walker.is_walking() and guard < 1000:
		walker.step(0.05)
		assert_true(grid.is_cell_walkable(Vector2i(walker.position.floor())), "шагнул в непроходимую клетку %s" % str(walker.position))
		guard += 1
	assert_true(walker.position.is_equal_approx(Vector2(4.5, 4.5)))
