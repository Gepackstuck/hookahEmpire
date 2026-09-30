class_name MixerScreen
extends Control
## Экран смешивания: порции ингредиентов кнопками − / +, состав, вкусовые полоски, ❄️, имя и сохранение.
## В M3 игроку показываются слова и полоски; числовое качество — только в книге рецептов.

signal closed
signal recipe_book_requested
signal recipe_committed(result: Dictionary)

var _recipes: RecipeSystem = null
var _mix := MixSelection.new(4, 4)
var _minus: Dictionary = {} # ingredient_id -> Button
var _plus: Dictionary = {}
var _rows: Dictionary = {} # ingredient_id -> строка (для затемнения)
var _counts: Dictionary = {} # ingredient_id -> Label (число порций)
var _percent_labels: Dictionary = {}
var _bars: Dictionary = {} # dimension -> ProgressBar
var _composition: Label
var _quality: Label
var _ice: CheckBox
var _name_edit: LineEdit
var _save_button: Button
var _status: Label
var _hint: Label
var _saved_since_open := false

const DIMMED := Color(1, 1, 1, 0.35)
const ICE_TEXT_OFF := "Ледяная нотка"
const ICE_TEXT_ON := "Ледяная нотка ❄️"


func _ready() -> void:
	visible = false
	_build()


## Вызывается из Main после создания RecipeSystem.
func setup(recipes: RecipeSystem) -> void:
	_recipes = recipes
	_mix = MixSelection.new(recipes.config.max_ingredients, recipes.config.max_portions)
	if is_node_ready():
		for child in get_children():
			child.queue_free()
		_minus.clear()
		_plus.clear()
		_counts.clear()
		_rows.clear()
		_percent_labels.clear()
		_bars.clear()
		_build()
		visible = false


func open() -> void:
	if _recipes == null:
		return
	visible = true
	_saved_since_open = false
	_status.text = ""
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if _saved_since_open:
		# Рецепт сохранён — следующее открытие начинается с чистого смесителя.
		_saved_since_open = false
		_mix.clear()
		_name_edit.text = ""
		_status.text = ""
		_sync_controls()
	closed.emit()


## Временно прячет экран (пока поверх открыта книга рецептов), не считая это закрытием.
func suspend() -> void:
	visible = false


func resume() -> void:
	visible = true
	_refresh()


