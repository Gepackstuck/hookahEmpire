extends TestCase
## Режим NPC: эмодзи вкусов над головами (совпало — зелёный, не совпало — красный) и надписи над головой.


func _catalog() -> IngredientCatalog:
	return IngredientCatalog.load_default()


func _states(chips: Array[Dictionary]) -> Array:
	var result: Array = []
	for chip in chips:
		result.append(chip["state"])
	return result


func test_every_dimension_has_an_emoji() -> void:
	for dimension in IngredientCatalog.DIMENSIONS:
		assert_true(TasteIcons.DIMENSION_EMOJI.has(dimension), "нет эмодзи для %s" % dimension)
	assert_eq(TasteIcons.item_emoji(_catalog(), "strawberry"), "🍓")
	assert_eq(TasteIcons.item_emoji(_catalog(), "ice"), "❄️")


func test_guest_chips_glow_until_picked_then_green_or_red() -> void:
	var catalog := _catalog()
	var prefs := {"sweet": 1.0, "fruit": 0.5}
	var start := TasteIcons.guest_chips(catalog, prefs, {}, [], false)
	assert_eq(start.size(), 2)
	assert_eq(start[0]["emoji"], "🍬", "самый важный вкус первым")
	assert_eq(_states(start), ["want", "want"])
	assert_eq(_states(TasteIcons.guest_chips(catalog, prefs, {}, ["strawberry"], true)), ["match", "match"])
	# Лимон даёт фруктовость (0.6), но не сладость (0.1): сладость не совпала.
	assert_eq(_states(TasteIcons.guest_chips(catalog, prefs, {}, ["lemon"], false)), ["want", "match"])
	assert_eq(_states(TasteIcons.guest_chips(catalog, prefs, {}, ["lemon"], true)), ["miss", "match"])


func test_dislike_chip_turns_red_when_violated() -> void:
	var catalog := _catalog()
	var prefs := {"sweet": 1.0}
	var dislikes := {"sour": 1.0}
	var chips := TasteIcons.guest_chips(catalog, prefs, dislikes, ["lemon"], true)
	assert_eq(chips[1]["emoji"], "🚫🍋")
	assert_eq(chips[1]["state"], "miss")
	assert_eq(TasteIcons.guest_chips(catalog, prefs, dislikes, ["strawberry"], true)[1]["state"], "match")


func test_ice_covers_fresh() -> void:
	var catalog := _catalog()
	assert_true(TasteIcons.covers(catalog, "ice", "fresh"))
	assert_true(not TasteIcons.covers(catalog, "ice", "sweet"))
	assert_eq(_states(TasteIcons.guest_chips(catalog, {"fresh": 1.0}, {}, ["ice"], true)), ["match"])


func test_cook_chips_green_when_ingredient_fits_the_order() -> void:
	var catalog := _catalog()
	assert_eq(_states(TasteIcons.cook_chips(catalog, ["strawberry", "lemon"], {"sweet": 1.0}, {})), ["match", "miss"])
	assert_eq(_states(TasteIcons.cook_chips(catalog, ["lemon"], {"sour": 1.0}, {})), ["match"])
	assert_eq(_states(TasteIcons.cook_chips(catalog, ["lemon"], {"sour": 1.0}, {"sour": 1.0})), ["miss"], "нарушает неприятие")
	assert_eq(TasteIcons.cook_chips(catalog, [], {"sweet": 1.0}, {}), [] as Array[Dictionary])


func test_head_labels_speech_and_chips() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var labels := HeadLabels.new()
	tree.root.add_child(labels)
	assert_true(not labels.is_speaking())
	var duration := labels.say("Привет! Сделаешь мне кальян?")
	assert_true(duration >= 1.8 and duration <= 7.0)
	assert_true(labels.is_speaking())
	labels.set_chips([{"emoji": "🍬", "state": "want"}, {"emoji": "🍓", "state": "match"}])
	assert_eq(labels.chip_count(), 2)
	labels.clear_chips()
	assert_eq(labels.chip_count(), 0)
	labels.clear_all()
	assert_true(not labels.is_speaking())
	assert_true(HeadLabels.duration_for("a very long phrase " .repeat(20)) <= 7.0)
	assert_true(HeadLabels.duration_for("Ну") < HeadLabels.duration_for("Это довольно длинная реплика гостя про кальян"))
	tree.root.remove_child(labels)
	labels.free()
