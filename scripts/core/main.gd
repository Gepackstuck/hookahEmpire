extends Node
## Корень игры. Держит мир (WorldRoot) и UI-слой и связывает системы между собой:
## гараж <-> диалоги <-> сюжетные эффекты <-> GameState.

const DIALOGUES_DIR := "res://data/dialogues"
const BEATS_PATH := "res://data/story/intro_beats.json"

var _state: Node = null
var _effects: StoryEffects = null
var _library := DialogueLibrary.new()
var _runner := DialogueRunner.new()
var _beats: StoryBeats = null
var _recipes: RecipeSystem = null
var _preparation: PreparationService = null
var _manual_screen: ManualPreparationScreen = null
var _reaction: GuestReaction = null
var _station := HookahStation.new()
var _order: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _pending_verdict: Dictionary = {}
## Последняя оценка кальяна гостем — чтобы он мог высказаться и при обычном разговоре.
var _last_verdict: Dictionary = {}
## Гость разрешил покурить вместе (сбрасывается при каждой новой подаче).
var _smoke_permission := false
## После отказа просить снова можно только через несколько затяжек гостя.
var _ask_blocked := false
var _puffs_until_ask := 0
var _hookah_at_prep := false
var _pending_serve := false
var _book_from_mixer := false
var _carrying := false
## Кальян стоит на столе для кальянов (взят с полки или принесён на перезабивку).
var _hookah_on_prep_table := false
var _objective_label: Label = null

@onready var _garage: GarageWorld = %Garage
@onready var _toast: MessageToast = %MessageToast
@onready var _dialogue_box: DialogueBox = %DialogueBox
@onready var _mixer: MixerScreen = %MixerScreen
@onready var _book: RecipeBookScreen = %RecipeBookScreen
@onready var _preparation_screen: PreparationScreen = %PreparationScreen


func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	GameLog.info("main", "Boot OK, version %s" % version)
	# GameState/SaveService — autoload; проверяем через путь, чтобы не падать при их отсутствии.
	for autoload_name in ["GameState", "SaveService"]:
		if get_node_or_null("/root/%s" % autoload_name) == null:
			GameLog.error("main", "Autoload не найден: %s" % autoload_name)

	_add_debug_button()
	_add_volume_slider()
	_add_objective_label()
	_garage.friend_arrived.connect(_on_friend_arrived)
	_garage.friend_inhaled.connect(_on_friend_inhaled)
	_garage.message_requested.connect(_toast.show_message)
	_garage.dialogue_requested.connect(_on_dialogue_requested)
	_garage.action_requested.connect(_on_action_requested)
	_mixer.closed.connect(_update_input_lock)
	_preparation_screen.closed.connect(_on_preparation_closed)
	_preparation_screen.prepared.connect(_on_prepared)
	_mixer.recipe_book_requested.connect(_on_book_from_mixer)
	_book.closed.connect(_on_book_closed)
	_book.load_requested.connect(_on_book_load_requested)
	_dialogue_box.advance_requested.connect(_runner.advance)
	_dialogue_box.choice_selected.connect(_runner.choose)
	_runner.node_entered.connect(_dialogue_box.show_node)
	_runner.finished.connect(_on_dialogue_finished)

	_state = get_node_or_null("/root/GameState")
	if _state == null:
		return
	_recipes = RecipeSystem.create(_state)
	if _recipes != null:
		_mixer.setup(_recipes)
		_book.setup(_recipes)
		_mixer.recipe_committed.connect(_on_recipe_committed)
		_reaction = GuestReaction.load_default()
		for message in _reaction.errors:
			GameLog.error("reaction", message)
		_preparation = PreparationService.create(_recipes)
		if _preparation != null:
			_preparation_screen.setup(_preparation)
			_setup_manual_screen()
	_effects = StoryEffects.new(_state)
	_runner.effect_requested.connect(_effects.apply)
	_refresh_objective()

	_library.load_directory(DIALOGUES_DIR)
	for message in _library.errors:
		GameLog.error("dialogue", message)
	_beats = StoryBeats.load_file(BEATS_PATH)
	for message in _beats.errors:
		GameLog.error("story", message)
	_start_story()


