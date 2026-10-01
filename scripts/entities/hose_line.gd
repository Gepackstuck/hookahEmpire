class_name HoseLine
extends Node2D
## Шланг кальяна: тонкая кривая от клапана до свободного конца с мундштуком. Концы двигает GarageWorld
## (шланг лежит на столе, висит в руке или идёт ко рту курящего). Все точки — в координатах Entities.
## Если свободный конец левее клапана (курящий по другую сторону кальяна), шланг заходит за колбу:
## кальян перерисовывается поверх шланга (cover_*), и шланг «обвивает» его сзади.

const WIDTH_OUTLINE := 2.2
const WIDTH_INNER := 1.3
const PIECE_SCALE := 0.38
## Длина мундштука на экране (от стыка со шлангом до кончика).
const PIECE_LENGTH := 13.9 * PIECE_SCALE
## Жёсткая ручка на конце шланга (за неё держат); мундштук надет на её кончик. Хват — на GRIP_OFFSET от шланга.
const HANDLE_LENGTH := 11.0
const GRIP_OFFSET := 5.0
const HANDLE_STYLES := 5

var color := Color("#22b8ff")
var start := Vector2.ZERO
var end := Vector2.ZERO
## Цвет смолы мундштука на конце; нулевая прозрачность — мундштука нет (голый конец).
var piece := Color(0, 0, 0, 0)
var piece_dir := Vector2.LEFT
## Шланг просто лежит на столе, а не провисает между руками.
var lying := false
## Лежит ровной S-образной змейкой (на столе для кальянов), а не петлёй у колбы.
var flat := false
var shown := false
## Вид ручки (0..HANDLE_STYLES-1): у каждого кальяна своя.
var handle_style := 0
## Кальян, за которым шланг может прятаться: его основание, цвет и приседание.
var cover_enabled := false
var cover_base := Vector2.ZERO
var cover_color := Color("#22b8ff")
var cover_squash := 0.0
var cover_top := 0


func _init() -> void:
	z_index = 3


func show_hose(value: bool) -> void:
	shown = value
	queue_redraw()


## Шланг идёт за кальяном: конец левее клапана, и есть кальян, который можно нарисовать поверх.
func is_wrapped() -> bool:
	return cover_enabled and not lying and end.x < start.x - 8.0


func curve() -> PackedVector2Array:
	var d := end - start
	if is_wrapped():
		var via := cover_base + Vector2(0.0, -11.0)
		var first := HookahArt.bezier([start, start + Vector2(12.0, 2.0), via + Vector2(9.0, 0.0), via])
		var second := HookahArt.bezier([via, via + Vector2(-9.0, 0.0), end + Vector2(12.0, minf(14.0, maxf(2.0, (end.y - via.y) * 0.4 + 8.0))), end])
		for i in range(1, second.size()):
			first.append(second[i])
		return first
	var c1: Vector2
	var c2: Vector2
	if lying and flat:
		var dir := d.normalized()
		var normal := Vector2(-dir.y, dir.x)
		c1 = start + d * 0.33 + normal * 7.0
		c2 = start + d * 0.66 - normal * 7.0
	elif lying:
		c1 = start + Vector2(26.0, 6.0)
		c2 = end + Vector2(18.0, 16.0)
	else:
		var sag := clampf(d.length() * 0.6, 12.0, 30.0)
		c1 = start + Vector2(d.x * 0.2, sag * 0.6 - 4.0)
		c2 = end + Vector2(-d.x * 0.2, sag)
	return HookahArt.bezier([start, c1, c2, end])


func _draw() -> void:
	if not shown:
		return
	var points := curve()
	draw_polyline(points, color.darkened(0.45), WIDTH_OUTLINE, true)
	draw_polyline(points, color, WIDTH_INNER, true)
	draw_circle(start, 1.6, Color("#c9ced6"))
	_draw_handle()
	var tip := end + piece_dir * HANDLE_LENGTH
	if piece.a > 0.0:
		HookahArt.draw_mouthpiece(self, tip, piece_dir, piece, PIECE_SCALE)
	if is_wrapped():
		HookahArt.draw_hookah(self, cover_base, cover_color, false, cover_squash, 0, 0.0, cover_top)


func _draw_handle() -> void:
	HookahArt.draw_handle(self, end, piece_dir, handle_style, HANDLE_LENGTH / 22.0)
