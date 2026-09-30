class_name InteractionSystem
extends RefCounted
## Определяет, с каким объектом игрок может взаимодействовать, и запускает взаимодействие.
## Не знает ни про ноды, ни про UI: общается сигналами.

signal focus_changed(data: InteractableData)
signal player_interacted(interactable_id: String)

## Текущий фокус сохраняется, пока он не хуже лучшего кандидата больше чем на этот запас (клетки).
## Защищает от мерцания подсказки на границе двух соседних объектов.
const FOCUS_HYSTERESIS := 0.25

var _items: Array[InteractableData] = []
var _focus: InteractableData = null

var focus: InteractableData:
	get:
		return _focus


func register(data: InteractableData) -> void:
	_items.append(data)


func update_focus(player_pos: Vector2) -> void:
	var best: InteractableData = null
	var best_distance := INF
	for item in _items:
		if not item.enabled:
			continue
		var distance := item.distance_to(player_pos)
		if distance <= item.radius and distance < best_distance:
			best = item
			best_distance = distance
	if _focus != null and _focus.enabled and best != null and best != _focus:
		var current_distance := _focus.distance_to(player_pos)
		if current_distance <= _focus.radius and current_distance <= best_distance + FOCUS_HYSTERESIS:
			best = _focus
	if best != _focus:
		_focus = best
		focus_changed.emit(_focus)


## Повторно сообщает текущий фокус (например, после закрытия диалога, чтобы вернулась подсказка).
func refocus() -> void:
	focus_changed.emit(_focus)


## Возвращает true, если было с чем взаимодействовать.
func interact() -> bool:
	if _focus == null:
		return false
	player_interacted.emit(_focus.id)
	return true


func find_by_id(interactable_id: String) -> InteractableData:
	for item in _items:
		if item.id == interactable_id:
			return item
	return null