## Загружает сохранённый рецепт в порции (из книги рецептов).
func load_recipe(recipe: Dictionary) -> void:
	_mix.load_recipe(recipe, _recipes.config.total_units)
	_name_edit.text = ""
	_sync_controls()
	_refresh()
	_status.text = "Загружено: %s" % _recipes.display_name(recipe)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	if _recipes == null:
		return
	var panel := UiStyle.build_frame(self, Vector2(1300, 780))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := UiStyle.label("⚗️ Смешивание", 34, UiStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var book_button := Button.new()
	book_button.text = "📜 Книга рецептов"
	book_button.pressed.connect(func() -> void: recipe_book_requested.emit())
	title_row.add_child(book_button)
	var close_button := Button.new()
	close_button.text = "✕ Закрыть"
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(UiStyle.label("Порции: всего %d (до %d ингредиентов)" % [_recipes.config.max_portions, _recipes.config.max_ingredients], 22, UiStyle.MUTED))
	for ingredient_id in _recipes.catalog.ingredient_ids():
		left.add_child(_make_row(ingredient_id))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_composition = UiStyle.label("", 24)
	_composition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_composition.custom_minimum_size = Vector2(440, 64)
	right.add_child(_composition)
	for dimension in IngredientCatalog.DIMENSIONS:
		right.add_child(_make_bar(dimension))
	_quality = UiStyle.label("", 30, UiStyle.GOLD)
	right.add_child(_quality)
	_ice = CheckBox.new()
	_ice.text = ICE_TEXT_OFF
	_ice.toggled.connect(_on_ice_toggled)
	right.add_child(_ice)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 40
	_name_edit.placeholder_text = "Название рецепта"
	right.add_child(_name_edit)
	_save_button = Button.new()
	_save_button.text = "💾 Сохранить рецепт"
	_save_button.pressed.connect(_on_save_pressed)
	right.add_child(_save_button)
	var reset_button := Button.new()
	reset_button.text = "🧹 Сбросить"
	reset_button.pressed.connect(_on_reset_pressed)
	right.add_child(reset_button)
	_status = UiStyle.label("", 22, UiStyle.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 60)
	right.add_child(_status)

	_hint = UiStyle.label("Esc — закрыть", 20, UiStyle.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint)


func _make_row(ingredient_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := UiStyle.label(_recipes.catalog.label(ingredient_id), 24)
	name_label.custom_minimum_size = Vector2(210, 0)
	row.add_child(name_label)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(48, 40)
	minus.pressed.connect(_on_step.bind(ingredient_id, -1))
	row.add_child(minus)
	var count := UiStyle.label("0", 26)
	count.custom_minimum_size = Vector2(40, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(48, 40)
	plus.pressed.connect(_on_step.bind(ingredient_id, 1))
	row.add_child(plus)
	var percent := UiStyle.label("—", 22, UiStyle.MUTED)
	percent.custom_minimum_size = Vector2(70, 0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(percent)
	_minus[ingredient_id] = minus
	_plus[ingredient_id] = plus
	_counts[ingredient_id] = count
	_rows[ingredient_id] = row
	_percent_labels[ingredient_id] = percent
	return row


func _make_bar(dimension: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := UiStyle.label(str(_recipes.config.dimension_names.get(dimension, dimension)), 22)
	name_label.custom_minimum_size = Vector2(130, 0)
	row.add_child(name_label)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	_bars[dimension] = bar
	return row


func _on_step(ingredient_id: String, direction: int) -> void:
	_mix.set_amount(ingredient_id, _mix.amount(ingredient_id) + direction)
	_sync_controls()
	_refresh()


func _on_reset_pressed() -> void:
	_mix.clear()
	_name_edit.text = ""
	_sync_controls()
	_refresh()
	_status.text = ""


func _on_ice_toggled(pressed: bool) -> void:
	_mix.set_ice(pressed)
	_sync_controls()
	_refresh()


func _sync_controls() -> void:
	for ingredient_id in _counts:
		var amount := _mix.amount(ingredient_id)
		(_counts[ingredient_id] as Label).text = str(amount)
		(_minus[ingredient_id] as Button).disabled = amount == 0
		(_plus[ingredient_id] as Button).disabled = not _mix.can_increase(ingredient_id)
		# Невыбранные ингредиенты, которые нельзя добавить (слоты или порции закончились), затемняем.
		var tint: Color = DIMMED if amount == 0 and not _mix.can_increase(ingredient_id) else Color.WHITE
		# Красим строку и каждого её потомка явно: название, эмодзи, число, кнопки, процент.
		(_rows[ingredient_id] as Control).modulate = Color.WHITE
		for child in (_rows[ingredient_id] as Control).get_children():
			(child as CanvasItem).modulate = tint
	_ice.set_pressed_no_signal(_mix.ice)
	_ice.text = ICE_TEXT_ON if _mix.ice else ICE_TEXT_OFF


func _refresh() -> void:
	if _recipes == null:
		return
	var evaluation := _recipes.evaluate(_mix.selection(), _mix.modifiers())
	for ingredient_id in _percent_labels:
		(_percent_labels[ingredient_id] as Label).text = "—"
	_save_button.disabled = true
	_name_edit.editable = true
	if not evaluation["ok"]:
		_composition.text = "Добавляйте порции кнопками «+», чтобы смешать вкусы"
		_quality.text = ""
		_name_edit.placeholder_text = "Название рецепта"
		for dimension in _bars:
			(_bars[dimension] as ProgressBar).value = 0
		return
	var canonical: Dictionary = evaluation["canonical"]
	var scoring: Dictionary = evaluation["scoring"]
	var parts: PackedStringArray = []
	var total := float(_recipes.config.total_units)
	for item in canonical["ingredients"]:
		var percent := int(round(float(item["units"]) / total * 100.0))
		(_percent_labels[item["id"]] as Label).text = "%d%%" % percent
		parts.append("%s %d%%" % [_recipes.catalog.label(item["id"]), percent])
	if canonical["modifiers"].has("ice"):
		parts.append("Ледяная нотка ❄️")
	_composition.text = " · ".join(parts)
	for dimension in _bars:
		(_bars[dimension] as ProgressBar).value = float(scoring["profile"][dimension]) * 100.0
	_quality.text = "Качество: %s" % scoring["band_name"]
	var is_secret: bool = scoring["secret_id"] != ""
	_name_edit.placeholder_text = evaluation["auto_name"] if not is_secret else "Секретный рецепт — имя нельзя менять"
	_name_edit.editable = not is_secret
	if is_secret:
		_name_edit.text = ""
	var exists: bool = not evaluation["existing"].is_empty()
	_save_button.disabled = exists
	_save_button.text = "✔ Уже в книге рецептов" if exists else "💾 Сохранить рецепт"


func _on_save_pressed() -> void:
	var result := _recipes.commit(_mix.selection(), _mix.modifiers(), _name_edit.text)
	if not result["ok"]:
		_status.text = str(result["error"])
		return
	var recipe: Dictionary = result["recipe"]
	var shown_name := _recipes.display_name(recipe)
	var band := _recipes.config.band_for(float(recipe["last_score"]))
	if result["is_new"]:
		_status.text = "Рецепт сохранён: «%s» — %s" % [shown_name, band["name"]]
		if result["is_secret"]:
			_status.text = "%s\n%s" % [result["secret_message"], _status.text]
	else:
		_status.text = "Такой рецепт уже есть в книге: «%s» — %s" % [shown_name, band["name"]]
	_name_edit.text = ""
	_saved_since_open = true
	_refresh()
	recipe_committed.emit(result)
