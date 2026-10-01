class_name BowlView
extends Control
## Чаша кальяна сверху: рисует состояние ручного приготовления и принимает действия мышью
## (перетаскивание порций/углей, удержание, протяжка, клики). Логика и оценки — в ManualPreparation.

signal acted(kind: String)

const RADIUS := 170.0
const GOOD := Color(0.5, 0.9, 0.5, 0.85)
## Сторона квадрата угля в пикселях.
const COAL_SIZE := 115.0

var state: ManualPreparation = null
var step: String = "mix"
## Показывать зоны-подсказки на шкале.
var hints_on: bool = true
var recipe_targets: Dictionary = {}
## ingredient_id -> эмодзи, показывается в кружках чаши на шаге состава.
var ingredient_emojis: Dictionary = {}

var _holding: bool = false
## Уголь, снятый с плитки щипцами и ещё не брошенный (вернётся на место, если бросок не удался).
var _drag_pending: bool = false
## Короткое сообщение о запрещённом действии (например, «сначала выключи плитку»).
var _notice: String = ""
var _notice_time: float = 0.0
var _drag_origin: Vector2 = Vector2.ZERO
var _stove_style: StyleBoxFlat = null
var _tick: float = 0.0
var _time: float = 0.0
var _crumbs: Array[Vector3] = [] # x, y (нормализованно), размер


func _ready() -> void:
	custom_minimum_size = Vector2(480, 560)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 120:
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * 0.92
		_crumbs.append(Vector3(cos(angle) * dist, sin(angle) * dist, rng.randf_range(2.0, 5.0)))


func center_point() -> Vector2:
	return Vector2(size.x * 0.5, RADIUS + 26.0)


func _to_normalized(point: Vector2) -> Vector2:
	return (point - center_point()) / RADIUS


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if state == null or not (data is Dictionary):
		return false
	var kind: String = str(data.get("kind", ""))
	if step == "mix" and kind == "portion":
		return state.slots.has("")
	var norm := _to_normalized(at_position)
	if norm.length() > 1.05:
		return false
	var spot := clamp_coal(norm)
	if step == "light":
		if state.stove_on:
			return false
		if kind == "coal":
			return state.can_place_cold_coal() and not coal_overlaps(spot, state.stove_coals)
		if kind == "stove_coal" or kind == "cold_stove_coal":
			return not coal_overlaps(spot, state.stove_coals)
		if kind == "hot_coal":
			return state.hot_coals > 0 and not coal_overlaps(spot, state.stove_coals)
	if step == "coals" and kind == "hot_coal":
		return state.hot_coals > 0 and state.coals.size() < state.config.manual_max_coals and not coal_overlaps(spot, state.coals)
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if state == null or not (data is Dictionary):
		return
	var kind: String = str(data.get("kind", ""))
	if kind == "portion":
		# Порция ложится в ближайший к месту сброса свободный кружок.
		if state.add_portion(str(data["id"]), _nearest_free_slot(at_position)):
			acted.emit("drop")
		return
	var spot := clamp_coal(_to_normalized(at_position))
	if step == "light" and (kind == "coal" or kind == "stove_coal" or kind == "cold_stove_coal" or kind == "hot_coal"):
		if not coal_overlaps(spot, state.stove_coals):
			# Уголь, вернувшийся на плитку (в том числе из ведёрка), снова греется.
			if kind == "hot_coal":
				state.hot_coals -= 1
			state.stove_coals.append(spot)
			acted.emit("coal")
	elif step == "coals" and kind == "hot_coal":
		if not coal_overlaps(spot, state.coals) and state.add_coal(spot):
			acted.emit("coal")


