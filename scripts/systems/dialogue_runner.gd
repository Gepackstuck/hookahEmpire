class_name DialogueRunner
extends RefCounted
## Проходит по диалогу узел за узлом. Ничего не знает про UI и сюжет:
## выдаёт сигналы (node_entered, effect_requested, finished), условия проверяет
## через переданный callable (condition: Dictionary) -> bool.

signal node_entered(node: Dictionary, choices: Array)
signal effect_requested(effect: Dictionary)
signal finished(dialogue_id: String)

var is_active: bool:
	get:
		return _active

var _dialogue: Dictionary = {}
var _checker: Callable = Callable()
var _current_id := ""
var _active := false


func start(dialogue: Dictionary, condition_checker: Callable = Callable()) -> bool:
	_dialogue = dialogue
	_checker = condition_checker
	var start_node := _resolve_start()
	if start_node.is_empty():
		GameLog.error("dialogue", "Не удалось определить стартовый узел диалога '%s'" % str(dialogue.get("id", "?")))
		return false
	_active = true
	_enter(start_node)
	return true


## Текущий узел (копия) с добавленным полем "id".
func current_node() -> Dictionary:
	if not _active:
		return {}
	var node: Dictionary = _dialogue["nodes"][_current_id].duplicate()
	node["id"] = _current_id
	return node


## Варианты ответа текущего узла, прошедшие условия.
func available_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _active:
		return result
	for choice in _dialogue["nodes"][_current_id].get("choices", []):
		if _conditions_pass(choice.get("conditions")):
			result.append(choice)
	return result


## Для узлов без выбора: переход к next или завершение.
func advance() -> void:
	if not _active:
		return
	var node: Dictionary = _dialogue["nodes"][_current_id]
	if node.has("choices"):
		if available_choices().is_empty():
			_finish() # все варианты отфильтрованы — не зависаем
		return
	if node.has("next"):
		_enter(str(node["next"]))
	else:
		_finish()


## Выбор варианта по индексу среди available_choices().
func choose(index: int) -> void:
	if not _active:
		return
	var choices := available_choices()
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	for effect in choice.get("effects", []):
		effect_requested.emit(effect)
	_enter(str(choice["next"]))


func _resolve_start() -> String:
	var start: Variant = _dialogue.get("start")
	if start is String:
		return start
	if start is Array:
		for entry in start:
			if _conditions_pass(entry.get("conditions")):
				return str(entry["node"])
	return ""


func _enter(node_id: String) -> void:
	var nodes: Dictionary = _dialogue["nodes"]
	if not nodes.has(node_id):
		GameLog.error("dialogue", "Нет узла '%s'" % node_id)
		_finish()
		return
	_current_id = node_id
	for effect in nodes[node_id].get("effects", []):
		effect_requested.emit(effect)
	node_entered.emit(current_node(), available_choices())


func _finish() -> void:
	_active = false
	finished.emit(str(_dialogue.get("id", "")))


func _conditions_pass(conditions: Variant) -> bool:
	if not (conditions is Array) or not _checker.is_valid():
		return true
	for condition in conditions:
		if not _checker.call(condition):
			return false
	return true
