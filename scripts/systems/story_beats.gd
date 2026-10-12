class_name StoryBeats
extends RefCounted
## Расписание сюжетных событий (data/story/*.json). В M2 — приход друга.
##
## Бит: {"id", "requires_progress", "delay" (сек), "action": "spawn_friend", "guest",
##       "entry_position" [x,y] (точка появления у двери), "entry_cell" [x,y],
##       "stand_cell" [x,y], "dialogue", "sets_progress"?,
##       "seat"? {"emoji", "facing": "left"|"right", "lift"? px} — поза друга, когда он дошёл (например, сел за стол)}

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


## Прогресс «гость обслужен» для гостя guest_id (friend_01_arrives -> friend_01_done); "" — у гостя нет бита.
func done_progress_for(guest_id: String) -> String:
	for beat in beats:
		if str(beat["guest"]) == guest_id and str(beat["sets_progress"]).ends_with("_arrives"):
			return str(beat["sets_progress"]).trim_suffix("_arrives") + "_done"
	return ""


## Прогресс «гость сейчас у нас» (приход или разговор окончен) для guest_id: сюда относится и "<...>_intro_done".
func is_in_progress_of(guest_id: String, progress: String) -> bool:
	var done := done_progress_for(guest_id)
	if done == "":
		return false
	var base := done.trim_suffix("_done")
	return progress == base + "_arrives" or progress == base + "_intro_done"


## Прогресс «гость в середине визита» (`<...>_arrives` / `<...>_intro_done`) после загрузки сохранения
## откатывается к условию прихода этого гостя (его бит запустится заново). Остальной прогресс не меняется.
func rewind_progress(progress: String) -> String:
	var arrives := progress
	if progress.ends_with("_intro_done"):
		arrives = progress.trim_suffix("_intro_done") + "_arrives"
	for beat in beats:
		if str(beat["sets_progress"]) == arrives:
			return str(beat["requires_progress"])
	return progress


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
	var seat := {}
	if entry.has("seat"):
		var raw_seat: Variant = entry["seat"]
		if not (raw_seat is Dictionary) or str(raw_seat.get("emoji", "")).is_empty() or not ["left", "right"].has(str(raw_seat.get("facing", ""))):
			errors.append("%s: seat должен быть {\"emoji\": ..., \"facing\": \"left\"|\"right\"}" % label)
			return {}
		seat = {"emoji": str(raw_seat["emoji"]), "facing": str(raw_seat["facing"]), "lift": float(raw_seat.get("lift", 0.0))}
	return {
		"seat": seat,
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
