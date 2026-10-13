class_name ManualPreparationScreen
extends Control
## Ручное приготовление (M5): мини-игра «ингредиенты → набивка → фольга → дырки → угли → розжиг».
## Экран собирает действия игрока в ManualPreparation; оценку и запись делает PreparationService.

signal closed
## Кальян подан: результат уже записан в рецепт (PreparationService.commit).
signal served(result: Dictionary)

const OK_COLOR := Color(0.6, 0.9, 0.6, 1)
const WARN_COLOR := Color(1.0, 0.75, 0.4, 1)
const STEP_NAMES := {
	"mix": "Состав", "pack": "Набивка", "foil": "Фольга", "holes": "Отверстия", "light": "Розжиг углей", "coals": "Угли на чашу",
}

var _service: PreparationService = null
var _manual: ManualPreparation = null
var _sfx: ManualSfx
var _recipe: Dictionary = {}
## Сколько порций нужно по рецепту (7:7:6 → 3 порции 1:1:1), не больше числа кружков.
var _needed_portions: int = 4
var _targets: Dictionary = {}
var _step_index: int = 0
## Подсказки всегда включены.
var _hints_on: bool = true
var _bowl: BowlView
var _step_labels: Dictionary = {}
var _instruction: Label
var _hint_label: Label
var _tray: HFlowContainer
var _mix_order: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _history: VBoxContainer
var _cold_bucket: CoalBucket
var _hot_bucket: CoalBucket
var _next_button: Button
var _redo_button: Button
var _main_box: VBoxContainer
var _result_box: VBoxContainer
var _result_title: Label
var _result_band: Label
var _result_bar: ProgressBar
var _result_lines: VBoxContainer
var _serve_button: Button
var _pending_result: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func setup(service: PreparationService) -> void:
	_service = service
	_manual = ManualPreparation.new(service.config)
	if is_node_ready():
		for child in get_children():
			child.queue_free()
		_step_labels.clear()
		_build()
		visible = false


## Запускает мини-игру для рецепта. show_hints оставлен для совместимости: подсказки включены всегда.
func open(recipe_id: String, _show_hints: bool = true) -> void:
	if _service == null:
		return
	var recipe := _service.recipes.get_recipe(recipe_id)
	if recipe.is_empty():
		GameLog.error("manual", "Рецепт не найден: %s" % recipe_id)
		return
	_recipe = recipe
	_needed_portions = _compute_needed_portions(recipe)
	_targets = ExecutionScoring.targets(ExecutionScoring.features(recipe, _service.recipes.catalog, _service.recipes.config), _service.config)
	_restart()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func current_step() -> String:
	return ManualPreparation.STEPS[_step_index]


func _restart() -> void:
	_manual.reset()
	_step_index = 0
	_pending_result = {}
	_main_box.visible = true
	_result_box.visible = false
	for child in _history.get_children():
		child.queue_free()
	_enter_step()


