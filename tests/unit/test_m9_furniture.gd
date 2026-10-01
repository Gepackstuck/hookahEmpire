extends TestCase
## Тесты M9: каталог мебели, покупка, размещение (сетка, наложения, стены, проходы), бонус к оценке.

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _make(state: Object, money: int = 1000) -> FurnitureSystem:
	state.set_money(money)
	var economy := EconomySystem.load_default(state, IngredientCatalog.load_default())
	var system := FurnitureSystem.load_default(state, economy)
	var layout := GarageLayout.load_file("res://data/garage/garage_main.json")
	system.set_room_from_layout(layout)
	return system


func _small_system(state: Object, items: Array, required: Array) -> FurnitureSystem:
	state.set_money(10000)
	var economy := EconomySystem.load_default(state, IngredientCatalog.load_default())
	var system := FurnitureSystem.from_dict({"bonus": {"per_point": 0.25, "cap": 3.0}, "room": {"required_cells": required}, "items": items}, state, economy)
	system.set_room(Vector2i(5, 3), [], [])
	return system


func test_catalog_valid_and_has_enough_items() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	assert_true(system.is_valid(), str(system.errors))
	assert_true(system.item_order.size() >= 6, "в каталоге минимум 6 предметов")
	for id in ["small_table", "wall_picture", "lamp", "plant"]:
		assert_true(system.has_item(id), "есть %s" % id)
	state.free()


func test_catalog_validation_rejects_bad_data() -> void:
	var state := GameStateScript.new()
	var economy := EconomySystem.load_default(state, IngredientCatalog.load_default())
	var bad_price := FurnitureSystem.from_dict({"items": [{"id": "a", "price": -1, "grid_size": [1, 1], "visual": {"type": "box"}}]}, state, economy)
	assert_true(not bad_price.is_valid())
	var bad_size := FurnitureSystem.from_dict({"items": [{"id": "a", "price": 1, "grid_size": [0, 1], "visual": {"type": "box"}}]}, state, economy)
	assert_true(not bad_size.is_valid())
	var dup := FurnitureSystem.from_dict({"items": [{"id": "a", "price": 1, "grid_size": [1, 1], "visual": {"type": "box"}}, {"id": "a", "price": 1, "grid_size": [1, 1], "visual": {"type": "box"}}]}, state, economy)
	assert_true(not dup.is_valid())
	var empty := FurnitureSystem.from_dict({"items": []}, state, economy)
	assert_true(not empty.is_valid())
	state.free()


func test_base_layout_keeps_all_work_cells_reachable() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	assert_true(system.base_layout_connected(), "в пустом гараже все рабочие клетки достижимы от двери")
	state.free()


func test_buy_spends_money_and_stores_item() -> void:
	var state := GameStateScript.new()
	var system := _make(state, 100)
	var result := system.buy("chair")
	assert_true(result["ok"])
	assert_eq(int(state.money), 100 - int(system.item("chair")["price"]))
	assert_eq(system.owned_count("chair"), 1)
	assert_true(not bool(system.entry_of(str(result["uid"]))["placed"]), "куплено, но не расставлено")
	var too_expensive := system.buy("couch")
	assert_true(not too_expensive["ok"], "на диван не хватает денег")
	assert_eq(system.owned_count(), 1)
	assert_true(not system.buy("no_such_item")["ok"])
	state.free()


func test_place_snaps_and_can_move_and_remove() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var uid := str(system.buy("chair")["uid"])
	assert_true(system.place(uid, Vector2i(16, 2), 0)["ok"])
	assert_eq(system.placed_entries().size(), 1)
	assert_true(system.place(uid, Vector2i(17, 3), 1)["ok"], "тот же предмет можно переставить на место, где он уже стоял рядом")
	assert_eq(system.placed_entries().size(), 1)
	assert_eq(system.entry_rect(system.entry_of(uid)), Rect2(Vector2(17, 3), Vector2(1, 1)))
	assert_true(system.remove(uid))
	assert_eq(system.placed_entries().size(), 0)
	assert_eq(system.stored_entries().size(), 1, "убранный предмет возвращается на склад")
	assert_true(not system.remove(uid), "повторно убрать нельзя")
	state.free()


