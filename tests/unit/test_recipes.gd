extends TestCase
## Тесты M3: каталог ингредиентов, каноникализация, скоринг, RecipeSystem, книга, MixSelection.

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _content() -> Array:
	var catalog := IngredientCatalog.load_default()
	var config := ScoringConfig.load_default(catalog)
	return [catalog, config]


func test_catalog_loads_and_valid() -> void:
	var catalog := IngredientCatalog.load_default()
	assert_true(catalog.is_valid(), str(catalog.errors))
	assert_true(catalog.ingredient_ids().size() >= 11)
	assert_true(catalog.has_ingredient("apple"))
	assert_true(catalog.has_modifier("ice"))
	assert_true(not catalog.has_ingredient("ice"))


func test_synergy_symmetric_and_unknown_neutral() -> void:
	var catalog := IngredientCatalog.load_default()
	assert_eq(catalog.synergy_between("apple", "vanilla"), catalog.synergy_between("vanilla", "apple"))
	assert_true(catalog.synergy_between("apple", "vanilla") > 0.0)
	assert_eq(catalog.synergy_between("cola", "cola"), 0.0)


func test_scoring_config_valid() -> void:
	var c := _content()
	assert_true(c[1].is_valid(), str(c[1].errors))
	assert_eq(c[1].total_units, 20)


func test_canonical_equivalent_mixes_same_id() -> void:
	var c := _content()
	var a := RecipeCanonical.canonicalize({"vanilla": 2, "strawberry": 1, "lemon": 1}, [], c[0], c[1])
	var b := RecipeCanonical.canonicalize({"lemon": 4, "strawberry": 4, "vanilla": 8}, [], c[0], c[1])
	assert_true(a["ok"] and b["ok"])
	assert_eq(a["id"], b["id"])
	assert_eq(a["key"], b["key"])
	var total := 0
	for item in a["ingredients"]:
		total += item["units"]
	assert_eq(total, 20)


func test_canonical_order_independent_and_ice_changes_id() -> void:
	var c := _content()
	var a := RecipeCanonical.canonicalize({"vanilla": 10, "strawberry": 10}, [], c[0], c[1])
	var b := RecipeCanonical.canonicalize({"strawberry": 10, "vanilla": 10}, [], c[0], c[1])
	var ice := RecipeCanonical.canonicalize({"strawberry": 10, "vanilla": 10}, ["ice"], c[0], c[1])
	assert_eq(a["id"], b["id"])
	assert_true(a["id"] != ice["id"])


func test_canonical_drops_tiny_share_and_rejects_bad_input() -> void:
	var c := _content()
	var tiny := RecipeCanonical.canonicalize({"vanilla": 1000, "strawberry": 1}, [], c[0], c[1])
	assert_true(tiny["ok"])
	assert_eq(tiny["ingredients"].size(), 1)
	var too_many := RecipeCanonical.canonicalize({"vanilla": 1, "strawberry": 1, "lemon": 1, "apple": 1, "grape": 1}, [], c[0], c[1])
	assert_true(not too_many["ok"])
	assert_true(not RecipeCanonical.canonicalize({}, [], c[0], c[1])["ok"])
	assert_true(not RecipeCanonical.canonicalize({"nope": 1}, [], c[0], c[1])["ok"])
	assert_true(not RecipeCanonical.canonicalize({"vanilla": 1}, ["nope"], c[0], c[1])["ok"])


func test_scoring_range_and_secret() -> void:
	var c := _content()
	var good := RecipeCanonical.canonicalize({"apple": 10, "vanilla": 10}, [], c[0], c[1])
	var good_result := RecipeScoring.evaluate(good, c[0], c[1])
	assert_true(good_result["quality"] >= 0.0 and good_result["quality"] <= 100.0)
	assert_true(good_result["synergy"] > 50.0)
	assert_eq(good_result["secret_id"], "")
	var secret := RecipeCanonical.canonicalize({"apple": 5}, ["ice"], c[0], c[1])
	var secret_result := RecipeScoring.evaluate(secret, c[0], c[1])
	assert_eq(secret_result["secret_id"], "double_apple")
	assert_eq(secret_result["secret_name"], "Двойное яблочко 🍎🍎")