func _build() -> void:
	if _service == null:
		return
	_sfx = ManualSfx.new()
	add_child(_sfx)
	var panel := UiStyle.build_frame(self, Vector2(1320, 820))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := UiStyle.label("✋ Ручное приготовление", 34, UiStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_button := Button.new()
	close_button.text = "✕ Закрыть"
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	column.add_child(_main_box)

	var steps_row := HBoxContainer.new()
	steps_row.add_theme_constant_override("separation", 10)
	_main_box.add_child(steps_row)
	for index in ManualPreparation.STEPS.size():
		var step_id: String = ManualPreparation.STEPS[index]
		var label := UiStyle.label("%d. %s" % [index + 1, STEP_NAMES[step_id]], 24, UiStyle.MUTED)
		steps_row.add_child(label)
		_step_labels[step_id] = label

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	_main_box.add_child(body)

	_bowl = BowlView.new()
	_bowl.state = _manual
	for ingredient_id in _service.recipes.catalog.ingredient_ids():
		_bowl.ingredient_emojis[ingredient_id] = str(_service.recipes.catalog.get_ingredient(ingredient_id)["emoji"])
	_bowl.acted.connect(_on_bowl_acted)
	body.add_child(_bowl)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(side)
	_instruction = UiStyle.label("", 26)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.custom_minimum_size = Vector2(620, 90)
	side.add_child(_instruction)
	_hint_label = UiStyle.label("", 22, UiStyle.GOLD)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(620, 60)
	side.add_child(_hint_label)
	_tray = HFlowContainer.new()
	_tray.add_theme_constant_override("h_separation", 8)
	_tray.add_theme_constant_override("v_separation", 8)
	_tray.custom_minimum_size = Vector2(620, 70)
	side.add_child(_tray)
	_history = VBoxContainer.new()
	_history.custom_minimum_size = Vector2(0, 170)
	side.add_child(_history)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	side.add_child(buttons)
	_redo_button = Button.new()
	_redo_button.text = "🧹 Переделать шаг"
	_redo_button.pressed.connect(_on_redo_pressed)
	buttons.add_child(_redo_button)
	_next_button = Button.new()
	_next_button.custom_minimum_size = Vector2(260, 52)
	_next_button.pressed.connect(_on_next_pressed)
	buttons.add_child(_next_button)

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
	_result_lines = VBoxContainer.new()
	_result_box.add_child(_result_lines)
	var again := Button.new()
	again.text = "↩ Начать заново"
	again.pressed.connect(_restart)
	_result_box.add_child(again)
	_serve_button = Button.new()
	_serve_button.custom_minimum_size = Vector2(0, 52)
	_serve_button.pressed.connect(_on_serve_pressed)
	_result_box.add_child(_serve_button)


func _on_bowl_acted(kind: String) -> void:
	_sfx.play(kind)
	_refresh_step_texts()


# --- Шаги ------------------------------------------------------------------------------------------

func _enter_step() -> void:
	var step := current_step()
	if step == "mix":
		_shuffle_mix_order()
	_bowl.step = step
	_bowl.recipe_targets = _targets
	_bowl.hints_on = _hints_on
	for step_id in _step_labels:
		var label: Label = _step_labels[step_id]
		var is_current: bool = step_id == step
		label.add_theme_color_override("font_color", UiStyle.GOLD if is_current else UiStyle.MUTED)
	_next_button.text = "🔥 Приготовить" if _step_index == ManualPreparation.STEPS.size() - 1 else "Далее ➜"
	_rebuild_tray(step)
	_refresh_step_texts()


func _process(_delta: float) -> void:
	# Кнопка «Далее» оживает сразу, как выполнено условие шага (розжиг набрал минимум и т. п.).
	if visible and _manual != null:
		_apply_next_state(current_step())


## «Далее» всегда на месте, но неактивна, пока игрок ничего не сделал на шаге; потом — по условиям шага.
func _apply_next_state(step: String) -> void:
	_next_button.visible = true
	_next_button.disabled = not _manual.has_action(step) or _next_blocked(step)


## Можно ли идти дальше с текущего шага.
func _next_blocked(step: String) -> bool:
	match step:
		"mix":
			return _manual.total_portions() < _needed_portions
		"holes":
			return _manual.holes.size() < _manual.config.manual_holes_min
		"light":
			# Угли разожжены минимум 0.2 с и все сняты с плитки в ведёрко.
			return _manual.average_heat() < ManualPreparation.MIN_HEAT_SECONDS or not _manual.stove_coals.is_empty() or _manual.hot_coals + _manual.coals.size() <= 0
		"coals":
			return _manual.hot_coals > 0 or _manual.coals.is_empty()
	return false


func _refresh_step_texts() -> void:
	var step := current_step()
	_bowl.hints_on = _hints_on
	_instruction.text = _instruction_for(step)
	_hint_label.text = _hint_for(step) if _hints_on else ""
	_apply_next_state(step)
	_update_buckets()


func _instruction_for(step: String) -> String:
	match step:
		"mix":
			var text := "Шаг 1. Перетащи порции в кружки чаши по рецепту: нужно %d (клик по занятому кружку убирает порцию)." % _needed_portions
			text += "\n💰 Ручная работа ценится: гость заплатит на 25% больше, чем за быстрый режим."
			var modifiers: Array = _recipe.get("modifiers", []) as Array
			if modifiers.has("ice"):
				text += "\nВ рецепте есть ❄️ Ледяная нотка — она добавится сама, класть её не нужно."
			return text
		"pack":
			return "Шаг 2. Удерживай мышь на чаше — табак набивается. Отпусти, когда набито как надо."
		"foil":
			return "Шаг 3. Зажми кнопку мыши и води по кругу вдоль края чаши — фольга разглаживается и натягивается. Остановись, когда натяжение в зелёной зоне (ослабить можно кнопкой «Переделать шаг»)."
		"holes":
			return "Шаг 4. Кликай по фольге, чтобы проколоть отверстия: нужно от %d до %d. «Переделать шаг» убирает все." % [_manual.config.manual_holes_min, _manual.config.manual_holes_max]
		"coals":
			return "Шаг 6. Бери горячие угли щипцами из ведёрка (тяни мышью) и клади в любое место чаши. Клик по углю в чаше возвращает его в ведёрко. Лучше всего — кольцом вокруг центра, не слишком кучно."
		"light":
			return "Шаг 5. Щипцами положи угли на плитку, включи её (сначала разогреется спираль, потом угли) и выключи, когда температура в зелёной зоне. Затем щипцами перенеси угли в ведёрко горячих — они понемногу остывают. Пока плитка включена, угли трогать нельзя."
	return ""


func _hint_for(step: String) -> String:
	var target := _manual.hint_target(step, _targets)
	var prep := _service.config
	match step:
		"pack", "foil":
			# Цель на краю шкалы (0% / 100%): честно говорим про «совсем чуть-чуть» и «почти до упора», а не «примерно 0%».
			var parameter_id := "packing" if step == "pack" else "foil"
			var tolerance_share := prep.manual_tolerance(parameter_id) / 2.0
			var name_text := "набивка" if step == "pack" else "натяжение фольги"
			if target <= tolerance_share * 0.5:
				return "💡 Этому рецепту нужна самая лёгкая %s: достаточно чуть-чуть (не больше ~%d%%)." % [name_text, int(round(tolerance_share * 100.0))]
			if target >= 1.0 - tolerance_share * 0.5:
				return "💡 Этому рецепту нужна самая плотная %s: тяни почти до упора (от ~%d%%)." % [name_text, int(round((1.0 - tolerance_share) * 100.0))]
			if step == "pack":
				return "💡 Этому рецепту подойдёт набивка примерно %d%%." % int(round(target * 100.0))
			return "💡 Нужное натяжение фольги — около %d%%." % int(round(target * 100.0))
		"holes":
			return "💡 Нужно примерно %d отверстий." % int(round(target))
		"light":
			var coal_count := int(round(_manual.hint_target("coals", _targets)))
			var burn := _manual.config.manual_light_burn_seconds
			var tolerance_seconds := prep.manual_tolerance("lighting") * _manual.config.manual_light_seconds_per_level
			var coals_text := "Нужно %d %s. Угли можно греть вместе или по одному." % [coal_count, "угля" if coal_count < 5 else "углей"]
			if target <= tolerance_seconds * 0.5:
				return "💡 %s Рецепту хватит самого слабого розжига: чуть подогрей (до ~%d°C) и сразу снимай." % [coals_text, int(round(lerpf(25.0, 400.0, tolerance_seconds / burn)))]
			return "💡 %s Доведи температуру до зелёной зоны (около %d°C)." % [coals_text, int(round(lerpf(25.0, 400.0, target / burn)))]
		"coals":
			return "💡 Угли лучше класть кольцом вокруг центра."
	return ""


func _compute_needed_portions(recipe: Dictionary) -> int:
	var cap := _manual.config.manual_portions
	var selection := MixSelection.new(maxi(_service.recipes.config.max_ingredients, 1), cap)
	selection.load_recipe(recipe, _service.recipes.config.total_units)
	var total := selection.total_portions()
	return clampi(total, 1, cap)


func _recipe_text() -> String:
	var parts: PackedStringArray = []
	for item in _recipe["ingredients"]:
		var percent := int(round(float(item["units"]) / float(_service.recipes.config.total_units) * 100.0))
		parts.append("%s %d%%" % [_service.recipes.catalog.label(item["id"]), percent])
	return " · ".join(parts)


func _rebuild_tray(step: String) -> void:
	_cold_bucket = null
	_hot_bucket = null
	for child in _tray.get_children():
		child.queue_free()
	if step == "mix":
		for ingredient_id in _mix_order:
			var token := DragToken.new()
			token.text = _service.recipes.catalog.label(ingredient_id)
			token.payload = {"kind": "portion", "id": ingredient_id}
			token.preview_text = str(_service.recipes.catalog.get_ingredient(ingredient_id)["emoji"])
			token.custom_minimum_size = Vector2(190, 52)
			token.pressed.connect(_on_token_clicked.bind(ingredient_id))
			_tray.add_child(token)
	elif step == "light":
		_cold_bucket = CoalBucket.new()
		_cold_bucket.accept_kind = "cold_stove_coal"
		_cold_bucket.received.connect(_on_cold_received)
		_tray.add_child(_cold_bucket)
		_hot_bucket = CoalBucket.new()
		_hot_bucket.hot = true
		_hot_bucket.draggable = false
		_hot_bucket.accept_kind = "stove_coal"
		_hot_bucket.received.connect(_on_hot_received)
		_tray.add_child(_hot_bucket)
		# Горячие угли слева, свежие справа.
		_tray.move_child(_hot_bucket, 0)
	elif step == "coals":
		_hot_bucket = CoalBucket.new()
		_hot_bucket.hot = true
		_tray.add_child(_hot_bucket)
	_update_buckets()


## Счётчики ведёрок берутся из состояния мини-игры.
func _update_buckets() -> void:
	if _cold_bucket != null and is_instance_valid(_cold_bucket) and _cold_bucket.is_inside_tree():
		_cold_bucket.count = _manual.config.manual_max_coals - _manual.total_coals()
	if _hot_bucket != null and is_instance_valid(_hot_bucket) and _hot_bucket.is_inside_tree():
		_hot_bucket.count = _manual.hot_coals
		if current_step() == "light":
			# Пока температура не зафиксирована, уголь можно вернуть из ведёрка на плиту.
			_hot_bucket.draggable = _manual.can_return_hot_coal()


func _on_cold_received() -> void:
	# Холодный уголь вернулся в ведёрко со свежими: счётчик считается из состояния.
	_on_bowl_acted("coal")


func _on_hot_received() -> void:
	# Уголь уже снят с плитки при начале перетаскивания; ведёрко его принимает.
	_manual.hot_coals += 1
	_manual.note_hot_coal_collected()
	_on_bowl_acted("coal")


## Все ингредиенты в случайном порядке (каждый раз при входе на шаг состава).
func _shuffle_mix_order() -> void:
	_mix_order.clear()
	for ingredient_id in _service.recipes.catalog.ingredient_ids():
		_mix_order.append(ingredient_id)
	_rng.randomize()
	for i in range(_mix_order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _mix_order[i]
		_mix_order[i] = _mix_order[j]
		_mix_order[j] = tmp


func _on_token_clicked(ingredient_id: String) -> void:
	if _manual.add_portion(ingredient_id):
		_on_bowl_acted("drop")


func _on_redo_pressed() -> void:
	_manual.reset_step(current_step())
	_sfx.play("bad")
	_refresh_step_texts()


func _on_next_pressed() -> void:
	var step := current_step()
	var feedback := _manual.step_feedback(step, _targets, _service.config)
	if not str(feedback["text"]).is_empty():
		_history.add_child(UiStyle.label("%s %s" % ["✓" if feedback["ok"] else "•", feedback["text"]], 22, OK_COLOR if feedback["ok"] else WARN_COLOR))
	if _step_index < ManualPreparation.STEPS.size() - 1:
		_manual.stove_on = false
		_step_index += 1
		_sfx.play("drop")
		_enter_step()
		return
	_finish()


func _finish() -> void:
	var result := _service.preview_manual(str(_recipe["id"]), _manual.levels(), _manual.extras(_recipe, _service.recipes.config.total_units))
	if not result["ok"]:
		GameLog.error("manual", str(result["error"]))
		return
	_pending_result = result
	_main_box.visible = false
	_result_box.visible = true
	_result_title.text = "Кальян готов! %s" % result["recipe_name"]
	_result_band.text = "Исполнение: %s" % result["execution_band"]
	_result_bar.value = float(result["execution_score"])
	var weak := _service.is_weak(result)
	_serve_button.text = "😬 И так сойдет" if weak else "✅ Подать кальян"
	_sfx.play("bad" if weak else "done")
	for child in _result_lines.get_children():
		child.queue_free()
	for detail in result["parameters"]:
		var text := "%s — %s: %s" % [detail["name"], detail["option_name"], detail["hint"]]
		_result_lines.add_child(UiStyle.label(text, 24, OK_COLOR if detail["is_ok"] else WARN_COLOR))


func _on_serve_pressed() -> void:
	if _pending_result.is_empty():
		return
	var result := _pending_result
	_pending_result = {}
	if not _service.commit(result):
		return
	visible = false
	served.emit(result)
