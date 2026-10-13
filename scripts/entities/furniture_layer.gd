class_name FurnitureLayer
extends Node2D
## M9: мебель в гараже. Создаёт GarageObject для расставленных предметов (по данным FurnitureSystem),
## блокирует клетки на сетке, даёт выбрать предмет кликом в мире и ведёт режим расстановки:
## «призрак» под мышью, подсветка допустимо/нельзя, ЛКМ — поставить, ПКМ или R — повернуть, Esc — отмена.

## Игрок подтвердил место (ЛКМ по допустимой клетке).
signal placement_confirmed(cell: Vector2, rotation: int)
signal placement_cancelled
## Подсказка для UI: "" — можно ставить, иначе причина.
signal hint_changed(problem: String)
## Клик по миру в режиме выбора: uid предмета ("" — мимо) и позиция мыши на экране (для меню).
signal item_clicked(uid: String, screen_position: Vector2)
## Предмет в мире потянули мышью (без меню): Main запускает расстановку в режиме перетаскивания.
signal drag_started(uid: String)

const VALID_COLOR := Color(0.6, 1.0, 0.6, 0.78)
const INVALID_COLOR := Color(1.0, 0.45, 0.45, 0.78)
const SELECTED_COLOR := Color(1.3, 1.2, 0.85)
const HOVER_COLOR := Color(1.22, 1.18, 1.0)
const DRAG_THRESHOLD := 6.0
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.24)
const HALF_GRID_COLOR := Color(1.0, 1.0, 1.0, 0.09)

var system: FurnitureSystem = null
var grid: GarageGrid = null
## Дополнительная проверка поверх правил системы (например, не ставить на персонажей): (item_id, cell, rotation, uid) -> причина или "".
var validator: Callable = Callable()
## Мышь над интерфейсом (панелью или меню)? Тогда мир не подсвечивается, а сброс при перетаскивании отменяет расстановку.
var ui_blocker: Callable = Callable()

var _entities: Node2D = null
var _rugs: Node2D = null
var _grid_node: Node2D = null # сетка рисуется под мебелью и персонажами, над полом
var _nodes: Dictionary = {} # uid -> GarageObject
var _signatures: Dictionary = {} # uid -> строка с клеткой, поворотом и основанием
var _blocked: Dictionary = {} # uid -> Rect2i, занятый на сетке

var _selection_enabled := false
var _selected_uid := ""
var _hover_uid := ""
var _dragging := false
var _press_uid := ""
var _press_mouse := Vector2.ZERO
var _placing := false
var _place_item := ""
var _place_uid := ""
var _place_rotation := 0
var _ghost: GarageObject = null
var _ghost_key := ""
var _ghost_cell := Vector2.ZERO
var _problem := "init"


func setup(furniture_system: FurnitureSystem, garage_grid: GarageGrid, entities: Node2D, rugs: Node2D) -> void:
	system = furniture_system
	grid = garage_grid
	_entities = entities
	_rugs = rugs
	_grid_node = Node2D.new()
	_grid_node.name = "GridLines"
	entities.get_parent().add_child(_grid_node)
	entities.get_parent().move_child(_grid_node, entities.get_index())
	_grid_node.draw.connect(_draw_grid)
	system.changed.connect(sync)
	set_process(false)
	set_process_unhandled_input(false)
	sync()


func is_placing() -> bool:
	return _placing


func placing_uid() -> String:
	return _place_uid


func selected_uid() -> String:
	return _selected_uid


## Режим выбора: ПКМ по мебели в мире выбирает её (открывается меню «переместить / повернуть / убрать»).
func set_selection_enabled(value: bool) -> void:
	_selection_enabled = value
	if not value:
		_press_uid = ""
		set_hover("")
		set_selected("")
	set_process(_selection_enabled or _placing)
	set_process_unhandled_input(_selection_enabled or _placing)
	if _grid_node != null:
		_grid_node.queue_redraw()


