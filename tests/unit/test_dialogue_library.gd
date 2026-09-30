extends TestCase

const DIALOGUES_DIR := "res://data/dialogues"


func _valid() -> Dictionary:
	return {
		"id": "d",
		"start": "a",
		"speakers": {"s": {"name": "С", "portrait": "🙂"}},
		"nodes": {
			"a": {"speaker": "s", "text": "Привет", "choices": [
				{"text": "Да", "next": "b"},
				{"text": "Нет", "next": "b", "effects": [{"type": "set_flag", "flag": "x"}]},
			]},
			"b": {"speaker": "s", "text": "Пока", "end": true},
		},
	}


func test_real_dialogues_load_without_errors() -> void:
	var library := DialogueLibrary.new()
	library.load_directory(DIALOGUES_DIR)
	assert_eq(library.errors, [], "ошибки: %s" % str(library.errors))
	assert_true(library.has_dialogue("friend_denis_intro"))


func test_valid_dialogue_passes() -> void:
	assert_eq(DialogueLibrary.validate(_valid()), [])


func test_rejects_dangling_next() -> void:
	var data := _valid()
	data["nodes"]["a"]["choices"][0]["next"] = "нет_такого"
	assert_true(not DialogueLibrary.validate(data).is_empty())


func test_rejects_node_with_two_forms() -> void:
	var data := _valid()
	data["nodes"]["b"]["next"] = "a" # end + next
	assert_true(not DialogueLibrary.validate(data).is_empty())


func test_rejects_undeclared_speaker() -> void:
	var data := _valid()
	data["nodes"]["b"]["speaker"] = "ghost"
	assert_true(not DialogueLibrary.validate(data).is_empty())


func test_rejects_unknown_effect_and_condition() -> void:
	var data := _valid()
	data["nodes"]["a"]["choices"][0]["effects"] = [{"type": "give_moon"}]
	assert_true(not DialogueLibrary.validate(data).is_empty())
	data = _valid()
	data["nodes"]["a"]["choices"][0]["conditions"] = [{"type": "weather_is", "value": "rain"}]
	assert_true(not DialogueLibrary.validate(data).is_empty())


func test_rejects_empty_choices_and_bad_start() -> void:
	var data := _valid()
	data["nodes"]["a"]["choices"] = []
	assert_true(not DialogueLibrary.validate(data).is_empty())
	data = _valid()
	data["start"] = "нет"
	assert_true(not DialogueLibrary.validate(data).is_empty())


func test_start_list_requires_unconditional_last_entry() -> void:
	var data := _valid()
	data["start"] = [{"node": "a", "conditions": [{"type": "flag_set", "flag": "x"}]}]
	assert_true(not DialogueLibrary.validate(data).is_empty())