## Запускает бит истории, подходящий текущему прогрессу (в M2 — приход Дениса).
func _start_story() -> void:
	var beat := _beats.find_for_progress(_state.story_progress)
	if beat.is_empty():
		return
	await get_tree().create_timer(float(beat["delay"])).timeout
	_run_beat(beat)


func _run_beat(beat: Dictionary) -> void:
	if not _library.has_dialogue(beat["dialogue"]):
		GameLog.error("story", "Бит '%s': нет диалога '%s'" % [beat["id"], beat["dialogue"]])
		return
	var guest := GuestCatalog.load_guest(beat["guest"])
	if guest.is_empty():
		return
	if not _garage.spawn_friend(guest, beat["entry_position"], beat["entry_cell"], beat["stand_cell"], beat["dialogue"], beat["seat"]):
		return
	if not str(beat["sets_progress"]).is_empty():
		_state.set_story_progress(beat["sets_progress"])


## Друг пришёл: кидаем его первый заказ (случайный вкус).
func _on_friend_arrived(guest_id: String) -> void:
	if _order.is_empty():
		var guest := GuestCatalog.load_guest(guest_id)
		if not guest.is_empty():
			_rng.randomize()
			_order = GuestCatalog.roll_order(guest, _rng)
			GameLog.info("guests", "Заказ %s: %s" % [guest_id, str(_order["id"])])
			if _recipes != null:
				_mixer.set_order_hint("💡 Заказ %s: %s" % [str(guest["name"]), OrderHint.suggest(_recipes.catalog, _order["preferences"], 2, _rng)])
	_refresh_objective()


## Ручное приготовление: экран создаётся кодом и стоит поверх окна приготовления.
func _setup_manual_screen() -> void:
	_manual_screen = ManualPreparationScreen.new()
	$UI/Root.add_child(_manual_screen)
	_manual_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_manual_screen.setup(_preparation)
	_preparation_screen.manual_requested.connect(_on_manual_requested)
	_manual_screen.closed.connect(_on_manual_closed)
	_manual_screen.served.connect(_on_manual_served)


func _on_manual_requested(recipe_id: String) -> void:
	_preparation_screen.suspend()
	_manual_screen.open(recipe_id, not _state.has_flag("manual_done"))
	_update_input_lock()


func _on_manual_closed() -> void:
	_preparation_screen.resume()
	_update_input_lock()


func _on_manual_served(result: Dictionary) -> void:
	_state.set_flag("manual_done", true)
	_preparation_screen.complete_with(result)


func _on_friend_inhaled(_guest_id: String) -> void:
	if not _ask_blocked:
		return
	_puffs_until_ask -= 1
	if _puffs_until_ask <= 0:
		_ask_blocked = false
		_apply_station()


func _on_dialogue_requested(dialogue_id: String) -> void:
	# Кальян уже подан: гость говорит, что о нём думает (а не повторяет приветствие).
	if _talk_about_hookah(dialogue_id):
		return
	var dialogue := _library.get_dialogue(dialogue_id)
	if not dialogue.is_empty() and not _order.is_empty():
		dialogue = _with_order_text(dialogue)
	if dialogue.is_empty() or _runner.is_active:
		GameLog.error("dialogue", "Не удалось запустить диалог '%s'" % dialogue_id)
		return
	_update_input_lock()
	_dialogue_box.open(dialogue["speakers"])
	if not _runner.start(dialogue, _effects.check):
		_on_dialogue_finished(dialogue_id)


func _on_dialogue_finished(_dialogue_id: String) -> void:
	_dialogue_box.close()
	_update_input_lock()
	_refresh_objective()


func _talk_about_hookah(dialogue_id: String) -> bool:
	if _last_verdict.is_empty() or _runner.is_active:
		return false
	if _station.state != HookahStation.STATE_LIKED and _station.state != HookahStation.STATE_DISLIKED:
		return false
	var guest_id := str(_last_verdict["guest_id"])
	if _garage.ready_friend_id() != guest_id or not dialogue_id.begins_with(guest_id):
		return false
	_garage.friend_react(guest_id, str(_last_verdict["emoji"]))
	_talk_about_hookah_async(guest_id)
	return true


func _talk_about_hookah_async(guest_id: String) -> void:
	_update_input_lock()
	await _play_verdict_dialogue(guest_id, _last_verdict)
	_update_input_lock()
	_refresh_objective()


