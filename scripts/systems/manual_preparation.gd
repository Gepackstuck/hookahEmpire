class_name ManualPreparation
extends RefCounted
## Состояние и логика ручного приготовления (M5), без UI: как действия игрока превращаются в уровни
## тех же пяти параметров, что и в быстром режиме, плюс подоценка состава (mix).
## Позиции углей и дырок — в нормализованных координатах чаши: центр (0, 0), край — длина 1.

## Минимальное отверстие друг от друга (доля радиуса чаши): рядом проколоть нельзя.
const HOLE_MIN_DISTANCE := 0.14
## Минимальная температура (секунды нагрева), с которой угли можно считать разожжёнными.
const MIN_HEAT_SECONDS := 0.2

const STEPS: Array[String] = ["mix", "pack", "foil", "holes", "light", "coals"]

var config: PreparationConfig
## ingredient_id -> число порций в чаше.
var portions: Dictionary = {}
## Кружки чаши: id ингредиента в каждом ("" — кружок пуст). Порция лежит именно в том кружке, куда её положили.
var slots: Array[String] = []
var fill: float = 0.0
var tension: float = 0.0
var holes: Array[Vector2] = []
## Угли на чаше.
var coals: Array[Vector2] = []
## Угли на плитке (шаг розжига): позиции в нормализованных координатах плитки.
var stove_coals: Array[Vector2] = []
## Горячие угли в ведёрке (уже сняты с плитки, ещё не на чаше).
var hot_coals: int = 0
## Температура углей в «секундах нагрева» (от неё считается уровень розжига); на плитке растёт и остывает.
var heat_seconds: float = 0.0
## Плитка включена и насколько разогрета спираль (0..1).
var stove_on: bool = false
var coil_temp: float = 0.0
## Первый снятый с плитки уголь фиксирует температуру: дальше она не меняется.
var temperature_locked: bool = false
## Температуры уже снятых с плитки разогретых углей (по одной записи на уголь): угли можно греть партиями, по одному.
var batch_temps: Array[float] = []


func _init(prep_config: PreparationConfig) -> void:
	config = prep_config
	slots.resize(config.manual_portions)


func reset() -> void:
	portions.clear()
	slots.clear()
	slots.resize(config.manual_portions)
	fill = 0.0
	tension = 0.0
	holes.clear()
	coals.clear()
	stove_coals.clear()
	hot_coals = 0
	heat_seconds = 0.0
	stove_on = false
	coil_temp = 0.0
	temperature_locked = false
	batch_temps.clear()


func reset_step(step: String) -> void:
	match step:
		"mix":
			portions.clear()
			slots.clear()
			slots.resize(config.manual_portions)
		"pack":
			fill = 0.0
		"foil":
			tension = 0.0
		"holes":
			holes.clear()
		"light":
			# Розжиг начинается заново: все угли (и на чаше тоже) возвращаются «холодными».
			stove_coals.clear()
			coals.clear()
			hot_coals = 0
			heat_seconds = 0.0
			stove_on = false
			coil_temp = 0.0
			temperature_locked = false
			batch_temps.clear()
		"coals":
			hot_coals += coals.size()
			coals.clear()


# --- Действия игрока -------------------------------------------------------------------------

func total_portions() -> int:
	var total := 0
	for ingredient_id in portions:
		total += int(portions[ingredient_id])
	return total


## Кладёт порцию в кружок slot (-1 — в первый свободный); false, если кружок занят или чаша полна.
func add_portion(ingredient_id: String, slot: int = -1) -> bool:
	if slot < 0:
		slot = slots.find("")
	if slot < 0 or slot >= slots.size() or slots[slot] != "":
		return false
	slots[slot] = ingredient_id
	portions[ingredient_id] = int(portions.get(ingredient_id, 0)) + 1
	return true


## Сделал ли игрок на шаге хоть что-то (без этого кнопка «Далее» не показывается).
func has_action(step: String) -> bool:
	match step:
		"mix":
			return total_portions() > 0
		"pack":
			return fill > 0.0
		"foil":
			return tension > 0.0
		"holes":
			return not holes.is_empty()
		"light":
			return not stove_coals.is_empty() or hot_coals > 0 or heat_seconds > 0.0
		"coals":
			return not coals.is_empty()
	return true


