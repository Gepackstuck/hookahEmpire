class_name IsoDraw
extends RefCounted
## Мелкие помощники для рисования заглушек в изометрии.


## Мягкая "тень" под объектом: эллипс с центром в точке (0,0) канваса.
static func draw_shadow(canvas: CanvasItem, radius_x: float, radius_y: float = -1.0) -> void:
	if radius_y < 0.0:
		radius_y = radius_x * 0.5
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	canvas.draw_colored_polygon(points, Color(0, 0, 0, 0.28))