## Щипцы: уголь на плитке берётся и тащится в ведёрко горячих углей.
func _get_drag_data(at_position: Vector2) -> Variant:
	if state == null or step != "light":
		return null
	if state.stove_on:
		for i in state.stove_coals.size():
			if _coal_hit(at_position, state.stove_coals[i]):
				_say("Сначала выключи плитку")
				return null
		return null
	for i in range(state.stove_coals.size() - 1, -1, -1):
		if _coal_hit(at_position, state.stove_coals[i]):
			_drag_pending = true
			state.lock_temperature()
			_drag_origin = state.stove_coals[i]
			state.stove_coals.remove_at(i)
			_holding = false
			var holder := Control.new()
			var tongs := CoalBucket.TongsPreview.new()
			tongs.hot = state.heat_seconds > 0.0
			tongs.position = Vector2(-COAL_SIZE * 0.5, -COAL_SIZE * 0.5)
			holder.add_child(tongs)
			set_drag_preview(holder)
			# Ещё не грелись — вернуть можно в ведёрко со свежими углями, иначе в ведёрко горячих.
			return {"kind": "cold_stove_coal" if state.heat_seconds <= 0.0 else "stove_coal"}
	return null


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_holding = false
	elif what == NOTIFICATION_DRAG_END and _drag_pending:
		_drag_pending = false
		# Уголь не попал в ведёрко или на плитку — возвращается туда, откуда взят.
		if state != null and not get_viewport().gui_is_drag_successful():
			state.stove_coals.append(_drag_origin)


func _say(text: String) -> void:
	_notice = text
	_notice_time = 2.5


## Подсказка по ходу розжига: что делать дальше.
func _light_status() -> String:
	if _notice_time > 0.0:
		return _notice
	if state.is_burnt():
		return "Подгорело! Выключи плитку" if state.stove_on else "Подгорело!"
	if state.temperature_locked:
		return "Температура зафиксирована"
	if state.stove_coals.is_empty():
		if state.hot_coals > 0 or not state.coals.is_empty():
			return "Горячие угли в ведёрке — можно дальше"
		return "Положи угли на плитку"
	if state.stove_on:
		if state.coil_temp < 1.0:
			return "Плитка разогревается…"
		if state.heat_seconds >= ManualPreparation.MIN_HEAT_SECONDS:
			return "Выключи плитку в зелёной зоне"
		return "Угли греются"
	if state.heat_seconds > 0.0:
		return "Угли остывают — сними их в ведёрко"
	return "Включи плитку"


func _coal_hit(point: Vector2, coal: Vector2) -> bool:
	var offset := point - (center_point() + coal * RADIUS)
	return absf(offset.x) <= COAL_SIZE * 0.5 and absf(offset.y) <= COAL_SIZE * 0.5


## Пересекается ли квадрат угла в этой точке с уже лежащими (квадраты выровнены по осям).
func coal_overlaps(norm: Vector2, others: Array[Vector2]) -> bool:
	for other in others:
		var delta := (other - norm) * RADIUS
		if absf(delta.x) < COAL_SIZE and absf(delta.y) < COAL_SIZE:
			return true
	return false


## Уголь целиком остаётся в чаше: центр сдвигается внутрь так, чтобы самый дальний край квадрата лёг на край чаши.
func clamp_coal(norm: Vector2) -> Vector2:
	if norm.is_zero_approx():
		return norm
	var direction := norm.normalized()
	var half := COAL_SIZE * 0.5
	var limit := (RADIUS - half * (absf(direction.x) + absf(direction.y))) / RADIUS
	return direction * minf(norm.length(), maxf(limit, 0.0))


func slot_center(slot: int) -> Vector2:
	var slots := state.config.manual_portions
	var angle := TAU * float(slot) / float(slots) - PI * 0.25
	return center_point() + Vector2(cos(angle), sin(angle)) * RADIUS * 0.46