## Копия диалога, где {order} заменён текстом текущего заказа.
func _with_order_text(dialogue: Dictionary) -> Dictionary:
	var copy: Dictionary = dialogue.duplicate(true)
	var nodes: Dictionary = copy.get("nodes", {})
	for node_id in nodes:
		var node: Dictionary = nodes[node_id]
		if node.has("text"):
			node["text"] = str(node["text"]).replace("{order}", str(_order["text"]))
	return copy


## Игра "заморожена" для мира, пока открыт любой экран или идёт диалог.
func _update_input_lock() -> void:
	_garage.set_input_locked(_carrying or _mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _runner.is_active)


func _on_action_requested(action_id: String) -> void:
	if _recipes == null:
		_toast.show_message("Система рецептов недоступна (ошибка данных, см. лог).")
		return
	match action_id:
		"open_mixer":
			_mixer.open()
		"open_preparation":
			if _preparation == null:
				_toast.show_message("Приготовление недоступно (ошибка данных, см. лог).")
			elif _garage.ready_friend_id() == "" or not _state.has_flag("denis_order_known"):
				_toast.show_message("Сначала узнай, чего хочет Денис.")
			else:
				if not _hookah_on_prep_table and not _hookah_at_prep:
					_carrying = true
					_update_input_lock()
					_refresh_objective()
					await _garage.fetch_random_hookah()
					_carrying = false
					_hookah_on_prep_table = true
					_refresh_objective()
				_preparation_screen.open()
		"retake_hookah":
			_update_input_lock()
			_carrying = true
			_update_input_lock()
			_refresh_objective()
			await _garage.carry_hookah_to_prep_table()
			_carrying = false
			_hookah_at_prep = true
			_hookah_on_prep_table = true
			_apply_station()
			_refresh_objective()
			_preparation_screen.open()
		"ask_to_smoke":
			_ask_to_smoke()
		"smoke_hookah":
			# Поза и дым игрока включает GarageWorld по player_emoji объекта.
			_state.set_flag("hookah_smoked_once", true)
			_refresh_objective()
		"open_recipe_book":
			_book_from_mixer = false
			_book.open()
		_:
			GameLog.error("main", "Неизвестное действие: %s" % action_id)
	_update_input_lock()


func _on_prepared(result: Dictionary) -> void:
	var verdict := {}
	var guest_id := _garage.ready_friend_id()
	if guest_id != "" and _reaction != null and _reaction.is_valid():
		var guest := GuestCatalog.load_guest(guest_id)
		if not guest.is_empty():
			if not _order.is_empty():
				guest["preferences"] = _order["preferences"]
			verdict = _reaction.evaluate(guest, _recipes.get_recipe(result["recipe_id"]), float(result["execution_score"]), _recipes.catalog, _recipes.config)
			verdict["guest_id"] = guest_id
	_station.apply_result(result, verdict)
	_pending_verdict = verdict
	_pending_serve = true


## После подачи: игрок несёт кальян к столу гостя и ставит его; затем гость реагирует.
func _on_preparation_closed() -> void:
	_update_input_lock()
	if not _pending_serve:
		_refresh_objective()
		return
	_pending_serve = false
	_smoke_permission = false
	_ask_blocked = false
	_carrying = true
	_update_input_lock()
	_refresh_objective()
	await _garage.carry_hookah_to_guest_table()
	_hookah_at_prep = false
	_hookah_on_prep_table = false
	_update_input_lock()
	if _pending_verdict.is_empty():
		_carrying = false
		_update_input_lock()
	else:
		var verdict := _pending_verdict
		_pending_verdict = {}
		_last_verdict = verdict
		var guest_id := str(verdict["guest_id"])
		# Гость сначала делает 3–5 затяжек и только потом выдаёт реакцию.
		_garage.set_friend_smoking(guest_id, true, "")
		await _garage.wait_for_friend_puffs(guest_id, randi_range(3, 5))
		_carrying = false
		_update_input_lock()
		_garage.friend_react(guest_id, str(verdict["emoji"]))
		_garage.set_friend_smoking(guest_id, _station.guest_smokes(), str(verdict["emoji"]))
		GameLog.info("reaction", "%s: %s (score %.1f)" % [guest_id, str(verdict["emotion_id"]), float(verdict["score"])])
		await _play_verdict_dialogue(guest_id, verdict)
	_apply_station()
	_update_input_lock()
	_refresh_objective()


