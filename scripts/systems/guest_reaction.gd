class_name GuestReaction
extends RefCounted
## ВРЕМЕННАЯ предварительная реакция гостя на приготовленный кальян (превью M6).
## score = взвешенное среднее: качество рецепта, соответствие вкусу гостя (fit) и исполнение.
## Полноценный GuestFit/TrendFit/штрафы появятся в M6 и заменят эту формулу.

const CONFIG_PATH := "res://data/config/reaction_preview.json"

var errors: Array[String] = []
var weight_quality: float = 0.5
var weight_fit: float = 0.3
var weight_execution: float = 0.2
var likes_min: float = 55.0
## По убыванию min: {"min", "id", "emoji"}.
var emotions: Array[Dictionary] = []


static func load_default() -> GuestReaction:
	var reaction := GuestReaction.new()
	if not FileAccess.file_exists(CONFIG_PATH):
		reaction.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return reaction
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		reaction.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return reaction
	reaction._parse(parsed)
	return reaction


static func from_dict(data: Dictionary) -> GuestReaction:
	var reaction := GuestReaction.new()
	reaction._parse(data)
	return reaction


func is_valid() -> bool:
	return errors.is_empty()


## guest — описание гостя (data/guests), recipe — запись рецепта. Возвращает
## {"score", "fit", "likes", "emotion_id", "emoji"}.
func evaluate(guest: Dictionary, recipe: Dictionary, execution_score: float, catalog: IngredientCatalog, scoring: ScoringConfig) -> Dictionary:
	var shape := {"ingredients": recipe["ingredients"], "modifiers": recipe["modifiers"]}
	var profile := RecipeScoring.taste_profile(shape, catalog, scoring)
	var fit := 50.0
	var preferences: Variant = guest.get("preferences", {})
	if preferences is Dictionary and not preferences.is_empty():
		var weighted := 0.0
		var total := 0.0
		for dimension in preferences:
			weighted += float(preferences[dimension]) * float(profile.get(dimension, 0.0))
			total += float(preferences[dimension])
		if total > 0.0:
			fit = weighted / total * 100.0
	var weight_sum := weight_quality + weight_fit + weight_execution
	var score := (weight_quality * float(recipe["best_score"]) + weight_fit * fit + weight_execution * execution_score) / weight_sum
	score = snappedf(clampf(score, 0.0, 100.0), 0.1)
	var emotion := emotions[emotions.size() - 1]
	for entry in emotions:
		if score >= float(entry["min"]):
			emotion = entry
			break
	return {
		"score": score,
		"fit": fit,
		"likes": score >= likes_min,
		"emotion_id": str(emotion["id"]),
		"emoji": str(emotion["emoji"]),
	}


func _parse(data: Dictionary) -> void:
	var weights: Variant = data.get("weights")
	if weights is Dictionary:
		weight_quality = float(weights.get("quality", weight_quality))
		weight_fit = float(weights.get("fit", weight_fit))
		weight_execution = float(weights.get("execution", weight_execution))
	else:
		errors.append("reaction: нет секции weights")
	if weight_quality + weight_fit + weight_execution <= 0.0:
		errors.append("reaction: сумма весов должна быть > 0")
	likes_min = float(data.get("likes_min", likes_min))
	var raw: Variant = data.get("emotions")
	if not (raw is Array) or raw.is_empty():
		errors.append("reaction: emotions должен быть непустым массивом")
		return
	for entry in raw:
		var good: bool = entry is Dictionary and (entry.get("min") is float or entry.get("min") is int) \
				and not str(entry.get("emoji", "")).is_empty() and not str(entry.get("id", "")).is_empty()
		if not good:
			errors.append("reaction: некорректная эмоция %s" % str(entry))
			continue
		emotions.append({"min": float(entry["min"]), "id": str(entry["id"]), "emoji": str(entry["emoji"])})
	emotions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["min"] > b["min"])
	if not emotions.is_empty() and float(emotions[emotions.size() - 1]["min"]) > 0.0:
		errors.append("reaction: нужна эмоция с min = 0 (иначе низкий score ничему не соответствует)")