## Пунктирная сетка клеток комнаты — видна, пока открыт режим мебели.
func _draw_grid() -> void:
	if system == null or not _selection_enabled or _grid_node == null:
		return
	var w := system.room_size.x
	var h := system.room_size.y
	# Шаг мебели — полклетки: целые линии ярче, половинные бледнее.
	for i in range(w * 2 + 1):
		var x := float(i) * 0.5
		var color := GRID_COLOR if i % 2 == 0 else HALF_GRID_COLOR
		_grid_node.draw_dashed_line(IsoProjection.grid_to_screen(Vector2(x, 0)), IsoProjection.grid_to_screen(Vector2(x, h)), color, 1.0, 5.0)
	for j in range(h * 2 + 1):
		var y := float(j) * 0.5
		var color := GRID_COLOR if j % 2 == 0 else HALF_GRID_COLOR
		_grid_node.draw_dashed_line(IsoProjection.grid_to_screen(Vector2(0, y)), IsoProjection.grid_to_screen(Vector2(w, y)), color, 1.0, 5.0)
	_draw_wall_hint(w, h)


## Подсказка при расстановке: стены, к которым можно поставить предмет (диван — только спинкой к стене, картина — на любую).
func _draw_wall_hint(w: int, h: int) -> void:
	if not _placing:
		return
	var item := system.item(_place_item)
	var back_wall := Color(1.0, 0.82, 0.35, 0.85)
	var left_wall := back_wall
	if bool(item.get("wall_back", false)):
		# Диван: при повороте 0 — к дальней стене (y = 0), при повороте 1 — к левой (x = 0).
		if _place_rotation == 0:
			left_wall = Color(0, 0, 0, 0)
		else:
			back_wall = Color(0, 0, 0, 0)
	elif str(item.get("placement", "floor")) != "wall":
		return
	if back_wall.a > 0.0:
		_grid_node.draw_line(IsoProjection.grid_to_screen(Vector2(0, 0)), IsoProjection.grid_to_screen(Vector2(w, 0)), back_wall, 4.0, true)
	if left_wall.a > 0.0:
		_grid_node.draw_line(IsoProjection.grid_to_screen(Vector2(0, 0)), IsoProjection.grid_to_screen(Vector2(0, h)), left_wall, 4.0, true)


func set_selected(uid: String) -> void:
	var previous := _selected_uid
	_selected_uid = uid if _nodes.has(uid) else ""
	_tint(previous)
	_tint(_selected_uid)


## Подсветка предмета под курсором (в режиме выбора).
func set_hover(uid: String) -> void:
	var previous := _hover_uid
	_hover_uid = uid if _nodes.has(uid) else ""
	_tint(previous)
	_tint(_hover_uid)


func _tint(uid: String) -> void:
	if not _nodes.has(uid):
		return
	var color := Color.WHITE
	if uid == _selected_uid:
		color = SELECTED_COLOR
	elif uid == _hover_uid:
		color = HOVER_COLOR
	(_nodes[uid] as Node2D).modulate = color


## Приводит узлы в мире в соответствие с system.placed_entries().
func sync() -> void:
	if system == null:
		return
	var wanted: Dictionary = {}
	for entry in system.placed_entries():
		wanted[str(entry["uid"])] = entry
	for uid in _nodes.keys():
		if not wanted.has(uid):
			_remove_node(str(uid))
	for uid in wanted:
		var entry: Dictionary = wanted[uid]
		var signature := "%s:%s:%s:%s:%s" % [str(entry["item"]), str(entry["cell"]), str(entry["rotation"]), str(entry.get("host", "")), system.chair_facing(entry)]
		if _signatures.get(uid, "") == signature:
			continue
		_remove_node(str(uid))
		_add_node(entry, signature)
	set_selected(_selected_uid)


## Нода поставленного предмета по uid (null — такого нет).
func node_of(uid: String) -> GarageObject:
	return _nodes.get(uid) as GarageObject


func _add_node(entry: Dictionary, signature: String) -> void:
	var uid := str(entry["uid"])
	var definition := system.object_definition(entry)
	var node := GarageObject.new()
	var data: Dictionary = system.item(str(entry["item"]))
	var parent: Node2D = _rugs if bool(data["flat"]) else _entities
	parent.add_child(node)
	node.setup(definition)
	_nodes[uid] = node
	_signatures[uid] = signature
	if bool(definition["blocks"]):
		var rect := system.cover_cells(system.entry_rect(entry))
		grid.set_blocked_rect(rect, true)
		_blocked[uid] = rect


