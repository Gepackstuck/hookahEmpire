class_name IntroGuide
extends RefCounted
## M10: ворота интро и цель-подсказка в углу экрана (data/config/intro.json). Чистая логика без UI и без нод.
##
## Ворота: ручная забивка доступна с начала, быстрый режим (переключатели) — после quick_after_sessions гостей,
## мебель — после furniture_after_sessions. Цель: первый не выполненный и применимый шаг из STEPS.

const CONFIG_PATH := "res://data/config/intro.json"
const STEPS: Array[String] = ["serve_first", "place_couch", "serve_second", "serve_third", "recipes", "heat", "decorate", "strong", "second_seat", "new_guest"]
const BEN_RANGES: Array[String] = ["remind_seconds", "sit_seconds", "linger_seconds", "phone_seconds"]

var errors: Array[String] = []
var quick_after_sessions: int = 2
var furniture_after_sessions: int = 1
## Номер гостя, с приходом которого открываются тренды.
var trends_at_guest: int = 10
var ben: Dictionary = {}
var texts: Dictionary = {}
var recipes_needed: int = 3
var ending_notice: String = ""


static func load_default() -> IntroGuide:
	var guide := IntroGuide.new()
	if not FileAccess.file_exists(CONFIG_PATH):
		guide.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return guide
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		guide.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return guide
	guide._parse(parsed)
	return guide


static func from_dict(data: Dictionary) -> IntroGuide:
	var guide := IntroGuide.new()
	guide._parse(data)
	return guide


func is_valid() -> bool:
	return errors.is_empty()


func is_quick_unlocked(sessions: int) -> bool:
	return sessions >= quick_after_sessions


## Тренды открываются, когда приходит гость номер trends_at_guest (sessions — сколько визитов уже завершено).
func is_trends_unlocked(sessions: int) -> bool:
	return sessions + 1 >= trends_at_guest


func is_furniture_unlocked(sessions: int) -> bool:
	return sessions >= furniture_after_sessions


## Бэн приходит с диваном после нужного числа гостей (один раз: already — он уже приходил).
func ben_should_arrive(sessions: int, already: bool) -> bool:
	return not already and sessions >= int(ben.get("arrives_after_sessions", 1))


## Случайное число из диапазона [a, b] в настройках Бэна (например, "remind_seconds").
func ben_range(key: String, rng: RandomNumberGenerator) -> float:
	var range_value: Array = ben.get(key, [1.0, 1.0])
	return rng.randf_range(float(range_value[0]), float(range_value[1]))


func ben_lines(key: String) -> Array:
	return ben.get(key, [])


## Контекст: heat_warn (угли просят замены), sessions, ben_here, couch_placed, recipe_count, coals_replaced, furniture_unlocked, extra_furniture_placed,
## goal_done, second_seat_done, new_guest_met, quick_served (гостя обслужили в быстром режиме), progress_text.
## Возвращает {"id", "text", "done_count", "total"}: id "done" — все шаги пройдены.
func current_step(ctx: Dictionary) -> Dictionary:
	var done_count := 0
	var found := ""
	for step_id in STEPS:
		var state := _step_state(step_id, ctx)
		if state == "skip":
			continue
		if state == "done":
			done_count += 1
		elif found == "":
			found = step_id
	var total := done_count + (1 if found != "" else 0)
	if found == "":
		return {"id": "done", "text": str(texts.get("done", "")), "done_count": done_count, "total": done_count}
	var text := str(texts.get(found, ""))
	text = text.replace("{progress}", str(ctx.get("progress_text", "")))
	return {"id": found, "text": text, "done_count": done_count, "total": total + _remaining_after(found, ctx)}


