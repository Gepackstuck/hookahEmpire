class_name CoalBucket
extends Control
## Ведёрко с углями: отсюда щипцами берут уголь (перетаскивание) и кладут в любое место чаши.

signal received

## Горячее ведёрко (угли красные).
var hot: bool = false
## Из ведёрка можно брать угли щипцами.
var draggable: bool = true
## Какие угли принимает ведёрко (kind перетаскивания): "" — никакие.
var accept_kind: String = ""
var count: int = 0:
	set(value):
		count = value
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(300, 170)
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func _get_drag_data(_at_position: Vector2) -> Variant:
	if count <= 0 or not draggable:
		return null
	var holder := Control.new()
	var tongs := TongsPreview.new()
	# Уголь в щипцах центрируется на курсоре.
	tongs.hot = hot
	tongs.position = Vector2(-BowlView.COAL_SIZE * 0.5, -BowlView.COAL_SIZE * 0.5)
	holder.add_child(tongs)
	set_drag_preview(holder)
	return {"kind": "hot_coal" if hot else "coal"}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return not accept_kind.is_empty() and data is Dictionary and data.get("kind") == accept_kind


func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	received.emit()


func _ellipse_poly(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points


## Ведёрко в новом виде: стальной конус с бликом, эллиптический ободок, дужка, угли с тлеющим свечением.
func _draw_modern(font: Font, base: Vector2) -> void:
	var rim_y := base.y - 84.0
	draw_texture_rect(VisualStyle.soft_disc(), Rect2(base + Vector2(-92, -16), Vector2(184, 40)), false, Color(0, 0, 0, 0.5))
	var metal := Color("#6b6f7e") if not hot else Color("#6f6068")
	draw_colored_polygon(PackedVector2Array([Vector2(base.x - 70, rim_y), Vector2(base.x + 70, rim_y), Vector2(base.x + 54, base.y - 2), Vector2(base.x - 54, base.y - 2)]), metal)
	draw_colored_polygon(PackedVector2Array([Vector2(base.x + 14, rim_y), Vector2(base.x + 70, rim_y), Vector2(base.x + 54, base.y - 2), Vector2(base.x + 10, base.y - 2)]), metal.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([Vector2(base.x - 58, rim_y + 6), Vector2(base.x - 44, rim_y + 6), Vector2(base.x - 36, base.y - 8), Vector2(base.x - 46, base.y - 8)]), Color(1, 1, 1, 0.18))
	draw_colored_polygon(_ellipse_poly(Vector2(base.x, base.y - 2), 54.0, 7.0), metal.darkened(0.35))
	draw_line(Vector2(base.x - 63, rim_y + 46), Vector2(base.x + 63, rim_y + 46), Color(1, 1, 1, 0.12), 2.0, true)
	# Внутренность и угли.
	draw_colored_polygon(_ellipse_poly(Vector2(base.x, rim_y), 70.0, 12.0), Color("#15121a"))
	for i in count:
		var at := Vector2(base.x - 42.0 + 28.0 * float(i), rim_y - 6.0 - 5.0 * float(i % 2))
		if hot:
			draw_texture_rect(VisualStyle.soft_disc(), Rect2(at - Vector2(30, 30), Vector2(60, 60)), false, Color(1.0, 0.45, 0.12, 0.6))
		var coal := Rect2(at - Vector2(13, 13), Vector2(26, 26))
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#c4431a") if hot else Color("#2b2b2e")
		box.set_corner_radius_all(7)
		box.border_color = Color(1, 0.75, 0.3, 0.9) if hot else Color(1, 0.6, 0.3, 0.4)
		box.set_border_width_all(2)
		draw_style_box(box, coal)
		draw_line(at + Vector2(-5, -3), at + Vector2(3, 5), Color(1, 0.7, 0.3, 0.8) if hot else Color(1, 1, 1, 0.12), 1.6, true)
	# Передняя кромка ободка и дужка.
	draw_arc(Vector2(base.x, rim_y), 70.0, 0.0, PI, 28, metal.lightened(0.3), 3.0, true)
	draw_arc(Vector2(base.x, rim_y - 6.0), 78.0, PI * 1.08, PI * 1.92, 28, Color(0.8, 0.82, 0.9, 0.55), 2.0, true)
	if font != null:
		var title := "Горячие угли" if hot else "Свежие угли"
		draw_string(font, Vector2(0, 18), "%s: %d" % [title, count], HORIZONTAL_ALIGNMENT_LEFT, size.x, 18, Color(0.92, 0.86, 0.76))


func _draw() -> void:
	var font := get_theme_default_font()
	var base := Vector2(size.x * 0.5, size.y - 10.0)
	if VisualStyle.modern:
		_draw_modern(font, base)
		return
	# Ведёрко.
	var bucket := PackedVector2Array([base + Vector2(-70, -84), base + Vector2(70, -84), base + Vector2(54, 0), base + Vector2(-54, 0)])
	draw_colored_polygon(bucket, Color("#5a5e66"))
	draw_polyline(PackedVector2Array([bucket[0], bucket[3], bucket[2], bucket[1], bucket[0]]), Color(1, 1, 1, 0.4), 2.0)
	draw_line(base + Vector2(-70, -60), base + Vector2(70, -60), Color(1, 1, 1, 0.2), 2.0)
	# Угли в ведёрке.
	for i in count:
		var at := base + Vector2(-42.0 + 28.0 * float(i), -92.0 - 6.0 * float(i % 2))
		draw_rect(Rect2(at - Vector2(13, 13), Vector2(26, 26)), Color("#c4431a") if hot else Color("#2b2b2e"))
		draw_rect(Rect2(at - Vector2(13, 13), Vector2(26, 26)), Color(1, 0.75, 0.3, 0.8) if hot else Color(1, 0.6, 0.3, 0.45), false, 2.0)
	if font != null:
		var title := "Горячие угли" if hot else "Свежие угли"
		var caption := "%s: %d" % [title, count]
		draw_string(font, Vector2(0, 18), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x, 18, Color(0.85, 0.8, 0.7))


## Уголь в щипцах под курсором.
class TongsPreview extends Control:
	var hot: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var coal := Vector2(BowlView.COAL_SIZE, BowlView.COAL_SIZE)
		var center := coal * 0.5
		var metal := Color("#b8bcc4")
		# Ручки щипцов сходятся к углю справа сверху.
		draw_line(center + Vector2(coal.x * 0.5, -coal.y * 0.35), center + Vector2(coal.x * 1.3, -coal.y * 1.4), metal, 6.0)
		draw_line(center + Vector2(coal.x * 0.5, coal.y * 0.35), center + Vector2(coal.x * 1.5, -coal.y * 1.1), metal, 6.0)
		if VisualStyle.modern:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("#c4431a") if hot else Color("#2b2b2e")
			box.set_corner_radius_all(18)
			box.border_color = Color(1, 0.75, 0.3, 0.85) if hot else Color(1, 0.6, 0.3, 0.5)
			box.set_border_width_all(2)
			draw_style_box(box, Rect2(Vector2.ZERO, coal))
			var inner := StyleBoxFlat.new()
			inner.bg_color = Color("#e0692a") if hot else Color("#3a3a3e")
			inner.set_corner_radius_all(12)
			draw_style_box(inner, Rect2(Vector2(10, 10), coal - Vector2(20, 20)))
			return
		draw_rect(Rect2(Vector2.ZERO, coal), Color("#c4431a") if hot else Color("#2b2b2e"))
		draw_rect(Rect2(Vector2(6, 6), coal - Vector2(12, 12)), Color("#e0692a") if hot else Color("#3a3a3e"))
		draw_rect(Rect2(Vector2.ZERO, coal), Color(1, 0.75, 0.3, 0.8) if hot else Color(1, 0.6, 0.3, 0.55), false, 3.0)
