extends TestCase

const LAYOUT_PATH := "res://data/garage/garage_main.json"


func _valid_dict() -> Dictionary:
	return {
		"id": "g",
		"size": [10, 8],
		"player_spawn": [1.5, 1.5],
		"objects": [
			{"id": "a", "cell": [4, 4], "size": [2, 1], "blocks": true, "visual": {"type": "box"}},
		],
	}


func test_real_layout_is_valid() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	assert_true(layout.is_valid(), "ошибки: %s" % str(layout.errors))
	assert_eq(layout.size, Vector2i(20, 15))
	assert_true(layout.hookah_prep_cell.x >= 0, "нужна клетка у стола для кальянов")
	assert_true(layout.player_seat_cell.x >= 0, "нужен стул игрока")
	var ids: Array[String] = []
	for object in layout.objects:
		ids.append(object["id"])
	for required in ["table_test", "hookah_test", "door_main", "recipe_book", "table_hookah", "chair_denis", "chair_player", "table_guest"]:
		assert_true(ids.has(required), "нет объекта %s" % required)


func test_valid_dict() -> void:
	var layout := GarageLayout.from_dict(_valid_dict())
	assert_true(layout.is_valid(), str(layout.errors))
	assert_eq(layout.objects[0]["anchor"], Vector2(5.0, 4.5))


func test_rejects_duplicate_ids() -> void:
	var data := _valid_dict()
	data["objects"].append({"id": "a", "cell": [0, 0], "visual": {"type": "emoji", "text": "x"}})
	assert_true(not GarageLayout.from_dict(data).is_valid())


func test_rejects_out_of_bounds_object() -> void:
	var data := _valid_dict()
	data["objects"][0]["cell"] = [9, 4]
	assert_true(not GarageLayout.from_dict(data).is_valid())


func test_rejects_overlapping_blocking_objects() -> void:
	var data := _valid_dict()
	data["objects"].append({"id": "b", "cell": [5, 4], "blocks": true, "visual": {"type": "box"}})
	assert_true(not GarageLayout.from_dict(data).is_valid())


func test_rejects_spawn_inside_object() -> void:
	var data := _valid_dict()
	data["player_spawn"] = [4.5, 4.5]
	assert_true(not GarageLayout.from_dict(data).is_valid())


func test_rejects_bad_visual_and_missing_file() -> void:
	var data := _valid_dict()
	data["objects"][0]["visual"] = {"type": "hologram"}
	assert_true(not GarageLayout.from_dict(data).is_valid())
	assert_true(not GarageLayout.load_file("res://data/garage/нет_такого.json").is_valid())


func test_real_layout_actions_and_rects() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var by_id := {}
	for object in layout.objects:
		by_id[object["id"]] = object
	assert_eq(by_id["table_test"]["interaction"]["action"], "open_mixer")
	assert_eq(by_id["recipe_book"]["interaction"]["action"], "open_recipe_book")
	assert_true(not by_id["recipe_book"]["blocks"])
	assert_eq(by_id["table_test"]["size"], Vector2i(4, 2))
	assert_true(by_id["recipe_book"]["visual"].get("glow", false))
	assert_eq(by_id["table_hookah"]["interaction"]["action"], "open_preparation")
	assert_true(by_id["table_hookah"]["blocks"])
	assert_true(not by_id["hookah_test"]["blocks"], "кальян стоит на столе")
	assert_true(by_id["hookah_test"]["hidden"], "кальяна на столе изначально нет")
	assert_true(not by_id["table_guest"]["interaction"]["enabled"], "курить можно только после подачи")


func test_rejects_bad_interaction_rect() -> void:
	var data := _valid_dict()
	data["objects"][0]["interaction"] = {"rect": [1, 2, 3]}
	assert_true(not GarageLayout.from_dict(data).is_valid())
	data["objects"][0]["interaction"] = {"rect": [1, 2, 0, 1]}
	assert_true(not GarageLayout.from_dict(data).is_valid())
	data["objects"][0]["interaction"] = {"rect": [1, 2, 3, 1], "action": "open_mixer"}
	var layout := GarageLayout.from_dict(data)
	assert_true(layout.is_valid(), str(layout.errors))
	assert_eq(layout.objects[0]["interaction"]["rect"], Rect2(1, 2, 3, 1))