## "done" / "todo" / "skip" (шаг сейчас неприменим: например, мебель ещё закрыта).
func _step_state(step_id: String, ctx: Dictionary) -> String:
	var sessions := int(ctx.get("sessions", 0))
	match step_id:
		"serve_first":
			return "done" if sessions >= 1 else "todo"
		"place_couch":
			if not bool(ctx.get("ben_here", false)):
				return "skip"
			return "done" if bool(ctx.get("couch_placed", false)) else "todo"
		"serve_second":
			return "done" if sessions >= 2 else "todo"
		"serve_third":
			# Условие висит, пока друга не обслужили именно в быстром режиме.
			return "done" if bool(ctx.get("quick_served", false)) else "todo"
		"recipes":
			return "done" if int(ctx.get("recipe_count", 0)) >= recipes_needed else "todo"
		"heat":
			# Шаг показывается только пока угли реально просят замены (heat_warn); иначе он не блокирует остальные цели.
			if bool(ctx.get("coals_replaced", false)):
				return "done"
			return "todo" if bool(ctx.get("heat_warn", false)) else "skip"
		"decorate":
			if not bool(ctx.get("furniture_unlocked", false)):
				return "skip"
			return "done" if int(ctx.get("extra_furniture_placed", 0)) >= 1 else "todo"
		"strong":
			return "done" if bool(ctx.get("goal_done", false)) else "todo"
		"second_seat":
			# Появляется после сильных рецептов: купить и поставить стол и стул для второго места.
			if not bool(ctx.get("goal_done", false)):
				return "skip"
			return "done" if bool(ctx.get("second_seat_done", false)) else "todo"
		"new_guest":
			if not bool(ctx.get("second_seat_done", false)):
				return "skip"
			return "done" if bool(ctx.get("new_guest_met", false)) else "todo"
	return "skip"


func _remaining_after(step_id: String, ctx: Dictionary) -> int:
	var count := 0
	var seen := false
	for other in STEPS:
		if other == step_id:
			seen = true
			continue
		if seen and _step_state(other, ctx) == "todo":
			count += 1
	return count


func _parse(data: Dictionary) -> void:
	var unlocks: Variant = data.get("unlocks", {})
	if not (unlocks is Dictionary):
		errors.append("intro: unlocks должен быть объектом")
	else:
		quick_after_sessions = int(unlocks.get("quick_after_sessions", quick_after_sessions))
		furniture_after_sessions = int(unlocks.get("furniture_after_sessions", furniture_after_sessions))
		trends_at_guest = int(unlocks.get("trends_at_guest", trends_at_guest))
		if trends_at_guest < 1:
			errors.append("intro: unlocks.trends_at_guest должен быть >= 1")
		if quick_after_sessions < 0 or furniture_after_sessions < 0:
			errors.append("intro: unlocks.* должны быть >= 0")
	var raw_ben: Variant = data.get("ben", {})
	if not (raw_ben is Dictionary):
		errors.append("intro: ben должен быть объектом")
	else:
		ben = (raw_ben as Dictionary).duplicate(true)
		for key in BEN_RANGES:
			var range_value: Variant = ben.get(key)
			if not (range_value is Array) or range_value.size() != 2 or float(range_value[0]) <= 0.0 or float(range_value[1]) < float(range_value[0]):
				errors.append("intro: ben.%s должен быть [мин, макс] > 0" % key)
		for key in ["remind_lines", "chill_lines"]:
			if not (ben.get(key) is Array) or (ben[key] as Array).is_empty():
				errors.append("intro: ben.%s должен быть непустым массивом строк" % key)
		var chance := float(ben.get("together_chance", 0.0))
		if chance < 0.0 or chance > 1.0:
			errors.append("intro: ben.together_chance должен быть 0..1")
	var raw_texts: Variant = data.get("guide", {})
	if not (raw_texts is Dictionary):
		errors.append("intro: guide должен быть объектом")
	else:
		texts = (raw_texts as Dictionary).duplicate(true)
		for step_id in STEPS + ["done"]:
			if str(texts.get(step_id, "")).is_empty():
				errors.append("intro: нет текста guide.%s" % step_id)
	recipes_needed = int(data.get("recipes_needed", recipes_needed))
	ending_notice = str(data.get("ending_notice", ""))
