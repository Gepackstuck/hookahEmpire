class_name HookahArt
extends RefCounted
## Векторные рисунки кальяна, щипцов и банки с табаком (общие для стола, полки и рук игрока).
## Все функции рисуют на переданном CanvasItem и вызываются из его _draw().

## Масштаб нарисованного кальяна (1.0 — исходные ~70 px высоты).
const SCALE := 0.75
## Высота кальяна на экране (px), без шланга.
const HEIGHT := 69.0 * SCALE
const HANDLE_STYLES := 5
## Точка клапана (откуда выходит шланг) в координатах кальяна до масштабирования.
const VALVE := Vector2(9.0, -43.0)

## Яркие «балдёжные» цвета колб. Красный/коричневый и серо-белые оттенки сюда не входят:
## их используют кальяны на столе для смешивания, чтобы цвета не пересекались.
const PALETTE: Array[String] = [
	"#ff3b6b", "#ff7a1a", "#ffd21f", "#7bd62f", "#19c9a0",
	"#22b8ff", "#3d5bff", "#a64dff", "#ff4fd8", "#00d4e6",
]


## Случайные цвета без одинаковых соседей: «мешок» палитры перемешивается, пока не кончится.
static func random_colors(count: int, palette: Array = []) -> Array[Color]:
	var source: Array = palette if not palette.is_empty() else PALETTE
	var result: Array[Color] = []
	var bag: Array = []
	while result.size() < count:
		if bag.is_empty():
			bag = source.duplicate()
			bag.shuffle()
			if not result.is_empty() and bag.size() > 1 and Color.html(str(bag[bag.size() - 1])) == result[result.size() - 1]:
				bag.reverse()
		result.append(Color.html(str(bag.pop_back())))
	return result


static func bezier(points: Array) -> PackedVector2Array:
	return _bezier(points)