func test_overlap_and_zones_rejected() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var first := str(system.buy("chair")["uid"])
	assert_true(system.place(first, Vector2i(16, 2), 0)["ok"])
	assert_true(system.check_placement("chair", Vector2i(16, 2), 0) != "", "второй стул на то же место нельзя")
	assert_true(system.check_placement("chair", Vector2i(7, 7), 0) != "", "на стол смешивания нельзя")
	assert_true(system.check_placement("chair", Vector2i(7, 8), 0) != "", "рабочая зона перед столом смешивания закрыта")
	assert_true(system.check_placement("chair", Vector2i(18, 7), 0) == "", "правая часть комнаты свободна")
	assert_true(system.check_placement("chair", Vector2i(2, 12), 0) == "", "левый нижний угол свободен")
	assert_true(system.check_placement("chair", Vector2i(20, 0), 0) != "", "за пределами комнаты нельзя")
	assert_true(system.check_placement("chair", Vector2i(-1, 3), 0) != "")
	assert_true(system.check_placement("chair", Vector2i(18, 13), 0) == "", "свободный угол подходит")
	state.free()


func test_flat_rug_can_go_under_other_furniture_but_not_over_another_rug() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var rug := str(system.buy("rug")["uid"])
	assert_true(system.place(rug, Vector2i(14, 1), 0)["ok"])
	assert_true(system.check_placement("chair", Vector2i(15, 2), 0) == "", "стул можно поставить на ковёр")
	assert_true(system.check_placement("rug", Vector2i(15, 2), 0) != "", "ковёр на ковёр нельзя")
	state.free()


func test_wall_items_stick_to_walls() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	assert_true(system.check_placement("wall_picture", Vector2i(15, 0), 0) == "", "на заднюю стену можно")
	assert_true(system.check_placement("wall_picture", Vector2i(15, 1), 0) != "", "в центре комнаты нельзя")
	assert_true(system.check_placement("wall_picture", Vector2i(10, 0), 0) != "", "поверх неоновой вывески нельзя")
	assert_true(system.check_placement("wall_picture", Vector2i(0, 9), 1) == "", "на левую стену (поворот) можно")
	assert_true(system.check_placement("wall_picture", Vector2i(0, 1), 1) != "", "поверх вывески-свитка нельзя")
	var uid := str(system.buy("wall_picture")["uid"])
	assert_true(system.place(uid, Vector2i(15, 0), 0)["ok"])
	assert_true(system.check_placement("wall_picture", Vector2i(16, 0), 0) != "", "две картины друг на друга нельзя")
	state.free()


func test_blocking_furniture_cannot_cut_off_required_cells() -> void:
	var state := GameStateScript.new()
	var wall_item := {"id": "wall", "price": 1, "grid_size": [1, 3], "placement": "floor", "blocks": true, "visual": {"type": "box"}}
	var short_item := {"id": "short", "price": 1, "grid_size": [1, 2], "placement": "floor", "blocks": true, "visual": {"type": "box"}}
	var system := _small_system(state, [wall_item, short_item], [[0, 0], [4, 0]])
	assert_true(system.check_placement("wall", Vector2i(2, 0), 0) != "", "сплошная стена отрезает правую часть комнаты")
	assert_true(system.check_placement("short", Vector2i(2, 0), 0) == "", "проход остаётся")
	var uid := str(system.buy("short")["uid"])
	assert_true(system.place(uid, Vector2i(2, 0), 0)["ok"])
	var second := str(system.buy("short")["uid"])
	assert_true(system.check_placement("short", Vector2i(2, 1), 0, second) != "", "второй блок закрыл бы последний проход")
	assert_true(system.check_placement("short", Vector2i(0, 0), 0, second) != "", "на нужную клетку нельзя")
	state.free()


func test_bonus_is_small_and_capped() -> void:
	var state := GameStateScript.new()
	var item := {"id": "big", "price": 1, "grid_size": [1, 1], "placement": "floor", "blocks": false, "comfort": 10, "atmosphere": 10, "visual": {"type": "box"}}
	var small := {"id": "tiny", "price": 1, "grid_size": [1, 1], "placement": "floor", "blocks": false, "comfort": 1, "atmosphere": 1, "visual": {"type": "box"}}
	var system := _small_system(state, [item, small], [])
	assert_eq(system.score_bonus(), 0.0, "без мебели бонуса нет")
	var tiny_uid := str(system.buy("tiny")["uid"])
	system.place(tiny_uid, Vector2i(0, 0), 0)
	assert_true(absf(system.score_bonus() - 0.5) < 0.001, "2 очка × 0.25")
	var big_uid := str(system.buy("big")["uid"])
	system.place(big_uid, Vector2i(1, 1), 0)
	assert_eq(system.score_bonus(), system.bonus_cap, "бонус не больше потолка")
	system.remove(big_uid)
	assert_true(absf(system.score_bonus() - 0.5) < 0.001, "убранная мебель не даёт бонус")
	state.free()


