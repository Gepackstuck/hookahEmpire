class_name DialogueLibrary
extends RefCounted
## Загрузка и валидация диалогов из data/dialogues/*.json.
##
## Формат диалога:
## {
##   "id": "...",
##   "start": "node_id"  |  [{"node": "id", "conditions": [...]}, ..., {"node": "id"}],
##   "speakers": {"speaker_id": {"name": "...", "portrait": "эмодзи"}},
##   "nodes": {"node_id": {"speaker", "text", "effects"?, и РОВНО ОДНО из:
##             "choices": [{"text", "next", "conditions"?, "effects"?}], "next": "id", "end": true}}
## }

var errors: Array[String] = []

var _dialogues: Dictionary = {}


func load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		errors.append("Не удалось открыть папку диалогов: %s" % path)
		return
	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [path, file_name]))
		if not (parsed is Dictionary):
			errors.append("%s: не JSON-объект" % file_name)
			continue
		var problems := validate(parsed)
		if not problems.is_empty():
			for problem in problems:
				errors.append("%s: %s" % [file_name, problem])
			continue
		var dialogue_id := str(parsed["id"])
		if _dialogues.has(dialogue_id):
			errors.append("%s: id диалога '%s' уже занят" % [file_name, dialogue_id])
			continue
		_dialogues[dialogue_id] = parsed


func has_dialogue(dialogue_id: String) -> bool:
	return _dialogues.has(dialogue_id)


func get_dialogue(dialogue_id: String) -> Dictionary:
	return _dialogues.get(dialogue_id, {})


static func validate(data: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if str(data.get("id", "")).is_empty():
		errs.append("не задан id")

	var speakers: Variant = data.get("speakers")
	if not (speakers is Dictionary) or speakers.is_empty():
		errs.append("speakers должен быть непустым объектом")
		speakers = {}
	else:
		for speaker_id in speakers:
			var speaker: Variant = speakers[speaker_id]
			if not (speaker is Dictionary) or str(speaker.get("name", "")).is_empty() or str(speaker.get("portrait", "")).is_empty():
				errs.append("speaker '%s': нужны name и portrait" % speaker_id)

	var nodes: Variant = data.get("nodes")
	if not (nodes is Dictionary) or nodes.is_empty():
		errs.append("nodes должен быть непустым объектом")
		return errs

	_validate_start(data.get("start"), nodes, errs)
	for node_id in nodes:
		_validate_node(str(node_id), nodes[node_id], nodes, speakers, errs)
	return errs


static func _validate_start(start: Variant, nodes: Dictionary, errs: Array[String]) -> void:
	if start is String:
		if not nodes.has(start):
			errs.append("start: нет узла '%s'" % start)
	elif start is Array and not start.is_empty():
		for index in start.size():
			var entry: Variant = start[index]
			if not (entry is Dictionary) or not nodes.has(str(entry.get("node", ""))):
				errs.append("start[%d]: нужен существующий node" % index)
				continue
			_check_list("start[%d].conditions" % index, entry.get("conditions"), true, errs)
			if index == start.size() - 1 and entry.has("conditions"):
				errs.append("start: последняя запись должна быть без conditions")
	else:
		errs.append("start должен быть id узла или непустым массивом")


static func _validate_node(node_id: String, node: Variant, nodes: Dictionary, speakers: Dictionary, errs: Array[String]) -> void:
	var label := "узел '%s'" % node_id
	if not (node is Dictionary):
		errs.append("%s: должен быть объектом" % label)
		return
	if not speakers.has(str(node.get("speaker", ""))):
		errs.append("%s: speaker '%s' не объявлен в speakers" % [label, str(node.get("speaker", ""))])
	if str(node.get("text", "")).is_empty():
		errs.append("%s: пустой text" % label)
	_check_list("%s.effects" % label, node.get("effects"), false, errs)

	var forms := 0
	if node.has("choices"):
		forms += 1
	if node.has("next"):
		forms += 1
	if node.get("end", false) == true:
		forms += 1
	if forms != 1:
		errs.append("%s: нужно ровно одно из choices / next / end" % label)
		return

	if node.has("next") and not nodes.has(str(node["next"])):
		errs.append("%s: next ведёт в несуществующий узел '%s'" % [label, str(node["next"])])
	if node.has("choices"):
		var choices: Variant = node["choices"]
		if not (choices is Array) or choices.is_empty():
			errs.append("%s: choices должен быть непустым массивом" % label)
			return
		for index in choices.size():
			var choice: Variant = choices[index]
			var choice_label := "%s.choices[%d]" % [label, index]
			if not (choice is Dictionary) or str(choice.get("text", "")).is_empty():
				errs.append("%s: нужен text" % choice_label)
				continue
			if not nodes.has(str(choice.get("next", ""))):
				errs.append("%s: next ведёт в несуществующий узел '%s'" % [choice_label, str(choice.get("next", ""))])
			_check_list("%s.conditions" % choice_label, choice.get("conditions"), true, errs)
			_check_list("%s.effects" % choice_label, choice.get("effects"), false, errs)


static func _check_list(label: String, value: Variant, are_conditions: bool, errs: Array[String]) -> void:
	if value == null:
		return
	if not (value is Array):
		errs.append("%s: должен быть массивом" % label)
		return
	for item in value:
		var problem := StoryEffects.validate_condition(item) if are_conditions else StoryEffects.validate_effect(item)
		if not problem.is_empty():
			errs.append("%s: %s" % [label, problem])