## Мундштук со смолы: чёрное резиновое основание (в него вставлен шланг), серебряное кольцо и цветной
## гнутый наконечник с раструбом. p — точка стыка со шлангом, dir — куда смотрит наконечник.
static func draw_mouthpiece(canvas: CanvasItem, p: Vector2, dir: Vector2, color: Color, piece_scale: float = 0.7) -> void:
	canvas.draw_set_transform(p, dir.angle(), Vector2(piece_scale, piece_scale))
	canvas.draw_rect(Rect2(0.0, -2.7, 5.5, 5.4), Color("#1c1d22"))
	canvas.draw_rect(Rect2(5.5, -3.1, 1.2, 6.2), Color("#d7dbe2"))
	var upper := [Vector2(6.7, -2.8), Vector2(9.2, -2.1), Vector2(11.0, -2.6), Vector2(13.4, -3.7)]
	var shape := PackedVector2Array()
	for point: Vector2 in upper:
		shape.append(point)
	for i in range(upper.size() - 1, -1, -1):
		var point: Vector2 = upper[i]
		shape.append(Vector2(point.x, -point.y))
	canvas.draw_colored_polygon(shape, color)
	canvas.draw_line(Vector2(7.4, -1.3), Vector2(12.6, -2.3), color.lightened(0.55), 0.9)
	canvas.draw_rect(Rect2(13.0, -2.5, 0.9, 5.0), color.darkened(0.6))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _ellipse(canvas: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	canvas.draw_colored_polygon(points, color)


static func _bezier(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		var a: Vector2 = points[0].lerp(points[1], t)
		var b: Vector2 = points[1].lerp(points[2], t)
		var c: Vector2 = points[2].lerp(points[3], t)
		result.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return result


## top = TOP_WATERED: чаши ещё нет (только тарелка), но в колбу уже налита вода.
const TOP_WATERED := -1
## Несут одну колбу (без кальяна): пустую / с водой.
const TOP_FLASK_EMPTY := -2
const TOP_FLASK_WATERED := -3

## Кальян: origin — точка на поверхности под центром колбы. squash — «затяжка» (0..1) приседает кальян.
## with_hose — рисовать длинный шланг (на столе; в руках и на полке кальян без шланга).
## top — что стоит на кальяне: 0 — только тарелка (кальян не забит), 1 — чаша без углей, 2 — чаша с углями.
## Вода в колбе (и пузырьки при затяжке, squash > 0) — только у забитого кальяна (top >= 1).
static func draw_hookah(canvas: CanvasItem, origin: Vector2, color: Color, with_hose: bool = true, squash: float = 0.0, handle_style: int = 0, tilt: float = 0.0, top: int = 0, heat_state: int = 1) -> void:
	if top <= TOP_FLASK_EMPTY:
		draw_flask(canvas, origin, color, top == TOP_FLASK_WATERED, tilt)
		return
	var stretch := Vector2(SCALE * (1.0 + 0.04 * squash), SCALE * (1.0 - 0.06 * squash))
	canvas.draw_set_transform(origin, tilt, stretch)
	_draw_hookah_shape(canvas, color, with_hose, Transform2D(tilt, stretch, 0.0, origin), handle_style, top, squash, heat_state)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Стройный кальян: тонкая стеклянная колба-колокол, чёрная шахта с «пузырями», тарелка, чаша, клапан.
static func _draw_hookah_shape(canvas: CanvasItem, color: Color, with_hose: bool, base: Transform2D = Transform2D.IDENTITY, handle_style: int = 0, top: int = 0, bubbling: float = 0.0, heat_state: int = 1) -> void:
	var black := Color("#1c1d22")
	var steel := Color("#c9ced6")
	var p := Vector2.ZERO
	_ellipse(canvas, p + Vector2(0, 1), 12.0, 4.6, Color(0, 0, 0, 0.25))
	if with_hose:
		var hose_back := _bezier([p + Vector2(8, -43), p + Vector2(34, -46), p + Vector2(31, -6), p + Vector2(18, 0)])
		canvas.draw_polyline(hose_back, color.darkened(0.45), 2.3 if VisualStyle.modern else 2.9, true)
		canvas.draw_polyline(hose_back, color, 1.7, true)
	_draw_flask_body(canvas, p, color, top >= 1 or top == TOP_WATERED, bubbling)
	canvas.draw_rect(Rect2(p + Vector2(-11, -2.5), Vector2(22, 3.5)), black)
	# Шахта с «пузырями» и воротником.
	canvas.draw_rect(Rect2(p + Vector2(-5, -31), Vector2(10, 4)), black)
	canvas.draw_rect(Rect2(p + Vector2(-1.4, -58), Vector2(2.8, 28)), black)
	for knuckle: Vector2 in [Vector2(0, -35), Vector2(0, -42), Vector2(0, -49)]:
		_ellipse(canvas, p + knuckle, 4.0, 3.0, black)
		_ellipse(canvas, p + knuckle + Vector2(-1.2, -1), 1.3, 0.9, Color(1, 1, 1, 0.25))
	canvas.draw_line(p + Vector2(1.5, -37), p + Vector2(8, -43), black, 3.2)
	canvas.draw_rect(Rect2(p + Vector2(6.5, -45), Vector2(3.5, 3.5)), steel)
	# Тарелка, чаша, уголёк.
	_ellipse(canvas, p + Vector2(0, -57), 11.0, 4.0, black)
	_ellipse(canvas, p + Vector2(0, -58), 9.8, 3.1, Color("#33363e"))
	if top >= 1:
		_bowl_shape(canvas, p + Vector2(0, -58), color, top >= 2, heat_state)
	if with_hose:
		var hose_front := _bezier([p + Vector2(18, 0), p + Vector2(6, 8), p + Vector2(-11, 9), p + Vector2(-19, 3)])
		canvas.draw_polyline(hose_front, color.darkened(0.45), 2.3 if VisualStyle.modern else 2.9, true)
		canvas.draw_polyline(hose_front, color, 1.7, true)
		# Ручка на конце шланга (как у остальных кальянов), лежит на столе влево-вниз; длина ~11 px на экране.
		draw_handle(canvas, p + Vector2(-19, 3), Vector2(-1.0, 0.25).normalized(), handle_style, 11.0 / 22.0 / SCALE, base)


## Только колба (стекло, узор, чёрное основание и горлышко): её несут к раковине отдельно от кальяна.
static func _draw_flask_body(canvas: CanvasItem, p: Vector2, color: Color, watered: bool, bubbling: float = 0.0) -> void:
	var black := Color("#1c1d22")
	# Колба: узкое горло, шар, талия, основание (профиль: [высота, полуширина]).
	var profile: Array = [[-28.0, 3.4], [-25.0, 4.1], [-22.0, 6.8], [-18.0, 7.9], [-14.0, 6.0], [-10.0, 5.6], [-6.0, 7.5], [-2.0, 10.1], [0.0, 10.9]]
	# В новом виде стенка колбы тонкая — контур не съедает цвет стекла.
	var wall_k := 0.92 if VisualStyle.modern else 0.76
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for point: Array in profile:
		outer.append(p + Vector2(float(point[1]), float(point[0])))
		inner.append(p + Vector2(float(point[1]) * wall_k, float(point[0]) * 0.97 - 0.5))
	for i in range(profile.size() - 1, -1, -1):
		var point: Array = profile[i]
		outer.append(p + Vector2(-float(point[1]), float(point[0])))
		inner.append(p + Vector2(-float(point[1]) * wall_k, float(point[0]) * 0.97 - 0.5))
	canvas.draw_colored_polygon(outer, color.darkened(0.45))
	canvas.draw_colored_polygon(inner, color)
	if VisualStyle.modern:
		# Глянец стекла: тёмный контур колбы и два блика.
		var rim := outer.duplicate()
		rim.append(outer[0])
		canvas.draw_polyline(rim, Color(0.05, 0.03, 0.06, 0.55), 0.7, true)
		canvas.draw_line(p + Vector2(-4.6, -19.0), p + Vector2(-5.6, -8.0), Color(1, 1, 1, 0.5), 1.4, true)
		_ellipse(canvas, p + Vector2(4.2, -4.5), 1.1, 2.2, Color(1, 1, 1, 0.3))
	if watered:
		_draw_water(canvas, p, color, bubbling)
	var pattern := color.lightened(0.4)
	pattern.a = 0.55
	for spot: Vector2 in [Vector2(-3, -17), Vector2(3, -13), Vector2(-5, -5), Vector2(1, -4), Vector2(6, -6)]:
		canvas.draw_colored_polygon(PackedVector2Array([p + spot + Vector2(0, -2), p + spot + Vector2(1.3, 0), p + spot + Vector2(0, 2), p + spot + Vector2(-1.3, 0)]), pattern)
	_ellipse(canvas, p + Vector2(-4, -17), 1.4, 4.0, Color(1, 1, 1, 0.4))
	canvas.draw_rect(Rect2(p + Vector2(-11, -2.5), Vector2(22, 3.5)), black)
	canvas.draw_rect(Rect2(p + Vector2(-5, -31), Vector2(10, 4)), black)
	canvas.draw_rect(Rect2(p + Vector2(-2.2, -35), Vector2(4.4, 5)), black)


## Колба в руках: top == TOP_FLASK_EMPTY — пустая, TOP_FLASK_WATERED — с водой.
static func draw_flask(canvas: CanvasItem, origin: Vector2, color: Color, watered: bool, tilt: float = 0.0) -> void:
	var stretch := Vector2(SCALE * 1.15, SCALE * 1.15)
	canvas.draw_set_transform(origin, tilt, stretch)
	_draw_flask_body(canvas, Vector2.ZERO, color, watered)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Вода в колбе (светлая заливка до уровня -15); при затяжке (bubbling > 0) поднимаются пузырьки.
static func _draw_water(canvas: CanvasItem, p: Vector2, color: Color, bubbling: float) -> void:
	var levels: Array = [[-15.0, 6.2], [-14.0, 6.0], [-10.0, 5.6], [-6.0, 7.5], [-2.0, 10.1], [0.0, 10.9]]
	var water := PackedVector2Array()
	for point: Array in levels:
		water.append(p + Vector2(float(point[1]) * 0.76, float(point[0]) * 0.97 - 0.5))
	for i in range(levels.size() - 1, -1, -1):
		var point: Array = levels[i]
		water.append(p + Vector2(-float(point[1]) * 0.76, float(point[0]) * 0.97 - 0.5))
	var tint := color.lightened(0.55)
	tint.a = 0.6
	canvas.draw_colored_polygon(water, tint)
	canvas.draw_line(p + Vector2(-4.5, -15.0), p + Vector2(4.5, -15.0), Color(1, 1, 1, 0.6), 0.9)
	if bubbling <= 0.05:
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	for k in 7:
		var phase := fposmod(t * 2.6 + float(k) * 0.143, 1.0)
		var x := sin(t * 3.1 + float(k) * 1.9) * 3.6
		var y := lerpf(-4.0, -14.2, phase)
		var radius := 0.6 + 0.35 * float(k % 3)
		canvas.draw_circle(p + Vector2(x, y), radius, Color(1, 1, 1, 0.85 * (1.0 - phase * 0.45)))
		canvas.draw_arc(p + Vector2(x, y), radius, 0.0, TAU, 8, Color(0.4, 0.6, 0.8, 0.5), 0.5)


## Чаша: цветной конус с ободком; с углями (coals) — раскалённые угольки, без — табак.
## heat_state — вид углей: 0 остыли (серые), 1 обычные, 2 жарко (ярко-жёлтые, с ореолом), 3 сгорели (чёрные с пеплом).
static func _bowl_shape(canvas: CanvasItem, at: Vector2, color: Color, coals: bool, heat_state: int = 1) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-4, 0), at + Vector2(4, 0), at + Vector2(3.2, -8), at + Vector2(-3.2, -8)]), color.darkened(0.15))
	_ellipse(canvas, at + Vector2(0, -8), 3.8, 1.6, color.lightened(0.3))
	if coals:
		var base_coal := Color("#3a3a40")
		var spot_a := Color("#ff6a2a")
		var spot_b := Color("#ffb347")
		match heat_state:
			0:
				base_coal = Color("#5a5a60")
				spot_a = Color("#7a6a66")
				spot_b = Color("#8a8484")
			2:
				_ellipse(canvas, at + Vector2(0, -9), 4.6, 2.0, Color(1.0, 0.55, 0.15, 0.28))
				spot_a = Color("#ffd23a")
				spot_b = Color("#fff3b0")
			3:
				base_coal = Color("#17171a")
				spot_a = Color("#2a2a2e")
				spot_b = Color("#9a9a9a")
		_ellipse(canvas, at + Vector2(0, -9), 2.5, 1.0, base_coal)
		_ellipse(canvas, at + Vector2(-0.8, -9.2), 1.2, 0.6, spot_a)
		_ellipse(canvas, at + Vector2(1.1, -8.8), 0.9, 0.5, spot_b)
	else:
		_ellipse(canvas, at + Vector2(0, -8.6), 2.4, 1.0, color.darkened(0.55))