## Убирает порцию из кружка (исправить ошибку); false, если кружок пуст.
func remove_portion(slot: int) -> bool:
	if slot < 0 or slot >= slots.size() or slots[slot] == "":
		return false
	var ingredient_id := slots[slot]
	slots[slot] = ""
	portions[ingredient_id] = int(portions[ingredient_id]) - 1
	if int(portions[ingredient_id]) <= 0:
		portions.erase(ingredient_id)
	return true


## Набивка: удержание повышает уровень заполнения (0..1).
func pack(delta_seconds: float) -> void:
	fill = clampf(fill + delta_seconds / config.manual_fill_seconds, 0.0, 1.0)


## Натяжение фольги: удержание натягивает её (0..1).
func tighten(delta_seconds: float) -> void:
	tension = clampf(tension + delta_seconds / config.manual_foil_seconds, 0.0, 1.0)


func set_tension(value: float) -> void:
	tension = clampf(value, 0.0, 1.0)


func add_hole(position: Vector2) -> bool:
	if holes.size() >= config.manual_holes_max or position.length() > 1.0:
		return false
	for other in holes:
		if other.distance_to(position) < HOLE_MIN_DISTANCE:
			return false
	holes.append(position)
	return true


## Всего углей в игре: на плитке, в ведёрке и на чаше.
func total_coals() -> int:
	return stove_coals.size() + hot_coals + coals.size()


## Кладёт свежий уголь на плитку; false, если угли кончились или позиция вне плитки.
func add_stove_coal(position: Vector2) -> bool:
	if total_coals() >= config.manual_max_coals or position.length() > 1.0:
		return false
	stove_coals.append(position)
	return true


## Новый (холодный) уголь можно класть на плитку, пока она выключена и угли на ней ещё не грелись.
## Если плитка уже пуста (прошлую партию сняли в ведёрко), можно начать новую партию и греть уголь отдельно, по одному.
func can_place_cold_coal() -> bool:
	return not stove_on and (heat_seconds <= 0.0 or stove_coals.is_empty()) and total_coals() < config.manual_max_coals


## Холодный уголь из ведёрка кладут на пустую плитку после прошлой партии: температура начинается с нуля (прошлые запомнены).
func begin_batch_if_needed() -> void:
	if stove_coals.is_empty() and heat_seconds > 0.0:
		heat_seconds = 0.0
		temperature_locked = false
		coil_temp = 0.0


## Уголь попал в ведёрко горячих (его температуру запоминаем: итог розжига — среднее по всем углям).
func note_hot_coal_collected() -> void:
	if heat_seconds >= MIN_HEAT_SECONDS:
		batch_temps.append(heat_seconds)


## Вернуть горячий уголь из ведёрка на плитку можно, только пока он не разогрет.
func can_return_hot_coal() -> bool:
	return hot_coals > 0 and not temperature_locked and (batch_temps.is_empty() or batch_temps.back() < MIN_HEAT_SECONDS)


func return_hot_coal_to_stove(position: Vector2) -> void:
	if hot_coals > 0:
		hot_coals -= 1
	if not batch_temps.is_empty() and batch_temps.back() < MIN_HEAT_SECONDS:
		batch_temps.pop_back()
	stove_coals.append(position)


## Средняя температура углей в «секундах нагрева»: снятые в ведёрко разогретые (по партиям) и лежащие на плитке.
func average_heat() -> float:
	var total := 0.0
	var count := 0
	for temp in batch_temps:
		total += temp
		count += 1
	for _coal in stove_coals:
		total += heat_seconds
		count += 1
	return total / float(count) if count > 0 else heat_seconds


## Угли с плитки можно трогать, только когда она выключена.
func can_take_stove_coal() -> bool:
	return not stove_on and not stove_coals.is_empty()


## Снимает уголь с плитки щипцами в ведёрко горячих углей (только при выключенной плитке).
func collect_stove_coal(index: int) -> bool:
	if index < 0 or index >= stove_coals.size() or stove_on:
		return false
	stove_coals.remove_at(index)
	hot_coals += 1
	note_hot_coal_collected()
	lock_temperature()
	return true


