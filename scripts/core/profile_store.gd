class_name ProfileStore
extends RefCounted
## M11: несколько профилей (кальянных) на диске. Чистая логика файлового хранилища без UI.
##
## Раскладка в каталоге `dir`: index.json (список профилей и активный) + <id>.json (сохранение профиля)
## и <id>.json.bak (предыдущая успешная запись). Запись атомарная: tmp -> rename.

const INDEX_FILE := "index.json"
const INDEX_VERSION := 1
const MAX_PROFILES := 8
const MAX_NAME_LENGTH := 24

var dir: String
var errors: Array[String] = []
var _active := ""
var _seq := 0
## Порядок профилей: [{"id": "p1", "number": 1}]
var _entries: Array[Dictionary] = []


static func open(directory: String) -> ProfileStore:
	var store := ProfileStore.new()
	store.dir = directory
	store._load_index()
	return store


## Приводит введённое название к допустимому: без управляющих символов, обрезано по длине.
static func clean_name(raw: String) -> String:
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += " " if code < 32 else raw[index]
	return result.strip_edges().left(MAX_NAME_LENGTH).strip_edges()


func active_id() -> String:
	return _active


func has_profile(id: String) -> bool:
	return _find(id) >= 0


func ids() -> Array[String]:
	var result: Array[String] = []
	for entry in _entries:
		result.append(str(entry["id"]))
	return result


func can_create() -> bool:
	return _entries.size() < MAX_PROFILES


## Создаёт пустой профиль (файла сохранения ещё нет). "" — достигнут лимит.
func create() -> String:
	if not can_create():
		return ""
	_seq += 1
	var id := "p%d" % _seq
	_entries.append({"id": id, "number": _seq})
	_write_index()
	return id


func set_active(id: String) -> bool:
	if id != "" and not has_profile(id):
		return false
	_active = id
	_write_index()
	return true


## Удаляет профиль вместе с файлами. Активный сбрасывается.
func delete(id: String) -> bool:
	var index := _find(id)
	if index < 0:
		return false
	_remove_files(id)
	_entries.remove_at(index)
	if _active == id:
		_active = ""
	_write_index()
	return true


## Очищает прогресс: профиль остаётся в списке, но без сохранения (и без названия бара).
func reset(id: String) -> bool:
	if not has_profile(id):
		return false
	_remove_files(id)
	return true


func has_save(id: String) -> bool:
	return FileAccess.file_exists(_path(id))


## Атомарно сохраняет данные профиля.
func save(id: String, data: Dictionary) -> Error:
	if not has_profile(id):
		return ERR_DOES_NOT_EXIST
	var path := _path(id)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		errors.append("Не удалось открыть %s: %d" % [tmp, FileAccess.get_open_error()])
		return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify(data))
	file.close()
	var access := DirAccess.open(dir)
	if access == null:
		return ERR_FILE_CANT_WRITE
	if access.file_exists(path.get_file()):
		if access.file_exists(path.get_file() + ".bak"):
			access.remove(path.get_file() + ".bak")
		access.rename(path.get_file(), path.get_file() + ".bak")
	return access.rename(tmp.get_file(), path.get_file())


## Читает сохранение; при повреждении — резервную копию. {} — нет сохранения/данных.
func load_data(id: String) -> Dictionary:
	if not has_profile(id):
		return {}
	for path in [_path(id), _path(id) + ".bak"]:
		var parsed := _read_json(path)
		if not parsed.is_empty():
			return parsed
	return {}


## Краткая информация о профиле для меню.
func summary(id: String, goal: ProgressionGoal = null) -> Dictionary:
	var index := _find(id)
	if index < 0:
		return {}
	var data := load_data(id)
	var flags: Dictionary = data.get("story_flags", {}) if data.get("story_flags", {}) is Dictionary else {}
	var recipes: Dictionary = data.get("recipes", {}) if data.get("recipes", {}) is Dictionary else {}
	var strong := goal.strong_count(recipes) if goal != null else 0
	var bar_name := str(data.get("bar_name", ""))
	var number := int(_entries[index]["number"])
	return {
		"id": id,
		"number": number,
		"has_save": not data.is_empty(),
		"bar_name": bar_name,
		"title": bar_name if bar_name != "" else "Профиль %d" % number,
		"money": int(data.get("money", 0)),
		"reputation": int(data.get("reputation", 0)),
		"recipes": recipes.size(),
		"strong": strong,
		"sessions": int(flags.get("sessions_done", 0)),
	}


func _path(id: String) -> String:
	return dir.path_join("%s.json" % id)


func _find(id: String) -> int:
	for index in _entries.size():
		if str(_entries[index]["id"]) == id:
			return index
	return -1


func _remove_files(id: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for file_name in ["%s.json" % id, "%s.json.bak" % id, "%s.json.tmp" % id]:
		if access.file_exists(file_name):
			access.remove(file_name)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return _restore_ints(json.data) if json.data is Dictionary else {}


## JSON хранит все числа как float; целые значения возвращаем в int (иначе типизированный код падает на int-полях).
static func _restore_ints(value: Variant) -> Variant:
	if value is float:
		var number: float = value
		if number == floorf(number) and absf(number) < 1.0e15:
			return int(number)
		return number
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_restore_ints(item))
		return items
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _restore_ints(value[key])
		return result
	return value


func _load_index() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var data := _read_json(dir.path_join(INDEX_FILE))
	if data.is_empty():
		return
	_seq = int(data.get("seq", 0))
	_active = str(data.get("active", ""))
	var raw: Variant = data.get("profiles", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary and str(entry.get("id", "")) != "":
				_entries.append({"id": str(entry["id"]), "number": int(entry.get("number", 0))})
				_seq = maxi(_seq, int(entry.get("number", 0)))
	if _find(_active) < 0:
		_active = ""


func _write_index() -> void:
	var file := FileAccess.open(dir.path_join(INDEX_FILE), FileAccess.WRITE)
	if file == null:
		errors.append("Не удалось записать индекс профилей")
		return
	file.store_string(JSON.stringify({"version": INDEX_VERSION, "seq": _seq, "active": _active, "profiles": _entries}))
	file.close()
