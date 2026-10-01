extends Node
## Корень игры. Держит мир (WorldRoot) и UI-слой и связывает системы между собой:
## гараж <-> диалоги <-> сюжетные эффекты <-> GameState.

## Сессия гостя закончилась: хук для репутации/экономики (M8–M9). result — итог оценки + guest_id, recipe_id.
signal session_finished(result: Dictionary)

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
var _scoring: SessionScoring = null
var _summary: SessionSummaryScreen = null
var _viewer: ImageViewer = null
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
## Вкусы предыдущего гостя: следующий гость со случайным вкусом старается отличаться от них.
var _last_order_prefs: Dictionary = {}
## Гость попрощался и уходит: стол и кальян недоступны.
var _guest_departing := false
var _pending_serve := false
var _book_from_mixer := false
var _carrying := false
## Кальян стоит на столе для кальянов (взят с полки или принесён на перезабивку).
var _hookah_on_prep_table := false
var _objective_label: Label = null
## Автопилот: кальянщик сам принимает заказ, смешивает рецепт, готовит и подаёт (затравка под нанятых работников).
var _autopilot := false
var _autopilot_running := false
var _autopilot_button: Button = null
var _camera_button: Button = null
var _camera_follow := true
var _autopilot_dialogue_timer := 0.0
var _autopilot_summary_timer := 0.0
const AUTOPILOT_DIALOGUE_DELAY := 1.8
const AUTOPILOT_SUMMARY_DELAY := 3.5
var _autopilot_dialogue_wait := AUTOPILOT_DIALOGUE_DELAY
## Над кем из гостей сейчас светятся вкусы (чипы), "" — ни над кем.
var _wants_guest_id := ""

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
	_garage.message_requested.connect(_notify)
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
	_runner.node_entered.connect(_on_node_entered)
	_runner.finished.connect(_on_dialogue_finished)

	_state = get_node_or_null("/root/GameState")
	if _state == null:
		return
	_recipes = RecipeSystem.create(_state)
	if _recipes != null:
		_mixer.setup(_recipes)
		_book.setup(_recipes)
		_mixer.recipe_committed.connect(_on_recipe_committed)
		_scoring = SessionScoring.load_default()
		for message in _scoring.errors:
			GameLog.error("scoring", message)
		_preparation = PreparationService.create(_recipes)
		if _preparation != null:
			_preparation_screen.setup(_preparation)
			_setup_manual_screen()
		_setup_summary_screen()
		_setup_image_viewer()
	_effects = StoryEffects.new(_state)
	_runner.effect_requested.connect(_effects.apply)
	_refresh_objective()

	_library.load_directory(DIALOGUES_DIR)
	for message in _library.errors:
		GameLog.error("dialogue", message)
	_beats = StoryBeats.load_file(BEATS_PATH)
	for message in _beats.errors:
		GameLog.error("story", message)
	_apply_station()
	_start_story()
	# Автопилот по умолчанию включён (в отладочной сборке, где есть кнопка 🤖).
	if OS.is_debug_build():
		_set_autopilot.call_deferred(true)


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


## Друг пришёл: кидаем его заказ (случайный вкус; гость со случайным вкусом отличается от предыдущего).
func _on_friend_arrived(guest_id: String) -> void:
	if _order.is_empty():
		var guest := GuestCatalog.load_guest(guest_id)
		if not guest.is_empty():
			_rng.randomize()
			_order = GuestCatalog.roll_order(guest, _rng, _last_order_prefs)
			_last_order_prefs = _order["preferences"]
			GameLog.info("guests", "Заказ %s: %s %s" % [guest_id, str(_order["id"]), str(_order["preferences"])])
			if _recipes != null:
				_mixer.set_order_hint("💡 Заказ %s: %s" % [str(guest["name"]), OrderHint.suggest(_recipes.catalog, _order["preferences"], 2, _rng)])
	_apply_station()
	_refresh_objective()


## Итоговая карточка сессии: создаётся кодом и стоит поверх всего.
func _setup_image_viewer() -> void:
	_viewer = ImageViewer.new()
	$UI/Root.add_child(_viewer)
	_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer.closed.connect(_update_input_lock)
	_garage.image_requested.connect(_on_image_requested)


func _on_image_requested(path: String, title: String, description: String) -> void:
	if _viewer != null and _viewer.open(path, title, description):
		_update_input_lock()