func _remove_node(uid: String) -> void:
	if _nodes.has(uid):
		(_nodes[uid] as Node).queue_free()
		_nodes.erase(uid)
	_signatures.erase(uid)
	if _blocked.has(uid):
		grid.set_blocked_rect(_blocked[uid], false)
		_blocked.erase(uid)


# --- Выбор предмета в мире --------------------------------------------------

## uid предмета под мышью ("" — нет). Предметы на столе важнее стола, ковёр — самый нижний слой.
func pick_at_mouse() -> String:
	var mouse := get_local_mouse_position()
	var grid_pos := IsoProjection.screen_to_grid(mouse)
	var best := ""
	var best_score := -INF
	for uid in _nodes:
		var node := _nodes[uid] as GarageObject
		var entry := system.entry_of(str(uid))
		if entry.is_empty() or not node.visible:
			continue
		var data: Dictionary = system.item(str(entry["item"]))
		var rect := system.entry_rect(entry)
		var score := node.position.y
		var hit := false
		if bool(data["flat"]):
			hit = rect.has_point(grid_pos)
			score -= 10000.0
		else:
			hit = _upright_bounds(node, rect).has_point(mouse)
			if str(entry.get("host", "")) != "":
				score += 5000.0
		if hit and score > best_score:
			best_score = score
			best = str(uid)
	return best


## Экранный прямоугольник стоящего предмета: основание (ромб) плюс высота.
func _upright_bounds(node: GarageObject, rect: Rect2) -> Rect2:
	var corners: Array[Vector2] = [
		IsoProjection.grid_to_screen(Vector2(rect.position)),
		IsoProjection.grid_to_screen(Vector2(rect.end.x, rect.position.y)),
		IsoProjection.grid_to_screen(Vector2(rect.end)),
		IsoProjection.grid_to_screen(Vector2(rect.position.x, rect.end.y))]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		bounds = bounds.expand(corner)
	var lift_origin := node.position.y - IsoProjection.grid_to_screen(Vector2(rect.position) + Vector2(rect.size) * 0.5).y
	bounds = bounds.expand(Vector2(bounds.position.x, node.position.y + node.top_y - 4.0 - lift_origin))
	return bounds


# --- Режим расстановки ------------------------------------------------------

## uid — id купленного предмета (его, пока ставим, временно скрываем на прежнем месте).
func begin_placement(uid: String, dragging: bool = false) -> void:
	var entry := system.entry_of(uid)
	if entry.is_empty():
		return
	cancel_placement(false)
	set_selected("")
	set_hover("")
	_press_uid = ""
	_dragging = dragging
	_place_uid = uid
	_place_item = str(entry["item"])
	_place_rotation = system.normalize_rotation(_place_item, int(entry["rotation"]))
	_placing = true
	_ghost_key = ""
	_problem = "init"
	if _grid_node != null:
		_grid_node.queue_redraw()
	if _nodes.has(uid):
		(_nodes[uid] as Node2D).visible = false
	set_process(true)
	set_process_unhandled_input(true)


func cancel_placement(emit: bool = true) -> void:
	if not _placing:
		return
	_placing = false
	_dragging = false
	if _grid_node != null:
		_grid_node.queue_redraw()
	set_process(_selection_enabled)
	set_process_unhandled_input(_selection_enabled)
	if _nodes.has(_place_uid):
		(_nodes[_place_uid] as Node2D).visible = true
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_key = ""
	_place_uid = ""
	_place_item = ""
	if emit:
		placement_cancelled.emit()


func rotate_placement() -> void:
	if _placing and bool(system.item(_place_item)["rotation_allowed"]):
		_place_rotation = (_place_rotation + 1) % 2
		if _grid_node != null:
			_grid_node.queue_redraw()


## Клетка, к которой привязан предмет под мышью (центр предмета у курсора; у стенных предметов — к стене).
func cell_under_mouse(item_id: String, rotation: int) -> Vector2:
	var mouse := IsoProjection.screen_to_grid(get_local_mouse_position())
	var size := Vector2(system.footprint(item_id, rotation))
	var step := FurnitureSystem.STEP
	var cell := Vector2(snappedf(mouse.x - size.x * 0.5, step), snappedf(mouse.y - size.y * 0.5, step))
	cell.x = clampf(cell.x, 0.0, maxf(float(system.room_size.x) - size.x, 0.0))
	cell.y = clampf(cell.y, 0.0, maxf(float(system.room_size.y) - size.y, 0.0))
	if str(system.item(item_id)["placement"]) == "wall":
		if system.normalize_rotation(item_id, rotation) == 0:
			cell.y = 0.0
		else:
			cell.x = 0.0
	return cell


