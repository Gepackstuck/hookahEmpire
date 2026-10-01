class_name SessionScoring
extends RefCounted
## Оценка гостевой сессии (M6, docs/GDD.md §7.3): GuestFit, TrendFit, ContextScore, FinalScore,
## полоса удовлетворения, оплата и репутационный эффект. Чистая логика без UI; все числа — в
## data/config/session_scoring.json.
##
##   ContextScore = w_q * RecipeQuality + w_f * GuestFit + w_t * TrendFit + w_e * ExecutionScore
##   FinalScore   = clamp(ContextScore - HeatPenalty - ServicePenalty, 0, 100)

const CONFIG_PATH := "res://data/config/session_scoring.json"
const COMPONENTS: Array[String] = ["recipe_quality", "guest_fit", "trend_fit", "execution"]

var errors: Array[String] = []
var weights: Dictionary = {"recipe_quality": 0.45, "guest_fit": 0.25, "trend_fit": 0.15, "execution": 0.15}
var fit_gain: float = 1.0
var dislike_penalty: float = 60.0
var no_preference_fit: float = 50.0
var trend_current: String = "neutral"
var trend_neutral_fit: float = 50.0
var trend_scale: float = 50.0
## id -> {"name", "dimensions": {dim: -1..1}}.
var trends: Dictionary = {}
var likes_min: float = 55.0
## По убыванию min: {"min", "id", "emoji", "name", "reputation"}.
var bands: Array[Dictionary] = []
var pay_max: float = 600.0
var pay_min: float = 0.0
var pay_exponent: float = 1.5
var pay_round_to: int = 5


static func load_default() -> SessionScoring:
	var scoring := SessionScoring.new()
	if not FileAccess.file_exists(CONFIG_PATH):
		scoring.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return scoring
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		scoring.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return scoring
	scoring._parse(parsed)
	return scoring


static func from_dict(data: Dictionary) -> SessionScoring:
	var scoring := SessionScoring.new()
	scoring._parse(data)
	return scoring


func is_valid() -> bool:
	return errors.is_empty()


## GuestFit 0..100: насколько вкусовой профиль рецепта (значения 0..1) попадает в предпочтения гостя.
## taste: {"preferences": {dim: вес}, "dislikes": {dim: вес}} (dislikes необязательны).
func guest_fit(profile: Dictionary, taste: Dictionary) -> float:
	var preferences: Dictionary = taste.get("preferences", {})
	var total := 0.0
	var weighted := 0.0
	for dimension in preferences:
		weighted += float(preferences[dimension]) * float(profile.get(dimension, 0.0))
		total += float(preferences[dimension])
	var fit := no_preference_fit
	if total > 0.0:
		fit = weighted / total * 100.0 * fit_gain
	var dislikes: Dictionary = taste.get("dislikes", {})
	for dimension in dislikes:
		fit -= float(dislikes[dimension]) * float(profile.get(dimension, 0.0)) * dislike_penalty
	return clampf(fit, 0.0, 100.0)


## TrendFit 0..100 для тренда (по умолчанию — текущий). Без тренда/нейтральный — neutral_fit.
func trend_fit(profile: Dictionary, trend_id: String = "") -> float:
	var id := trend_current if trend_id.is_empty() else trend_id
	var trend: Dictionary = trends.get(id, {})
	var dimensions: Dictionary = trend.get("dimensions", {})
	var total := 0.0
	var weighted := 0.0
	for dimension in dimensions:
		weighted += float(dimensions[dimension]) * float(profile.get(dimension, 0.0))
		total += absf(float(dimensions[dimension]))
	if total <= 0.0:
		return trend_neutral_fit
	return clampf(trend_neutral_fit + trend_scale * clampf(weighted / total, -1.0, 1.0), 0.0, 100.0)


func trend_name(trend_id: String = "") -> String:
	var id := trend_current if trend_id.is_empty() else trend_id
	return str(trends.get(id, {}).get("name", ""))