func test_rotation_swaps_footprint_and_object_definition() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	assert_eq(system.footprint("couch", 0), Vector2i(3, 1))
	assert_eq(system.footprint("couch", 1), Vector2i(1, 3))
	assert_eq(system.footprint("lamp", 1), Vector2i(1, 1), "торшер не поворачивается")
	var definition := system.definition_for("chair", Vector2i(4, 4), 1, "x")
	assert_eq(str(definition["visual"]["facing"]), "y")
	var couch := system.definition_for("couch", Vector2i(2, 2), 1, "c")
	assert_eq(couch["size"], Vector2i(1, 3))
	assert_eq(couch["anchor"], Vector2(2.5, 3.5))
	state.free()


func test_furniture_survives_state_round_trip() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var uid := str(system.buy("lamp")["uid"])
	assert_true(system.place(uid, Vector2i(18, 13), 0)["ok"])
	var snapshot: Dictionary = state.to_dict()
	var restored := GameStateScript.new()
	restored.apply_dict(snapshot)
	assert_eq(restored.furniture.size(), 1)
	assert_eq(str(restored.furniture[0]["item"]), "lamp")
	assert_eq(int(restored.furniture[0]["cell"][0]), 18)
	assert_true(bool(restored.furniture[0]["placed"]))
	assert_eq(int(restored.furniture_seq), int(state.furniture_seq))
	state.free()
	restored.free()


func test_furniture_bonus_raises_final_score_and_is_kept_on_rescore() -> void:
	var scoring := SessionScoring.load_default()
	var components := {"recipe_quality": 60.0, "guest_fit": 60.0, "trend_fit": 60.0, "execution": 60.0}
	var plain := scoring.build_result(components)
	var with_bonus := scoring.build_result(components, 0.0, 0.0, {}, "", "", 2.0)
	assert_true(absf(float(with_bonus["final_score"]) - float(plain["final_score"]) - 2.0) < 0.11)
	assert_eq(float(with_bonus["furniture_bonus"]), 2.0)
	var revised := scoring.rescore(with_bonus, 5.0, 0.0)
	assert_eq(float(revised["furniture_bonus"]), 2.0, "бонус переживает пересчёт со штрафом")
	var capped := scoring.build_result({"recipe_quality": 99.0, "guest_fit": 99.0, "trend_fit": 99.0, "execution": 99.0}, 0.0, 0.0, {}, "", "", 3.0)
	assert_eq(float(capped["final_score"]), 100.0, "итог не выше 100")
	var rows := SessionSummaryScreen.breakdown_rows(with_bonus, scoring.weights)
	var has_row := false
	for row in rows:
		if str(row[0]) == "Обстановка гаража":
			has_row = true
	assert_true(has_row, "в карточке итога виден бонус обстановки")


func test_items_can_stand_on_a_rug() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var rug := str(system.buy("rug")["uid"])
	assert_true(system.place(rug, Vector2i(8, 12), 0)["ok"], "ковёр под центром комнаты (захватывает старт игрока)")
	for item_id in ["chair", "lamp", "plant", "small_table", "couch"]:
		assert_true(system.check_placement(item_id, Vector2i(8, 11), 0) == "" or system.check_placement(item_id, Vector2i(8, 13), 0) == "", "%s можно поставить на ковёр" % item_id)
	assert_true(system.check_placement("chair", Vector2i(10, 12), 0) != "", "стартовую клетку игрока занимать нельзя даже на ковре")
	state.free()


func test_plant_stands_on_table_and_shelf_and_falls_off_with_host() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var table := str(system.buy("small_table")["uid"])
	assert_true(system.place(table, Vector2i(17, 2), 0)["ok"])
	var info := system.placement_info("plant", Vector2i(17, 2), 0)
	assert_eq(str(info["problem"]), "")
	assert_eq(str(info["host"]), table, "растение ставится на стол")
	assert_eq(system.surface_lift(table), 20.0)
	var plant := str(system.buy("plant")["uid"])
	assert_true(system.place(plant, Vector2i(17, 2), 0)["ok"])
	assert_eq(str(system.entry_of(plant)["host"]), table)
	assert_true(system.check_placement("plant", Vector2i(17, 2), 0) != "", "вторую вазу на ту же клетку стола нельзя")
	var second := str(system.buy("plant")["uid"])
	assert_true(system.place(second, Vector2i(18, 2), 0)["ok"], "вторая клетка стола свободна")
	assert_true(system.check_placement("lamp", Vector2i(17, 2), 0) != "", "торшер на стол нельзя")
	var definition := system.object_definition(system.entry_of(plant))
	assert_true(not bool(definition["blocks"]), "предмет на столе не блокирует пол")
	assert_eq(float(definition["visual"]["lift"]), 20.0)
	assert_true(system.place(table, Vector2i(17, 5), 0)["ok"], "стол можно переставить")
	assert_eq(system.last_detached, 2, "предметы со стола вернулись на склад")
	assert_true(not bool(system.entry_of(plant)["placed"]))
	assert_true(system.place(plant, Vector2i(17, 5), 0)["ok"])
	assert_true(system.remove(table))
	assert_eq(system.last_detached, 1)
	assert_true(not bool(system.entry_of(plant)["placed"]), "убрали стол — растение на склад")
	state.free()