## Чаша отдельно (лежит на столе, пока в неё кладут угли): p — точка под дном чаши.
static func draw_bowl(canvas: CanvasItem, p: Vector2, color: Color, coals: bool) -> void:
	canvas.draw_set_transform(p, 0.0, Vector2(SCALE, SCALE))
	_ellipse(canvas, Vector2(0, 1), 5.0, 1.6, Color(0, 0, 0, 0.22))
	_bowl_shape(canvas, Vector2.ZERO, color, coals)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Низкая круглая жестяная банка: светлое тело, тёмная крышка и цветная лента-этикетка.
static func draw_jar(canvas: CanvasItem, p: Vector2, color: Color) -> void:
	var tin := Color("#e7e3da")
	var lid := Color("#2a2c33")
	if VisualStyle.modern:
		_draw_jar_modern(canvas, p, color, tin, lid)
		return
	_ellipse(canvas, p + Vector2(0, 1), 9.0, 3.4, Color(0, 0, 0, 0.22))
	canvas.draw_rect(Rect2(p + Vector2(-7.5, -10), Vector2(15, 10)), tin)
	_ellipse(canvas, p, 7.5, 3.0, tin)
	# Цветная лента-этикетка с закруглённым низом и белым «логотипом».
	canvas.draw_rect(Rect2(p + Vector2(-7.5, -7.5), Vector2(15, 5.5)), color)
	_ellipse(canvas, p + Vector2(0, -2.0), 7.5, 3.0, color)
	canvas.draw_line(p + Vector2(-7.5, -7.5), p + Vector2(7.5, -7.5), color.darkened(0.3), 1.0)
	_ellipse(canvas, p + Vector2(0.5, -4.2), 2.4, 1.5, Color(1, 1, 1, 0.8))
	# Объём: тень слева, блик справа.
	canvas.draw_rect(Rect2(p + Vector2(-7.5, -10), Vector2(2.5, 10)), Color(0, 0, 0, 0.14))
	canvas.draw_rect(Rect2(p + Vector2(4.2, -10), Vector2(1.4, 10)), Color(1, 1, 1, 0.2))
	# Тёмная крышка с ободком.
	_ellipse(canvas, p + Vector2(0, -10), 7.8, 3.1, lid)
	canvas.draw_rect(Rect2(p + Vector2(-7.8, -13.5), Vector2(15.6, 3.5)), lid)
	_ellipse(canvas, p + Vector2(0, -13.5), 7.8, 3.1, lid.lightened(0.12))
	_ellipse(canvas, p + Vector2(0, -13.7), 5.4, 2.1, lid.lightened(0.04))
	canvas.draw_arc(p + Vector2(0, -13.7), 5.4, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.25), 1.0)