## ContextScore из готовых компонентов (0..100 каждая).
func context_score(components: Dictionary) -> float:
	var weight_sum := 0.0
	var total := 0.0
	for key in COMPONENTS:
		weight_sum += float(weights[key])
		total += float(weights[key]) * float(components.get(key, 0.0))
	return total / weight_sum if weight_sum > 0.0 else 0.0


## FinalScore = clamp(ContextScore - штрафы, 0, 100), округление до 0.1.
func final_score(context: float, heat_penalty: float = 0.0, service_penalty: float = 0.0) -> float:
	return snappedf(clampf(context - heat_penalty - service_penalty, 0.0, 100.0), 0.1)


## Полоса удовлетворения для итоговой оценки.
func band_for(score: float) -> Dictionary:
	for band in bands:
		if score >= float(band["min"]):
			return band
	return bands[bands.size() - 1]


## Оплата по итоговой оценке: pay_min + (pay_max - pay_min) * (score/100)^exponent, округление до round_to.
func payment_for(score: float) -> int:
	var ratio := pow(clampf(score, 0.0, 100.0) / 100.0, pay_exponent)
	var raw := pay_min + (pay_max - pay_min) * ratio
	var step := float(maxi(pay_round_to, 1))
	return int(round(raw / step) * step)


## taste — вкус гостя (см. guest_fit), recipe — запись рецепта, execution_score — исполнение 0..100,
## extras: {"heat_penalty", "service_penalty", "trend"} (необязательно).
func evaluate(taste: Dictionary, recipe: Dictionary, execution_score: float, catalog: IngredientCatalog, scoring: ScoringConfig, extras: Dictionary = {}) -> Dictionary:
	var shape := {"ingredients": recipe["ingredients"], "modifiers": recipe["modifiers"]}
	var profile := RecipeScoring.taste_profile(shape, catalog, scoring)
	var trend_id := str(extras.get("trend", ""))
	var components := {
		"recipe_quality": float(recipe["best_score"]),
		"guest_fit": guest_fit(profile, taste),
		"trend_fit": trend_fit(profile, trend_id),
		"execution": execution_score,
	}
	var used_trend := trend_current if trend_id.is_empty() else trend_id
	return build_result(components, float(extras.get("heat_penalty", 0.0)), float(extras.get("service_penalty", 0.0)), profile, trend_name(used_trend), used_trend)


## Пересчёт готового итога со штрафами (жар, redo): компоненты берутся из итога, поля гостя/рецепта сохраняются.
func rescore(verdict: Dictionary, heat_penalty: float, service_penalty: float = 0.0) -> Dictionary:
	var components := {}
	for key in COMPONENTS:
		components[key] = float(verdict.get(key, 0.0))
	var result := build_result(components, heat_penalty, service_penalty, verdict.get("profile", {}), str(verdict.get("trend_name", "")), str(verdict.get("trend_id", "")))
	for key in ["guest_id", "recipe_id", "phrase"]:
		if verdict.has(key):
			result[key] = verdict[key]
	return result


## Собирает итог из компонентов (отдельно от evaluate — для детерминированных тестов).
func build_result(components: Dictionary, heat_penalty: float = 0.0, service_penalty: float = 0.0, profile: Dictionary = {}, trend_label: String = "", trend_key: String = "") -> Dictionary:
	var context := context_score(components)
	var final := final_score(context, heat_penalty, service_penalty)
	var band := band_for(final)
	return {
		"recipe_quality": float(components["recipe_quality"]),
		"guest_fit": float(components["guest_fit"]),
		"trend_fit": float(components["trend_fit"]),
		"trend_name": trend_label,
		"trend_id": trend_key,
		"execution": float(components["execution"]),
		"heat_penalty": heat_penalty,
		"service_penalty": service_penalty,
		"context_score": snappedf(context, 0.1),
		"final_score": final,
		"band_id": str(band["id"]),
		"band_name": str(band["name"]),
		"profile": profile,
		"payment": payment_for(final),
		"reputation_delta": int(band["reputation"]),
		# Совместимые поля для сцены (реакция гостя).
		"score": final,
		"fit": float(components["guest_fit"]),
		"emotion_id": str(band["id"]),
		"emoji": str(band["emoji"]),
		"likes": final >= likes_min,
	}


