class_name InteractableData
extends RefCounted
## Данные интерактивного объекта. Не зависит от нод и графики.

var id: String = ""
var display_name: String = ""
var prompt: String = "Взаимодействовать"
var message: String = ""
## Если не пусто — на время нахождения рядом с объектом аватар игрока меняется на этот эмодзи.
var player_emoji: String = ""
## Если не пусто — взаимодействие запускает этот диалог (id из data/dialogues).
var dialogue_id: String = ""
## Если не пусто — взаимодействие запрашивает игровое действие (например, "open_mixer").
var action: String = ""
## Прямоугольник объекта в клетках сетки.
var rect: Rect2 = Rect2()
## Максимальное расстояние от игрока до края прямоугольника, в клетках.
var radius: float = 1.0


func distance_to(grid_pos: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - grid_pos.x, 0.0), grid_pos.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - grid_pos.y, 0.0), grid_pos.y - rect.end.y)
	return Vector2(dx, dy).length()