func test_scoring_bad_pair_lower_than_good_pair() -> void:
	var c := _content()
	var good := RecipeScoring.evaluate(RecipeCanonical.canonicalize({"apple": 1, "vanilla": 1}, [], c[0], c[1]), c[0], c[1])
	var bad := RecipeScoring.evaluate(RecipeCanonical.canonicalize({"apple": 1, "blueberry": 1}, [], c[0], c[1]), c[0], c[1])
	assert_true(good["quality"] > bad["quality"])


func _system(state: Node) -> RecipeSystem:
	var c := _content()
	return RecipeSystem.create_with(state, c[0], c[1])


func test_recipe_system_commit_reuse_and_stats() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var first := system.commit({"strawberry": 1, "vanilla": 1}, [])
	assert_true(first["ok"] and first["is_new"])
	var second := system.commit({"vanilla": 4, "strawberry": 4}, [])
	assert_true(second["ok"] and not second["is_new"])
	assert_eq(second["recipe_id"], first["recipe_id"])
	assert_eq(state.recipes.size(), 1)
	assert_eq(state.recipes[first["recipe_id"]]["times_used"], 0, "повторное сохранение не считается использованием")
	var other := system.commit({"strawberry": 1, "vanilla": 1}, ["ice"])
	assert_true(other["is_new"])
	assert_eq(state.recipes.size(), 2)
	assert_true(system.get_recipe(first["recipe_id"])["last_used_seq"] < system.get_recipe(other["recipe_id"])["created_seq"])
	state.free()


func test_recipe_system_names_and_rename() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var result := system.commit({"strawberry": 3, "vanilla": 1}, ["ice"])
	assert_eq(result["recipe"]["name"], "🍓 Клубника + 🍦 Ваниль ❄️")
	assert_eq(system.display_name(result["recipe"]), "🍓 Клубника + 🍦 Ваниль ❄️")
	assert_true(system.rename(result["recipe_id"], "  Моя лучшая  "))
	assert_eq(system.display_name(system.get_recipe(result["recipe_id"])), "Моя лучшая")
	assert_true(system.rename(result["recipe_id"], ""))
	assert_eq(system.display_name(system.get_recipe(result["recipe_id"])), "🍓 Клубника + 🍦 Ваниль ❄️")
	assert_true(not system.rename("missing", "x"))
	var solo := system.commit({"lemon": 1}, [])
	assert_eq(solo["recipe"]["name"], "Соло: 🍋 Лимон")
	state.free()


func test_recipe_system_secret_and_invalid() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var secret := system.commit({"apple": 4}, [])
	assert_true(secret["is_secret"])
	assert_eq(secret["recipe"]["name"], "Двойное яблочко 🍎🍎")
	assert_true(secret["secret_message"] != "")
	var again := system.commit({"apple": 4}, ["ice"])
	assert_true(again["is_new"] and again["is_secret"], "лёд — другой рецепт, но тоже секретный")
	var repeat := system.commit({"apple": 4}, ["ice"])
	assert_true(not repeat["is_secret"])
	assert_true(not system.commit({}, [])["ok"])
	state.free()


func test_recipe_system_persists_via_game_state() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	system.commit({"strawberry": 1, "vanilla": 1}, [])
	var snapshot: Dictionary = state.to_dict()
	var restored := GameStateScript.new()
	restored.apply_dict(snapshot)
	assert_eq(restored.recipes.size(), 1)
	assert_eq(restored.recipe_seq, state.recipe_seq)
	restored.reset_to_defaults()
	assert_eq(restored.recipes.size(), 0)
	state.free()
	restored.free()