## Гость высказывается о кальяне (и просит перезабить, если не понравилось) — только потом доступны действия.
## Просим у гостя разрешения покурить с ним: он случайно соглашается или отказывает.
func _ask_to_smoke() -> void:
	var guest_id := _station.guest_id
	var guest := GuestCatalog.load_guest(guest_id)
	if guest.is_empty() or _runner.is_active:
		return
	_rng.randomize()
	var allowed := GuestCatalog.roll_smoke_permission(guest, _rng)
	var lines: Array = [
		["player", GuestCatalog.smoke_line(guest, "ask", _rng)],
		["guest", GuestCatalog.smoke_line(guest, "yes" if allowed else "no", _rng)]]
	_update_input_lock()
	await _play_lines(guest, lines)
	_garage.friend_react(guest_id, "👍" if allowed else "🙅")
	if allowed:
		_smoke_permission = true
	else:
		_ask_blocked = true
		_puffs_until_ask = randi_range(3, 5)
	_apply_station()
	_update_input_lock()
	_refresh_objective()


## Показывает короткий диалог из пар [говорящий ("player"/"guest"), текст] и ждёт его конца.
func _play_lines(guest: Dictionary, lines: Array) -> void:
	var nodes := {}
	for index in lines.size():
		var node := {"speaker": str(lines[index][0]), "text": str(lines[index][1])}
		if index + 1 < lines.size():
			node["next"] = "line_%d" % (index + 1)
		else:
			node["end"] = true
		nodes["line_%d" % index] = node
	var dialogue := {
		"id": "lines_%s" % str(guest["id"]),
		"start": [{"node": "line_0"}],
		"speakers": {
			"player": {"name": "Я", "portrait": "🕺"},
			"guest": {"name": str(guest["name"]), "portrait": str(guest["emoji"])}},
		"nodes": nodes,
	}
	_dialogue_box.open(dialogue["speakers"])
	_update_input_lock()
	if _runner.start(dialogue, _effects.check):
		await _runner.finished


func _play_verdict_dialogue(guest_id: String, verdict: Dictionary) -> void:
	var guest := GuestCatalog.load_guest(guest_id)
	if guest.is_empty() or _runner.is_active:
		return
	_rng.randomize()
	var text := GuestCatalog.reaction_text(guest, str(verdict["emotion_id"]), bool(verdict["likes"]), _rng)
	var dialogue := {
		"id": "verdict_%s" % guest_id,
		"start": [{"node": "verdict"}],
		"speakers": {"guest": {"name": str(guest["name"]), "portrait": str(guest["emoji"])}},
		"nodes": {"verdict": {"speaker": "guest", "text": text, "end": true}},
	}
	_dialogue_box.open(dialogue["speakers"])
	_update_input_lock()
	if _runner.start(dialogue, _effects.check):
		await _runner.finished


## Стол для кальянов и стол гостя: подсказки и действия зависят от состояния кальяна.
func _apply_station() -> void:
	var retake := _station.state == HookahStation.STATE_DISLIKED and not _hookah_at_prep
	if _station.can_prepare() and not retake:
		_garage.configure_interaction("table_hookah", _station.prompt(), "open_preparation")
	else:
		_garage.configure_interaction("table_hookah", "", "", "", "", false)
	if retake:
		_garage.configure_interaction("table_guest", "Забрать и перезабить", "retake_hookah")
	elif _station.can_smoke() and (_smoke_permission or _station.guest_id == ""):
		_garage.configure_interaction("table_guest", "Покурить", "smoke_hookah", _station.player_emoji(), _station.message())
	elif _station.can_smoke() and not _ask_blocked:
		_garage.configure_interaction("table_guest", "Попросить покурить", "ask_to_smoke")
	else:
		_garage.configure_interaction("table_guest", "", "", "", "", false)


