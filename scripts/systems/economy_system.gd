class_name EconomySystem
extends RefCounted
## M8: деньги, стоимость ингредиентов и репутация поверх GameState. Чистая логика без UI.
## Бесплатные ингредиенты (free_ingredients) всегда доступны, поэтому банкротства нет.

const CONFIG_PATH := "res://data/config/economy.json"
const START_MONEY_FLAG := "start_money_given"

var errors: Array[String] = []
var start_money: int = 150
var cost_multiplier: float = 10.0
## Цена одной замены углей (списывается, сколько есть: замена никогда не блокируется).
var coal_cost: int = 40
## Цена одного мундштука при пополнении коробки (списывается, сколько есть).
var mouthpiece_cost: int = 8
var free_ingredients: Array[String] = []
## Расширения кальянной полки по порядку: {"price": цена, "extra": сколько докупленных кальянов всего после покупки}.
var shelf_upgrades: Array[Dictionary] = []
var reputation_min: int = -20
var reputation_max: int = 100
## Статистика за запуск (в сохранение не идёт).
var earned_total: int = 0
var spent_total: int = 0

var _state: Object
var _catalog: IngredientCatalog


func _init(state: Object = null, catalog: IngredientCatalog = null) -> void:
	_state = state
	_catalog = catalog


static func load_default(state: Object, catalog: IngredientCatalog) -> EconomySystem:
	var system := EconomySystem.new(state, catalog)
	if not FileAccess.file_exists(CONFIG_PATH):
		system.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return system
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		system.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return system
	system._parse(parsed)
	return system


static func from_dict(data: Dictionary, state: Object, catalog: IngredientCatalog) -> EconomySystem:
	var system := EconomySystem.new(state, catalog)
	system._parse(data)
	return system


func is_valid() -> bool:
	return errors.is_empty()


func balance() -> int:
	return int(_state.money)


func reputation() -> int:
	return int(_state.reputation)


## Начальные деньги выдаются один раз за игру (флаг в сюжетных флагах).
func grant_start_money() -> bool:
	if _state.has_flag(START_MONEY_FLAG):
		return false
	_state.set_flag(START_MONEY_FLAG, true)
	_state.set_money(_state.money + start_money)
	return true


func earn(amount: int) -> void:
	if amount <= 0:
		return
	_state.set_money(_state.money + amount)
	earned_total += amount


func can_afford(amount: int) -> bool:
	return amount <= balance()


## Списывает ровно amount; false (и ничего не меняется), если денег не хватает.
func spend(amount: int) -> bool:
	if amount < 0 or not can_afford(amount):
		return false
	_state.set_money(_state.money - amount)
	spent_total += amount
	return true


## Списывает стоимость замены углей (не больше баланса). Возвращает списанную сумму.
func charge_coals() -> int:
	var charged := mini(coal_cost, balance())
	if charged > 0 and spend(charged):
		return charged
	return 0


## Списывает стоимость count новых мундштуков (не больше баланса). Возвращает списанную сумму.
func charge_mouthpieces(count: int) -> int:
	var charged := mini(mouthpiece_cost * maxi(count, 0), balance())
	if charged > 0 and spend(charged):
		return charged
	return 0


func is_free(ingredient_id: String) -> bool:
	return free_ingredients.has(ingredient_id)


## Стоимость рецепта: платные ингредиенты × их доля в рецепте × cost_multiplier. Бесплатные и ❄️ — 0.
func recipe_cost(recipe: Dictionary, total_units: int) -> int:
	if _catalog == null or total_units <= 0:
		return 0
	var cost := 0.0
	for item in recipe.get("ingredients", []):
		var id := str(item["id"])
		if is_free(id) or not _catalog.has_ingredient(id):
			continue
		cost += float(_catalog.get_ingredient(id).get("cost", 0)) * float(item["units"]) / float(total_units) * cost_multiplier
	return int(round(cost))


func can_afford_recipe(recipe: Dictionary, total_units: int) -> bool:
	return can_afford(recipe_cost(recipe, total_units))


## Репутационный эффект визита; значение ограничено [reputation_min, reputation_max].
func add_reputation(delta: int) -> int:
	var value := clampi(int(_state.reputation) + delta, reputation_min, reputation_max)
	_state.set_reputation(value)
	return value


func _parse(data: Dictionary) -> void:
	var money: Variant = data.get("start_money", start_money)
	if not (money is int or money is float) or int(money) < 0:
		errors.append("economy: start_money должен быть числом >= 0")
	else:
		start_money = int(money)
	var multiplier: Variant = data.get("cost_multiplier", cost_multiplier)
	if not (multiplier is int or multiplier is float) or float(multiplier) < 0.0:
		errors.append("economy: cost_multiplier должен быть числом >= 0")
	else:
		cost_multiplier = float(multiplier)
	var coal: Variant = data.get("coal_cost", coal_cost)
	if not (coal is int or coal is float) or int(coal) < 0:
		errors.append("economy: coal_cost должен быть числом >= 0")
	else:
		coal_cost = int(coal)
	var piece: Variant = data.get("mouthpiece_cost", mouthpiece_cost)
	if not (piece is int or piece is float) or int(piece) < 0:
		errors.append("economy: mouthpiece_cost должен быть числом >= 0")
	else:
		mouthpiece_cost = int(piece)
	var upgrades: Variant = data.get("shelf_upgrades", [])
	if not (upgrades is Array):
		errors.append("economy: shelf_upgrades должен быть массивом")
	else:
		shelf_upgrades.clear()
		for raw in upgrades:
			if raw is Dictionary and ((raw as Dictionary).get("price") is float or (raw as Dictionary).get("price") is int) \
					and ((raw as Dictionary).get("extra") is float or (raw as Dictionary).get("extra") is int):
				shelf_upgrades.append({"price": int(raw["price"]), "extra": int(raw["extra"])})
			else:
				errors.append("economy: shelf_upgrades: нужны числа price и extra")
	var free: Variant = data.get("free_ingredients", [])
	if not (free is Array):
		errors.append("economy: free_ingredients должен быть массивом")
	else:
		for entry in free:
			if _catalog != null and not _catalog.has_ingredient(str(entry)):
				errors.append("economy: бесплатный ингредиент '%s' не описан в каталоге" % str(entry))
			else:
				free_ingredients.append(str(entry))
	var rep: Variant = data.get("reputation", {})
	if rep is Dictionary:
		reputation_min = int(rep.get("min", reputation_min))
		reputation_max = int(rep.get("max", reputation_max))
		if reputation_min > reputation_max:
			errors.append("economy: reputation.min не может быть больше max")