## Банка табака в новом виде: мягкая тень, тёмный контур, цветная этикетка, крышка с бликом.
static func _draw_jar_modern(canvas: CanvasItem, p: Vector2, color: Color, tin: Color, lid: Color) -> void:
	var outline := color.darkened(0.7)
	_ellipse(canvas, p + Vector2(0, 1.5), 10.5, 4.0, Color(0.06, 0.02, 0.04, 0.3))
	_ellipse(canvas, p + Vector2(0, 0.5), 9.2, 3.5, outline)
	canvas.draw_rect(Rect2(p + Vector2(-8.5, -11), Vector2(17, 11)), outline)
	_ellipse(canvas, p, 8.5, 3.3, tin.darkened(0.1))
	canvas.draw_rect(Rect2(p + Vector2(-7.5, -10), Vector2(15, 10)), tin)
	_ellipse(canvas, p, 7.5, 3.0, tin)
	canvas.draw_rect(Rect2(p + Vector2(-7.5, -8), Vector2(15, 6.5)), color)
	_ellipse(canvas, p + Vector2(0, -1.5), 7.5, 3.0, color.darkened(0.08))
	_ellipse(canvas, p + Vector2(0.5, -4.8), 2.6, 1.6, Color(1, 1, 1, 0.85))
	canvas.draw_rect(Rect2(p + Vector2(-7.5, -10), Vector2(2.6, 10)), Color(0, 0, 0, 0.16))
	canvas.draw_rect(Rect2(p + Vector2(4.3, -10), Vector2(1.4, 10)), Color(1, 1, 1, 0.25))
	_ellipse(canvas, p + Vector2(0, -10.5), 8.4, 3.4, outline)
	canvas.draw_rect(Rect2(p + Vector2(-8.2, -14), Vector2(16.4, 4)), lid)
	_ellipse(canvas, p + Vector2(0, -14), 8.2, 3.2, lid.lightened(0.14))
	canvas.draw_arc(p + Vector2(0, -14.2), 5.6, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.3), 1.0)


