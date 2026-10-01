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


func _draw() -> void:
	var font := get_theme_default_font()
	var base := Vector2(size.x * 0.5, size.y - 10.0)
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
		draw_rect(Rect2(Vector2.ZERO, coal), Color("#c4431a") if hot else Color("#2b2b2e"))
		draw_rect(Rect2(Vector2(6, 6), coal - Vector2(12, 12)), Color("#e0692a") if hot else Color("#3a3a3e"))
		draw_rect(Rect2(Vector2.ZERO, coal), Color(1, 0.75, 0.3, 0.8) if hot else Color(1, 0.6, 0.3, 0.55), false, 3.0)
