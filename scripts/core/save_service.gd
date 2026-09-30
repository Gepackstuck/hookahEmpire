extends Node
## Autoload SaveService: сериализация и версионирование сохранений.
##
## M0: только скелет. Построение/разбор данных чистые и тестируемые,
## реальный файловый I/O появится в M11 (save_game/load_game пока заглушки).

const SAVE_VERSION := 1
const SAVE_PATH := "user://save.json"


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


func save_game() -> Error:
	GameLog.warn("save", "save_game() не реализован (запланировано на M11)")
	return ERR_UNAVAILABLE


func load_game() -> Error:
	GameLog.warn("save", "load_game() не реализован (запланировано на M11)")
	return ERR_UNAVAILABLE