## Стальные щипцы для углей, лежащие на столе: пружинная головка и две раскрытые ручки с лопаточками.
static func draw_tongs(canvas: CanvasItem, p: Vector2, flip: bool = false) -> void:
	var dir := Vector2(0.894, 0.447)
	if flip:
		dir = Vector2(0.894, -0.447)
	var normal := Vector2(-dir.y, dir.x)
	var steel := Color("#cfd4dc")
	var shade := Color("#7d8594")
	var head := p
	var tip_a := p + dir * 36.0 + normal * 3.6
	var tip_b := p + dir * 36.0 - normal * 3.6
	var mid_a := p + dir * 18.0 + normal * 1.8
	var mid_b := p + dir * 18.0 - normal * 1.8
	canvas.draw_line(head + Vector2(1, 2), tip_a + Vector2(1, 2), Color(0, 0, 0, 0.22), 2.4)
	canvas.draw_line(head + Vector2(1, 2), tip_b + Vector2(1, 2), Color(0, 0, 0, 0.22), 2.4)
	for tip: Vector2 in [tip_a, tip_b]:
		var mid := mid_a if tip == tip_a else mid_b
		canvas.draw_polyline(PackedVector2Array([head, mid, tip]), shade, 2.4, true)
		canvas.draw_polyline(PackedVector2Array([head, mid, tip]), steel, 1.3, true)
		_ellipse(canvas, tip, 2.6, 1.6, steel)
		_ellipse(canvas, tip, 1.4, 0.8, shade)
	# Пружинная головка (петля) и заклёпка.
	_ellipse(canvas, head - dir * 1.5, 3.0, 2.0, shade)
	_ellipse(canvas, head - dir * 1.5, 1.8, 1.1, steel)
	_ellipse(canvas, head + dir * 5.0, 1.1, 0.8, shade)


