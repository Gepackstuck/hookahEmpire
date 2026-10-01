class_name FurnitureScreen
extends PanelContainer
## M9: панель мебели на всю левую сторону экрана. Две вкладки: «Магазин» и «В наличии» (купленное).
## Предметы — карточки-сетка с миниатюрами (рисуются тем же GarageObject, что и в мире).
## Из «В наличии» карточку можно потянуть в гараж (drag_started) или нажать (place_requested).
## Пока идёт расстановка, сверху показываются подсказка и кнопка отмены; список остаётся на месте.

signal closed
signal buy_requested(item_id: String)
signal place_requested(uid: String)
signal drag_started(uid: String)
signal remove_requested(uid: String)
signal sell_requested(uid: String)
signal placement_cancel_requested

const PANEL_WIDTH := 430.0
const COLUMNS := 3
const CARD_WIDTH := 124.0
const THUMB_SIZE := Vector2i(112, 84)
const DRAG_THRESHOLD := 8.0
const TAB_SHOP := 0
const TAB_OWNED := 1

var _system: FurnitureSystem = null
var _economy: EconomySystem = null
var _money_label: Label
var _summary_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _hint_label: Label
var _status_label: Label
var _note_label: Label
var _cancel_button: Button
var _shop_tab: Button
var _owned_tab: Button
var _last_money := -1
var _last_header_tick := 0
var _placing := false
var _tab := TAB_SHOP
var _thumbs: Dictionary = {} # item_id -> Texture2D
var _thumb_viewports: Array[SubViewport] = []
var _press_uid := ""
var _press_pos := Vector2.ZERO
var _overlay: Control = null
var _toast_box: VBoxContainer = null
var _toasts: Array[Dictionary] = [] # {node: PanelContainer, until: int (мс)}
var _confirm_label: Label
var _confirm_action: Callable = Callable()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	offset_left = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	offset_right = PANEL_WIDTH
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "🛋️ Мебель"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 18)
	head.add_child(_money_label)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 14)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary_label)
	_note_label = Label.new()
	_note_label.add_theme_font_size_override("font_size", 14)
	_note_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.visible = false
	root.add_child(_note_label)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.visible = false
	root.add_child(_hint_label)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	root.add_child(_status_label)
	_cancel_button = Button.new()
	_cancel_button.text = "Отмена (Esc)"
	_cancel_button.focus_mode = Control.FOCUS_NONE
	_cancel_button.visible = false
	_cancel_button.pressed.connect(func() -> void: placement_cancel_requested.emit())
	root.add_child(_cancel_button)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	var group := ButtonGroup.new()
	_shop_tab = _tab_button("🛒 Магазин", group, TAB_SHOP)
	_owned_tab = _tab_button("📦 В наличии", group, TAB_OWNED)
	tabs.add_child(_shop_tab)
	tabs.add_child(_owned_tab)
	_shop_tab.button_pressed = true
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Колесо листает напрямую: при паузе игры (time_scale ≈ 0) плавная прокрутка не двигалась бы.
	_scroll.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var wheel := event as InputEventMouseButton
			if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll.scroll_vertical += 70
				_scroll.accept_event()
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll.scroll_vertical -= 70
				_scroll.accept_event())
	root.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_scroll.add_child(_grid)
	var footer := Label.new()
	footer.text = "Колесо мыши (нажатие) — двигать камеру"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	root.add_child(footer)


func _tab_button(text: String, group: ButtonGroup, tab: int) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(func() -> void: select_tab(tab))
	return button


