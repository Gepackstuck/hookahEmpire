class_name CarriedHookah
extends Node2D
## Кальян в руках игрока: векторный, того цвета, который взяли с полки.

var color := Color("#22b8ff")


func _draw() -> void:
	HookahArt.draw_hookah(self, Vector2.ZERO, color, false)
