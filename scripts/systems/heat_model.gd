class_name HeatModel
extends RefCounted
## M7: жар кальяна на столе гостя. Жар 0..100 растёт от затяжек и остывает со временем; пороги дают состояние
## cold / normal / hot / burned. Накапливает ограниченный штраф за плохое состояние и умеет «обслужить» угли.
## Чистая логика без UI; все числа — в data/config/heat.json.

const CONFIG_PATH := "res://data/config/heat.json"
const STATE_COLD := "cold"
const STATE_NORMAL := "normal"
const STATE_HOT := "hot"
const STATE_BURNED := "burned"
const LINE_KEYS: Array[String] = ["cold", "hot", "burned", "redo", "thanks"]

var errors: Array[String] = []
var start_heat: float = 55.0
var cool_per_second: float = 0.25
var puff_gain: float = 3.0
var service_heat: float = 55.0
var cold_below: float = 30.0
var hot_from: float = 75.0
var burned_from: float = 95.0
var pace_manual: float = 1.0
var pace_npc_min: float = 0.4
var pace_npc_max: float = 1.9
var pace_change_min: float = 20.0
var pace_change_max: float = 45.0
var penalty_per_second: Dictionary = {STATE_COLD: 0.12, STATE_HOT: 0.18, STATE_BURNED: 0.3}
var burn_once: float = 10.0
var max_heat_penalty: float = 30.0
var redo_cost: float = 5.0
var redo_ignored: float = 12.0
var redo_chance: float = 0.3
var redo_min_puff: int = 3
var redo_max_puff: int = 8
var redo_timeout: float = 45.0
var service_seconds: float = 5.0
var npc_notice_chance: float = 0.5
var complaint_cooldown: float = 14.0
var lines: Dictionary = {}

# --- Состояние сессии ---
var heat: float = 55.0
var pace: float = 1.0
var penalty: float = 0.0
var burn_applied := false
var state: String = STATE_NORMAL


static func load_default() -> HeatModel:
	var model := HeatModel.new()
	if not FileAccess.file_exists(CONFIG_PATH):
		model.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return model
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		model.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return model
	model._parse(parsed)
	model.begin()
	return model


static func from_dict(data: Dictionary) -> HeatModel:
	var model := HeatModel.new()
	model._parse(data)
	model.begin()
	return model


func is_valid() -> bool:
	return errors.is_empty()


## Новая сессия: свежие угли, штраф обнулён.
func begin(npc_pace: float = -1.0) -> void:
	heat = start_heat
	penalty = 0.0
	burn_applied = false
	pace = pace_manual if npc_pace < 0.0 else npc_pace
	state = state_for(heat)


func state_for(value: float) -> String:
	if value >= burned_from:
		return STATE_BURNED
	if value >= hot_from:
		return STATE_HOT
	if value < cold_below:
		return STATE_COLD
	return STATE_NORMAL