## Окно подтверждения по центру экрана: всё вокруг затемняется, интерфейс панели не сдвигается.
func _build_confirm() -> void:
	_overlay = Control.new()
	_overlay.name = "FurnitureConfirm"
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	get_parent().add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			_answer(false))
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.14, 0.08, 0.98)
	style.border_color = Color(1.0, 0.85, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	_confirm_label = Label.new()
	_confirm_label.add_theme_font_size_override("font_size", 18)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_confirm_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	for answer in [true, false]:
		var button := Button.new()
		button.text = "✔ Да" if answer else "✖ Нет"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(func() -> void: _answer(answer))
		buttons.add_child(button)


## Плашки в правом нижнем углу (отступ 40 px от краёв), несколько — списком друг под другом с зазором 20 px.
## Время реальное: на паузе мебели обычные тосты и твины стоят.
func _build_toast() -> void:
	# Полноэкранный контейнер с отступом 40 px; список плашек прижат к правому нижнему углу и сам подстраивается под содержимое.
	var margin := MarginContainer.new()
	margin.name = "FurnitureToasts"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 40)
	get_parent().add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_box = VBoxContainer.new()
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_theme_constant_override("separation", 20)
	_toast_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toast_box.size_flags_vertical = Control.SIZE_SHRINK_END
	margin.add_child(_toast_box)


func show_toast(text: String, seconds: float = 2.6) -> void:
	if _toast_box == null:
		return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.18, 0.1, 0.96)
	style.border_color = Color(0.6, 1.0, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_toast_box.add_child(panel)
	_toast_box.get_parent().move_to_front()
	_toasts.append({"node": panel, "until": Time.get_ticks_msec() + int(seconds * 1000.0)})


func _update_toasts() -> void:
	if _toasts.is_empty():
		return
	var now := Time.get_ticks_msec()
	for toast in _toasts.duplicate():
		var node := toast["node"] as PanelContainer
		var left := int(toast["until"]) - now
		if left <= 0:
			_toasts.erase(toast)
			node.queue_free()
		else:
			node.modulate.a = clampf(float(left) / 400.0, 0.0, 1.0)


func _exit_tree() -> void:
	if _toast_box != null and is_instance_valid(_toast_box):
		_toast_box.get_parent().queue_free()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()


## Окно подтверждения покупки или продажи: action выполняется только после «Да».
func _ask(text: String, action: Callable) -> void:
	_confirm_label.text = text
	_confirm_action = action
	_overlay.move_to_front()
	_overlay.visible = true


func _answer(yes: bool) -> void:
	var action := _confirm_action
	_confirm_action = Callable()
	if _overlay != null:
		_overlay.visible = false
	if yes and action.is_valid():
		action.call()


func select_tab(tab: int) -> void:
	_answer(false)
	_tab = tab
	if _shop_tab != null:
		_shop_tab.set_pressed_no_signal(tab == TAB_SHOP)
		_owned_tab.set_pressed_no_signal(tab == TAB_OWNED)
	_scroll.scroll_vertical = 0
	refresh()


func setup(system: FurnitureSystem, economy: EconomySystem) -> void:
	_system = system
	_economy = economy
	_system.changed.connect(refresh)
	_build_thumbs()
	_build_confirm()
	_build_toast()


func open() -> void:
	visible = true
	notify("Потяните купленное в гараж. Мебель в гараже: ЛКМ — тянуть, ПКМ — меню.")
	set_placing(false)
	_press_uid = ""
	_answer(false)
	_rerender_thumbs()
	refresh()


## Сообщение в самом окне (тосты на паузе не гаснут, поэтому для мебели используем строку окна).
func notify(text: String) -> void:
	if _note_label != null:
		_note_label.text = text
		_note_label.visible = text != "" and not _placing


func close() -> void:
	if not visible:
		return
	visible = false
	_press_uid = ""
	_answer(false)
	closed.emit()


func is_placing() -> bool:
	return _placing


## Расстановка: сверху подсказка и кнопка отмены (карточки остаются на месте).
func set_placing(value: bool, item_name: String = "") -> void:
	_placing = value
	_hint_label.visible = value
	_status_label.visible = value
	_cancel_button.visible = value
	if _note_label != null:
		_note_label.visible = not value and _note_label.text != ""
	if value:
		_hint_label.text = "Ставим: %s\nЛКМ — поставить, ПКМ или R — повернуть, Esc — отмена." % item_name
		show_problem("init")


## problem: "" — можно поставить, иначе причина отказа ("init" — ещё не проверено).
func show_problem(problem: String) -> void:
	if problem == "init":
		_status_label.text = ""
	elif problem == "":
		_status_label.text = "✅ Можно поставить"
		_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	else:
		_status_label.text = "⛔ %s" % problem
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))


