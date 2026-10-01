class_name PreparationConfig
extends RefCounted
## Параметры быстрого приготовления (data/preparation/preparation.json): варианты выбора,
## веса подоценок и формулы оптимума. Ошибки валидации копятся в errors.

const CONFIG_PATH := "res://data/preparation/preparation.json"
const EXTRA_FEATURES: Array[String] = ["intensity", "heat_sensitivity"]

var errors: Array[String] = []
var penalty_per_level: float = 45.0
var ok_tolerance: float = 0.5
## Исполнение ниже этого значения считается слабым: кнопка подачи называется «И так сойдет».
var serve_weak_below: float = 60.0
## Порядок как в файле. Элемент: id, name, weight, base, weights, options [{id, name}], hint_low/high/ok.
var parameters: Array[Dictionary] = []
## Ручной режим (M5): вес подоценки состава и числа, по которым действия переводятся в уровни.
var manual_mix_weight: float = 0.15
var manual_portions: int = 4
var manual_fill_seconds: float = 2.5
var manual_light_seconds_per_level: float = 1.25
var manual_light_burn_seconds: float = 3.6
## Допустимое число отверстий: min даёт уровень «мало» (0), max — «много» (2).
var manual_holes_min: int = 4
var manual_holes_max: int = 10
var manual_max_coals: int = 3
## Идеальное расстояние угля от центра чаши (доля радиуса).
var manual_coal_ring: float = 0.5
## Ручной режим строже быстрого: допуск (доля ok_tolerance) и множитель штрафа за отклонение.
var manual_tolerance_factor: float = 0.6
var manual_penalty_factor: float = 1.4
## Индивидуальные множители допуска для параметров (у набивки и фольги зона уже).
var manual_tolerance_overrides: Dictionary = {}
## Сколько секунд удержания нужно, чтобы натянуть фольгу до конца.
var manual_foil_seconds: float = 3.0
## Скорость нагрева углей на горячей плитке (секунд «нагрева» в секунду).
var manual_heat_rate: float = 0.5
## Плитка: сколько секунд разогревается спираль и остывает после выключения.
var manual_coil_warmup_seconds: float = 2.5
var manual_coil_cooldown_seconds: float = 8.0
## Остывание углей на плитке без нагрева: секунд «нагрева» в секунду.
var manual_cool_rate: float = 0.12


## Допуск ручного режима для параметра (в уровнях).
func manual_tolerance(parameter_id: String) -> float:
	return ok_tolerance * float(manual_tolerance_overrides.get(parameter_id, manual_tolerance_factor))


static func load_default() -> PreparationConfig:
	return load_file(CONFIG_PATH)


static func load_file(path: String) -> PreparationConfig:
	var config := PreparationConfig.new()
	if not FileAccess.file_exists(path):
		config.errors.append("Файл не найден: %s" % path)
		return config
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		config.errors.append("%s: не JSON-объект" % path)
		return config
	config._parse(parsed)
	return config


static func from_dict(data: Dictionary) -> PreparationConfig:
	var config := PreparationConfig.new()
	config._parse(data)
	return config


func is_valid() -> bool:
	return errors.is_empty()


func parameter(parameter_id: String) -> Dictionary:
	for entry in parameters:
		if entry["id"] == parameter_id:
			return entry
	return {}


## Уровень варианта (его индекс) или -1, если такого варианта нет.
func option_level(parameter_id: String, option_id: String) -> int:
	var entry := parameter(parameter_id)
	if entry.is_empty():
		return -1
	var options: Array = entry["options"]
	for index in options.size():
		if options[index]["id"] == option_id:
			return index
	return -1


## Выбор по умолчанию — средний вариант каждого параметра.
func default_choices() -> Dictionary:
	var choices := {}
	for entry in parameters:
		var options: Array = entry["options"]
		choices[entry["id"]] = options[floori(options.size() / 2.0)]["id"]
	return choices