## Кладёт уголь на чашу (берётся из ведёрка, если там есть).
func add_coal(position: Vector2) -> bool:
	if coals.size() >= config.manual_max_coals or position.length() > 1.0:
		return false
	if hot_coals > 0:
		hot_coals -= 1
	coals.append(position)
	return true


## Возвращает уголь с чаши в ведёрко.
func remove_coal(index: int) -> bool:
	if index < 0 or index >= coals.size():
		return false
	coals.remove_at(index)
	hot_coals += 1
	return true


## Розжиг: греет угли на плитке; без углей на плитке ничего не происходит.
func light(delta_seconds: float) -> void:
	if stove_coals.is_empty():
		return
	heat_seconds = minf(heat_seconds + delta_seconds, config.manual_light_burn_seconds * 1.5)


## Включить/выключить плитку; включить можно только когда на ней лежат угли.
func toggle_stove() -> bool:
	if not stove_on and stove_coals.is_empty():
		return false
	stove_on = not stove_on
	return true


## Вызывается, когда с плитки взят первый уголь.
## Пока угли толком не прогрелись, фиксировать нечего (иначе разогрев стал бы невозможен).
func lock_temperature() -> void:
	if heat_seconds >= MIN_HEAT_SECONDS:
		temperature_locked = true


## Плитка: спираль разогревается за несколько секунд, только потом греются угли; выключенная плитка остывает,
## а угли на ней медленно теряют температуру (после переноса в ведёрко температура больше не меняется).
func tick_stove(delta_seconds: float) -> void:
	if stove_on:
		coil_temp = minf(coil_temp + delta_seconds / config.manual_coil_warmup_seconds, 1.0)
	else:
		coil_temp = maxf(coil_temp - delta_seconds / config.manual_coil_cooldown_seconds, 0.0)
	if stove_coals.is_empty() or temperature_locked:
		return
	if stove_on and coil_temp >= 1.0:
		heat_seconds = minf(heat_seconds + delta_seconds * config.manual_heat_rate, config.manual_light_burn_seconds * 1.5)
	else:
		heat_seconds = maxf(heat_seconds - delta_seconds * config.manual_cool_rate, 0.0)


func is_burnt() -> bool:
	if heat_seconds > config.manual_light_burn_seconds:
		return true
	for temp in batch_temps:
		if temp > config.manual_light_burn_seconds:
			return true
	return false


# --- Перевод в уровни параметров (0..2; у углей и розжига возможны значения вне диапазона) --------

func packing_level() -> float:
	return clampf(fill, 0.0, 1.0) * 2.0


func foil_level() -> float:
	return clampf(tension, 0.0, 1.0) * 2.0


func holes_level() -> float:
	return clampf(float(holes.size() - config.manual_holes_min) / float(config.manual_holes_max - config.manual_holes_min) * 2.0, 0.0, 2.0)


func coals_level() -> float:
	return float(coals.size()) - 2.0


func lighting_level() -> float:
	return clampf(average_heat() / config.manual_light_seconds_per_level, 0.0, 3.0)


func level_of(parameter_id: String) -> float:
	match parameter_id:
		"packing":
			return packing_level()
		"foil":
			return foil_level()
		"holes":
			return holes_level()
		"coals":
			return coals_level()
		"lighting":
			return lighting_level()
	return 0.0


## Качество расстановки углей 0..1: лучше всего, когда они лежат на кольце вокруг центра и разведены по кругу.
func coal_placement_quality() -> float:
	if coals.is_empty():
		return 0.0
	var ring_error := 0.0
	for position in coals:
		ring_error += absf(position.length() - config.manual_coal_ring)
	ring_error /= float(coals.size())
	var spread := 1.0
	if coals.size() > 1:
		# Среднее расстояние между соседними углями относительно равномерной расстановки.
		var min_gap := INF
		for i in coals.size():
			for j in range(i + 1, coals.size()):
				min_gap = minf(min_gap, coals[i].distance_to(coals[j]))
		spread = clampf(min_gap / 0.35, 0.0, 1.0)
	return clampf((1.0 - ring_error * 1.6) * (0.6 + 0.4 * spread), 0.0, 1.0)


