extends Node
## Корень главной сцены. На M0 только показывает placeholder-экран.
## Дальше отвечает за переключение high-level экранов (WorldRoot / UI).

@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	_status_label.text = "Foundation · v%s" % version
	GameLog.info("main", "Boot OK, version %s" % version)
	# GameState/SaveService — autoload; проверяем через путь, чтобы не падать при их отсутствии.
	for autoload_name in ["GameState", "SaveService"]:
		if get_node_or_null("/root/%s" % autoload_name) == null:
			GameLog.error("main", "Autoload не найден: %s" % autoload_name)
