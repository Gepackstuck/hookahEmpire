extends TestCase

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _dialogue() -> Dictionary:
	return {
		"id": "d",
		"start": [
			{"node": "again", "conditions": [{"type": "flag_set", "flag": "met"}]},
			{"node": "hello"},
		],
		"speakers": {"s": {"name": "С", "portrait": "🙂"}},
		"nodes": {
			"hello": {"speaker": "s", "text": "Привет", "next": "ask", "effects": [{"type": "set_flag", "flag": "met"}]},
			"ask": {"speaker": "s", "text": "Выбери", "choices": [
				{"text": "Первый", "next": "one", "effects": [{"type": "set_flag", "flag": "pick", "value": "one"}]},
				{"text": "Секретный", "next": "one", "conditions": [{"type": "flag_equals", "flag": "secret", "value": true}]},
				{"text": "Второй", "next": "two"},
			]},
			"one": {"speaker": "s", "text": "Один", "end": true},
			"two": {"speaker": "s", "text": "Два", "end": true},
			"again": {"speaker": "s", "text": "Снова ты", "end": true},
		},
	}


func _record(runner: DialogueRunner) -> Dictionary:
	var events := {"nodes": [], "effects": [], "finished": 0}
	runner.node_entered.connect(func(node: Dictionary, _choices: Array) -> void: events["nodes"].append(node["id"]))
	runner.effect_requested.connect(func(effect: Dictionary) -> void: events["effects"].append(effect["flag"] if effect.has("flag") else effect["type"]))
	runner.finished.connect(func(_id: String) -> void: events["finished"] += 1)
	return events


func test_linear_then_branch_then_finish() -> void:
	var state := GameStateScript.new()
	var effects := StoryEffects.new(state)
	var runner := DialogueRunner.new()
	var events := _record(runner)
	runner.effect_requested.connect(effects.apply)
	assert_true(runner.start(_dialogue(), effects.check))
	assert_eq(runner.current_node()["id"], "hello")
	runner.advance()
	assert_eq(runner.current_node()["id"], "ask")
	runner.choose(0) # "Первый"
	assert_eq(runner.current_node()["id"], "one")
	assert_eq(state.get_flag("pick"), "one", "эффект выбора применён")
	assert_true(state.has_flag("met"), "эффект узла применён")
	runner.advance()
	assert_true(not runner.is_active)
	assert_eq(events["nodes"], ["hello", "ask", "one"])
	assert_eq(events["finished"], 1)
	state.free()


func test_choices_are_filtered_by_conditions() -> void:
	var state := GameStateScript.new()
	var effects := StoryEffects.new(state)
	var runner := DialogueRunner.new()
	runner.start(_dialogue(), effects.check)
	runner.advance()
	assert_eq(runner.available_choices().size(), 2, "секретный вариант скрыт")
	state.set_flag("secret", true)
	assert_eq(runner.available_choices().size(), 3, "секретный вариант открылся")
	runner.choose(1) # после фильтра индекс 1 — "Секретный"
	assert_eq(runner.current_node()["id"], "one")
	state.free()


func test_choose_second_visible_choice_leads_to_other_branch() -> void:
	var runner := DialogueRunner.new()
	runner.start(_dialogue(), func(_c: Dictionary) -> bool: return false)
	runner.advance()
	runner.choose(1) # при скрытом секретном индекс 1 — "Второй"
	assert_eq(runner.current_node()["id"], "two")


func test_conditional_start() -> void:
	var state := GameStateScript.new()
	var effects := StoryEffects.new(state)
	state.set_flag("met")
	var runner := DialogueRunner.new()
	runner.start(_dialogue(), effects.check)
	assert_eq(runner.current_node()["id"], "again")
	state.free()


func test_invalid_choice_index_is_ignored() -> void:
	var runner := DialogueRunner.new()
	# Все условия ложны: стартуем с "hello" (а не с условного "again").
	runner.start(_dialogue(), func(_c: Dictionary) -> bool: return false)
	runner.advance()
	runner.choose(99)
	runner.choose(-1)
	assert_eq(runner.current_node()["id"], "ask")
	assert_true(runner.is_active)


func test_denis_intro_end_to_end() -> void:
	var library := DialogueLibrary.new()
	library.load_directory("res://data/dialogues")
	var dialogue := library.get_dialogue("friend_denis_intro")
	var state := GameStateScript.new()
	var effects := StoryEffects.new(state)
	var runner := DialogueRunner.new()
	runner.effect_requested.connect(effects.apply)
	assert_true(runner.start(dialogue, effects.check))
	assert_eq(runner.current_node()["id"], "greet")
	while runner.is_active and runner.available_choices().is_empty():
		runner.advance()
	assert_eq(runner.current_node()["id"], "player_choice")
	runner.choose(1)
	while runner.is_active:
		runner.advance()
	assert_eq(state.get_flag("denis_intro_choice"), "explore")
	assert_eq(state.story_progress, "friend_01_intro_done")
	# повторный разговор идёт по ветке "repeat"
	runner.start(dialogue, effects.check)
	assert_eq(runner.current_node()["id"], "repeat")
	state.free()
