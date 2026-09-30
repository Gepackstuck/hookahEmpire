extends TestCase


func test_round_trip() -> void:
	for grid_pos in [Vector2.ZERO, Vector2(3.5, 7.25), Vector2(19.9, 0.1)]:
		var back := IsoProjection.screen_to_grid(IsoProjection.grid_to_screen(grid_pos))
		assert_true(back.is_equal_approx(grid_pos), "round trip для %s дал %s" % [str(grid_pos), str(back)])


func test_axes_directions() -> void:
	# Ось X сетки идёт вправо-вниз, ось Y — влево-вниз.
	var x_step := IsoProjection.grid_to_screen(Vector2(1, 0))
	var y_step := IsoProjection.grid_to_screen(Vector2(0, 1))
	assert_true(x_step.x > 0 and x_step.y > 0)
	assert_true(y_step.x < 0 and y_step.y > 0)


func test_input_directions_move_on_screen_as_expected() -> void:
	var cases := {
		Vector2(0, -1): Vector2(0, -1),
		Vector2(0, 1): Vector2(0, 1),
		Vector2(1, 0): Vector2(1, 0),
		Vector2(-1, 0): Vector2(-1, 0),
	}
	for screen_dir in cases:
		var grid_dir := IsoProjection.screen_dir_to_grid_dir(screen_dir)
		assert_true(is_equal_approx(grid_dir.length(), 1.0), "направление должно быть единичным")
		var on_screen := IsoProjection.grid_to_screen(grid_dir).normalized()
		assert_true(on_screen.is_equal_approx(screen_dir) or on_screen.dot(screen_dir) > 0.4,
			"%s ушёл в %s" % [str(screen_dir), str(on_screen)])


func test_zero_input_gives_zero() -> void:
	assert_eq(IsoProjection.screen_dir_to_grid_dir(Vector2.ZERO), Vector2.ZERO)