# --- Миниатюры --------------------------------------------------------------

## Для каждого предмета каталога рисует его GarageObject в маленький SubViewport — это и есть картинка карточки.
func _build_thumbs() -> void:
	for item_id in _system.item_order:
		var viewport := SubViewport.new()
		viewport.size = THUMB_SIZE
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(viewport)
		var holder := Node2D.new()
		viewport.add_child(holder)
		var node := GarageObject.new()
		holder.add_child(node)
		node.setup(_system.definition_for(item_id, Vector2i.ZERO, 0, "thumb_%s" % item_id))
		var size := _system.footprint(item_id, 0)
		var corners: Array[Vector2] = [
			IsoProjection.grid_to_screen(Vector2.ZERO),
			IsoProjection.grid_to_screen(Vector2(size.x, 0)),
			IsoProjection.grid_to_screen(Vector2(size)),
			IsoProjection.grid_to_screen(Vector2(0, size.y))]
		var bounds := Rect2(corners[0], Vector2.ZERO)
		for corner in corners:
			bounds = bounds.expand(corner)
		var center := IsoProjection.grid_to_screen(Vector2(size) * 0.5)
		bounds = bounds.expand(Vector2(center.x, center.y + node.top_y - 6.0))
		var fit := minf(float(THUMB_SIZE.x - 8) / maxf(bounds.size.x, 1.0), float(THUMB_SIZE.y - 8) / maxf(bounds.size.y, 1.0))
		fit = minf(fit, 1.3)
		holder.scale = Vector2(fit, fit)
		holder.position = Vector2(THUMB_SIZE) * 0.5 - bounds.get_center() * fit
		_thumbs[item_id] = viewport.get_texture()
		_thumb_viewports.append(viewport)


func _rerender_thumbs() -> void:
	for viewport in _thumb_viewports:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# --- Карточки ---------------------------------------------------------------

func refresh() -> void:
	if _system == null or _grid == null:
		return
	_update_header()
	_owned_tab.text = "📦 В наличии (%d)" % _system.owned_count()
	for child in _grid.get_children():
		child.queue_free()
		_grid.remove_child(child)
	if _tab == TAB_SHOP:
		for item_id in _system.item_order:
			_grid.add_child(_shop_card(_system.item(item_id)))
		return
	var entries := _system.entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Пока ничего не куплено.\nКупите мебель во вкладке «Магазин»."
		empty.add_theme_font_size_override("font_size", 14)
		_grid.add_child(empty)
		return
	for entry in entries:
		_grid.add_child(_owned_card(entry))


func _update_header() -> void:
	_money_label.text = "💰 %d" % (_economy.balance() if _economy != null else 0)
	var totals := _system.totals()
	_summary_label.text = "Комфорт: %d  ·  Атмосфера: %d  ·  Бонус к оценке: +%.1f (макс. +%.1f)\nРасставлено: %d, куплено: %d" % [
		int(totals["comfort"]), int(totals["atmosphere"]), float(totals["bonus"]), _system.bonus_cap, int(totals["placed"]), _system.owned_count()]


func _card_style(highlight: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.26, 0.95) if highlight else Color(0.14, 0.12, 0.19, 0.95)
	style.border_color = Color(1.0, 0.85, 0.45, 0.9) if highlight else Color(0.4, 0.36, 0.5, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	return style


## Общая часть карточки: миниатюра, название. Возвращает (карточка, вертикальный контейнер).
func _card_base(data: Dictionary) -> Array:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style(false))
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", _card_style(true)))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", _card_style(false)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var picture := TextureRect.new()
	picture.texture = _thumbs.get(str(data["id"]))
	picture.custom_minimum_size = Vector2(THUMB_SIZE)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	return [card, box]