## Салфетница: стальной корпус с золотой полоской и стопкой белых салфеток, торчащих веером.
static func draw_napkins(canvas: CanvasItem, p: Vector2) -> void:
	_ellipse(canvas, p + Vector2(0, 1), 10.0, 3.6, Color(0, 0, 0, 0.22))
	var sheet := Color("#f4f1ea")
	for i in 5:
		var x := -5.5 + float(i) * 2.7
		var lift := 6.5 + float(i % 2) * 2.0
		canvas.draw_colored_polygon(PackedVector2Array([
			p + Vector2(x - 1.6, -7.0), p + Vector2(x + 0.2, -7.0 - lift), p + Vector2(x + 2.4, -7.5 - lift * 0.6), p + Vector2(x + 2.0, -7.0)]),
			sheet if i % 2 == 0 else sheet.darkened(0.08))
	canvas.draw_rect(Rect2(p + Vector2(-8.5, -8.0), Vector2(17.0, 8.0)), Color("#4a4f58"))
	canvas.draw_rect(Rect2(p + Vector2(-8.5, -8.0), Vector2(17.0, 2.2)), Color("#7a808c"))
	canvas.draw_rect(Rect2(p + Vector2(-8.5, -3.6), Vector2(17.0, 1.2)), Color("#e8c46a"))
	canvas.draw_rect(Rect2(p + Vector2(-8.5, -8.0), Vector2(2.5, 8.0)), Color(0, 0, 0, 0.16))