func _setup_summary_screen() -> void:
	_summary = SessionSummaryScreen.new()
	$UI/Root.add_child(_summary)
	_summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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


## Подсказки/сообщения не показываются в режиме NPC.
func _notify(text: String) -> void:
	if not _autopilot:
		_toast.show_message(text)


## Окно диалога; в режиме NPC реплики идут облачками над головами (см. _on_node_entered).
func _open_dialogue_ui(speakers: Dictionary) -> void:
	if not _autopilot:
		_dialogue_box.open(speakers)


func _on_node_entered(node: Dictionary, choices: Array) -> void:
	if not _autopilot:
		_dialogue_box.show_node(node, choices)
		return
	var who := "player" if str(node.get("speaker", "")) == "player" else _dialogue_guest_id()
	var duration := _garage.say(who, str(node.get("text", "")), str(node.get("emoji", "")))
	_autopilot_dialogue_wait = maxf(duration, 1.0) + 0.3
	_autopilot_dialogue_timer = 0.0


## Гость, который сейчас говорит/слушает.
func _dialogue_guest_id() -> String:
	var guest_id := _garage.ready_friend_id()
	return guest_id if guest_id != "" else _station.guest_id


func _on_dialogue_requested(dialogue_id: String) -> void:
	# Кальян уже подан: гость говорит, что о нём думает (а не повторяет приветствие).
	if _talk_about_hookah(dialogue_id):
		return
	# Подошли к гостю: если в коробке мало мундштуков, кальянщик докладывает новые.
	if dialogue_id.begins_with("friend_") and not _autopilot and _garage.top_up_mouthpieces(2):
		_notify("Кальянщик докладывает мундштуки в коробку.")
	var dialogue := _library.get_dialogue(dialogue_id)
	if not dialogue.is_empty() and not _order.is_empty():
		dialogue = _with_order_text(dialogue)
	if dialogue.is_empty() or _runner.is_active:
		GameLog.error("dialogue", "Не удалось запустить диалог '%s'" % dialogue_id)
		return
	_update_input_lock()
	_open_dialogue_ui(dialogue["speakers"])
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
	# Мышь (маски, книги, свиток) работает, пока не открыто окно или диалог.
	_garage.set_pointer_enabled(not (_mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) \
		or (_summary != null and _summary.visible) or (_viewer != null and _viewer.visible) or (_runner.is_active and not _autopilot)))
	_garage.set_input_locked(_carrying or _mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or (_summary != null and _summary.visible) or _runner.is_active or _autopilot)


func _on_action_requested(action_id: String) -> void:
	if _recipes == null:
		_notify("Система рецептов недоступна (ошибка данных, см. лог).")
		return
	match action_id:
		"open_mixer":
			_mixer.open()
		"open_preparation":
			if _preparation == null:
				_notify("Приготовление недоступно (ошибка данных, см. лог).")
			elif not _order_known():
				_notify("Сначала узнай, чего хочет гость.")
			else:
				await _ensure_hookah_on_prep_table()
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


## Кальян берётся с полки и ставится на стол для кальянов (если его там ещё нет).
func _ensure_hookah_on_prep_table() -> void:
	if _hookah_on_prep_table:
		return
	_carrying = true
	_update_input_lock()
	_refresh_objective()
	await _garage.fetch_random_hookah()
	_carrying = false
	_hookah_on_prep_table = true
	_refresh_objective()


func _on_prepared(result: Dictionary) -> void:
	var verdict := {}
	var guest_id := _garage.ready_friend_id()
	if guest_id != "" and _scoring != null and _scoring.is_valid():
		var guest := GuestCatalog.load_guest(guest_id)
		if not guest.is_empty():
			var taste := {"preferences": guest.get("preferences", {}), "dislikes": guest.get("dislikes", {})}
			if not _order.is_empty():
				taste["preferences"] = _order["preferences"]
				taste["dislikes"] = _order.get("dislikes", taste["dislikes"])
			var recipe := _recipes.get_recipe(result["recipe_id"])
			verdict = _scoring.evaluate(taste, recipe, float(result["execution_score"]), _recipes.catalog, _recipes.config)
			verdict["guest_id"] = guest_id
			verdict["recipe_id"] = str(result["recipe_id"])
			_recipes.record_session(str(result["recipe_id"]), float(verdict["final_score"]), guest_id, int(verdict["payment"]))
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
	_hookah_on_prep_table = false
	_update_input_lock()
	var finished_guest := ""
	var finished_verdict := {}
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
		_clear_wants_badge()
		if not _autopilot:
			_garage.friend_react(guest_id, str(verdict["emoji"]))
		_garage.set_friend_smoking(guest_id, _station.guest_smokes(), str(verdict["emoji"]))
		GameLog.info("reaction", "%s: %s (score %.1f)" % [guest_id, str(verdict["emotion_id"]), float(verdict["score"])])
		verdict["phrase"] = await _play_verdict_dialogue(guest_id, verdict)
		await _show_summary(guest_id, verdict)
		finished_guest = guest_id
		finished_verdict = verdict
	_apply_station()
	_update_input_lock()
	_refresh_objective()
	if finished_guest != "":
		_finish_session(finished_guest, finished_verdict)


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
	_open_dialogue_ui(dialogue["speakers"])
	_update_input_lock()
	if _runner.start(dialogue, _effects.check):
		await _runner.finished