func _process(_delta: float) -> void:
	if not _placing:
		_update_hover()
		return
	_ghost_cell = cell_under_mouse(_place_item, _place_rotation)
	var info := system.placement_info(_place_item, _ghost_cell, _place_rotation, _place_uid)
	var problem := str(info["problem"])
	if problem == "" and validator.is_valid():
		problem = str(validator.call(_place_item, _ghost_cell, _place_rotation, _place_uid))
	var key := "%.1f:%.1f:%d:%s" % [_ghost_cell.x, _ghost_cell.y, _place_rotation, str(info["host"])]
	if key != _ghost_key:
		_rebuild_ghost(system.surface_lift(str(info["host"])))
		_ghost_key = key
	if _ghost != null:
		_ghost.modulate = VALID_COLOR if problem == "" else INVALID_COLOR
	if problem != _problem:
		_problem = problem
		hint_changed.emit(problem)


func _update_hover() -> void:
	if not _selection_enabled:
		return
	if ui_blocker.is_valid() and bool(ui_blocker.call()):
		set_hover("")
		return
	set_hover(pick_at_mouse())


## Поставить предмет там, где сейчас «призрак» (если можно). true — подтверждено.
func confirm_current() -> bool:
	if not _placing or _problem != "":
		return false
	placement_confirmed.emit(_ghost_cell, _place_rotation)
	return true


## Отпускание кнопки при перетаскивании: над интерфейсом — отмена, над допустимым местом — поставить, иначе остаёмся в режиме расстановки.
func _input(event: InputEvent) -> void:
	if not _dragging or not _placing:
		return
	var mouse_button := event as InputEventMouseButton
	# Пока кнопка зажата, правый клик может уйти в интерфейс (карточку), поэтому поворот при перетаскивании ловим здесь.
	if mouse_button != null and mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		rotate_placement()
		return
	if mouse_button != null and not mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		if ui_blocker.is_valid() and bool(ui_blocker.call()):
			cancel_placement()
		elif _problem == "":
			confirm_current()
		else:
			hint_changed.emit(_problem)


func _rebuild_ghost(lift: float) -> void:
	if _ghost != null:
		_ghost.queue_free()
	_ghost = GarageObject.new()
	add_child(_ghost)
	_ghost.z_index = 50
	_ghost.setup(system.definition_for(_place_item, _ghost_cell, _place_rotation, "ghost", lift))


func _unhandled_input(event: InputEvent) -> void:
	if _placing:
		_placing_input(event)
		return
	if not _selection_enabled:
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
		# ПКМ по предмету — меню (переместить / повернуть / убрать), мимо — закрыть меню.
		get_viewport().set_input_as_handled()
		var menu_uid := pick_at_mouse()
		_press_uid = ""
		set_selected(menu_uid)
		item_clicked.emit(menu_uid, get_viewport().get_mouse_position())
	elif mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if mouse_button.pressed:
			# ЛКМ: потянуть предмет; простой клик без движения только подсвечивает (меню — по ПКМ).
			get_viewport().set_input_as_handled()
			var uid := pick_at_mouse()
			set_selected(uid)
			_press_uid = uid
			_press_mouse = get_viewport().get_mouse_position()
			if uid == "":
				item_clicked.emit("", _press_mouse)
		else:
			_press_uid = ""
	elif event is InputEventMouseMotion and _press_uid != "":
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_press_uid = ""
		elif get_viewport().get_mouse_position().distance_to(_press_mouse) > DRAG_THRESHOLD:
			var dragged := _press_uid
			_press_uid = ""
			drag_started.emit(dragged)


func _placing_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if _problem == "":
				var cell := _ghost_cell
				var rotation := _place_rotation
				placement_confirmed.emit(cell, rotation)
			else:
				hint_changed.emit(_problem)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			rotate_placement()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_R:
			get_viewport().set_input_as_handled()
			rotate_placement()
		elif key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			cancel_placement()
