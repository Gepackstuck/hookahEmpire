class_name TasteIcons
extends RefCounted
## Эмодзи вкусов и ингредиентов для режима «NPC»: чипы над головой гостя (чего он хочет) и кальянщика
## (что подобрал). Чистая логика: состояния чипов считаются здесь, а рисует их HeadLabels.
##
## Состояния чипа: "want" — ещё не проверено (светится), "match" — совпало (зелёный),
## "miss" — не совпало (красный), "pick" — кальянщик ещё выбирает (мерцание).

const DIMENSION_EMOJI := {
	"sweet": "🍬", "fresh": "❄️", "sour": "🍋", "fruit": "🍓", "creamy": "🥛", "spicy": "🌶️", "heavy": "💨",
}
## Ингредиент «даёт» вкус, если значение измерения не меньше этого порога.
const COVER_MIN := 0.5
const ICE_ID := "ice"


static func dimension_emoji(dimension: String) -> String:
	return str(DIMENSION_EMOJI.get(dimension, "❔"))


## Эмодзи ингредиента (или модификатора льда).
static func item_emoji(catalog: IngredientCatalog, item_id: String) -> String:
	if item_id == ICE_ID:
		return "❄️"
	return str(catalog.get_ingredient(item_id).get("emoji", "❔"))


## Даёт ли выбранный элемент (ингредиент или лёд) этот вкус.
static func covers(catalog: IngredientCatalog, item_id: String, dimension: String) -> bool:
	if item_id == ICE_ID:
		return dimension == "fresh"
	return float(catalog.get_ingredient(item_id).get(dimension, 0.0)) >= COVER_MIN


static func _covered(catalog: IngredientCatalog, chosen: Array, dimension: String) -> bool:
	for item_id in chosen:
		if covers(catalog, str(item_id), dimension):
			return true
	return false


static func _by_weight(weights: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for dimension in weights:
		if float(weights[dimension]) > 0.0:
			result.append(str(dimension))
	result.sort_custom(func(a: String, b: String) -> bool:
		var wa := float(weights[a])
		var wb := float(weights[b])
		return wa > wb or (is_equal_approx(wa, wb) and a < b))
	return result


## Чипы над гостем: его вкусы (и «🚫» неприятия). chosen — что уже подобрал кальянщик; final — выбор закончен
## (тогда несовпавшие вкусы красные, а до этого просто светятся).
static func guest_chips(catalog: IngredientCatalog, preferences: Dictionary, dislikes: Dictionary, chosen: Array, final: bool) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	for dimension in _by_weight(preferences):
		var state := "want"
		if _covered(catalog, chosen, dimension):
			state = "match"
		elif final:
			state = "miss"
		chips.append({"emoji": dimension_emoji(dimension), "state": state})
	for dimension in _by_weight(dislikes):
		var state := "want"
		if _covered(catalog, chosen, dimension):
			state = "miss"
		elif final:
			state = "match"
		chips.append({"emoji": "🚫" + dimension_emoji(dimension), "state": state})
	return chips


## Чипы над кальянщиком: выбранные ингредиенты (и лёд); зелёный — попадает во вкус гостя и не нарушает неприятие,
## красный — не попадает или нарушает.
static func cook_chips(catalog: IngredientCatalog, chosen: Array, preferences: Dictionary, dislikes: Dictionary) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	for item_id in chosen:
		var good := false
		for dimension in _by_weight(preferences):
			if covers(catalog, str(item_id), dimension):
				good = true
		for dimension in _by_weight(dislikes):
			if covers(catalog, str(item_id), dimension):
				good = false
		chips.append({"emoji": item_emoji(catalog, str(item_id)), "state": "match" if good else "miss"})
	return chips
