class_name GuestCatalog
extends RefCounted
## Загрузка описаний гостей/друзей из data/guests/<id>.json.

const DIR := "res://data/guests"


## Возвращает словарь гостя или пустой словарь (ошибка уже залогирована).
static func load_guest(guest_id: String) -> Dictionary:
	var path := "%s/%s.json" % [DIR, guest_id]
	if not FileAccess.file_exists(path):
		GameLog.error("guests", "Нет файла гостя: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		GameLog.error("guests", "%s: не JSON-объект" % path)
		return {}
	for key in ["id", "name", "emoji"]:
		if str(parsed.get(key, "")).is_empty():
			GameLog.error("guests", "%s: не задано поле '%s'" % [path, key])
			return {}
	var faces := str(parsed.get("sprite_faces", "right"))
	if faces != "left" and faces != "right":
		GameLog.error("guests", "%s: sprite_faces должен быть 'left' или 'right'" % path)
		return {}
	if str(parsed["id"]) != guest_id:
		GameLog.error("guests", "%s: id '%s' не совпадает с именем файла" % [path, str(parsed["id"])])
		return {}
	return parsed