func test_visual_props_validation() -> void:
	var data := _valid_dict()
	data["objects"][0]["visual"]["props"] = [{"type": "hookah", "at": [0.5, -0.5], "color": "#3fa7d6"}, {"type": "coals", "at": [1, 0]}]
	var layout := GarageLayout.from_dict(data)
	assert_true(layout.is_valid(), str(layout.errors))
	data["objects"][0]["visual"]["props"] = [{"type": "dragon", "at": [0, 0]}]
	assert_true(not GarageLayout.from_dict(data).is_valid())
	data["objects"][0]["visual"]["props"] = [{"type": "jar", "at": [0]}]
	assert_true(not GarageLayout.from_dict(data).is_valid())
	data["objects"][0]["visual"]["props"] = [{"type": "jar", "at": [0, 0], "color": "zzz"}]
	assert_true(not GarageLayout.from_dict(data).is_valid())


func test_real_table_has_props() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	for object in layout.objects:
		if object["id"] == "table_test":
			assert_true(object["visual"]["props"].size() >= 5)


func test_shelf_and_neon_sign_in_real_layout() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	assert_true(layout.is_valid(), str(layout.errors))
	var by_id := {}
	for object in layout.objects:
		by_id[object["id"]] = object
	assert_true(by_id.has("shelf_hookah") and by_id.has("sign_neon"))
	assert_eq(by_id["shelf_hookah"]["visual"]["type"], "shelf")
	assert_true(by_id["shelf_hookah"]["visual"]["props"].size() >= 5, "на полке есть банки и мелочь")
	var slots: Dictionary = by_id["shelf_hookah"]["visual"]["hookah_slots"]
	assert_true(slots["rows"].size() * int(slots["count"]) >= 12, "на полке много кальянов")
	var blinking := 0
	for line in by_id["sign_neon"]["visual"]["lines"]:
		if bool(line.get("blink", false)):
			blinking += 1
	assert_eq(blinking, 1, "моргает одна строка")


func test_neon_sign_validation() -> void:
	var data := _valid_dict()
	data["objects"][0]["visual"] = {"type": "neon_sign"}
	assert_true(not GarageLayout.from_dict(data).is_valid(), "без lines вывеска невалидна")
	data["objects"][0]["visual"] = {"type": "neon_sign", "lines": [{"text": "Привет", "color": "#ffffff"}]}
	assert_true(GarageLayout.from_dict(data).is_valid(), str(GarageLayout.from_dict(data).errors))


func test_hookah_slots_and_tongs_validation() -> void:
	var data := _valid_dict()
	data["objects"][0]["visual"] = {"type": "shelf", "hookah_slots": {"rows": [{"z": 4}], "count": 5, "span": 3.0}, "props": [{"type": "tongs", "at": [0, 0]}]}
	var layout := GarageLayout.from_dict(data)
	assert_true(layout.is_valid(), str(layout.errors))
	data["objects"][0]["visual"]["hookah_slots"] = {"rows": [], "count": 5, "span": 3.0}
	assert_true(not GarageLayout.from_dict(data).is_valid(), "пустые ряды")
	data["objects"][0]["visual"]["hookah_slots"] = {"rows": [{"z": 4}], "count": 0, "span": 3.0}
	assert_true(not GarageLayout.from_dict(data).is_valid(), "count < 1")
	data["objects"][0]["visual"]["hookah_slots"] = {"rows": [{"z": 4}], "count": 3, "span": 3.0, "palette": ["zzz"]}
	assert_true(not GarageLayout.from_dict(data).is_valid(), "плохой цвет палитры")


func test_prep_hookah_object_and_table_colors_do_not_clash_with_shelf() -> void:
	var layout := GarageLayout.load_file(LAYOUT_PATH)
	var by_id := {}
	for object in layout.objects:
		by_id[object["id"]] = object
	assert_eq(by_id["hookah_prep"]["visual"]["type"], "hookah")
	assert_true(by_id["hookah_prep"]["hidden"], "на столе для кальянов кальяна изначально нет")
	for prop in by_id["table_test"]["visual"]["props"]:
		if prop["type"] == "hookah":
			assert_true(not HookahArt.PALETTE.has(str(prop["color"])), "цвет кальяна на столе-смесителе не из палитры полки")
