extends TestCase
## M11: профили — хранилище, сохранение/загрузка, очистка, откат сюжетного прогресса.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const SaveServiceScript := preload("res://scripts/core/save_service.gd")


func _temp_dir() -> String:
	return "user://test_profiles_%d" % Time.get_ticks_usec()


func _cleanup(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for file_name in access.get_files():
		access.remove(file_name)
	DirAccess.remove_absolute(dir)


func test_create_and_limit() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	assert_eq(store.ids().size(), 0)
	var first := store.create()
	var second := store.create()
	assert_true(first != "" and first != second, "id уникальны")
	assert_eq(store.ids(), [first, second])
	for index in ProfileStore.MAX_PROFILES - 2:
		store.create()
	assert_true(not store.can_create())
	assert_eq(store.create(), "", "сверх лимита профиль не создаётся")
	_cleanup(dir)


func test_index_persists_between_opens() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var first := store.create()
	var second := store.create()
	assert_true(store.set_active(second))
	var reopened := ProfileStore.open(dir)
	assert_eq(reopened.ids(), [first, second])
	assert_eq(reopened.active_id(), second)
	reopened.delete(first)
	var third := reopened.create()
	assert_true(third != first, "номер удалённого профиля не переиспользуется")
	_cleanup(dir)


func test_save_load_round_trip() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var id := store.create()
	assert_true(not store.has_save(id))
	assert_eq(store.load_data(id), {})
	assert_eq(store.save(id, {"money": 120, "bar_name": "Дымный гараж", "save_version": 1}), OK)
	var data := store.load_data(id)
	assert_eq(int(data["money"]), 120)
	assert_eq(str(data["bar_name"]), "Дымный гараж")
	_cleanup(dir)


func test_corrupted_save_falls_back_to_backup() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var id := store.create()
	store.save(id, {"money": 10})
	store.save(id, {"money": 20})
	var file := FileAccess.open(dir.path_join("%s.json" % id), FileAccess.WRITE)
	file.store_string("{ не json")
	file.close()
	assert_eq(int(store.load_data(id).get("money", -1)), 10, "берётся предыдущая успешная запись")
	_cleanup(dir)


func test_reset_keeps_profile_but_drops_progress() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var id := store.create()
	store.save(id, {"money": 99, "bar_name": "Клуб"})
	store.save(id, {"money": 100, "bar_name": "Клуб"})
	assert_true(store.reset(id))
	assert_true(store.has_profile(id))
	assert_true(not store.has_save(id))
	assert_eq(store.load_data(id), {}, "ни сохранения, ни резервной копии")
	assert_eq(str(store.summary(id)["title"]), "Профиль 1")
	_cleanup(dir)


func test_delete_removes_profile_and_active() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var id := store.create()
	store.set_active(id)
	store.save(id, {"money": 5})
	assert_true(store.delete(id))
	assert_true(not store.has_profile(id))
	assert_eq(store.active_id(), "")
	assert_true(not store.delete(id), "повторное удаление — false")
	_cleanup(dir)


func test_summary_shows_bar_name_and_stats() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var id := store.create()
	assert_eq(str(store.summary(id)["title"]), "Профиль 1")
	assert_true(not bool(store.summary(id)["has_save"]))
	store.save(id, {"money": 300, "reputation": 7, "bar_name": "Дымный гараж", "story_flags": {"sessions_done": 4}, "recipes": {"r1": {}, "r2": {"strong_trends": ["base"]}}})
	var info := store.summary(id, ProgressionGoal.load_default())
	assert_eq(str(info["title"]), "Дымный гараж")
	assert_eq(int(info["money"]), 300)
	assert_eq(int(info["sessions"]), 4)
	assert_eq(int(info["recipes"]), 2)
	assert_eq(int(info["strong"]), 1)
	_cleanup(dir)


func test_clean_name() -> void:
	assert_eq(ProfileStore.clean_name("  Дымный\nгараж  "), "Дымный гараж")
	assert_eq(ProfileStore.clean_name("   "), "")
	assert_eq(ProfileStore.clean_name("а".repeat(60)).length(), ProfileStore.MAX_NAME_LENGTH)


func test_bar_name_round_trip_and_reset() -> void:
	var service := SaveServiceScript.new()
	var source := GameStateScript.new()
	source.bar_name = "Дымный гараж"
	var target := GameStateScript.new()
	assert_eq(service.apply_save_data(target, service.build_save_data(source)), OK)
	assert_eq(target.bar_name, "Дымный гараж")
	target.reset_to_defaults()
	assert_eq(target.bar_name, "")
	source.free()
	target.free()
	service.free()


func test_load_into_without_save_gives_defaults() -> void:
	var dir := _temp_dir()
	var service := SaveServiceScript.new()
	service._store = ProfileStore.open(dir)
	var id: String = service._store.create()
	var state := GameStateScript.new()
	state.set_money(77)
	assert_eq(service.load_into(state, id), OK)
	assert_eq(state.money, 0, "у нового профиля чистое состояние")
	service._store.save(id, {"save_version": 1, "money": 40, "bar_name": "Клуб"})
	assert_eq(service.load_into(state, id), OK)
	assert_eq(state.money, 40)
	assert_eq(state.bar_name, "Клуб")
	state.free()
	service.free()
	_cleanup(dir)


func test_save_game_is_noop_in_headless() -> void:
	var service := SaveServiceScript.new()
	assert_true(not service.needs_profile_choice(), "в headless меню профилей не нужно")
	assert_eq(service.save_game(), ERR_UNAVAILABLE)
	service.free()


func test_rewind_progress_for_mid_visit() -> void:
	var beats := StoryBeats.load_file("res://data/story/intro_beats.json")
	assert_eq(beats.rewind_progress("friend_01_arrives"), "intro_start")
	assert_eq(beats.rewind_progress("friend_02_intro_done"), "friend_01_done")
	assert_eq(beats.rewind_progress("friend_04_arrives"), "friend_03_lera")
	assert_eq(beats.rewind_progress("friend_02_done"), "friend_02_done", "между гостями прогресс не трогаем")
	assert_eq(beats.rewind_progress("intro_start"), "intro_start")


func test_loaded_whole_numbers_are_ints() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var id := store.create()
	store.save(id, {"money": 5, "recipes": {"r": {"ingredients": [{"id": "mint", "units": 3}], "best_score": 72.5, "times_used": 2}}})
	var data := store.load_data(id)
	var ingredient: Dictionary = data["recipes"]["r"]["ingredients"][0]
	assert_true(typeof(ingredient["units"]) == TYPE_INT, "целое после JSON снова int")
	assert_true(typeof(data["money"]) == TYPE_INT)
	assert_true(typeof(data["recipes"]["r"]["best_score"]) == TYPE_FLOAT, "дробное остаётся float")
	_cleanup(dir)


## Сыгранное состояние (рецепты, мебель, флаги) проходит через диск и дальше работает в системах — как при «Продолжить».
func test_played_state_survives_disk_round_trip() -> void:
	var dir := _temp_dir()
	var store := ProfileStore.open(dir)
	var id := store.create()
	var source := GameStateScript.new()
	source.set_money(2000)
	var recipes := RecipeSystem.create(source)
	var committed := recipes.commit({"lemon": 2, "lime": 2}, ["ice"])
	assert_true(bool(committed["ok"]))
	var recipe_id: String = committed["recipe_id"]
	recipes.record_preparation(recipe_id, 80.0)
	recipes.record_session(recipe_id, 72.5, "friend_denis", 190)
	var goal := ProgressionGoal.load_default()
	goal.record(source.recipes[recipe_id], "", 80.0)
	var economy := EconomySystem.load_default(source, IngredientCatalog.load_default())
	var furniture := FurnitureSystem.load_default(source, economy)
	furniture.set_room_from_layout(GarageLayout.load_file("res://data/garage/garage_main.json"))
	var bought := furniture.buy("chair")
	furniture.place(str(bought["uid"]), Vector2(5, 4), 0)
	furniture.grant_gift("couch")
	source.set_flag("sessions_done", 5)
	source.set_flag("ben_here", true)
	source.bar_name = "Клуб"
	var service := SaveServiceScript.new()
	service._store = store
	assert_eq(store.save(id, service.build_save_data(source)), OK)

	var loaded := GameStateScript.new()
	assert_eq(service.load_into(loaded, id), OK)
	assert_eq(loaded.bar_name, "Клуб")
	assert_eq(int(loaded.get_flag("sessions_done", 0)), 5)
	assert_eq(loaded.get_flag("ben_here", false) == true, true)
	assert_eq(loaded.money, source.money)
	var recipes2 := RecipeSystem.create(loaded)
	var evaluation := recipes2.evaluate({"lemon": 2, "lime": 2}, ["ice"])
	assert_true(bool(evaluation["ok"]))
	assert_true(not (evaluation["existing"] as Dictionary).is_empty(), "рецепт найден по id после загрузки")
	assert_true(recipes2.record_preparation(recipe_id, 75.0))
	assert_eq(int(loaded.recipes[recipe_id]["times_used"]), 2)
	assert_true(recipes2.record_session(recipe_id, 70.0, "friend_max", 150))
	assert_eq(goal.strong_count(loaded.recipes), goal.strong_count(source.recipes))
	var economy2 := EconomySystem.load_default(loaded, IngredientCatalog.load_default())
	var furniture2 := FurnitureSystem.load_default(loaded, economy2)
	furniture2.set_room_from_layout(GarageLayout.load_file("res://data/garage/garage_main.json"))
	assert_eq(furniture2.owned_count(), furniture.owned_count())
	assert_eq(furniture2.placed_count("chair"), furniture.placed_count("chair"))
	assert_eq(furniture2.totals()["placed"], furniture.totals()["placed"])
	for entry in furniture2.placed_entries():
		assert_true(furniture2.entry_rect(entry).size.x > 0.0, "размер предмета считается после загрузки")
	var next_bought := furniture2.buy("lamp")
	assert_true(bool(next_bought["ok"]), "после загрузки можно покупать")
	for node in [source, loaded, service]:
		node.free()
	_cleanup(dir)