func test_plant_on_shelf() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var shelf := str(system.buy("small_shelf")["uid"])
	assert_true(system.place(shelf, Vector2i(17, 2), 0)["ok"])
	assert_eq(str(system.placement_info("plant", Vector2i(18, 2), 0)["host"]), shelf)
	assert_eq(system.surface_lift(shelf), 64.0)
	state.free()


func test_rotate_in_place() -> void:
	var state := GameStateScript.new()
	var system := _make(state)
	var couch := str(system.buy("couch")["uid"])
	assert_true(system.place(couch, Vector2i(2, 11), 0)["ok"])
	var result := system.rotate_in_place(couch)
	assert_true(result["ok"], str(result))
	assert_eq(int(system.entry_of(couch)["rotation"]), 1)
	assert_eq(system.entry_rect(system.entry_of(couch)).size, Vector2(1, 3))
	var lamp := str(system.buy("lamp")["uid"])
	system.place(lamp, Vector2i(18, 13), 0)
	assert_true(not system.rotate_in_place(lamp)["ok"], "торшер не поворачивается")
	var picture := str(system.buy("wall_picture")["uid"])
	assert_true(system.place(picture, Vector2i(15, 0), 0)["ok"])
	assert_true(system.rotate_in_place(picture)["ok"], "картина переезжает на левую стену")
	assert_eq(system.entry_rect(system.entry_of(picture)).position.x, 0)
	state.free()


func test_sell_returns_part_of_price_and_drops_item() -> void:
	var state := GameStateScript.new()
	var system := _make(state, 1000)
	var uid := str(system.buy("chair")["uid"])
	assert_true(system.place(uid, Vector2i(16, 2), 0)["ok"])
	var money_before := int(state.money)
	var price := int(system.item("chair")["price"])
	var expected := system.sell_price("chair")
	assert_true(expected > 0 and expected < price, "продажа дешевле покупки")
	var result := system.sell(uid)
	assert_true(result["ok"])
	assert_eq(int(state.money), money_before + expected)
	assert_eq(system.owned_count(), 0)
	assert_eq(system.placed_entries().size(), 0)
	assert_true(not system.sell(uid)["ok"], "второй раз продать нельзя")
	state.free()


func test_sell_host_sends_items_on_it_to_storage() -> void:
	var state := GameStateScript.new()
	var system := _make(state, 1000)
	var table_uid := str(system.buy("small_table")["uid"])
	var plant_uid := str(system.buy("plant")["uid"])
	assert_true(system.place(table_uid, Vector2i(16, 2), 0)["ok"])
	assert_true(system.place(plant_uid, Vector2i(16, 2), 0)["ok"])
	assert_true(system.sell(table_uid)["ok"])
	assert_eq(system.owned_count(), 1)
	assert_true(not bool(system.entry_of(plant_uid)["placed"]), "растение вернулось на склад")
	state.free()


func test_half_cell_step_placement() -> void:
	var state := GameStateScript.new()
	var system := _make(state, 1000)
	var first := str(system.buy("chair")["uid"])
	assert_true(system.place(first, Vector2(16.5, 2.5), 0)["ok"], "стул можно поставить на половину клетки")
	assert_true(system.check_placement("chair", Vector2(16.0, 2.0), 0) != "", "пересечение на пол-клетки запрещено")
	assert_true(system.check_placement("chair", Vector2(17.5, 2.5), 0) == "", "вплотную рядом можно")
	assert_true(system.check_placement("chair", Vector2(17.5, 3.5), 0) == "", "по диагонали вплотную тоже")
	assert_eq(system.cover_cells(system.entry_rect(system.entry_of(first))), Rect2i(16, 2, 2, 2), "для пути занято 4 клетки сетки")
	assert_eq(system.cover_cells(Rect2(Vector2(3, 4), Vector2(2, 1))), Rect2i(3, 4, 2, 1))
	state.free()