func _play_verdict_dialogue(guest_id: String, verdict: Dictionary) -> String:
	var guest := GuestCatalog.load_guest(guest_id)
	if guest.is_empty() or _runner.is_active:
		return ""
	_rng.randomize()
	var text := GuestCatalog.reaction_text(guest, str(verdict["emotion_id"]), bool(verdict["likes"]), _rng)
	var dialogue := {
		"id": "verdict_%s" % guest_id,
		"start": [{"node": "verdict"}],
		"speakers": {"guest": {"name": str(guest["name"]), "portrait": str(guest["emoji"])}},
		"nodes": {"verdict": {"speaker": "guest", "text": text, "emoji": str(verdict.get("emoji", "")), "end": true}},
	}
	_open_dialogue_ui(dialogue["speakers"])
	_update_input_lock()
	if _runner.start(dialogue, _effects.check):
		await _runner.finished
	return text


## Карточка итогов сессии: показывается после реакции гостя, ждёт кнопку «Дальше».
func _show_summary(guest_id: String, verdict: Dictionary) -> void:
	var guest := GuestCatalog.load_guest(guest_id)
	var recipe := _recipes.get_recipe(str(verdict["recipe_id"]))
	if guest.is_empty() or recipe.is_empty() or _summary == null:
		return
	if _autopilot:
		# Режим NPC: без карточки — оценка видна по реакции и репликам над головами.
		GameLog.info("session", "Итог (NPC): %.1f, оплата %d" % [float(verdict["final_score"]), int(verdict["payment"])])
		return
	_summary.open({
		"guest_name": str(guest["name"]),
		"guest_emoji": str(guest["emoji"]),
		"recipe_name": _recipes.display_name(recipe),
		"composition": _recipes.composition_text(recipe),
		"verdict": verdict,
		"phrase": str(verdict.get("phrase", "")),
		"weights": _scoring.weights,
	})
	_update_input_lock()
	await _summary.continued
	_update_input_lock()


## Конец сессии: гость докуривает (если понравилось; игрок может присесть рядом), прощается и платит,
## встаёт, уходит через дверь; стол освобождается, через паузу приходит следующий гость.
func _finish_session(guest_id: String, verdict: Dictionary) -> void:
	var guest := GuestCatalog.load_guest(guest_id)
	var payment := int(verdict["payment"])
	var likes := bool(verdict["likes"])
	session_finished.emit({
		"guest_id": guest_id, "recipe_id": str(verdict["recipe_id"]), "final_score": float(verdict["final_score"]),
		"band_id": str(verdict["band_id"]), "payment": payment, "reputation_delta": int(verdict["reputation_delta"])})
	GameLog.info("session", "%s: %.1f (%s), оплата %d" % [guest_id, float(verdict["final_score"]), str(verdict["band_id"]), payment])
	if likes:
		await _garage.wait_for_friend_puffs(guest_id, randi_range(6, 12))
	_garage.set_friend_smoking(guest_id, false)
	await _wait_until_free()
	_rng.randomize()
	if not guest.is_empty():
		var line := GuestCatalog.farewell_text(guest, str(verdict["emotion_id"]), likes, payment, _rng)
		await _play_lines(guest, [["guest", line]])
	_guest_departing = true
	_station.reset()
	_last_verdict = {}
	_smoke_permission = false
	_ask_blocked = false
	_apply_station()
	await _garage.friend_leave(guest_id)
	_order = {}
	_mixer.set_order_hint("")
	var progress: String = _state.story_progress
	if progress.ends_with("_intro_done"):
		_state.set_story_progress(progress.replace("_intro_done", "_done"))
	_guest_departing = false
	_apply_station()
	# Новый гость приходит и садится, пока кальянщик моет кальян и убирает его на полку.
	_start_story()
	_carrying = true
	_update_input_lock()
	_refresh_objective()
	await _garage.wash_hookah_and_shelve()
	_carrying = false
	_update_input_lock()
	_apply_station()
	_refresh_objective()


