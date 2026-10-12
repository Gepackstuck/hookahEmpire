class_name ProfileMenu
extends Control
## M11: список профилей (кальянных): играть, очистить прогресс, удалить, создать новый.
## Работает и как стартовый экран (без кнопки «Закрыть»), и как внутриигровое меню.

signal play_requested(id: String)
signal reset_requested(id: String)
signal delete_requested(id: String)
signal create_requested
signal rename_requested(id: String)
signal closed

var _store: ProfileStore = null
var _goal: ProgressionGoal = null
var _current_id := ""
var _allow_close := false
var _confirm: Dictionary = {}
var _list: VBoxContainer = null
var _create_button: Button = null
var _hint: Label = null


## current_id — профиль, в котором играют сейчас ("" на стартовом экране).
func setup(store: ProfileStore, goal: ProgressionGoal, current_id: String, allow_close: bool) -> void:
	_store = store
	_goal = goal
	_current_id = current_id
	_allow_close = allow_close
	_build()
	refresh()


func _input(event: InputEvent) -> void:
	if visible and _allow_close and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var ids := _store.ids()
	if ids.is_empty():
		_list.add_child(UiStyle.label("Пока нет ни одной кальянной. Нажми «Новый профиль», чтобы начать!", 22, UiStyle.MUTED))
	for id in ids:
		_list.add_child(_build_row(_store.summary(id, _goal)))
	_create_button.disabled = not _store.can_create()
	_hint.text = "" if _store.can_create() else "Достигнут лимит профилей (%d)." % ProfileStore.MAX_PROFILES


func _build() -> void:
	var panel := UiStyle.build_frame(self, Vector2(760, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := UiStyle.label("🪔 Hookah Empire" if not _allow_close else "Мои кальянные", 40, UiStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_hint = UiStyle.label("", 18, UiStyle.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	box.add_child(footer)
	_create_button = _button("＋ Новый профиль", 240)
	_create_button.pressed.connect(func() -> void: create_requested.emit())
	footer.add_child(_create_button)
	if _allow_close:
		var close := _button("Закрыть" if _current_id != "" else "Назад", 160)
		close.pressed.connect(func() -> void: closed.emit())
		footer.add_child(close)


func _build_row(info: Dictionary) -> Control:
	var id := str(info["id"])
	var is_current := id == _current_id
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.1, 0.08, 0.95)
	style.set_border_width_all(2)
	style.border_color = UiStyle.GOLD if is_current else Color(0.4, 0.34, 0.28)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var title_text := "🪔 " + str(info["title"]) + ("   ● играете сейчас" if is_current else "")
	box.add_child(UiStyle.label(title_text, 26, UiStyle.GOLD))
	var detail := "Новая игра" if not bool(info["has_save"]) else "💰 %d   ⭐ репутация %d   📖 рецептов %d (сильных %d)   🧾 визитов %d" % [
		int(info["money"]), int(info["reputation"]), int(info["recipes"]), int(info["strong"]), int(info["sessions"])]
	box.add_child(UiStyle.label(detail, 19, UiStyle.MUTED))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	if _confirm.get("id", "") == id:
		var action := str(_confirm["action"])
		var question := "Очистить весь прогресс профиля?" if action == "reset" else "Удалить профиль навсегда?"
		buttons.add_child(UiStyle.label(question, 20, Color(1.0, 0.7, 0.55)))
		var yes := _button("Да", 90)
		yes.pressed.connect(_on_confirmed.bind(id, action))
		buttons.add_child(yes)
		var no := _button("Отмена", 120)
		no.pressed.connect(func() -> void:
			_confirm = {}
			refresh())
		buttons.add_child(no)
		return card
	var play := _button("▶ Играть" if not is_current else "▶ Продолжить", 160)
	play.pressed.connect(func() -> void:
		if is_current:
			closed.emit()
		else:
			play_requested.emit(id))
	buttons.add_child(play)
	if is_current and _goal != null and bool(info["has_save"]) and _can_rename():
		var rename := _button("✏️ Название", 160)
		rename.pressed.connect(func() -> void: rename_requested.emit(id))
		buttons.add_child(rename)
	var reset := _button("🧹 Очистить", 150)
	reset.disabled = not bool(info["has_save"]) and not is_current
	reset.pressed.connect(_ask_confirm.bind(id, "reset"))
	buttons.add_child(reset)
	var remove := _button("🗑 Удалить", 140)
	remove.pressed.connect(_ask_confirm.bind(id, "delete"))
	buttons.add_child(remove)
	return card


## Переименовать можно после выполнения цели (флаг ставится в Main); меню спрашивает у него через мета-данные.
func _can_rename() -> bool:
	return has_meta("can_rename") and bool(get_meta("can_rename"))


func _ask_confirm(id: String, action: String) -> void:
	_confirm = {"id": id, "action": action}
	refresh()


func _on_confirmed(id: String, action: String) -> void:
	_confirm = {}
	if action == "reset":
		reset_requested.emit(id)
	else:
		delete_requested.emit(id)


func _button(text: String, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size = Vector2(width, 46)
	return button