func test_recipe_system_rejects_invalid_content() -> void:
	GameLog.muted = true
	var state := GameStateScript.new()
	var bad := IngredientCatalog.from_dicts({}, {}, {})
	var config := ScoringConfig.from_dicts({}, {}, bad)
	assert_true(RecipeSystem.create_with(state, bad, config) == null)
	GameLog.muted = false
	state.free()


func test_book_query_filter_and_sort() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	system.commit({"strawberry": 1, "vanilla": 1}, [])
	system.commit({"apple": 1, "vanilla": 1}, [])
	system.commit({"lemon": 1}, [])
	var sb := system.commit({"strawberry": 1, "vanilla": 1}, [])
	system.record_preparation(sb["recipe_id"], 70.0)
	var all := system.all_recipes()
	assert_eq(RecipeBookQuery.filter_sort(all, "", RecipeBookQuery.SORT_BEST).size(), 3)
	assert_eq(RecipeBookQuery.filter_sort(all, "vanilla", RecipeBookQuery.SORT_BEST).size(), 2)
	assert_eq(RecipeBookQuery.filter_sort(all, "cola", RecipeBookQuery.SORT_BEST).size(), 0)
	var best := RecipeBookQuery.filter_sort(all, "", RecipeBookQuery.SORT_BEST)
	assert_true(best[0]["best_score"] >= best[1]["best_score"] and best[1]["best_score"] >= best[2]["best_score"])
	var recent := RecipeBookQuery.filter_sort(all, "", RecipeBookQuery.SORT_RECENT)
	assert_eq(recent[0]["name"], "🍓 Клубника + 🍦 Ваниль")
	var by_name := RecipeBookQuery.filter_sort(all, "", RecipeBookQuery.SORT_NAME, system.sort_key)
	assert_true(system.sort_key(by_name[0]).naturalnocasecmp_to(system.sort_key(by_name[1])) <= 0)
	state.free()


func test_mix_selection_limits() -> void:
	var mix := MixSelection.new(4, 4)
	assert_eq(mix.set_amount("a", 99), 4, "один ингредиент — до 4 порций")
	assert_true(not mix.can_increase("a"))
	assert_eq(mix.set_amount("a", 1), 1)
	assert_eq(mix.set_amount("b", 99), 3, "остаток бюджета: 1 + 3")
	assert_eq(mix.total_portions(), 4)
	mix.set_amount("b", 2)
	mix.set_amount("a", 2)
	assert_eq(mix.total_portions(), 4, "2 + 2")
	mix.set_amount("a", 1)
	mix.set_amount("b", 1)
	assert_eq(mix.set_amount("c", 1), 1)
	assert_eq(mix.set_amount("d", 1), 1)
	assert_eq(mix.active_count(), 4)
	assert_true(mix.is_locked("e"))
	assert_eq(mix.set_amount("e", 1), 0)
	mix.set_amount("a", 0)
	assert_true(not mix.is_locked("e"))
	assert_eq(mix.set_amount("e", 3), 1, "бюджет: 3 порции уже заняты")
	mix.set_ice(true)
	assert_eq(mix.modifiers(), ["ice"])
	mix.clear()
	assert_true(mix.is_empty() and not mix.ice)


func test_mix_selection_load_recipe() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var result := system.commit({"strawberry": 3, "vanilla": 1}, ["ice"])
	var mix := MixSelection.new(4, 4)
	mix.load_recipe(result["recipe"])
	assert_eq(mix.amount("strawberry"), 3, "доли сокращаются до минимальных порций")
	assert_eq(mix.amount("vanilla"), 1)
	assert_true(mix.ice)
	var again := system.commit(mix.selection(), mix.modifiers())
	assert_eq(again["recipe_id"], result["recipe_id"])
	state.free()


