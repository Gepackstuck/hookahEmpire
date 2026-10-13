class_name SeatOverlay
extends Node2D
## Передняя часть сиденья, рисуется поверх сидящего человечка, чтобы он выглядел "в стуле".
## Для стула, смотрящего вдоль y, узел отражается по горизонтали (scale.x = -1).

var color := Color("#8a5a3c")


func _draw() -> void:
	var west := IsoProjection.grid_to_screen(Vector2(-0.36, 0.36))
	var south := IsoProjection.grid_to_screen(Vector2(0.36, 0.36))
	var east := IsoProjection.grid_to_screen(Vector2(0.36, -0.36))
	var low := Vector2(0, -8.0)
	var high := Vector2(0, -20.0)
	draw_colored_polygon(PackedVector2Array([west + low, south + low, south + high, west + high]), color.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([south + low, east + low, east + high, south + high]), color.darkened(0.2))
	if VisualStyle.modern:
		# Новый вид: светлая кромка сиденья и мягкая тень под ним.
		var rim := color.lightened(0.35)
		rim.a = 0.8
		draw_polyline(PackedVector2Array([west + high, south + high, east + high]), rim, 1.2, true)
		draw_polyline(PackedVector2Array([west + low, south + low, east + low]), Color(0, 0, 0, 0.3), 1.0, true)
		draw_line(south + low, south + high, Color(1, 1, 1, 0.12), 1.0, true)
