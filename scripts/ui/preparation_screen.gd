class_name PreparationScreen
extends Control
## Окно приготовления: выбор рецепта, выбор режима (переключатели / вручную), затем пять параметров и результат.
## Окно только собирает запрос и показывает результат; расчёт и запись делает PreparationService.

signal closed
signal prepared(result: Dictionary)
## Игрок выбрал ручное приготовление (мини-игру) для рецепта.
signal manual_requested(recipe_id: String)

const OK_COLOR := Color(0.6, 0.9, 0.6, 1)
const WARN_COLOR := Color(1.0, 0.75, 0.4, 1)

var _service: PreparationService = null
var _choices: Dictionary = {}
var _recipe_ids: Array[String] = []
var _selected_recipe_id := ""
var _option_buttons: Dictionary = {} # parameter_id -> {option_id: Button}
var _recipe_picker: OptionButton
var _recipe_info: Label
var _form: VBoxContainer
var _empty: Label
var _result_box: VBoxContainer
var _result_title: Label
var _result_band: Label
var _result_bar: ProgressBar
var _result_quality: Label
var _result_lines: VBoxContainer
var _serve_button: Button
var _pending_result: Dictionary = {}
## M8: Callable(recipe: Dictionary) -> {"cost": int, "affordable": bool}; стоимость ингредиентов рецепта.
var cost_info: Callable = Callable()
var _prepare_button: Button
var _manual_button: Button
## Выбор режима: две большие карточки; переключатели появляются только после выбора «Быстрая готовка».
var _mode_box: VBoxContainer
var _switch_box: VBoxContainer
var _quick_card: Button
var _quick_tag: Label
var _quick_locked := false
var _affordable := true
var _quick_hint := ""


func _ready() -> void:
	visible = false
	_build()


func setup(service: PreparationService) -> void:
	_service = service
	_choices = service.default_choices()
	if is_node_ready():
		for child in get_children():
			child.queue_free()
		_option_buttons.clear()
		_build()
		visible = false


func open() -> void:
	if _service == null:
		return
	visible = true
	_result_box.visible = false
	_pending_result = {}
	_show_mode_stage()
	_refresh_recipes()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	if _service == null:
		return
	var panel := UiStyle.build_frame(self, Vector2(1100, 760))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := UiStyle.label("🔥 Приготовление кальяна", 34, UiStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_button := Button.new()
	close_button.text = "✕ Закрыть"
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	_empty = UiStyle.label("Рецептов пока нет. Сначала смешайте вкус за столом смешивания и сохраните рецепт.", 26, UiStyle.MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(900, 0)
	column.add_child(_empty)

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 12)
	column.add_child(_form)

	var recipe_row := HBoxContainer.new()
	recipe_row.add_theme_constant_override("separation", 14)
	_form.add_child(recipe_row)
	recipe_row.add_child(UiStyle.label("Рецепт:", 26))
	_recipe_picker = OptionButton.new()
	_recipe_picker.custom_minimum_size = Vector2(560, 0)
	_recipe_picker.item_selected.connect(_on_recipe_selected)
	recipe_row.add_child(_recipe_picker)
	var info := UiStyle.label("ⓘ", 28)
	info.mouse_filter = Control.MOUSE_FILTER_STOP
	info.tooltip_text = "Рецепт — то, что будет приготовлено для гостя. Здесь можно выбрать любой рецепт из книги рецептов; сверху всегда последний собранный. Состав выбранного рецепта показан ниже, а параметры забивки подбираются под него."
	recipe_row.add_child(info)
	_recipe_info = UiStyle.label("", 22, UiStyle.MUTED)
	_recipe_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(_recipe_info)

	_mode_box = VBoxContainer.new()
	_mode_box.add_theme_constant_override("separation", 12)
	_form.add_child(_mode_box)
	var mode_title := UiStyle.label("Как будем готовить?", 28, UiStyle.GOLD)
	_mode_box.add_child(mode_title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 20)
	_mode_box.add_child(cards)
	_quick_card = _make_mode_card("⚡", "Быстрая готовка",
		"Выставляешь упаковку, фольгу, отверстия, угли и розжиг — кальян забьётся автоматически.",
		"🕐 Результат сразу")
	_quick_card.pressed.connect(_show_switch_stage)
	cards.add_child(_quick_card)
	_quick_tag = _quick_card.get_meta("tag") as Label
	_manual_button = _make_mode_card("✋", "Ручная забивка",
		"Сам набиваешь чашу, кладёшь фольгу и раскладываешь угли — мини-игра с реальными действиями.",
		"💰 +25% к оплате за визит")
	_manual_button.tooltip_text = "+25% к оплате: если кальян забиваешь сам (вручную), а не автоматом, гость ценит ручную работу и платит на 25% больше итоговой суммы за визит."
	_manual_button.pressed.connect(_on_manual_pressed)
	cards.add_child(_manual_button)

	_switch_box = VBoxContainer.new()
	_switch_box.add_theme_constant_override("separation", 12)
	_switch_box.visible = false
	_form.add_child(_switch_box)
	_switch_box.add_child(UiStyle.label("⚡ Настрой забивку", 28, UiStyle.GOLD))
	for entry in _service.config.parameters:
		_switch_box.add_child(_make_parameter_row(entry))
	var prepare_row := HBoxContainer.new()
	prepare_row.add_theme_constant_override("separation", 14)
	_switch_box.add_child(prepare_row)
	var back_button := Button.new()
	back_button.text = "← Выбор режима"
	back_button.custom_minimum_size = Vector2(260, 52)
	back_button.pressed.connect(_show_mode_stage)
	prepare_row.add_child(back_button)
	_prepare_button = Button.new()
	_prepare_button.text = "⚡ Приготовить"
	_prepare_button.custom_minimum_size = Vector2(0, 52)
	_prepare_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prepare_button.pressed.connect(_on_prepare_pressed)
	prepare_row.add_child(_prepare_button)

	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 10)
	_result_box.visible = false
	column.add_child(_result_box)
	_result_title = UiStyle.label("", 30, UiStyle.GOLD)
	_result_box.add_child(_result_title)
	_result_band = UiStyle.label("", 28)
	_result_box.add_child(_result_band)
	_result_bar = ProgressBar.new()
	_result_bar.min_value = 0
	_result_bar.max_value = 100
	_result_bar.show_percentage = false
	_result_bar.custom_minimum_size = Vector2(500, 24)
	_result_box.add_child(_result_bar)
	_result_quality = UiStyle.label("", 22, UiStyle.MUTED)
	_result_box.add_child(_result_quality)
	_result_lines = VBoxContainer.new()
	_result_box.add_child(_result_lines)
	var again_button := Button.new()
	again_button.text = "↩ Изменить и приготовить ещё раз"
	again_button.pressed.connect(func() -> void:
		_result_box.visible = false
		_form.visible = true
		_show_switch_stage())
	_result_box.add_child(again_button)
	_serve_button = Button.new()
	_serve_button.custom_minimum_size = Vector2(0, 52)
	_serve_button.pressed.connect(_on_serve_pressed)
	_result_box.add_child(_serve_button)