func _nearest_free_slot(point: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for slot in state.slots.size():
		if state.slots[slot] != "":
			continue
		var distance := slot_center(slot).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = slot
	return best


func _slot_at(point: Vector2) -> int:
	for slot in state.slots.size():
		if slot_center(slot).distance_to(point) <= RADIUS * 0.27:
			return slot
	return -1


func _gui_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		else:
			_holding = false


func _on_press(point: Vector2) -> void:
	match step:
		"mix":
			# Клик по занятому кружку возвращает порцию обратно.
			var slot := _slot_at(point)
			if slot >= 0 and state.remove_portion(slot):
				acted.emit("drop")
		"coals":
			# Клик по углю в чаше возвращает его в ведёрко.
			for i in range(state.coals.size() - 1, -1, -1):
				if _coal_hit(point, state.coals[i]):
					if state.remove_coal(i):
						acted.emit("drop")
					break
		"light":
			# Кнопка плитки; за уголь можно потянуть — он берётся щипцами.
			if _switch_rect().has_point(point) and state.toggle_stove():
				acted.emit("hole")
		"pack":
			_holding = true
		"foil":
			_holding = true
		"holes":
			var norm := _to_normalized(point)
			if norm.length() <= 0.98 and state.add_hole(norm):
				acted.emit("hole")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if _notice_time > 0.0:
		_notice_time -= delta
	if state != null and step == "light":
		state.tick_stove(delta)
	if state != null and _holding:
		if step == "pack":
			state.pack(delta)
		elif step == "foil":
			state.tighten(delta)
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.18
			acted.emit("pack" if step == "pack" else "foil")
	queue_redraw()


# --- Рисование ----------------------------------------------------------------------------------

func _draw() -> void:
	if state == null:
		return
	var c := center_point()
	if step == "light":
		_draw_stove(c)
		_draw_coal_list(c, state.stove_coals)
		_draw_gauge(c)
		return
	draw_circle(c + Vector2(0, 8), RADIUS + 22.0, Color(0, 0, 0, 0.35))
	draw_circle(c, RADIUS + 16.0, Color("#8a4a2a"))
	draw_circle(c, RADIUS + 6.0, Color("#b5653a"))
	draw_circle(c, RADIUS, Color("#3a2316"))
	var step_index := ManualPreparation.STEPS.find(step)
	_draw_contents(c, step_index)
	if step_index >= ManualPreparation.STEPS.find("foil") and step != "mix":
		_draw_foil(c)
	_draw_holes(c)
	_draw_coal_list(c, state.coals)
	_draw_gauge(c)


func _portion_color(ingredient_id: String) -> Color:
	return Color.from_hsv(float(absi(hash(ingredient_id)) % 360) / 360.0, 0.55, 0.85)


func _draw_contents(c: Vector2, step_index: int) -> void:
	if step == "mix":
		for slot in state.slots.size():
			var at := slot_center(slot)
			var ingredient_id := state.slots[slot]
			if ingredient_id != "":
				draw_circle(at, RADIUS * 0.27, _portion_color(ingredient_id).darkened(0.25))
				draw_arc(at, RADIUS * 0.27, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
				var font := get_theme_default_font()
				if font != null:
					var emoji := str(ingredient_emojis.get(ingredient_id, "?"))
					draw_string(font, at + Vector2(-26, 16), emoji, HORIZONTAL_ALIGNMENT_CENTER, 52, 48, Color.WHITE)
			else:
				draw_arc(at, RADIUS * 0.27, 0.0, TAU, 32, Color(1, 1, 1, 0.25), 2.0)
		return
	# Табак: цвет — смесь выбранных порций, заполнение — по уровню набивки.
	var tobacco := Color("#6a4a2a")
	if not state.portions.is_empty():
		var r := 0.0
		var g := 0.0
		var b := 0.0
		var n := 0.0
		for ingredient_id in state.portions:
			var color := _portion_color(str(ingredient_id)).darkened(0.35)
			var weight := float(state.portions[ingredient_id])
			r += color.r * weight
			g += color.g * weight
			b += color.b * weight
			n += weight
		tobacco = Color(r / n, g / n, b / n)
	var fill_shown := state.fill if step_index >= ManualPreparation.STEPS.find("pack") else 0.0
	draw_circle(c, RADIUS * (0.35 + 0.6 * fill_shown), tobacco.darkened(0.25 * (1.0 - fill_shown)))
	for crumb in _crumbs:
		if Vector2(crumb.x, crumb.y).length() <= 0.35 + 0.6 * fill_shown:
			draw_circle(c + Vector2(crumb.x, crumb.y) * RADIUS, crumb.z, tobacco.lightened(0.18))


func _draw_foil(c: Vector2) -> void:
	var tension := state.tension
	var foil_color := Color(0.8, 0.82, 0.86, 0.3 + 0.6 * tension)
	draw_circle(c, RADIUS * 1.02, foil_color)
	# Складки: чем слабее натяжение, тем их больше.
	var wrinkle := Color(1, 1, 1, 0.5 * (1.0 - tension))
	for i in 14:
		var angle := TAU * float(i) / 14.0 + 0.2
		var inner := RADIUS * 0.15
		var outer := RADIUS * (0.5 + 0.45 * (1.0 - tension) * (0.6 + 0.4 * sin(float(i) * 2.3)))
		draw_line(c + Vector2(cos(angle), sin(angle)) * inner, c + Vector2(cos(angle + 0.12), sin(angle + 0.12)) * outer, wrinkle, 2.0)
	draw_arc(c, RADIUS * 1.02, 0.0, TAU, 64, Color(1, 1, 1, 0.6), 2.0)


func _draw_holes(c: Vector2) -> void:
	for hole in state.holes:
		draw_circle(c + hole * RADIUS, 6.0, Color("#1a1512"))
		draw_arc(c + hole * RADIUS, 6.0, 0.0, TAU, 12, Color(1, 1, 1, 0.5), 1.5)


func _draw_coal_list(c: Vector2, list: Array[Vector2]) -> void:
	var heat := clampf(state.heat_seconds / state.config.manual_light_seconds_per_level / 2.0, 0.0, 1.0)
	for coal in list:
		var at := c + coal * RADIUS
		var body := Color("#2b2b2e")
		if state.is_burnt():
			body = Color("#0e0e0f")
		elif heat > 0.0:
			body = Color("#2b2b2e").lerp(Color("#d9541a"), heat * 0.8)
		if heat > 0.0 and not state.is_burnt():
			draw_circle(at, COAL_SIZE * 0.85 + 8.0 * sin(_time * 8.0), Color(1.0, 0.5, 0.15, 0.22 * heat))
		var half := Vector2(COAL_SIZE, COAL_SIZE) * 0.5
		draw_rect(Rect2(at - half, half * 2.0), body)
		draw_rect(Rect2(at - half + Vector2(6, 6), half * 2.0 - Vector2(12, 12)), body.lightened(0.12))
		draw_rect(Rect2(at - half, half * 2.0), Color(1, 0.6, 0.3, 0.5 * heat + 0.15), false, 3.0)


## Где на экране кнопка включения плитки.
func _switch_rect() -> Rect2:
	return Rect2(center_point() + Vector2(-RADIUS - 22.0 + 22.0, RADIUS + 19.0), Vector2(78.0, 28.0))


## Электроплитка для углей (вид сверху): корпус, спираль, кнопка, лампа и ручка.
func _draw_stove(c: Vector2) -> void:
	var coil_heat := state.coil_temp
	if _stove_style == null:
		_stove_style = StyleBoxFlat.new()
		_stove_style.bg_color = Color("#2a2d33")
		_stove_style.border_color = Color("#14161a")
		_stove_style.set_border_width_all(4)
		_stove_style.set_corner_radius_all(30)
		_stove_style.shadow_color = Color(0, 0, 0, 0.4)
		_stove_style.shadow_size = 10
	var body_half := RADIUS + 22.0
	draw_style_box(_stove_style, Rect2(c + Vector2(-body_half, -body_half + 6.0), Vector2(body_half * 2.0, body_half * 2.0 + 28.0)))
	# Конфорка: ободок, тёмное дно, спираль; разогревается — краснеет.
	draw_circle(c, RADIUS, Color("#6b7079"))
	draw_circle(c, RADIUS - 8.0, Color("#15171a"))
	var coil := Color("#5b5f68").lerp(Color("#ff5a1f"), coil_heat)
	if coil_heat > 0.0:
		draw_circle(c, RADIUS - 10.0, Color(1.0, 0.35, 0.1, 0.14 * coil_heat))
	for k in 4:
		draw_arc(c, RADIUS * (0.2 + 0.2 * float(k)), 0.0, TAU, 48, coil, 9.0)
	for k in 6:
		var angle := TAU * float(k) / 6.0 + 0.3
		draw_line(c + Vector2.from_angle(angle) * RADIUS * 0.2, c + Vector2.from_angle(angle) * RADIUS * 0.8, coil.darkened(0.15), 6.0)
	# Нижняя панель: кнопка ВЫКЛ/ВКЛ слева и светодиод справа.
	var panel_y := c.y + RADIUS + 33.0
	var switch_rect := _switch_rect()
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var usable := state.stove_on or not state.stove_coals.is_empty()
	draw_rect(switch_rect, Color("#1a1b1e") if usable else Color("#141517"))
	var half_rect := Rect2(switch_rect.position + Vector2(3, 3), Vector2(switch_rect.size.x * 0.5 - 4.0, switch_rect.size.y - 6.0))
	if state.stove_on:
		half_rect.position.x += switch_rect.size.x * 0.5 - 2.0
		draw_rect(half_rect, Color("#e0322a"))
	else:
		draw_rect(half_rect, Color("#4a4d55") if usable else Color("#2a2c31"))
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, switch_rect.position + Vector2(6, 20), "ВЫКЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8) if usable else Color(0.4, 0.4, 0.4))
		draw_string(font, switch_rect.position + Vector2(switch_rect.size.x - 32.0, 20), "ВКЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE if state.stove_on else Color(0.5, 0.5, 0.5))
	var lamp := Vector2(c.x + body_half - 40.0, panel_y)
	if state.stove_on:
		draw_circle(lamp, 20.0, Color(1.0, 0.2, 0.15, 0.25 + 0.1 * pulse))
		draw_circle(lamp, 10.0, Color("#ff3b2f"))
		draw_circle(lamp + Vector2(-3, -3), 3.5, Color(1, 0.8, 0.75))
	else:
		draw_circle(lamp, 10.0, Color("#3a1512"))


## Шкала внизу: текущее значение шага и (с подсказкой) зона цели.
func _draw_gauge(c: Vector2) -> void:
	var info := gauge_info()
	if info.is_empty():
		return
	var width := 380.0
	var gauge_gap := 76.0 if step == "light" else 34.0
	var rect := Rect2(Vector2(c.x - width * 0.5, c.y + RADIUS + gauge_gap), Vector2(width, 22.0))
	draw_rect(rect, Color(0.12, 0.1, 0.09))
	if hints_on:
		var zone_left := clampf(float(info["zone_center"]) - float(info["zone_half"]), 0.0, 1.0)
		var zone_right := clampf(float(info["zone_center"]) + float(info["zone_half"]), 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(zone_left * width, 0), Vector2((zone_right - zone_left) * width, rect.size.y)), GOOD)
	var value := clampf(float(info["value"]), 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(value * width, rect.size.y)), Color(1.0, 0.85, 0.4, 0.75))
	draw_rect(rect, Color(1, 1, 1, 0.5), false, 2.0)
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, rect.position + Vector2(0, rect.size.y + 26.0), str(info["caption"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.8, 0.7))
		var status := str(info.get("status", ""))
		if not status.is_empty():
			draw_string(font, rect.position + Vector2(0, rect.size.y + 54.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.5))


## {"value", "zone_center", "zone_half", "caption"} в долях шкалы 0..1; пусто — шкалы у шага нет.
func gauge_info() -> Dictionary:
	if state == null:
		return {}
	var prep := state.config
	var tolerance := prep.manual_tolerance(ManualPreparation._parameter_of(step))
	var target := state.hint_target(step, recipe_targets)
	match step:
		"pack":
			return {"value": state.fill, "zone_center": target, "zone_half": tolerance / 2.0, "caption": "Набивка: %d%%" % int(round(state.fill * 100.0))}
		"foil":
			return {"value": state.tension, "zone_center": target, "zone_half": tolerance / 2.0, "caption": "Натяжение фольги: %d%%" % int(round(state.tension * 100.0))}
		"holes":
			var max_holes := float(prep.manual_holes_max)
			var half_holes := tolerance / 2.0 * float(prep.manual_holes_max - prep.manual_holes_min)
			return {"value": float(state.holes.size()) / max_holes, "zone_center": target / max_holes, "zone_half": half_holes / max_holes, "caption": "Отверстий: %d (нужно %d–%d)" % [state.holes.size(), prep.manual_holes_min, prep.manual_holes_max]}
		"light":
			var burn := prep.manual_light_burn_seconds
			var degrees := int(round(lerpf(25.0, 400.0, state.heat_seconds / burn)))
			var status := _light_status()
			return {"value": state.heat_seconds / burn, "zone_center": target / burn, "zone_half": tolerance * prep.manual_light_seconds_per_level / burn, "caption": "Температура углей: %d°C" % degrees, "status": status}
	return {}