## Коробочка с мундштуками: тёмный футляр с золотой окантовкой и цветными мундштуками, торчащими из открытой крышки.
static func draw_mouthpiece_box(canvas: CanvasItem, p: Vector2, colors: Array[Color] = []) -> void:
	_ellipse(canvas, p + Vector2(0, 1), 11.0, 3.8, Color(0, 0, 0, 0.22))
	var slots := maxi(colors.size(), 1)
	for i in colors.size():
		if colors[i].a <= 0.0:
			continue
		var x := -6.0 + float(i) * (12.0 / float(maxi(slots - 1, 1)))
		HookahArt.draw_mouthpiece(canvas, p + Vector2(x, -6.0), Vector2(0.12 * float(i - 2), -1.0), colors[i], 0.45)
	canvas.draw_rect(Rect2(p + Vector2(-9.5, -6.5), Vector2(19.0, 6.5)), Color("#26282e"))
	canvas.draw_rect(Rect2(p + Vector2(-9.5, -6.5), Vector2(19.0, 1.6)), Color("#3c3f48"))
	canvas.draw_rect(Rect2(p + Vector2(-9.5, -3.2), Vector2(19.0, 0.9)), Color("#e8c46a"))
	canvas.draw_rect(Rect2(p + Vector2(-1.4, -4.0), Vector2(2.8, 2.6)), Color("#cfd4dc"))
	canvas.draw_rect(Rect2(p + Vector2(-9.5, -6.5), Vector2(2.6, 6.5)), Color(0, 0, 0, 0.16))


## Ручка шланга: у шланга — серебряное кольцо, затем корпус (пять видов), на кончике — металлический наконечник.
## end — основание ручки, dir — куда она смотрит, shrink — масштаб относительно «полной» длины 22.
## base — преобразование, действующее на холсте (например, масштаб кальяна), чтобы его не потерять.
static func draw_handle(canvas: CanvasItem, end: Vector2, dir: Vector2, style: int, shrink: float, base: Transform2D = Transform2D.IDENTITY) -> void:
	canvas.draw_set_transform_matrix(base * Transform2D(dir.angle(), Vector2(shrink, shrink), 0.0, end))
	var length := 22.0
	var width := 3.8
	var body := Color("#8a2a1f")
	var accent := Color("#3a0f0b")
	match style % HANDLE_STYLES:
		1:
			body = Color("#1c1d22")
			accent = Color("#d6392f")
		2:
			body = Color("#c9ced6")
			accent = Color("#5d6470")
			width = 2.8
		3:
			body = Color("#5c8a3a")
			accent = Color("#2c4a1a")
		4:
			body = Color("#2a3f7a")
			accent = Color("#e8c46a")
	canvas.draw_rect(Rect2(0.0, -width * 0.5, length, width), body)
	match style % HANDLE_STYLES:
		0:
			for x: float in [4.0, 8.0, 12.0, 16.0]:
				canvas.draw_colored_polygon(PackedVector2Array([Vector2(x, -1.6), Vector2(x + 1.3, 0.0), Vector2(x, 1.6), Vector2(x - 1.3, 0.0)]), accent)
		1:
			for x: float in [3.5, 7.5, 11.5, 15.5]:
				canvas.draw_rect(Rect2(x, -width * 0.5, 1.4, width), accent)
		2:
			for x: float in [5.0, 11.0, 17.0]:
				canvas.draw_line(Vector2(x, -width * 0.5), Vector2(x, width * 0.5), accent, 0.8)
		3:
			for x: float in [5.5, 11.0, 16.5]:
				canvas.draw_rect(Rect2(x, -width * 0.5 - 0.4, 1.2, width + 0.8), accent)
		4:
			for x: float in [3.0, 4.6, 16.0, 17.6]:
				canvas.draw_rect(Rect2(x, -width * 0.5 - 0.3, 0.9, width + 0.6), accent)
	canvas.draw_line(Vector2(0.5, -width * 0.5 + 0.7), Vector2(length - 1.0, -width * 0.5 + 0.7), Color(1, 1, 1, 0.28), 0.8)
	canvas.draw_rect(Rect2(-0.4, -width * 0.5 - 0.6, 1.8, width + 1.2), Color("#d7dbe2"))
	canvas.draw_rect(Rect2(length - 1.6, -1.2, 2.2, 2.4), Color("#d7dbe2"))
	canvas.draw_set_transform_matrix(base)