func _parse(data: Dictionary) -> void:
	penalty_per_level = float(data.get("penalty_per_level", penalty_per_level))
	ok_tolerance = float(data.get("ok_tolerance", ok_tolerance))
	serve_weak_below = float(data.get("serve_weak_below", serve_weak_below))
	if penalty_per_level <= 0.0:
		errors.append("preparation: penalty_per_level должен быть > 0")
	_parse_manual(data.get("manual", {}))
	var raw: Variant = data.get("parameters")
	if not (raw is Array) or raw.is_empty():
		errors.append("preparation: parameters должен быть непустым массивом")
		return
	var seen := {}
	var weight_sum := 0.0
	for index in raw.size():
		var entry: Variant = raw[index]
		var label := "параметр #%d" % index
		if not (entry is Dictionary):
			errors.append("%s: должен быть объектом" % label)
			continue
		var parameter_id := str(entry.get("id", ""))
		if parameter_id.is_empty() or seen.has(parameter_id):
			errors.append("%s: id пустой или повторяется" % label)
			continue
		seen[parameter_id] = true
		label = "параметр '%s'" % parameter_id
		var options := _parse_options(entry.get("options"), label)
		var formula := _parse_weights(entry.get("weights", {}), label)
		var weight := float(entry.get("weight", 0.0))
		if weight <= 0.0:
			errors.append("%s: weight должен быть > 0" % label)
		weight_sum += weight
		parameters.append({
			"id": parameter_id,
			"name": str(entry.get("name", parameter_id)),
			"weight": weight,
			"base": float(entry.get("base", 0.0)),
			"weights": formula,
			"options": options,
			"hint_low": str(entry.get("hint_low", "маловато")),
			"hint_high": str(entry.get("hint_high", "слишком много")),
			"hint_ok": str(entry.get("hint_ok", "в самый раз")),
		})
	if weight_sum <= 0.0:
		errors.append("preparation: сумма весов параметров должна быть > 0")


func _parse_manual(raw: Variant) -> void:
	if not (raw is Dictionary):
		errors.append("preparation: manual должен быть объектом")
		return
	manual_mix_weight = float(raw.get("mix_weight", manual_mix_weight))
	manual_portions = int(raw.get("portions", manual_portions))
	manual_fill_seconds = float(raw.get("fill_seconds", manual_fill_seconds))
	manual_light_seconds_per_level = float(raw.get("light_seconds_per_level", manual_light_seconds_per_level))
	manual_light_burn_seconds = float(raw.get("light_burn_seconds", manual_light_burn_seconds))
	manual_holes_min = int(raw.get("holes_min", manual_holes_min))
	manual_holes_max = int(raw.get("holes_max", manual_holes_max))
	manual_max_coals = int(raw.get("max_coals", manual_max_coals))
	manual_coal_ring = float(raw.get("coal_ring", manual_coal_ring))
	manual_tolerance_factor = float(raw.get("tolerance_factor", manual_tolerance_factor))
	manual_penalty_factor = float(raw.get("penalty_factor", manual_penalty_factor))
	var overrides: Variant = raw.get("tolerance_overrides", {})
	if overrides is Dictionary:
		manual_tolerance_overrides = overrides
	manual_foil_seconds = float(raw.get("foil_seconds", manual_foil_seconds))
	manual_heat_rate = float(raw.get("heat_rate", manual_heat_rate))
	manual_coil_warmup_seconds = float(raw.get("coil_warmup_seconds", manual_coil_warmup_seconds))
	manual_coil_cooldown_seconds = float(raw.get("coil_cooldown_seconds", manual_coil_cooldown_seconds))
	manual_cool_rate = float(raw.get("cool_rate", manual_cool_rate))
	if manual_mix_weight < 0.0 or manual_portions < 1 or manual_fill_seconds <= 0.0 or manual_light_seconds_per_level <= 0.0 \
			or manual_holes_min < 1 or manual_holes_max <= manual_holes_min or manual_max_coals < 1 \
			or manual_foil_seconds <= 0.0 or manual_heat_rate <= 0.0 or manual_tolerance_factor <= 0.0 or manual_penalty_factor <= 0.0 or manual_coil_warmup_seconds <= 0.0 or manual_coil_cooldown_seconds <= 0.0 or manual_cool_rate < 0.0:
		errors.append("preparation: manual содержит некорректные числа")


func _parse_options(raw: Variant, label: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (raw is Array) or raw.size() < 2:
		errors.append("%s: нужно минимум 2 варианта" % label)
		return result
	var seen := {}
	for option in raw:
		if not (option is Dictionary) or str(option.get("id", "")).is_empty() or str(option.get("name", "")).is_empty() or seen.has(str(option["id"])):
			errors.append("%s: некорректный или повторяющийся вариант %s" % [label, str(option)])
			continue
		seen[str(option["id"])] = true
		result.append({"id": str(option["id"]), "name": str(option["name"])})
	return result


func _parse_weights(raw: Variant, label: String) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		errors.append("%s: weights должен быть объектом" % label)
		return result
	for feature in raw:
		var known: bool = IngredientCatalog.DIMENSIONS.has(str(feature)) or EXTRA_FEATURES.has(str(feature))
		if not known or not (raw[feature] is float or raw[feature] is int):
			errors.append("%s: неизвестный признак или не число: %s" % [label, str(feature)])
			continue
		result[str(feature)] = float(raw[feature])
	return result
