class_name PlaytestStats
extends RefCounted
## Статистика для ручного тестирования: счётчики событий и итоги сессий за запуск игры.
## Только данные и форматирование; живые значения (жар, гость, режим) собирает Main и передаёт в панель.

var counters: Dictionary = {}
## guest_id -> {"count": int, "score_sum": float}
var guests: Dictionary = {}
## band_id -> количество
var bands: Dictionary = {}
var sessions: int = 0
var score_sum: float = 0.0
var payment_sum: int = 0
var last_session: Dictionary = {}
var started_msec: int = 0


func _init() -> void:
	started_msec = Time.get_ticks_msec()


func bump(key: String, amount: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + amount


func count(key: String) -> int:
	return int(counters.get(key, 0))


## result — словарь из session_finished: guest_id, recipe_id, final_score, band_id, payment.
func record_session(result: Dictionary) -> void:
	sessions += 1
	var score := float(result.get("final_score", 0.0))
	score_sum += score
	payment_sum += int(result.get("payment", 0))
	var guest_id := str(result.get("guest_id", "?"))
	var entry: Dictionary = guests.get(guest_id, {"count": 0, "score_sum": 0.0})
	entry["count"] = int(entry["count"]) + 1
	entry["score_sum"] = float(entry["score_sum"]) + score
	guests[guest_id] = entry
	var band := str(result.get("band_id", "?"))
	bands[band] = int(bands.get(band, 0)) + 1
	last_session = result.duplicate()


func average_score() -> float:
	return score_sum / float(sessions) if sessions > 0 else 0.0


func average_payment() -> float:
	return float(payment_sum) / float(sessions) if sessions > 0 else 0.0


func reset() -> void:
	counters.clear()
	guests.clear()
	bands.clear()
	sessions = 0
	score_sum = 0.0
	payment_sum = 0
	last_session = {}
	started_msec = Time.get_ticks_msec()


func uptime_text() -> String:
	var seconds := (Time.get_ticks_msec() - started_msec) / 1000
	return "%d:%02d" % [seconds / 60, seconds % 60]


## Строки итогов за запуск (показываются под «живыми» значениями).
func summary_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Запуск: %s" % uptime_text())
	lines.append("Гостей обслужено: %d, средний балл %.1f, оплата всего %d (в среднем %.1f)" % [sessions, average_score(), payment_sum, average_payment()])
	var parts: PackedStringArray = []
	for guest_id in guests:
		var entry: Dictionary = guests[guest_id]
		parts.append("%s: %d (ср. %.1f)" % [str(guest_id).trim_prefix("friend_"), int(entry["count"]), float(entry["score_sum"]) / maxf(float(entry["count"]), 1.0)])
	lines.append("По гостям: " + (", ".join(parts) if not parts.is_empty() else "—"))
	var band_parts: PackedStringArray = []
	for band in bands:
		band_parts.append("%s ×%d" % [band, int(bands[band])])
	lines.append("Оценки: " + (", ".join(band_parts) if not band_parts.is_empty() else "—"))
	if not last_session.is_empty():
		lines.append("Последний: %s, %s, балл %.1f, оплата %d" % [str(last_session.get("guest_id", "?")).trim_prefix("friend_"), str(last_session.get("recipe_id", "?")), float(last_session.get("final_score", 0.0)), int(last_session.get("payment", 0))])
	if sessions > 0:
		lines.append("На визит: жарких эпизодов %.2f, жалоб %.2f, просьб перезабить %.2f (цель: ~0.2 / ≤1.5 / ~0.3)" % [float(count("heat_hot") + count("heat_burned")) / float(sessions), float(count("complaints")) / float(sessions), float(count("redo_requested")) / float(sessions)])
	lines.append("Жар: холодно ×%d, жарко ×%d, сгорели ×%d, жалоб %d" % [count("heat_cold"), count("heat_hot"), count("heat_burned"), count("complaints")])
	lines.append("Углей заменено: %d (автопилотом %d)" % [count("coal_service"), count("coal_service_npc")])
	lines.append("Перезабивок: просили %d, сделано %d" % [count("redo_requested"), count("redo")])
	lines.append("Мундштуки доложены: %d раз (в простое %d)" % [count("mouthpiece_refill"), count("mouthpiece_refill_idle")])
	lines.append("Экономика: заработано %d, потрачено %d (в т.ч. перезабивки %d, угли %d, мундштуки %d), доход на визит %.1f" % [count("earned"), count("spent"), count("spent_redo"), count("spent_coals"), count("spent_pieces"), float(count("earned") - count("spent")) / float(maxi(sessions, 1))])
	lines.append("Тренды: смен %d, сильных рецептов найдено %d, цель выполнена %d раз" % [count("trend_changes"), count("strong_recipes"), count("goal_done")])
	lines.append("Кругов гостей (Ден → Макс) завершено: %d" % count("guest_cycles"))
	var idle_parts: PackedStringArray = []
	var idle_keys: Array = []
	for key in counters:
		if str(key).begins_with("idle_"):
			idle_keys.append(key)
	idle_keys.sort()
	for key in idle_keys:
		idle_parts.append("%s ×%d" % [str(key).trim_prefix("idle_"), int(counters[key])])
	lines.append("Простой: " + (", ".join(idle_parts) if not idle_parts.is_empty() else "—"))
	return lines
