class_name VisitScheduler
extends RefCounted
## M12: одновременные гости. Чистая логика без UI и нод (числа — в data/config/visits.json).
##
## Решает: можно ли впустить ещё одного гостя (цель выполнена, есть свободный слот, прошла пауза),
## и следит за терпением гостя, которому не нашлось места: он стоит wait_seconds и уходит рассерженным.

const CONFIG_PATH := "res://data/config/visits.json"

var errors: Array[String] = []
var max_guests := 3
var delay_range: Array = [12.0, 25.0]
var wait_seconds := 45.0
var angry_reputation := -3
var angry_line := "Мне тут даже присесть негде! Я пошёл."
## Рост потока: [{"sessions", "max_guests", "delay": [min, max]}] по возрастанию sessions.
var growth: Array = []
## Значения из конфига до роста (apply_progress считает от них).
var _base_max_guests := 3
var _base_delay: Array = [12.0, 25.0]
var level := 0

## guest_id -> сколько секунд осталось ждать места.
var _waiting: Dictionary = {}
## Сколько секунд осталось до прихода следующего гостя (-1 — таймер не запущен).
var _arrival_timer := -1.0


static func load_default() -> VisitScheduler:
	var parsed: Variant = null
	if FileAccess.file_exists(CONFIG_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var scheduler := from_dict(parsed if parsed is Dictionary else {})
	if not (parsed is Dictionary):
		scheduler.errors.append("%s: нет файла или не JSON-объект, взяты значения по умолчанию" % CONFIG_PATH)
	return scheduler


static func from_dict(data: Dictionary) -> VisitScheduler:
	var scheduler := VisitScheduler.new()
	scheduler.max_guests = int(data.get("max_guests", scheduler.max_guests))
	scheduler.wait_seconds = float(data.get("wait_seconds", scheduler.wait_seconds))
	scheduler.angry_reputation = int(data.get("angry_reputation", scheduler.angry_reputation))
	scheduler.angry_line = str(data.get("angry_line", scheduler.angry_line))
	var raw: Variant = data.get("second_guest_delay_seconds", scheduler.delay_range)
	if raw is Array and (raw as Array).size() == 2:
		scheduler.delay_range = [float(raw[0]), float(raw[1])]
	else:
		scheduler.errors.append("visits: second_guest_delay_seconds должен быть массивом из двух чисел")
	var raw_growth: Variant = data.get("growth", [])
	if raw_growth is Array:
		for tier in raw_growth:
			if tier is Dictionary and tier.has("sessions") and tier.has("max_guests") and tier.get("delay") is Array and (tier["delay"] as Array).size() == 2:
				scheduler.growth.append({"sessions": int(tier["sessions"]), "max_guests": int(tier["max_guests"]),
					"delay": [float(tier["delay"][0]), float(tier["delay"][1])]})
			else:
				scheduler.errors.append("visits: некорректная ступень growth")
	if scheduler.max_guests < 1:
		scheduler.errors.append("visits: max_guests должен быть >= 1")
		scheduler.max_guests = 1
	if scheduler.wait_seconds <= 0.0:
		scheduler.errors.append("visits: wait_seconds должен быть > 0")
		scheduler.wait_seconds = 45.0
	if float(scheduler.delay_range[0]) > float(scheduler.delay_range[1]):
		scheduler.errors.append("visits: в second_guest_delay_seconds первое число больше второго")
		scheduler.delay_range = [float(scheduler.delay_range[1]), float(scheduler.delay_range[0])]
	scheduler._base_max_guests = scheduler.max_guests
	scheduler._base_delay = scheduler.delay_range.duplicate()
	return scheduler


## Рост потока: по числу обслуженных гостей выбирает ступень и обновляет max_guests и паузу между приходами.
## Возвращает номер ступени (0 — рост ещё не начался).
func apply_progress(sessions_done: int) -> int:
	level = 0
	var guests := _base_max_guests
	var delay := _base_delay
	for i in growth.size():
		var tier: Dictionary = growth[i]
		if sessions_done >= int(tier["sessions"]):
			level = i + 1
			guests = int(tier["max_guests"])
			delay = tier["delay"]
	max_guests = guests
	delay_range = delay.duplicate()
	return level


## Можно ли впустить ещё одного гостя прямо сейчас (таймер прихода — отдельно, см. tick_arrival).
## guests_here — сколько гостей уже в гараже (включая ждущих места).
func can_admit(goal_done: bool, guests_here: int) -> bool:
	return goal_done and guests_here < max_guests


## Пока может прийти ещё гость (can_admit), заводим таймер до его прихода; иначе таймер сбрасывается.
## Возвращает true в тот тик, когда пора впускать гостя.
func tick_arrival(delta: float, admit_possible: bool, rng: RandomNumberGenerator) -> bool:
	if not admit_possible:
		_arrival_timer = -1.0
		return false
	if _arrival_timer < 0.0:
		_arrival_timer = rng.randf_range(float(delay_range[0]), float(delay_range[1]))
		return false
	_arrival_timer -= delta
	if _arrival_timer <= 0.0:
		_arrival_timer = -1.0
		return true
	return false


func arrival_timer_running() -> bool:
	return _arrival_timer >= 0.0


## Гость пришёл, но места (стола и стула) нет: запускаем отсчёт терпения.
func start_waiting(guest_id: String) -> void:
	_waiting[guest_id] = wait_seconds


## Место появилось (куплены и поставлены стол и стул) — гость больше не ждёт.
func seat_found(guest_id: String) -> void:
	_waiting.erase(guest_id)


func is_waiting(guest_id: String) -> bool:
	return _waiting.has(guest_id)


func waiting_ids() -> Array[String]:
	var result: Array[String] = []
	for id in _waiting:
		result.append(str(id))
	return result


func seconds_left(guest_id: String) -> float:
	return float(_waiting.get(guest_id, 0.0))


## Идёт время: возвращает гостей, у которых кончилось терпение (они уходят рассерженными).
func tick_waiting(delta: float) -> Array[String]:
	var gone: Array[String] = []
	for id in _waiting.keys():
		var left := float(_waiting[id]) - delta
		if left <= 0.0:
			gone.append(str(id))
			_waiting.erase(id)
		else:
			_waiting[id] = left
	return gone


## Гость ушёл (рассерженным или обслуженным): отсчёт для него больше не нужен.
func forget(guest_id: String) -> void:
	_waiting.erase(guest_id)
