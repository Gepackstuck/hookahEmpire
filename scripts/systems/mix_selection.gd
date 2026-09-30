class_name MixSelection
extends RefCounted
## Состояние экрана смешивания: порции ингредиентов и флаг льда.
## Общий бюджет порций ограничен (max_portions, по умолчанию 4): один ингредиент — до 4 порций,
## два — 1+3 или 2+2, три — 1+2+1 или 1+1+1, четыре — 1+1+1+1.
## Одновременно активны не более max_active ингредиентов.

signal changed

var max_active: int
var max_portions: int
var ice: bool = false
var _amounts: Dictionary = {}


func _init(max_active_value: int = 4, max_portions_value: int = 4) -> void:
	max_active = max_active_value
	max_portions = max_portions_value


func amount(ingredient_id: String) -> int:
	return int(_amounts.get(ingredient_id, 0))


func active_count() -> int:
	var count := 0
	for id in _amounts:
		if _amounts[id] > 0:
			count += 1
	return count


func total_portions() -> int:
	var total := 0
	for id in _amounts:
		total += int(_amounts[id])
	return total


## Ингредиент нельзя добавить, если он ещё не выбран, а все слоты ингредиентов заняты.
func is_locked(ingredient_id: String) -> bool:
	return amount(ingredient_id) == 0 and active_count() >= max_active


## Можно ли добавить ещё одну порцию этого ингредиента.
func can_increase(ingredient_id: String) -> bool:
	return total_portions() < max_portions and not is_locked(ingredient_id)


## Возвращает фактически установленное значение (с учётом бюджета порций и слотов).
func set_amount(ingredient_id: String, value: int) -> int:
	var current := amount(ingredient_id)
	var room := max_portions - (total_portions() - current)
	var clamped := clampi(value, 0, maxi(room, 0))
	if clamped > 0 and is_locked(ingredient_id):
		clamped = 0
	if clamped == current:
		return clamped
	if clamped == 0:
		_amounts.erase(ingredient_id)
	else:
		_amounts[ingredient_id] = clamped
	changed.emit()
	return clamped


func set_ice(value: bool) -> void:
	if value == ice:
		return
	ice = value
	changed.emit()


func clear() -> void:
	_amounts.clear()
	ice = false
	changed.emit()


func is_empty() -> bool:
	return active_count() == 0


func selection() -> Dictionary:
	return _amounts.duplicate()


func modifiers() -> Array:
	return ["ice"] if ice else []


## Загружает сохранённый рецепт: ищет наименьшее число порций (не больше бюджета), которое
## даёт те же канонические доли (15:5 -> 3:1, 7:7:6 -> 1:1:1). Для "чужих" пропорций берёт
## ближайшее приближение в рамках бюджета.
func load_recipe(recipe: Dictionary, total_units: int = 20) -> void:
	_amounts.clear()
	var items: Array = recipe["ingredients"]
	var wanted := {}
	for item in items:
		wanted[item["id"]] = int(item["units"])
	var found := false
	# Секретный рецепт требует полного бюджета порций.
	var first_total := max_portions if str(recipe.get("secret_id", "")) != "" else 1
	for total in range(first_total, max_portions + 1):
		var portions := {}
		var sum := 0
		for id in wanted:
			portions[id] = maxi(roundi(float(wanted[id]) * float(total) / float(total_units)), 1)
			sum += portions[id]
		if sum == total and RecipeCanonical.distribute_units(portions, total_units) == wanted:
			_amounts = portions
			found = true
			break
	if not found:
		var weights := {}
		for id in wanted:
			weights[id] = float(wanted[id])
		var approx := RecipeCanonical.distribute_units(weights, max_portions)
		for id in approx:
			if approx[id] > 0:
				_amounts[id] = approx[id]
	ice = recipe["modifiers"].has("ice")
	changed.emit()