## Подоценка состава 0..100: насколько доли порций совпали с долями рецепта (1 - полное расстояние).
static func mix_score(recipe: Dictionary, chosen: Dictionary, total_units: int) -> float:
	var chosen_total := 0
	for ingredient_id in chosen:
		chosen_total += int(chosen[ingredient_id])
	if chosen_total <= 0:
		return 0.0
	var wanted := {}
	for item in recipe["ingredients"]:
		wanted[str(item["id"])] = float(item["units"]) / float(total_units)
	var ids := {}
	for ingredient_id in wanted:
		ids[ingredient_id] = true
	for ingredient_id in chosen:
		ids[str(ingredient_id)] = true
	var distance := 0.0
	for ingredient_id in ids:
		var share := float(chosen.get(ingredient_id, 0)) / float(chosen_total)
		distance += absf(share - float(wanted.get(ingredient_id, 0.0)))
	return clampf((1.0 - distance * 0.5) * 100.0, 0.0, 100.0)


## Всё, что нужно ExecutionScoring.evaluate_levels / PreparationService.preview_manual.
func levels() -> Dictionary:
	return {
		"packing": packing_level(),
		"foil": foil_level(),
		"holes": holes_level(),
		"coals": coals_level(),
		"lighting": lighting_level(),
	}


func _tolerance_factors() -> Dictionary:
	var factors := {}
	for entry in config.parameters:
		var parameter_id: String = entry["id"]
		factors[parameter_id] = float(config.manual_tolerance_overrides.get(parameter_id, config.manual_tolerance_factor))
	return factors


func extras(recipe: Dictionary, total_units: int) -> Dictionary:
	var mix := mix_score(recipe, portions, total_units)
	var quality := coal_placement_quality()
	var labels := {
		"packing": "%d%%" % int(round(fill * 100.0)),
		"foil": "натяжение %d%%" % int(round(tension * 100.0)),
		"holes": "%d шт." % holes.size(),
		"coals": "%d шт." % coals.size(),
		"lighting": "%.1f с%s" % [average_heat(), " (подгорело!)" if is_burnt() else ""],
		"mix": "%d порц." % total_portions(),
	}
	return {
		"multipliers": {"coals": 0.8 + 0.2 * quality},
		"tolerance_factors": _tolerance_factors(),
		"penalty_factor": config.manual_penalty_factor,
		"labels": labels,
		"mix_score": mix,
		"mix_hint": "в точности по рецепту" if mix >= 90.0 else "состав отличается от рецепта",
	}


## Пояснение к шагу по текущему результату: {"text", "ok"} — для обратной связи после шага.
func step_feedback(step: String, recipe_targets: Dictionary, prep: PreparationConfig) -> Dictionary:
	if step == "mix":
		return {"text": "Состав набран", "ok": true}
	var entry := prep.parameter(_parameter_of(step))
	if entry.is_empty():
		return {"text": "", "ok": true}
	var level := level_of(str(entry["id"]))
	var target: float = recipe_targets.get(str(entry["id"]), 0.0)
	var distance := absf(level - target)
	var tolerance := prep.manual_tolerance(str(entry["id"]))
	var hint: String = entry["hint_ok"]
	if distance > tolerance:
		hint = entry["hint_high"] if level > target else entry["hint_low"]
	if step == "light" and is_burnt():
		hint = "подгорело"
	return {"text": "%s: %s" % [entry["name"], hint], "ok": distance <= tolerance and not (step == "light" and is_burnt())}


## Ориентир для подсказки: целевое значение шага в единицах самого действия.
func hint_target(step: String, recipe_targets: Dictionary) -> float:
	var target: float = recipe_targets.get(_parameter_of(step), 0.0)
	match step:
		"pack", "foil":
			return target / 2.0 # доля шкалы 0..1
		"holes":
			return config.manual_holes_min + target / 2.0 * float(config.manual_holes_max - config.manual_holes_min)
		"coals":
			return target + 2.0
		"light":
			return target * config.manual_light_seconds_per_level
	return 0.0


static func _parameter_of(step: String) -> String:
	match step:
		"pack":
			return "packing"
		"foil":
			return "foil"
		"holes":
			return "holes"
		"coals":
			return "coals"
		"light":
			return "lighting"
	return ""
