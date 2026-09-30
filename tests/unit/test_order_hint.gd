extends TestCase


func test_hint_prefers_matching_ingredients() -> void:
	var catalog := IngredientCatalog.load_default()
	var ranked := OrderHint.rank(catalog, {"sweet": 1.0, "fruit": 0.5})
	assert_eq(ranked.size(), catalog.ingredient_ids().size())
	var top := catalog.get_ingredient(ranked[0])
	var last := catalog.get_ingredient(ranked[ranked.size() - 1])
	assert_true(float(top["sweet"]) >= float(last["sweet"]), "первым должен идти более сладкий")


func test_hint_text_names_ingredients() -> void:
	var catalog := IngredientCatalog.load_default()
	assert_true(OrderHint.suggest(catalog, {"fresh": 1.0}).begins_with("попробуй "))
	assert_true(OrderHint.suggest(catalog, {}).length() > 0)


func test_random_hints_vary_for_sweet_order() -> void:
	var catalog := IngredientCatalog.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for i in 40:
		seen[OrderHint.suggest(catalog, {"sweet": 1.0, "fruit": 0.5}, 2, rng)] = true
	assert_true(seen.size() >= 3, "подсказки не должны повторяться одна и та же (вариантов: %d)" % seen.size())
