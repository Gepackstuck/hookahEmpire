class_name GameLog
extends RefCounted
## Единая конвенция debug-логов проекта.
##
## Формат: "[LEVEL][tag] message".
## - tag — короткое имя системы в нижнем регистре (например "main", "save").
## - debug выводится только в debug-сборках, info/warn/error — всегда.
## - warn/error дополнительно попадают в панель отладчика через push_warning/push_error.

## Глушит warn/error (нужно тестам, которые намеренно провоцируют ошибки).
static var muted: bool = false

const LEVEL_DEBUG := "DEBUG"
const LEVEL_INFO := "INFO"
const LEVEL_WARN := "WARN"
const LEVEL_ERROR := "ERROR"


static func format_message(level: String, tag: String, message: String) -> String:
	return "[%s][%s] %s" % [level, tag, message]


static func debug(tag: String, message: String) -> void:
	if OS.is_debug_build():
		print(format_message(LEVEL_DEBUG, tag, message))


static func info(tag: String, message: String) -> void:
	print(format_message(LEVEL_INFO, tag, message))


static func warn(tag: String, message: String) -> void:
	if muted:
		return
	push_warning(format_message(LEVEL_WARN, tag, message))


static func error(tag: String, message: String) -> void:
	if muted:
		return
	push_error(format_message(LEVEL_ERROR, tag, message))
