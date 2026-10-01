class_name CarriedHookah
extends Node2D
## Кальян в руках игрока: векторный, того цвета, который взяли с полки.

var color := Color("#22b8ff")
## Что на кальяне: 0 — ничего, 1 — чаша, 2 — чаша с углями (HookahArt.draw_hookah).
var top := 0


func _draw() -> void:
	HookahArt.draw_hookah(self, Vector2.ZERO, color, false, 0.0, 0, 0.0, top)