func _parse(data: Dictionary) -> void:
	var raw_weights: Variant = data.get("context_weights")
	if raw_weights is Dictionary:
		var sum := 0.0
		for key in COMPONENTS:
			var value: Variant = raw_weights.get(key)
			if not (value is float or value is int) or float(value) < 0.0:
				errors.append("session: context_weights.%s должен быть числом >= 0" % key)
				continue
			weights[key] = float(value)
			sum += float(value)
		if sum <= 0.0 and errors.is_empty():
			errors.append("session: сумма context_weights должна быть > 0")
	else:
		errors.append("session: нет секции context_weights")
	var fit: Variant = data.get("fit", {})
	if fit is Dictionary:
		fit_gain = float(fit.get("gain", fit_gain))
		dislike_penalty = float(fit.get("dislike_penalty", dislike_penalty))
		no_preference_fit = float(fit.get("no_preference_fit", no_preference_fit))
	_parse_trend(data.get("trend"))
	likes_min = float(data.get("likes_min", likes_min))
	_parse_bands(data.get("bands"))
	var pay: Variant = data.get("payment")
	if pay is Dictionary:
		pay_max = float(pay.get("max", pay_max))
		pay_min = float(pay.get("min", pay_min))
		pay_exponent = float(pay.get("exponent", pay_exponent))
		pay_round_to = int(pay.get("round_to", pay_round_to))
		if pay_max < pay_min or pay_exponent <= 0.0 or pay_round_to < 1:
			errors.append("session: payment: нужно max >= min, exponent > 0, round_to >= 1")
	else:
		errors.append("session: нет секции payment")


func _parse_trend(raw: Variant) -> void:
	if not (raw is Dictionary):
		errors.append("session: нет секции trend")
		return
	trend_current = str(raw.get("current", trend_current))
	trend_neutral_fit = float(raw.get("neutral_fit", trend_neutral_fit))
	trend_scale = float(raw.get("scale", trend_scale))
	var raw_trends: Variant = raw.get("trends")
	if not (raw_trends is Dictionary) or raw_trends.is_empty():
		errors.append("session: trend.trends должен быть непустым объектом")
		return
	for id in raw_trends:
		var entry: Variant = raw_trends[id]
		if not (entry is Dictionary) or not (entry.get("dimensions", {}) is Dictionary):
			errors.append("session: некорректный тренд '%s'" % str(id))
			continue
		for dimension in entry["dimensions"]:
			var value: Variant = entry["dimensions"][dimension]
			if not IngredientCatalog.DIMENSIONS.has(str(dimension)) or not (value is float or value is int) or absf(float(value)) > 1.0:
				errors.append("session: тренд '%s': некорректное измерение '%s'" % [str(id), str(dimension)])
		trends[str(id)] = {"name": str(entry.get("name", id)), "dimensions": entry["dimensions"]}
	if not trends.has(trend_current):
		errors.append("session: текущий тренд '%s' не описан" % trend_current)


func _parse_bands(raw: Variant) -> void:
	if not (raw is Array) or raw.is_empty():
		errors.append("session: bands должен быть непустым массивом")
		return
	for entry in raw:
		var good: bool = entry is Dictionary and (entry.get("min") is float or entry.get("min") is int) \
				and not str(entry.get("id", "")).is_empty() and not str(entry.get("emoji", "")).is_empty() \
				and not str(entry.get("name", "")).is_empty()
		if not good:
			errors.append("session: некорректная полоса %s" % str(entry))
			continue
		bands.append({"min": float(entry["min"]), "id": str(entry["id"]), "emoji": str(entry["emoji"]),
				"name": str(entry["name"]), "reputation": int(entry.get("reputation", 0))})
	bands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["min"] > b["min"])
	if not bands.is_empty() and float(bands[bands.size() - 1]["min"]) > 0.0:
		errors.append("session: нужна полоса с min = 0 (иначе низкий score ничему не соответствует)")
