class_name StoryBeats
extends RefCounted
## Расписание сюжетных событий (data/story/*.json). В M2 — приход друга.
##
## Бит: {"id", "requires_progress", "delay" (сек), "action": "spawn_friend", "guest",
##       "entry_position" [x,y] (точка появления у двери), "entry_cell" [x,y],
##       "stand_cell" [x,y], "dialogue", "sets_progress"?}

const ACTIONS := ["spawn_friend"]

var beats: Array[Dictionary] = []
var errors: Array[String] = []


static func load_file(path: String) -> StoryBeats:
	var result := StoryBeats.new()
	if not FileAccess.file_exists(path):
		result.errors.append("Файл не найден: %s" % path)
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		result.errors.append("%s: не JSON-объект" % path)
		return result
	result._parse(parsed)
	return result


static func from_dict(data: Dictionary) -> StoryBeats:
	var result := StoryBeats.new()
	result._parse(data)
	return result


func is_valid() -> bool:
	return errors.is_empty()


## Первый бит, для которого требуется именно этот story_progress. Пустой словарь, если нет.
func find_for_progress(progress: String) -> Dictionary:
	for beat in beats:
		if beat["requires_progress"] == progress:
			return beat
	return {}


func _parse(data: Dictionary) -> void:
	var raw: Variant = data.get("beats")
	if not (raw is Array):
		errors.append("beats должен быть массивом")
		return
	var seen := {}
	for index in raw.size():
		var entry: Variant = raw[index]
		var beat := _parse_beat(entry, index, seen)
		if not beat.is_empty():
			beats.append(beat)


func _parse_beat(entry: Variant, index: int, seen: Dictionary) -> Dictionary:
	var label := "бит #%d" % index
	if not (entry is Dictionary):
		errors.append("%s: должен быть объектом" % label)
		return {}
	var beat_id := str(entry.get("id", ""))
	if beat_id.is_empty() or seen.has(beat_id):
		errors.append("%s: id пуст или повторяется" % label)
		return {}
	seen[beat_id] = true
	label = "бит '%s'" % beat_id
	if str(entry.get("requires_progress", "")).is_empty():
		errors.append("%s: не задан requires_progress" % label)
		return {}
	if not ACTIONS.has(str(entry.get("action", ""))):
		errors.append("%s: action должен быть одним из %s" % [label, str(ACTIONS)])
		return {}
	var delay: Variant = entry.get("delay", 0.0)
	if not (delay is int or delay is float) or delay < 0:
		errors.append("%s: delay должен быть числом >= 0" % label)
		return {}
	for key in ["guest", "dialogue"]:
		if str(entry.get(key, "")).is_empty():
			errors.append("%s: не задано поле '%s'" % [label, key])
			return {}
	var entry_position: Variant = DataUtil.vec2(entry.get("entry_position"))
	var entry_cell: Variant = DataUtil.vec2(entry.get("entry_cell"))
	var stand_cell: Variant = DataUtil.vec2(entry.get("stand_cell"))
	if entry_position == null or entry_cell == null or stand_cell == null:
		errors.append("%s: entry_position, entry_cell и stand_cell должны быть [x, y]" % label)
		return {}
	return {
		"id": beat_id,
		"requires_progress": str(entry["requires_progress"]),
		"delay": float(delay),
		"action": str(entry["action"]),
		"guest": str(entry["guest"]),
		"entry_position": entry_position,
		"entry_cell": Vector2i(entry_cell),
		"stand_cell": Vector2i(stand_cell),
		"dialogue": str(entry["dialogue"]),
		"sets_progress": str(entry.get("sets_progress", "")),
	}