## Ждёт, пока игрок закончит диалог/закроет окна (чтобы прощание не легло поверх них).
func _wait_until_free() -> void:
	while _runner.is_active or _mixer.visible or _book.visible or _preparation_screen.visible \
			or (_manual_screen != null and _manual_screen.visible) or (_summary != null and _summary.visible):
		await get_tree().process_frame


## Стол для кальянов и стол гостя: подсказки и действия зависят от состояния кальяна.
func _apply_station() -> void:
	if _station.can_prepare() and _garage.has_friend() and not _guest_departing:
		_garage.configure_interaction("table_hookah", _station.prompt(), "open_preparation")
	else:
		_garage.configure_interaction("table_hookah", "", "", "", "", false)
	if _guest_departing:
		_garage.configure_interaction("table_guest", "", "", "", "", false)
	elif _station.can_smoke() and (_smoke_permission or _station.guest_id == ""):
		_garage.configure_interaction("table_guest", "Покурить", "smoke_hookah", _station.player_emoji(), _station.message())
	elif _station.can_smoke() and not _ask_blocked:
		_garage.configure_interaction("table_guest", "Попросить покурить", "ask_to_smoke")
	else:
		_garage.configure_interaction("table_guest", "", "", "", "", false)


## Известен ли заказ гостя, который сейчас у стола (диалог ставит флаг "<имя>_order_known").
func _order_known() -> bool:
	var guest_id := _garage.ready_friend_id()
	if guest_id == "" or _state == null:
		return false
	var flag := "%s_order_known" % guest_id.trim_prefix("friend_")
	return _state.has_flag(flag) and _state.get_flag(flag) == true