func _info_label(text: String, size: int = 13, color: Color = Color(0.9, 0.9, 0.95)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _shop_card(data: Dictionary) -> Control:
	var item_id := str(data["id"])
	var parts := _card_base(data)
	var card := parts[0] as PanelContainer
	var box := parts[1] as VBoxContainer
	box.add_child(_info_label(str(data["name"]), 14))
	box.add_child(_info_label("комфорт +%d · атм. +%d" % [int(data["comfort"]), int(data["atmosphere"])], 11, Color(0.7, 0.8, 0.9)))
	var price := int(data["price"])
	var item_name := str(data["name"])
	var affordable := _economy != null and _economy.can_afford(price)
	var button := Button.new()
	button.text = "%d 💰" % price
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	if not affordable:
		button.modulate = Color(1.0, 0.6, 0.55, 0.75)
	button.pressed.connect(func() -> void: _try_buy(item_id, item_name, price))
	box.add_child(button)
	# Купить можно и кликом по самой карточке.
	card.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_try_buy(item_id, item_name, price))
	return card


func _try_buy(item_id: String, item_name: String, price: int) -> void:
	if _economy == null or not _economy.can_afford(price):
		notify("⛔ Не хватает денег: нужно %d 💰" % price)
		_answer(false)
		return
	_ask("Купить «%s» за %d 💰?" % [item_name, price], func() -> void: buy_requested.emit(item_id))


func _owned_card(entry: Dictionary) -> Control:
	var data: Dictionary = _system.item(str(entry["item"]))
	var placed := bool(entry.get("placed", false))
	var uid := str(entry["uid"])
	var parts := _card_base(data)
	var card := parts[0] as PanelContainer
	var box := parts[1] as VBoxContainer
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _info_label(str(data["name"]), 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_label)
	if placed:
		var remove_button := Button.new()
		remove_button.text = "✕"
		remove_button.tooltip_text = "Убрать на склад"
		remove_button.focus_mode = Control.FOCUS_NONE
		remove_button.add_theme_font_size_override("font_size", 13)
		remove_button.pressed.connect(func() -> void: remove_requested.emit(uid))
		title_row.add_child(remove_button)
	box.add_child(title_row)
	box.add_child(_info_label("✅ стоит" if placed else "📦 на складе", 12, Color(0.6, 1.0, 0.6) if placed else Color(0.85, 0.85, 0.9)))
	var price := _system.sell_price(str(entry["item"]))
	var sell_button := Button.new()
	sell_button.focus_mode = Control.FOCUS_NONE
	sell_button.add_theme_font_size_override("font_size", 12)
	sell_button.text = "Продать +%d 💰" % price
	var sell_name := str(data["name"])
	sell_button.pressed.connect(func() -> void:
		_ask("Продать «%s» за %d 💰? Куплен он был дороже." % [sell_name, price], func() -> void: sell_requested.emit(uid)))
	box.add_child(sell_button)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_press_uid = uid
			_press_pos = (event as InputEventMouseButton).global_position)
	return card


## Карточка нажата: если мышь ушла дальше порога — это перетаскивание, если отпустили на месте — обычный клик.
func _input(event: InputEvent) -> void:
	if _press_uid == "" or not visible:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_press_uid = ""
		elif motion.global_position.distance_to(_press_pos) > DRAG_THRESHOLD:
			var uid := _press_uid
			_press_uid = ""
			drag_started.emit(uid)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			var uid := _press_uid
			_press_uid = ""
			place_requested.emit(uid)


## Деньги проверяем по реальному времени: на паузе мебели игровое время почти стоит, а баланс может измениться (например, отладочной кнопкой).
func _process(_delta: float) -> void:
	_update_toasts()
	if not visible or _economy == null:
		return
	var balance := _economy.balance()
	if balance != _last_money:
		_last_money = balance
		refresh()
		return
	var now := Time.get_ticks_msec()
	if now - _last_header_tick >= 300:
		_last_header_tick = now
		_update_header()