## Большая карточка режима: иконка, название, описание и «выгода» внизу. Дополнительная метка — в meta "tag".
func _make_mode_card(icon: String, title: String, description: String, tag: String) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 250)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_bottom", 26)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var head := UiStyle.label("%s  %s" % [icon, title], 32, UiStyle.GOLD)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var body := UiStyle.label(description, 21)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(380, 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	var tag_label := UiStyle.label(tag, 22, OK_COLOR)
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag_label)
	card.set_meta("tag", tag_label)
	return card


func _show_mode_stage() -> void:
	if _mode_box == null:
		return
	_mode_box.visible = true
	_switch_box.visible = false


func _show_switch_stage() -> void:
	if _quick_locked or not _affordable:
		return
	_mode_box.visible = false
	_switch_box.visible = true
	_sync_options()


func _make_parameter_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := UiStyle.label(str(entry["name"]), 26)
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	var group := ButtonGroup.new()
	var buttons := {}
	for option in entry["options"]:
		var button := Button.new()
		button.text = str(option["name"])
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(190, 46)
		button.pressed.connect(_on_option_pressed.bind(str(entry["id"]), str(option["id"])))
		row.add_child(button)
		buttons[str(option["id"])] = button
	_option_buttons[str(entry["id"])] = buttons
	return row


func _refresh_recipes() -> void:
	var recipes := RecipeBookQuery.filter_sort(_service.recipes.all_recipes(), "", RecipeBookQuery.SORT_RECENT)
	_recipe_ids.clear()
	_recipe_picker.clear()
	for recipe in recipes:
		_recipe_ids.append(str(recipe["id"]))
		_recipe_picker.add_item(_service.recipes.display_name(recipe))
	var has_recipes := not _recipe_ids.is_empty()
	_empty.visible = not has_recipes
	_form.visible = has_recipes
	if not has_recipes:
		_selected_recipe_id = ""
		return
	# Всегда показываем последнюю сборку (список отсортирован по давности).
	var index := 0
	_recipe_picker.select(index)
	_select_recipe(index)
	_sync_options()


func _on_recipe_selected(index: int) -> void:
	_select_recipe(index)


