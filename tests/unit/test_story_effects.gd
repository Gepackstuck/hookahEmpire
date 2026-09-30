extends TestCase

const GameStateScript := preload("res://scripts/core/game_state.gd")
const SaveServiceScript := preload("res://scripts/core/save_service.gd")


func test_apply_effects() -> void:
	var state := GameStateScript.new()
	var effects := StoryEffects.new(state)
	effects.apply({"type": "set_flag", "flag": "a"})
	effects.apply({"type": "set_flag", "flag": "b", "value": "x"})
	effects.apply({"type": "set_story_progress", "value": "step_2"})
	assert_eq(state.get_flag("a"), true)
	assert_eq(state.get_flag("b"), "x")
	assert_eq(state.story_progress, "step_2")
	state.free()


func test_check_conditions() -> void:
	var state := GameStateScript.new()
	var effects := StoryEffects.new(state)
	state.set_flag("a")
	state.set_flag("b", "x")
	assert_true(effects.check({"type": "flag_set", "flag": "a"}))
	assert_true(not effects.check({"type": "flag_set", "flag": "zzz"}))
	assert_true(effects.check({"type": "flag_equals", "flag": "b", "value": "x"}))
	assert_true(not effects.check({"type": "flag_equals", "flag": "b", "value": "y"}))
	assert_true(effects.check({"type": "story_progress_is", "value": GameStateScript.DEFAULT_STORY_PROGRESS}))
	state.free()


func test_validation() -> void:
	assert_eq(StoryEffects.validate_effect({"type": "set_flag", "flag": "a"}), "")
	assert_true(StoryEffects.validate_effect({"type": "set_flag"}) != "")
	assert_true(StoryEffects.validate_effect({"type": "nope"}) != "")
	assert_true(StoryEffects.validate_effect("строка") != "")
	assert_eq(StoryEffects.validate_condition({"type": "flag_equals", "flag": "a", "value": 1}), "")
	assert_true(StoryEffects.validate_condition({"type": "flag_equals", "flag": "a"}) != "")


func test_flags_survive_save_round_trip_and_reset() -> void:
	var service := SaveServiceScript.new()
	var source := GameStateScript.new()
	source.set_flag("denis_intro_choice", "sweet")
	var data := service.build_save_data(source)
	var target := GameStateScript.new()
	assert_eq(service.apply_save_data(target, data), OK)
	assert_eq(target.get_flag("denis_intro_choice"), "sweet")
	target.reset_to_defaults()
	assert_true(target.story_flags.is_empty())
	source.free()
	target.free()
	service.free()


func test_flag_signal_fires_only_on_change() -> void:
	var state := GameStateScript.new()
	var changes: Array[String] = []
	state.story_flag_changed.connect(func(flag: String, _value: Variant) -> void: changes.append(flag))
	state.set_flag("a")
	state.set_flag("a")
	state.set_flag("a", false)
	assert_eq(changes, ["a", "a"])
	state.free()