func _refresh_objective() -> void:
	if _objective_label == null or _state == null:
		return
	var friend_id := _garage.ready_friend_id()
	var goal := ObjectiveTracker.current({
		"busy": _carrying,
		"friend_ready": friend_id != "",
		"friend_id": friend_id,
		"order_known": _state.has_flag("denis_order_known"),
		"recipe_count": _state.recipes.size(),
		"station_state": _station.state,
		"smoked_once": _state.has_flag("hookah_smoked_once"),
		"hookah_at_prep": _hookah_at_prep,
	})
	_objective_label.text = str(goal["text"])
	_objective_label.visible = not _objective_label.text.is_empty()
	_garage.set_marker(str(goal["target"]))


## Подсказка цели вверху экрана (под окнами, чтобы не мешать им).
func _add_objective_label() -> void:
	_objective_label = Label.new()
	_objective_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objective_label.offset_left = -500.0
	_objective_label.offset_right = 500.0
	_objective_label.offset_top = 16.0
	_objective_label.offset_bottom = 60.0
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 28)
	_objective_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_objective_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_objective_label.add_theme_constant_override("outline_size", 8)
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_label.visible = false
	$UI/Root.add_child(_objective_label)
	$UI/Root.move_child(_objective_label, 1)


## Отладка: F9 или кнопка 🔃 в углу освобождают кальян (в релизе это делают заказы гостей, M6).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_fullscreen()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_debug_reset_hookah()


func _debug_reset_hookah() -> void:
	var guest_id := _station.guest_id
	_station.reset()
	_last_verdict = {}
	_smoke_permission = false
	_ask_blocked = false
	_hookah_at_prep = false
	_hookah_on_prep_table = false
	_apply_station()
	_garage.hide_object(GarageWorld.HOOKAH_OBJECT_ID)
	_garage.hide_object(GarageWorld.HOOKAH_PREP_OBJECT_ID)
	_garage.restock_shelf()
	_garage.reset_hose()
	if guest_id != "":
		_garage.set_friend_smoking(guest_id, false)
	_toast.show_message("Отладка: кальян снова пустой.")
	_refresh_objective()


## Полноэкранный режим (F11); игра масштабируется под экран (stretch canvas_items + expand).
func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Громкость: ползунок рядом с кнопкой отладки; по умолчанию 0%.
const DEFAULT_VOLUME_PERCENT := 0.0


func _add_volume_slider() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -290.0
	box.offset_right = -84.0
	box.offset_top = 16.0
	box.offset_bottom = 68.0
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_END
	var icon := Label.new()
	icon.text = "🔊"
	icon.add_theme_font_size_override("font_size", 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = DEFAULT_VOLUME_PERCENT
	slider.custom_minimum_size = Vector2(150, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = "Громкость"
	slider.value_changed.connect(_set_volume_percent)
	box.add_child(slider)
	$UI/Root.add_child(box)
	_set_volume_percent(DEFAULT_VOLUME_PERCENT)


func _set_volume_percent(percent: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(percent, 0.0, 100.0) / 100.0))
	AudioServer.set_bus_mute(0, percent <= 0.0)


## Кнопка 🔃 в правом верхнем углу (только в отладочной сборке).
func _add_debug_button() -> void:
	if not OS.is_debug_build():
		return
	var button := Button.new()
	button.text = "🔃"
	button.tooltip_text = "Отладка: освободить кальян (F9)"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 28)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -72.0
	button.offset_right = -16.0
	button.offset_top = 16.0
	button.offset_bottom = 68.0
	button.pressed.connect(_debug_reset_hookah)
	$UI/Root.add_child(button)


func _on_book_from_mixer() -> void:
	_book_from_mixer = true
	_mixer.suspend()
	_book.open()


func _on_book_closed() -> void:
	if _book_from_mixer:
		_book_from_mixer = false
		_mixer.resume()
	_update_input_lock()


func _on_book_load_requested(recipe_id: String) -> void:
	var recipe := _recipes.get_recipe(recipe_id)
	if recipe.is_empty():
		return
	_book_from_mixer = false
	_book.close()
	_mixer.open()
	_mixer.load_recipe(recipe)
	_update_input_lock()


func _on_recipe_committed(result: Dictionary) -> void:
	_refresh_objective()
	GameLog.info("recipes", "Рецепт '%s' %s" % [result["recipe_id"], "создан" if result["is_new"] else "использован повторно"])
