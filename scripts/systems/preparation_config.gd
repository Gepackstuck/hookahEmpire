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