func _refresh_objective() -> void:
	if _objective_label == null or _state == null:
		return
	if _autopilot:
		_objective_label.visible = false
		_garage.set_marker("")
		return
	var friend_id := _garage.ready_friend_id()
	var goal := ObjectiveTracker.current({
		"busy": _carrying,
		"friend_ready": friend_id != "",
		"friend_id": friend_id,
		"friend_name": str(GuestCatalog.load_guest(friend_id).get("name", "")) if friend_id != "" else "",
		"has_friend": _garage.has_friend(),
		"day_over": _beats != null and _beats.find_for_progress(_state.story_progress).is_empty(),
		"order_known": _order_known(),
		"recipe_count": _state.recipes.size(),
		"station_state": _station.state,
		"smoked_once": _state.has_flag("hookah_smoked_once"),
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


# --- Автопилот ---------------------------------------------------------------------------------

func _set_autopilot(on: bool) -> void:
	_autopilot = on
	if _autopilot_button != null:
		_autopilot_button.set_pressed_no_signal(on)
		_autopilot_button.modulate = Color(0.55, 1.0, 0.6) if on else Color.WHITE
	# Режим NPC: камера по умолчанию следует за кальянщиком (кнопка 🎥 отключает следование и ставит камеру по центру); вручную — как раньше.
	_camera_follow = true
	if _camera_button != null:
		_camera_button.disabled = not on
		_camera_button.set_pressed_no_signal(on)
		_camera_button.modulate = Color(0.55, 1.0, 0.6) if on else Color.WHITE
	_garage.set_camera_follow(true)
	_toast.show_message("Автопилот включён: кальянщик работает сам." if on else "Автопилот выключен.")
	_update_input_lock()
	_refresh_objective()
	if on:
		if not _autopilot_running:
			_autopilot_loop()
	else:
		_clear_wants_badge()
		_garage.clear_all_head_labels()
		# Диалог, начатый облачками, закрываем: окна у него нет.
		while _runner.is_active:
			if _runner.available_choices().is_empty():
				_runner.advance()
			else:
				_runner.choose(0)


func _on_camera_button_toggled(pressed: bool) -> void:
	_camera_follow = pressed
	if _camera_button != null:
		_camera_button.modulate = Color(0.55, 1.0, 0.6) if pressed else Color.WHITE
	_garage.set_camera_follow(pressed)


func _autopilot_loop() -> void:
	_autopilot_running = true
	while _autopilot:
		await get_tree().create_timer(0.6).timeout
		if _autopilot:
			await _autopilot_step()
	_autopilot_running = false


## Один шаг автопилота: смотрит, что сейчас нужно гостю, и делает это (разговор -> рецепт -> кальян -> подача).
func _autopilot_step() -> void:
	if _recipes == null or _preparation == null or _scoring == null or _state == null:
		return
	if _carrying or _guest_departing or _runner.is_active or _mixer.visible or _book.visible \
			or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _summary.visible:
		return
	var guest_id := _garage.ready_friend_id()
	if not _autopilot_needs_action():
		# Делать нечего (гость курит или ждём нового): изображаем работу у объектов гаража.
		await _autopilot_idle()
		return
	if not _order_known():
		await _autopilot_talk(guest_id)
	elif _station.state == HookahStation.STATE_EMPTY and not _order.is_empty():
		if _wants_guest_id != guest_id:
			_show_wants_badge(guest_id)
		await _autopilot_serve()


## Объекты, у которых кальянщик «работает», пока ждёт: раковина, стол для кальянов, стол смешивания, полка, книга рецептов.
const IDLE_TARGETS := {
	"sink_wash": ["💦", "🫧", "🧽"],
	"table_hookah": ["🔥", "🧰", "💨"],
	"table_test": ["🧪", "🍓", "🍋", "❄️"],
	"shelf_hookah": ["📦", "🔍", "🧐"],
	"recipe_book": ["📖", "🤔", "✍️"],
}
const IDLE_MIN_SECONDS := 3.0
const IDLE_MAX_SECONDS := 6.0
var _idle_last := ""


## Есть ли у кальянщика реальное дело: новый гость без заказа или заказ, ожидающий кальяна.
func _autopilot_needs_action() -> bool:
	if _garage.ready_friend_id() == "":
		return false
	if not _order_known():
		return true
	return _station.state == HookahStation.STATE_EMPTY and not _order.is_empty()


func _autopilot_busy() -> bool:
	return _carrying or _guest_departing or _runner.is_active or _mixer.visible or _book.visible \
		or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _summary.visible \
		or (_viewer != null and _viewer.visible)


## Один «заход» простоя: идёт к случайному объекту (не к тому же, что в прошлый раз) и 3–6 с делает вид, что работает.
## Прерывается, как только появляется настоящее дело.
func _autopilot_idle() -> void:
	var options: Array = []
	for id in IDLE_TARGETS:
		if id != _idle_last and _garage.has_object(id):
			options.append(id)
	if options.is_empty():
		return
	var target: String = options.pick_random()
	_idle_last = target
	_carrying = true
	_update_input_lock()
	await _garage.walk_to_object(target)
	_carrying = false
	_update_input_lock()
	var emojis: Array = IDLE_TARGETS[target]
	var duration := randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)
	var elapsed := 0.0
	var next_emoji := 0.0
	_garage.set_idle_work(target, true)
	while elapsed < duration and _autopilot and not _autopilot_busy() and not _autopilot_needs_action():
		if elapsed >= next_emoji:
			_garage.set_chips("player", [{"emoji": str(emojis.pick_random()), "state": "pick"}])
			next_emoji += 1.1
		await get_tree().create_timer(0.2).timeout
		elapsed += 0.2
	_garage.set_idle_work(target, false)
	_garage.clear_chips("player")


func _autopilot_talk(guest_id: String) -> void:
	var dialogue_id := _garage.friend_dialogue_id(guest_id)
	if dialogue_id == "":
		return
	_carrying = true
	_update_input_lock()
	# Мало мундштуков — сначала к коробке, докладываем, и только потом к гостю за заказом.
	if _garage.mouthpieces_low(2):
		await _garage.walk_to_mouthpiece_box()
		if not _autopilot:
			_carrying = false
			return
		_garage.say("player", "Докладываю мундштуки в коробку.")
		await get_tree().create_timer(1.4).timeout
		_garage.top_up_mouthpieces(2)
	await _garage.walk_to_friend(guest_id)
	_carrying = false
	_on_dialogue_requested(dialogue_id)
	while _runner.is_active and _autopilot:
		await get_tree().process_frame
	if _autopilot and _order_known() and not _order.is_empty():
		_show_wants_badge(guest_id)


## Кальянщик сам выбирает рецепт под заказ. Подходящий рецепт есть в книге — сразу идёт за кальяном и забивает.
## Нет — сначала идёт к столу смешивания и подбирает вкус (над головой мелькают ингредиенты, не всегда удачно),
## и только потом берёт кальян, готовит с мелкими ошибками и подаёт гостю.
func _autopilot_serve() -> void:
	_rng.randomize()
	var taste := {"preferences": _order["preferences"], "dislikes": _order.get("dislikes", {})}
	var recipe_id := AutoCook.find_fitting_recipe(_recipes.all_recipes(), _recipes.catalog, _recipes.config, _scoring, taste, AutoCook.FIT_MIN_FOR_EXISTING)
	if recipe_id != "":
		var known := _recipes.get_recipe(recipe_id)
		_garage.say("player", "Есть подходящий рецепт: %s." % _recipes.display_name(known))
		var items := AutoCook.recipe_items(known)
		_garage.set_chips("player", TasteIcons.cook_chips(_recipes.catalog, items, taste["preferences"], taste["dislikes"]))
		_update_wants_badge(items, true)
		await get_tree().create_timer(1.2).timeout
	else:
		recipe_id = await _autopilot_mix_new_recipe()
		if recipe_id == "":
			return
	if not _autopilot:
		_garage.clear_chips("player")
		return
	_refresh_objective()
	await _ensure_hookah_on_prep_table()
	if not _autopilot:
		_garage.clear_chips("player")
		return
	var recipe := _recipes.get_recipe(recipe_id)
	var choices := AutoCook.pick_choices(_preparation.config, recipe, _recipes.catalog, _recipes.config, _rng)
	var result := _preparation.preview(recipe_id, choices)
	if not result["ok"] or not _preparation.commit(result):
		GameLog.error("autopilot", "Не удалось приготовить %s" % recipe_id)
		_garage.clear_chips("player")
		return
	# Забивка: выбранные вкусы остаются над головой, пока кальянщик набивает чашу.
	await get_tree().create_timer(1.5).timeout
	_garage.clear_chips("player")
	_on_prepared(result)
	await _on_preparation_closed()


## Идёт к столу смешивания, подбирает новый микс под заказ и сохраняет его в книгу. Возвращает id рецепта ("" — не вышло).
func _autopilot_mix_new_recipe() -> String:
	var mix := {}
	for attempt in 6:
		var noise := AutoCook.DEFAULT_NOISE if attempt < 3 else 0.0
		var candidate := AutoCook.pick_mix(_recipes.catalog, _order["preferences"], _rng, noise)
		if _recipes.evaluate(candidate["selection"], candidate["modifiers"])["ok"]:
			mix = candidate
			break
	if mix.is_empty():
		GameLog.error("autopilot", "Не удалось составить микс под заказ %s" % str(_order.get("id", "")))
		return ""
	_carrying = true
	_update_input_lock()
	_refresh_objective()
	await _garage.walk_to_object("table_test")
	_garage.say("player", "Такого вкуса в книге нет — смешаю новый.")
	var items: Array = mix["selection"].keys()
	for modifier in mix["modifiers"]:
		items.append(modifier)
	await _autopilot_pick_animation(items)
	var committed := {}
	if _autopilot:
		committed = _recipes.commit(mix["selection"], mix["modifiers"])
	_carrying = false
	_update_input_lock()
	if not committed.get("ok", false):
		_garage.clear_chips("player")
		return ""
	GameLog.info("autopilot", "Заказ %s -> новый рецепт %s" % [str(_order.get("id", "")), str(committed["recipe_id"])])
	return str(committed["recipe_id"])


## Над кальянщиком по очереди мелькают эмодзи ингредиентов, пока он не остановится на выбранном;
## выбранные подсвечиваются зелёным (подходит гостю) или красным (нет), у гостя совпавшие вкусы зеленеют.
func _autopilot_pick_animation(items: Array) -> void:
	var prefs: Dictionary = _order["preferences"]
	var dislikes: Dictionary = _order.get("dislikes", {})
	var all_ids: Array[String] = _recipes.catalog.ingredient_ids()
	var settled: Array = []
	for item in items:
		var steps := randi_range(7, 11)
		for i in steps:
			if not _autopilot:
				return
			var shown: String = all_ids.pick_random() if i < steps - 1 else str(item)
			var chips := TasteIcons.cook_chips(_recipes.catalog, settled, prefs, dislikes)
			chips.append({"emoji": TasteIcons.item_emoji(_recipes.catalog, shown), "state": "pick"})
			_garage.set_chips("player", chips)
			await get_tree().create_timer(0.13).timeout
		settled.append(item)
		_garage.set_chips("player", TasteIcons.cook_chips(_recipes.catalog, settled, prefs, dislikes))
		_update_wants_badge(settled, false)
		await get_tree().create_timer(0.35).timeout
	_update_wants_badge(settled, true)
	await get_tree().create_timer(1.0).timeout


## Вкусы, которые хочет гость, светятся у него над головой, пока он не попробует кальян.
func _show_wants_badge(guest_id: String) -> void:
	_wants_guest_id = guest_id
	_update_wants_badge([], false)


func _update_wants_badge(chosen: Array, final: bool) -> void:
	if _wants_guest_id == "" or _order.is_empty():
		return
	_garage.set_chips(_wants_guest_id, TasteIcons.guest_chips(_recipes.catalog, _order["preferences"], _order.get("dislikes", {}), chosen, final))


func _clear_wants_badge() -> void:
	if _wants_guest_id != "":
		_garage.clear_chips(_wants_guest_id)
	_wants_guest_id = ""


## Автопилот «нажимает» за игрока: листает диалоги и закрывает карточку итогов.
func _process(delta: float) -> void:
	if not _autopilot:
		_autopilot_dialogue_timer = 0.0
		_autopilot_summary_timer = 0.0
		return
	if _runner.is_active:
		_autopilot_dialogue_timer += delta
		if _autopilot_dialogue_timer >= _autopilot_dialogue_wait:
			_autopilot_dialogue_timer = 0.0
			if _runner.available_choices().is_empty():
				_runner.advance()
			else:
				_runner.choose(0)
	else:
		_autopilot_dialogue_timer = 0.0
	if _summary != null and _summary.visible:
		_autopilot_summary_timer += delta
		if _autopilot_summary_timer >= AUTOPILOT_SUMMARY_DELAY:
			_autopilot_summary_timer = 0.0
			_summary.press_next()
	else:
		_autopilot_summary_timer = 0.0


## Отладка: F9 или кнопка 🔃 в углу освобождают кальян (в релизе это делают заказы гостей, M6).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_fullscreen()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_debug_reset_hookah()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_set_autopilot(not _autopilot)


func _debug_reset_hookah() -> void:
	var guest_id := _station.guest_id
	_station.reset()
	_last_verdict = {}
	_smoke_permission = false
	_ask_blocked = false
	_hookah_on_prep_table = false
	_apply_station()
	_garage.hide_object(GarageWorld.HOOKAH_OBJECT_ID)
	_garage.hide_object(GarageWorld.HOOKAH_PREP_OBJECT_ID)
	_garage.restock_shelf()
	_garage.reset_hose()
	if guest_id != "":
		_garage.set_friend_smoking(guest_id, false)
	_notify("Отладка: кальян снова пустой.")
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
	box.offset_left = -410.0
	box.offset_right = -204.0
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
	_autopilot_button = Button.new()
	_autopilot_button.text = "🤖"
	_autopilot_button.tooltip_text = "Автопилот кальянщика (F10)"
	_autopilot_button.toggle_mode = true
	_autopilot_button.focus_mode = Control.FOCUS_NONE
	_autopilot_button.add_theme_font_size_override("font_size", 28)
	_autopilot_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_autopilot_button.offset_left = -132.0
	_autopilot_button.offset_right = -76.0
	_autopilot_button.offset_top = 16.0
	_autopilot_button.offset_bottom = 68.0
	_autopilot_button.toggled.connect(_set_autopilot)
	$UI/Root.add_child(_autopilot_button)
	_camera_button = Button.new()
	_camera_button.text = "🎥"
	_camera_button.tooltip_text = "Режим NPC: камера следует за кальянщиком (вкл/выкл)"
	_camera_button.toggle_mode = true
	_camera_button.disabled = true
	_camera_button.focus_mode = Control.FOCUS_NONE
	_camera_button.add_theme_font_size_override("font_size", 28)
	_camera_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_camera_button.offset_left = -192.0
	_camera_button.offset_right = -136.0
	_camera_button.offset_top = 16.0
	_camera_button.offset_bottom = 68.0
	_camera_button.toggled.connect(_on_camera_button_toggled)
	$UI/Root.add_child(_camera_button)


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