func test_secret_recipe_cannot_be_renamed() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var secret := system.commit({"apple": 4}, [], "Моё имя")
	assert_eq(system.display_name(secret["recipe"]), "Двойное яблочко 🍎🍎", "имя секретного рецепта не задаётся")
	assert_true(not system.rename(secret["recipe_id"], "Другое"))
	assert_eq(system.display_name(system.get_recipe(secret["recipe_id"])), "Двойное яблочко 🍎🍎")
	state.free()


func test_record_preparation_counts_usage() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var result := system.commit({"strawberry": 1, "vanilla": 1}, [])
	var recipe: Dictionary = system.get_recipe(result["recipe_id"])
	assert_eq(recipe["times_used"], 0)
	assert_eq(recipe["best_execution"], RecipeSystem.NO_EXECUTION)
	assert_true(system.record_preparation(result["recipe_id"], 80.0))
	assert_true(system.record_preparation(result["recipe_id"], 60.0))
	recipe = system.get_recipe(result["recipe_id"])
	assert_eq(recipe["times_used"], 2)
	assert_eq(recipe["best_execution"], 80.0)
	assert_eq(recipe["last_execution"], 60.0)
	assert_eq(recipe["best_score"], result["recipe"]["best_score"], "качество рецепта не меняется от приготовления")
	assert_true(not system.record_preparation("missing", 10.0))
	state.free()


func test_perfect_recipe_exists_and_mint_removed() -> void:
	var c := _content()
	assert_true(not c[0].has_ingredient("mint"))
	var canonical := RecipeCanonical.canonicalize({"strawberry": 1, "vanilla": 1}, [], c[0], c[1])
	var result := RecipeScoring.evaluate(canonical, c[0], c[1])
	assert_eq(result["band_id"], "exceptional", "клубника + ваниль — идеальное сочетание")
	assert_eq(result["secret_id"], "")


func test_mix_selection_load_three_equal_portions() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var result := system.commit({"strawberry": 1, "vanilla": 1, "lemon": 1}, [])
	var mix := MixSelection.new(4, 4)
	mix.load_recipe(result["recipe"])
	assert_eq(mix.total_portions(), 3)
	assert_eq(mix.amount("strawberry"), 1)
	assert_eq(system.commit(mix.selection(), mix.modifiers())["recipe_id"], result["recipe_id"])
	state.free()


func test_secret_requires_full_portions() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var partial := system.commit({"apple": 2}, [])
	assert_true(not partial["is_secret"])
	assert_eq(partial["recipe"]["name"], "Соло: 🍎 Яблоко")
	assert_eq(partial["recipe"]["secret_id"], "")
	var full := system.commit({"apple": 4}, [])
	assert_true(full["is_new"] and full["is_secret"])
	assert_true(full["recipe_id"] != partial["recipe_id"])
	assert_true(system.rename(partial["recipe_id"], "Просто яблоко"), "обычное яблоко переименовать можно")
	var one := system.commit({"apple": 1}, [])
	assert_eq(one["recipe_id"], partial["recipe_id"], "1 и 2 порции яблока — один обычный рецепт")
	var mix := MixSelection.new(4, 4)
	mix.load_recipe(full["recipe"])
	assert_eq(mix.amount("apple"), 4, "секретный рецепт загружается со всеми порциями")
	mix.load_recipe(partial["recipe"])
	assert_true(mix.amount("apple") < 4)
	state.free()


func test_auto_name_extra_ingredients_as_emoji() -> void:
	var state := GameStateScript.new()
	var system := _system(state)
	var three := system.commit({"apple": 2, "blueberry": 1, "lemon": 1}, [])
	assert_eq(three["recipe"]["name"], "🍎 Яблоко + 🫐 Черника + 🍋")
	var four := system.commit({"apple": 1, "blueberry": 1, "lemon": 1, "grape": 1}, [])
	assert_eq(four["recipe"]["name"], "🍎 Яблоко + 🫐 Черника + 🍇🍋")
	var key := system.sort_key(three["recipe"])
	assert_true(key.begins_with("яблоко") and key.ends_with("черника"), "ключ сортировки без эмодзи: %s" % key)
	state.free()
