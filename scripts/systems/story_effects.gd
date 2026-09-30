class_name StoryEffects
extends RefCounted
## Применение сюжетных эффектов и проверка условий поверх GameState.
## Диалоговый движок не знает, что значат эффекты: он лишь отдаёт их сюда.
##
## Эффекты:   {"type": "set_flag", "flag": id, "value": любое (по умолч. true)}
##            {"type": "set_story_progress", "value": node_id}
## Условия:   {"type": "flag_set", "flag": id}
##            {"type": "flag_equals", "flag": id, "value": любое}
##            {"type": "story_progress_is", "value": node_id}

var _state: Object


func _init(state: Object) -> void:
	_state = state


func apply(effect: Dictionary) -> void:
	match str(effect.get("type", "")):
		"set_flag":
			_state.set_flag(str(effect["flag"]), effect.get("value", true))
		"set_story_progress":
			_state.set_story_progress(str(effect["value"]))
		_:
			GameLog.error("story", "Неизвестный эффект: %s" % str(effect))


func check(condition: Dictionary) -> bool:
	match str(condition.get("type", "")):
		"flag_set":
			return _state.has_flag(str(condition["flag"]))
		"flag_equals":
			return _state.has_flag(str(condition["flag"])) and _state.get_flag(str(condition["flag"])) == condition["value"]
		"story_progress_is":
			return _state.story_progress == str(condition["value"])
		_:
			GameLog.error("story", "Неизвестное условие: %s" % str(condition))
			return false


## Пустая строка — эффект корректен, иначе текст ошибки.
static func validate_effect(effect: Variant) -> String:
	if not (effect is Dictionary):
		return "эффект должен быть объектом"
	match str(effect.get("type", "")):
		"set_flag":
			if str(effect.get("flag", "")).is_empty():
				return "set_flag: не задан flag"
		"set_story_progress":
			if str(effect.get("value", "")).is_empty():
				return "set_story_progress: не задан value"
		_:
			return "неизвестный тип эффекта '%s'" % str(effect.get("type", ""))
	return ""


static func validate_condition(condition: Variant) -> String:
	if not (condition is Dictionary):
		return "условие должно быть объектом"
	match str(condition.get("type", "")):
		"flag_set":
			if str(condition.get("flag", "")).is_empty():
				return "flag_set: не задан flag"
		"flag_equals":
			if str(condition.get("flag", "")).is_empty() or not condition.has("value"):
				return "flag_equals: нужны flag и value"
		"story_progress_is":
			if str(condition.get("value", "")).is_empty():
				return "story_progress_is: не задан value"
		_:
			return "неизвестный тип условия '%s'" % str(condition.get("type", ""))
	return ""
