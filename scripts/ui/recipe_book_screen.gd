class_name RecipeBookScreen
extends Control
## Книга рецептов: список, фильтр по ингредиенту, сортировка, детали, переименование, загрузка в смеситель.
## Числовое качество показывается только здесь.

signal closed
signal load_requested(recipe_id: String)

var _recipes: RecipeSystem = null
var _shown: Array[Dictionary] = []
var _selected_id := ""
var _filter: OptionButton
var _sort: OptionButton
var _list: ItemList
var _empty: Label
var _detail: VBoxContainer
var _title: Label
var _badge: Label
var _composition: Label
var _stats: Label
var _rename_edit: LineEdit
var _rename_button: Button
var _load_button: Button


func _ready() -> void:
	visible = false
	_build()


func setup(recipes: RecipeSystem) -> void:
	_recipes = recipes
	if is_node_ready():
		for child in get_children():
			child.queue_free()
		_build()
		visible = false


func open() -> void:
	if _recipes == null:
		return
	visible = true
	_selected_id = ""
	_refresh_list()


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
	if _recipes == null:
		return
	var panel := UiStyle.build_frame(self, Vector2(1200, 720))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	column.add_child(top)
	var heading := UiStyle.label("📜 Книга рецептов", 34, UiStyle.GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	_filter = OptionButton.new()
	_filter.add_item("Все ингредиенты")
	_filter.set_item_metadata(0, "")
	for ingredient_id in _recipes.catalog.ingredient_ids():
		_filter.add_item(_recipes.catalog.label(ingredient_id))
		_filter.set_item_metadata(_filter.item_count - 1, ingredient_id)
	_filter.item_selected.connect(func(_i: int) -> void: _refresh_list())
	top.add_child(_filter)
	_sort = OptionButton.new()
	for entry in [["Лучшие", RecipeBookQuery.SORT_BEST], ["Недавние", RecipeBookQuery.SORT_RECENT], ["По названию", RecipeBookQuery.SORT_NAME]]:
		_sort.add_item(entry[0])
		_sort.set_item_metadata(_sort.item_count - 1, entry[1])
	_sort.item_selected.connect(func(_i: int) -> void: _refresh_list())
	top.add_child(_sort)
	var close_button := Button.new()
	close_button.text = "✕ Закрыть"
	close_button.pressed.connect(close)
	top.add_child(close_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(480, 500)
	_list.item_selected.connect(_on_item_selected)
	body.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_empty = UiStyle.label("Рецептов пока нет. Смешайте что-нибудь и сохраните!", 24, UiStyle.MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_empty)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 12)
	right.add_child(_detail)
	_title = UiStyle.label("", 30, UiStyle.GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_title)
	_badge = UiStyle.label("⭐ Секретный рецепт", 22, UiStyle.GOLD)
	_detail.add_child(_badge)
	_composition = UiStyle.label("", 24)
	_composition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_composition)
	_stats = UiStyle.label("", 24)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_stats)
	_rename_edit = LineEdit.new()
	_rename_edit.placeholder_text = "Новое название"
	_rename_edit.max_length = 40
	_rename_edit.text_submitted.connect(func(_t: String) -> void: _on_rename_pressed())
	_detail.add_child(_rename_edit)
	_rename_button = Button.new()
	_rename_button.text = "✏️ Переименовать"
	_rename_button.pressed.connect(_on_rename_pressed)
	_detail.add_child(_rename_button)
	_load_button = Button.new()
	_load_button.text = "⚗️ Загрузить в смеситель"
	_load_button.pressed.connect(func() -> void:
		if not _selected_id.is_empty():
			load_requested.emit(_selected_id))
	_detail.add_child(_load_button)
	_detail.visible = false


func _refresh_list() -> void:
	var ingredient_id := str(_filter.get_item_metadata(_filter.selected))
	var sort_mode := str(_sort.get_item_metadata(_sort.selected))
	_shown = RecipeBookQuery.filter_sort(_recipes.all_recipes(), ingredient_id, sort_mode, _recipes.sort_key)
	_list.clear()
	var keep_index := -1
	for index in _shown.size():
		var recipe := _shown[index]
		var star := "⭐ " if str(recipe["secret_id"]) != "" else ""
		_list.add_item("%s%s — %s" % [star, _recipes.display_name(recipe), _recipes.config.band_for(float(recipe["best_score"]))["name"]])
		if recipe["id"] == _selected_id:
			keep_index = index
	if _shown.is_empty():
		_empty.text = "Рецептов пока нет. Смешайте что-нибудь и сохраните!" if _recipes.all_recipes().is_empty() else "Нет рецептов с этим ингредиентом."
	_empty.visible = _shown.is_empty()
	if keep_index >= 0:
		_list.select(keep_index)
		_show_detail(_shown[keep_index])
	else:
		_selected_id = ""
		_list.deselect_all()
		_detail.visible = false


func _on_item_selected(index: int) -> void:
	if index >= 0 and index < _shown.size():
		_show_detail(_shown[index])


func _show_detail(recipe: Dictionary) -> void:
	_selected_id = str(recipe["id"])
	_detail.visible = true
	_title.text = _recipes.display_name(recipe)
	_badge.visible = str(recipe["secret_id"]) != ""
	var parts: PackedStringArray = []
	for item in recipe["ingredients"]:
		var percent := int(round(float(item["units"]) / float(_recipes.config.total_units) * 100.0))
		parts.append("%s %d%%" % [_recipes.catalog.label(item["id"]), percent])
	if recipe["modifiers"].has("ice"):
		parts.append("Ледяная нотка ❄️")
	_composition.text = " · ".join(parts)
	var best := float(recipe["best_score"])
	var last := float(recipe["last_score"])
	_stats.text = "Лучший: %.1f (%s)\nПоследний: %.1f (%s)\nИспользован раз: %d" % [
		best, _recipes.config.band_for(best)["name"],
		last, _recipes.config.band_for(last)["name"],
		int(recipe["times_used"])]
	_rename_edit.text = ""
	var secret := str(recipe["secret_id"]) != ""
	_rename_edit.visible = not secret
	_rename_button.visible = not secret


func _on_rename_pressed() -> void:
	if _selected_id.is_empty():
		return
	_recipes.rename(_selected_id, _rename_edit.text)
	_refresh_list()