## Сколько секунд до следующей смены темпа в режиме NPC и новое значение темпа (суета / спокойствие).
func roll_npc_pace(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(pace_npc_min, pace_npc_max)


func roll_pace_interval(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(pace_change_min, pace_change_max)


## Течение времени: остывание и штраф за состояние. Возвращает новое состояние, если оно сменилось, иначе "".
func tick(delta: float) -> String:
	heat = clampf(heat - cool_per_second * delta, 0.0, 100.0)
	return _update_state(delta)


## Затяжка (гостя или игрока): жар растёт, темп (pace) усиливает рост. Возвращает новое состояние, если сменилось.
func puff() -> String:
	heat = clampf(heat + puff_gain * pace, 0.0, 100.0)
	return _update_state(0.0)


func _update_state(delta: float) -> String:
	var new_state := state_for(heat)
	if delta > 0.0:
		add_penalty(float(penalty_per_second.get(new_state, 0.0)) * delta)
	var changed := ""
	if new_state != state:
		state = new_state
		changed = new_state
		if new_state == STATE_BURNED and not burn_applied:
			burn_applied = true
			add_penalty(burn_once)
	return changed


func add_penalty(amount: float) -> void:
	penalty = minf(penalty + maxf(amount, 0.0), max_heat_penalty)


## Замена углей: жар возвращается к service_heat, состояние пересчитывается (штраф остаётся).
func service() -> void:
	heat = service_heat
	state = state_for(heat)
	burn_applied = false


func needs_service() -> bool:
	return state != STATE_NORMAL


## Штраф для SessionScoring (округлённый).
func heat_penalty() -> float:
	return snappedf(penalty, 0.1)


func random_line(key: String, rng: RandomNumberGenerator) -> String:
	var options: Array = lines.get(key, [])
	if options.is_empty():
		return ""
	return str(options[rng.randi() % options.size()])


func _parse(data: Dictionary) -> void:
	var heat_cfg: Variant = data.get("heat")
	if heat_cfg is Dictionary:
		start_heat = _number(heat_cfg, "start", start_heat, 0.0, 100.0, "heat.start")
		cool_per_second = _number(heat_cfg, "cool_per_second", cool_per_second, 0.0, 100.0, "heat.cool_per_second")
		puff_gain = _number(heat_cfg, "puff_gain", puff_gain, 0.0, 100.0, "heat.puff_gain")
		service_heat = _number(heat_cfg, "service_heat", service_heat, 0.0, 100.0, "heat.service_heat")
	else:
		errors.append("heat: нет секции heat")
	var thresholds: Variant = data.get("thresholds")
	if thresholds is Dictionary:
		cold_below = _number(thresholds, "cold_below", cold_below, 0.0, 100.0, "thresholds.cold_below")
		hot_from = _number(thresholds, "hot_from", hot_from, 0.0, 100.0, "thresholds.hot_from")
		burned_from = _number(thresholds, "burned_from", burned_from, 0.0, 100.0, "thresholds.burned_from")
		if not (cold_below < hot_from and hot_from < burned_from):
			errors.append("heat: пороги должны идти по возрастанию cold_below < hot_from < burned_from")
	else:
		errors.append("heat: нет секции thresholds")
	var pace_cfg: Variant = data.get("pace")
	if pace_cfg is Dictionary:
		pace_manual = _number(pace_cfg, "manual", pace_manual, 0.0, 10.0, "pace.manual")
		pace_npc_min = _number(pace_cfg, "npc_min", pace_npc_min, 0.0, 10.0, "pace.npc_min")
		pace_npc_max = _number(pace_cfg, "npc_max", pace_npc_max, 0.0, 10.0, "pace.npc_max")
		pace_change_min = _number(pace_cfg, "npc_change_min_seconds", pace_change_min, 1.0, 600.0, "pace.npc_change_min_seconds")
		pace_change_max = _number(pace_cfg, "npc_change_max_seconds", pace_change_max, 1.0, 600.0, "pace.npc_change_max_seconds")
		if pace_npc_min > pace_npc_max or pace_change_min > pace_change_max:
			errors.append("heat: pace: min не может быть больше max")
	else:
		errors.append("heat: нет секции pace")
	var penalties: Variant = data.get("penalty")
	if penalties is Dictionary:
		penalty_per_second = {
			STATE_COLD: _number(penalties, "cold_per_second", 0.12, 0.0, 100.0, "penalty.cold_per_second"),
			STATE_HOT: _number(penalties, "hot_per_second", 0.18, 0.0, 100.0, "penalty.hot_per_second"),
			STATE_BURNED: _number(penalties, "burned_per_second", 0.3, 0.0, 100.0, "penalty.burned_per_second"),
		}
		burn_once = _number(penalties, "burn_once", burn_once, 0.0, 100.0, "penalty.burn_once")
		max_heat_penalty = _number(penalties, "max_heat", max_heat_penalty, 0.0, 100.0, "penalty.max_heat")
		redo_cost = _number(penalties, "redo_cost", redo_cost, 0.0, 100.0, "penalty.redo_cost")
		redo_ignored = _number(penalties, "redo_ignored", redo_ignored, 0.0, 100.0, "penalty.redo_ignored")
	else:
		errors.append("heat: нет секции penalty")
	var redo: Variant = data.get("redo")
	if redo is Dictionary:
		redo_chance = _number(redo, "chance", redo_chance, 0.0, 1.0, "redo.chance")
		redo_min_puff = int(_number(redo, "min_puff", float(redo_min_puff), 1.0, 100.0, "redo.min_puff"))
		redo_max_puff = int(_number(redo, "max_puff", float(redo_max_puff), 1.0, 100.0, "redo.max_puff"))
		redo_timeout = _number(redo, "timeout_seconds", redo_timeout, 1.0, 600.0, "redo.timeout_seconds")
		if redo_min_puff > redo_max_puff:
			errors.append("heat: redo.min_puff не может быть больше max_puff")
	else:
		errors.append("heat: нет секции redo")
	var service_cfg: Variant = data.get("service")
	if service_cfg is Dictionary:
		service_seconds = _number(service_cfg, "seconds", service_seconds, 0.1, 60.0, "service.seconds")
		npc_notice_chance = _number(service_cfg, "npc_notice_chance", npc_notice_chance, 0.0, 1.0, "service.npc_notice_chance")
	else:
		errors.append("heat: нет секции service")
	complaint_cooldown = _number(data, "complaint_cooldown_seconds", complaint_cooldown, 1.0, 600.0, "complaint_cooldown_seconds")
	var raw_lines: Variant = data.get("lines")
	if raw_lines is Dictionary:
		for key in LINE_KEYS:
			var options: Variant = raw_lines.get(key)
			if not (options is Array) or options.is_empty():
				errors.append("heat: lines.%s должен быть непустым массивом строк" % key)
				continue
			lines[key] = options
	else:
		errors.append("heat: нет секции lines")


func _number(source: Dictionary, key: String, fallback: float, low: float, high: float, label: String) -> float:
	var value: Variant = source.get(key)
	if not (value is float or value is int):
		errors.append("heat: %s должен быть числом" % label)
		return fallback
	if float(value) < low or float(value) > high:
		errors.append("heat: %s вне диапазона %s..%s" % [label, str(low), str(high)])
		return fallback
	return float(value)