func _select_recipe(index: int) -> void:
	_selected_recipe_id = _recipe_ids[index]
	var recipe := _service.recipes.get_recipe(_selected_recipe_id)
	var parts: PackedStringArray = []
	for item in recipe["ingredients"]:
		var percent := int(round(float(item["units"]) / float(_service.recipes.config.total_units) * 100.0))
		parts.append("%s %d%%" % [_service.recipes.catalog.label(item["id"]), percent])
	if recipe["modifiers"].has("ice"):
		parts.append("Ледяная нотка ❄️")
	_recipe_info.text = " · ".join(parts)
	var affordable := true
	if cost_info.is_valid():
		var info: Dictionary = cost_info.call(recipe)
		var cost := int(info.get("cost", 0))
		affordable = bool(info.get("affordable", true))
		if cost <= 0:
			_recipe_info.text += "\nИнгредиенты бесплатные 🆓"
		elif affordable:
			_recipe_info.text += "\nСтоимость ингредиентов: %d 💰 (спишется при подаче)" % cost
		else:
			_recipe_info.text += "\n⛔ Не хватает денег: нужно %d 💰. Бесплатны: яблоко, лимон, лайм, ваниль, кола." % cost
	_affordable = affordable
	_apply_quick_lock()


func _sync_options() -> void:
	for parameter_id in _option_buttons:
		var buttons: Dictionary = _option_buttons[parameter_id]
		for option_id in buttons:
			(buttons[option_id] as Button).set_pressed_no_signal(option_id == _choices.get(parameter_id))


func _on_option_pressed(parameter_id: String, option_id: String) -> void:
	_choices[parameter_id] = option_id


func _on_manual_pressed() -> void:
	if not _selected_recipe_id.is_empty():
		manual_requested.emit(_selected_recipe_id)


## Окно временно скрыто, пока открыта мини-игра (не считается закрытием).
func suspend() -> void:
	visible = false


func resume() -> void:
	visible = true


## Мини-игра подала кальян (результат уже записан): завершаем так же, как подача в быстром режиме.
func complete_with(result: Dictionary) -> void:
	_pending_result = {}
	visible = true
	prepared.emit(result)
	close()


## M10: быстрый режим (переключатели) закрыт до нужного числа гостей; hint — подпись на кнопке.
func set_quick_locked(locked: bool, hint: String = "") -> void:
	_quick_locked = locked
	_quick_hint = hint
	_apply_quick_lock()


func _apply_quick_lock() -> void:
	if _quick_card == null:
		return
	_quick_card.disabled = not _affordable or _quick_locked
	if _quick_locked:
		_quick_tag.text = "🔒 %s" % (_quick_hint if _quick_hint != "" else "Пока недоступно")
		_quick_tag.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_quick_tag.text = "🕐 Результат сразу"
		_quick_tag.add_theme_color_override("font_color", OK_COLOR)
	_prepare_button.disabled = not _affordable or _quick_locked
	_manual_button.disabled = not _affordable
	if not _affordable:
		_quick_card.tooltip_text = "Не хватает денег на ингредиенты."
	else:
		_quick_card.tooltip_text = ""
	# Пока быстрый режим закрыт, переключатели тоже недоступны (и сами скрыты).
	if _quick_locked and _switch_box != null and _switch_box.visible:
		_show_mode_stage()
	for parameter_id in _option_buttons:
		var buttons: Dictionary = _option_buttons[parameter_id]
		for option_id in buttons:
			(buttons[option_id] as Button).disabled = _quick_locked


func _on_prepare_pressed() -> void:
	if _selected_recipe_id.is_empty() or _quick_locked:
		return
	var result := _service.preview(_selected_recipe_id, _choices)
	if not result["ok"]:
		GameLog.error("preparation", str(result["error"]))
		return
	_pending_result = result
	_show_result(result)


## «Подать кальян» / «И так сойдет»: результат записывается, окно закрывается.
func _on_serve_pressed() -> void:
	if _pending_result.is_empty():
		return
	var result := _pending_result
	_pending_result = {}
	if not _service.commit(result):
		return
	prepared.emit(result)
	close()


func _show_result(result: Dictionary) -> void:
	_form.visible = false
	_result_box.visible = true
	_result_title.text = "Кальян готов! %s" % result["recipe_name"]
	_result_band.text = "Исполнение: %s" % result["execution_band"]
	_result_bar.value = float(result["execution_score"])
	_result_quality.text = "Качество рецепта: %s" % result["recipe_quality_band"]
	_serve_button.text = "😬 И так сойдет" if _service.is_weak(result) else "✅ Подать кальян"
	for child in _result_lines.get_children():
		child.queue_free()
	for detail in result["parameters"]:
		var line := UiStyle.label("%s — %s: %s" % [detail["name"], detail["option_name"], detail["hint"]], 24, OK_COLOR if detail["is_ok"] else WARN_COLOR)
		_result_lines.add_child(line)
