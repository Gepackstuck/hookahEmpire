extends Node
## Autoload SaveService: сериализация, версионирование и профили сохранений.
##
## M11: у игрока несколько профилей (кальянных). Файловое хранилище — ProfileStore;
## здесь клей: какой профиль активен в этом запуске, загрузка в GameState и автосохранение.
## В headless-режиме (тесты, проверки) профили и запись на диск отключены.

const SAVE_VERSION := 1
const PROFILES_DIR := "user://profiles"
const SETTINGS_PATH := "user://settings.cfg"

## Включается, когда выбран профиль: только тогда save_game() пишет на диск.
var autosave_enabled := false
var _store: ProfileStore = null
var _active_id := ""


## Нужны ли профили в этом запуске (в headless — нет).
func persistence_enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## Меню профилей нужно показать, пока профиль не выбран.
func needs_profile_choice() -> bool:
	return persistence_enabled() and _active_id == ""


func store() -> ProfileStore:
	if _store == null:
		_store = ProfileStore.open(PROFILES_DIR)
	return _store


func active_profile_id() -> String:
	return _active_id


## Делает профиль активным в этом запуске (дальше Main загрузит его в GameState).
func begin_profile(id: String) -> bool:
	if not store().set_active(id):
		return false
	_active_id = id
	autosave_enabled = true
	return true


## Выход из профиля (удалён или переключение через меню): автосохранение выключается.
func leave_profile() -> void:
	_active_id = ""
	autosave_enabled = false


## Собирает словарь сохранения из state (ожидается объект с to_dict(), т.е. GameState).
func build_save_data(state: Object) -> Dictionary:
	var data: Dictionary = state.to_dict()
	data["save_version"] = SAVE_VERSION
	return data


## Проверяет версию и применяет данные к state (объект с apply_dict()).
## Возвращает OK или код ошибки; при ошибке state не меняется.
func apply_save_data(state: Object, data: Dictionary) -> Error:
	if not data.has("save_version"):
		GameLog.error("save", "В данных сохранения нет поля save_version")
		return ERR_INVALID_DATA
	if int(data["save_version"]) != SAVE_VERSION:
		GameLog.error("save", "Неподдерживаемая версия сохранения: %s (ожидается %d)" % [str(data["save_version"]), SAVE_VERSION])
		return ERR_INVALID_DATA
	state.apply_dict(data)
	return OK


## Пишет GameState в активный профиль. ERR_UNAVAILABLE — автосохранение выключено.
func save_game() -> Error:
	if not autosave_enabled or _active_id == "":
		return ERR_UNAVAILABLE
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return ERR_UNAVAILABLE
	var err := store().save(_active_id, build_save_data(state))
	if err != OK:
		GameLog.error("save", "Не удалось сохранить профиль %s: %s" % [_active_id, error_string(err)])
	return err


## Загружает активный профиль в GameState; нет сохранения (новый/очищенный профиль) — состояние по умолчанию.
func load_game() -> Error:
	var state := get_node_or_null("/root/GameState")
	if state == null or _active_id == "":
		return ERR_UNAVAILABLE
	return load_into(state, _active_id)


func load_into(state: Object, id: String) -> Error:
	var data := store().load_data(id)
	if data.is_empty():
		state.reset_to_defaults()
		return OK
	state.reset_to_defaults()
	var err := apply_save_data(state, data)
	if err != OK:
		state.reset_to_defaults()
		GameLog.error("save", "Профиль %s повреждён или другой версии — начата новая игра" % id)
	return err


# --- Настройки (общие для всех профилей) ---

func load_setting(key: String, default_value: Variant) -> Variant:
	if not persistence_enabled():
		return default_value
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return default_value
	return config.get_value("main", key, default_value)


func save_setting(key: String, value: Variant) -> void:
	if not persistence_enabled():
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("main", key, value)
	config.save(SETTINGS_PATH)
