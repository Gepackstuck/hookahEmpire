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
	var ids: Array[String] = []
	for object in layout.objects:
		ids.append(object["id"])
	for required in ["table_test", "hookah_test", "door_main", "crate_test", "lamp_test", "recipe_book"]:
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
	assert_eq(by_id["hookah_test"]["interaction"]["action"], "")


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
