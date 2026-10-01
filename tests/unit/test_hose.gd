extends TestCase
## Шланг и мундштуки: кривая, мундштук на шнурке мастера, рука фигурки.


func test_hose_curve_connects_both_ends() -> void:
	var hose := HoseLine.new()
	hose.start = Vector2(10, -30)
	hose.end = Vector2(-40, 5)
	var points := hose.curve()
	assert_true(points.size() > 4)
	assert_true(points[0].is_equal_approx(hose.start), "кривая начинается у клапана")
	assert_true(points[points.size() - 1].is_equal_approx(hose.end), "кривая заканчивается у мундштука")
	hose.lying = true
	var lying := hose.curve()
	assert_true(lying[0].is_equal_approx(hose.start))
	hose.free()


func test_master_wears_mouthpiece_on_lanyard_and_guest_does_not() -> void:
	var player := CharacterFigure.make("player")
	assert_true(player.lanyard, "у кальянного мастера мундштук на шнурке")
	assert_true(not player.piece_hidden)
	var guest := CharacterFigure.make("denis")
	assert_true(not guest.lanyard)
	assert_true(player.piece_color != guest.piece_color, "у каждого свой мундштук")
	player.free()
	guest.free()


func test_hookah_object_valve_is_above_base() -> void:
	var layout := GarageLayout.load_file("res://data/garage/garage_main.json")
	var hookah := GarageObject.new()
	for object in layout.objects:
		if object["id"] == "hookah_prep":
			(Engine.get_main_loop() as SceneTree).root.add_child(hookah)
			hookah.setup(object)
	assert_true(hookah.hookah_valve_position().y < hookah.hookah_base_position().y, "клапан выше основания")
	(Engine.get_main_loop() as SceneTree).root.remove_child(hookah)
	hookah.free()


func test_hose_wraps_behind_hookah_when_smoker_is_on_far_side() -> void:
	var hose := HoseLine.new()
	hose.start = Vector2(100, -30)
	hose.cover_enabled = true
	hose.cover_base = Vector2(94, 0)
	hose.end = Vector2(150, -10)
	assert_true(not hose.is_wrapped(), "курящий справа — шланг идёт напрямую")
	hose.end = Vector2(40, -10)
	assert_true(hose.is_wrapped(), "курящий слева — шланг идёт за кальяном")
	var points := hose.curve()
	assert_true(points[0].is_equal_approx(hose.start))
	assert_true(points[points.size() - 1].is_equal_approx(hose.end))
	var passes_behind := false
	for point in points:
		if absf(point.x - hose.cover_base.x) < 4.0:
			passes_behind = true
	assert_true(passes_behind, "кривая проходит через колонну кальяна")
	hose.lying = true
	assert_true(not hose.is_wrapped(), "лежащий шланг не прячется")
	hose.free()


func test_hose_is_thin_and_mouthpiece_small() -> void:
	assert_true(HoseLine.WIDTH_OUTLINE <= 3.0)
	assert_true(HoseLine.PIECE_SCALE <= 0.4)


func test_handle_geometry_matches_figure_grip() -> void:
	var grip_to_mouth := HoseLine.HANDLE_LENGTH - HoseLine.GRIP_OFFSET + HoseLine.PIECE_LENGTH
	var reach := Vector2(CharacterFigure.GRIP_REACH, CharacterFigure.GRIP_DROP).length() * CharacterFigure.BODY_SCALE
	assert_true(absf(reach - grip_to_mouth) < 1.0, "рука у рта = хват ручки")
	assert_true(HoseLine.HANDLE_STYLES >= 4, "несколько видов ручек")
