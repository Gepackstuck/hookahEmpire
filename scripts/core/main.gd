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
## M8: тренды, деньги/репутация, цель MVP.
var _trends: TrendSystem = null
var _economy: EconomySystem = null
var _goal: ProgressionGoal = null
var _hud: StatusHud = null
var _hud_timer := 0.0
## M9: мебель (декор): магазин, расстановка, бонус к оценке.
var _furniture: FurnitureSystem = null
var _furniture_screen: FurnitureScreen = null
var _furniture_button: Button = null
var _furniture_menu: FurnitureContextMenu = null
var _furniture_paused := false
var _saved_time_scale := 1.0
## Масштаб времени на паузе (не 0, чтобы нигде не делить на нулевой delta).
const FURNITURE_PAUSE_SCALE := 0.0001
var _pending_cost := 0
var _summary: SessionSummaryScreen = null
var _viewer: ImageViewer = null
## M7: жар кальяна, замена углей, перезабивка (redo).
var _heat: HeatModel = null
var _heat_active := false
var _session_token := 0
var _session_puffs := 0
var _session_guest_id := ""
var _pace_timer := 0.0
var _complaint_timer := 0.0
var _npc_service_pending := false
var _servicing := false
var _redoing := false
var _redo_requested := false
var _redo_used := false
var _redo_timer := 0.0
var _service_penalty := 0.0
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
## guest_id -> тексты заказов, которые гость уже делал (чтобы заказы не повторялись и книга рецептов росла).
var _used_orders: Dictionary = {}
var _stats := PlaytestStats.new()
var _stats_panel: StatsPanel = null
var _stats_button: Button = null
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

# --- M10: интро-срез ---
signal _notice_closed
const BEN_ID := "friend_ben"
const BEN_ENTRY_POSITION := Vector2(0.3, 7.5)
const BEN_ENTRY_CELL := Vector2i(1, 7)
const BEN_WAIT_CELL := Vector2i(9, 12)
const NOTICE_AUTOPILOT_DELAY := 4.0
const AUTOPILOT_AFTER_SESSIONS := 3
## Минимальное совпадение рецепта с заказом, чтобы автопилот повторил «почти сильный» рецепт при новом тренде.
const STRONG_HUNT_MIN_FIT := 55.0
var _intro: IntroGuide = null
var _buddy: Buddy = null
var _guide_panel: PanelContainer = null
var _guide_header: Label = null
var _guide_label: Label = null
var _game_seconds := 0.0
var _strong_count := 0
var _notice_overlay: Control = null
var _notice_timer := 0.0
var _furnish_next_try := 0.0
var _modal_dim: ColorRect = null
var _milk_button: Button = null
var _drinking := false
const MILK_LINES: Array[String] = [
	"Ммм... вот это кайф!",
	"Молочко и свобода — что ещё нужно?",
	"Свобода пахнет кальяном и молоком.",
	"Кайф... никто мне не указ!",
	"Каждый глоток — маленькая свобода.",
	"Эх, жизнь удалась. Кайф!",
	"Вот ради этого я и ушёл в кальянщики. Свобода!",
	"Холодное молоко, тёплый гараж — чистый кайф.",
]

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
	_add_stats_panel()
	_add_objective_label()
	_garage.friend_arrived.connect(_on_friend_arrived)
	_garage.friend_inhaled.connect(_on_friend_inhaled)
	_garage.player_inhaled.connect(_on_player_inhaled)
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
		_heat = HeatModel.load_default()
		for message in _heat.errors:
			GameLog.error("heat", message)
		for message in _scoring.errors:
			GameLog.error("scoring", message)
		_preparation = PreparationService.create(_recipes)
		if _preparation != null:
			_preparation_screen.setup(_preparation)
			_setup_manual_screen()
		_setup_summary_screen()
		_setup_image_viewer()
		_setup_m8()
		_setup_m9()
		_setup_m10()
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
		if _autopilot_allowed():
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
	_mark_beat("arrive_%s" % guest_id)
	if _order.is_empty():
		var guest := GuestCatalog.load_guest(guest_id)
		if not guest.is_empty():
			_rng.randomize()
			var used: Array = _used_orders.get(guest_id, [])
			_order = GuestCatalog.roll_order(guest, _rng, _last_order_prefs, used)
			# Список «уже было» у гостя: когда он заказал всё, начинаем сначала.
			if used.size() >= int(guest.get("orders", []).size()) and guest.has("orders"):
				used = []
			used.append(str(_order["text"]))
			while used.size() > 8:
				used.pop_front()
			_used_orders[guest_id] = used
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
		$UI/Root.move_child(_viewer, -1)
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
	_session_puffs += 1
	_heat_puff()
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
	if dialogue_id.begins_with("friend_") and not _autopilot and _top_up_mouthpieces():
		_stats.bump("mouthpiece_refill")
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
	_garage.set_pointer_enabled(not (_mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _furniture_open() \
		or (_summary != null and _summary.visible) or (_viewer != null and _viewer.visible) or (_runner.is_active and not _autopilot)))
	_garage.set_input_locked(_carrying or _mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _furniture_open() or (_summary != null and _summary.visible) or _runner.is_active or _autopilot)


var _chiptune: ChipTune = null


## Бумбокс на полке: включает/выключает короткую 8-битную мелодию (оригинальная, синтезируется кодом).
func _toggle_boombox() -> void:
	if _chiptune == null:
		_chiptune = ChipTune.new()
		add_child(_chiptune)
	var on := _chiptune.toggle()
	_notify("🎵 Бумбокс: играет" if on else "🎵 Бумбокс выключен")


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
		"toggle_boombox":
			_toggle_boombox()
		"replace_coals":
			await _replace_coals()
		"redo_hookah":
			await _do_redo()
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
			verdict = _scoring.evaluate(taste, recipe, float(result["execution_score"]), _recipes.catalog, _recipes.config, {"furniture_bonus": _furniture.score_bonus() if _furniture != null else 0.0})
			verdict["guest_id"] = guest_id
			verdict["recipe_id"] = str(result["recipe_id"])
			_recipes.record_session(str(result["recipe_id"]), float(verdict["final_score"]), guest_id, int(verdict["payment"]))
	_station.apply_result(result, verdict)
	_pending_verdict = verdict
	_pending_cost = 0
	if _economy != null:
		_pending_cost = _economy.recipe_cost(_recipes.get_recipe(str(result["recipe_id"])), _recipes.config.total_units)
	_pending_serve = true


## После подачи: игрок несёт кальян к столу гостя и ставит его; затем гость реагирует.
func _on_preparation_closed() -> void:
	_update_input_lock()
	if not _pending_serve:
		_refresh_objective()
		return
	_pending_serve = false
	_charge_pending_cost()
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
		_start_heat(guest_id)
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
	var token := _session_token
	# Гость курит, пока идёт жар/обслуживание; он может попросить перезабить (тогда сессию продолжит новая подача).
	verdict = await _run_smoking_phase(guest_id, verdict, token)
	if token != _session_token:
		return
	var payment := int(verdict["payment"])
	var likes := bool(verdict["likes"])
	session_finished.emit({
		"guest_id": guest_id, "recipe_id": str(verdict["recipe_id"]), "final_score": float(verdict["final_score"]),
		"band_id": str(verdict["band_id"]), "payment": payment, "reputation_delta": int(verdict["reputation_delta"])})
	_apply_session_economy(verdict)
	_state.set_flag("sessions_done", _sessions_done() + 1)
	_mark_beat("session_%d" % _sessions_done())
	_apply_unlocks()
	var visit_recipe := _recipes.get_recipe(str(verdict["recipe_id"]))
	_stats.record_session({"guest_id": guest_id, "recipe_id": str(verdict["recipe_id"]), "final_score": float(verdict["final_score"]), "band_id": str(verdict["band_id"]), "payment": payment,
		"prefs": _order.get("preferences", {}), "dislikes": _order.get("dislikes", {}), "trend_name": str(verdict.get("trend_name", "")),
		"recipe_name": _recipes.display_name(visit_recipe) if not visit_recipe.is_empty() else ""})
	GameLog.info("session", "%s: %.1f (%s), оплата %d" % [guest_id, float(verdict["final_score"]), str(verdict["band_id"]), payment])
	_garage.set_friend_smoking(guest_id, false)
	await _wait_until_free()
	_rng.randomize()
	if not guest.is_empty():
		var line := GuestCatalog.farewell_text(guest, str(verdict["emotion_id"]), likes, payment, _rng)
		await _play_lines(guest, [["guest", line]])
	_guest_departing = true
	_redo_used = false
	_redo_requested = false
	_service_penalty = 0.0
	_station.reset()
	_last_verdict = {}
	_smoke_permission = false
	_ask_blocked = false
	_apply_station()
	await _garage.friend_leave(guest_id)
	_order = {}
	_mixer.set_order_hint("")
	var progress: String = _state.story_progress
	# Гость обслужен: заказ снова неизвестен (при следующем визите он опять сделает заказ),
	# а сюжет переходит к «обслужен» даже если разговор при визите был пропущен.
	_state.set_flag("%s_order_known" % guest_id.trim_prefix("friend_"), false)
	if _beats != null and _beats.is_in_progress_of(guest_id, progress):
		_state.set_story_progress(_beats.done_progress_for(guest_id))
	elif progress.ends_with("_intro_done"):
		_state.set_story_progress(progress.replace("_intro_done", "_done"))
	# Гости ходят по кругу: после последнего (Макс) снова приходит первый (Ден).
	if _state.story_progress == LOOP_END_PROGRESS and _beats != null and _beats.find_for_progress(LOOP_RESTART_PROGRESS).size() > 0:
		_state.set_story_progress(LOOP_RESTART_PROGRESS)
		_stats.bump("guest_cycles")
	_guest_departing = false
	_apply_station()
	_advance_trend()
	await _maybe_play_ending()
	await _maybe_ben_arrival()
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


# --- M7: жар, замена углей, перезабивка ------------------------------------------------------

const WAIT_LINE_DELAY := 2.0
const WAIT_LINES: Array[String] = ["Я сейчас!", "Секунду, я сейчас!", "Минутку, сейчас подойду!"]
var _wait_timer := 0.0
var _wait_guest_id := ""


## Гость пришёл и ждёт заказа, а кальянщик занят: один раз за приход говорим «я сейчас».
func _tick_wait_line(delta: float) -> void:
	var guest_id := _garage.ready_friend_id() if _garage != null else ""
	if guest_id == "" or _order_known() or _runner.is_active or (_summary != null and _summary.visible):
		_wait_timer = 0.0
		if guest_id == "":
			_wait_guest_id = ""
		return
	if _wait_guest_id == guest_id:
		return
	var busy := _servicing or _carrying or _mixer.visible or _book.visible or _preparation_screen.visible \
		or (_manual_screen != null and _manual_screen.visible) or _autopilot_running
	if not busy:
		_wait_timer = 0.0
		return
	_wait_timer += delta
	if _wait_timer >= WAIT_LINE_DELAY:
		_wait_guest_id = guest_id
		_wait_timer = 0.0
		_garage.say("player", WAIT_LINES[_rng.randi_range(0, WAIT_LINES.size() - 1)])


func _ui_paused() -> bool:
	return _runner.is_active or _mixer.visible or _book.visible or _preparation_screen.visible \
		or (_manual_screen != null and _manual_screen.visible) or (_summary != null and _summary.visible) \
		or (_viewer != null and _viewer.visible)


func _start_heat(guest_id: String) -> void:
	if _heat == null:
		return
	_session_guest_id = guest_id
	_session_puffs = 0
	_heat.begin(_heat.roll_npc_pace(_rng) if _autopilot else -1.0)
	_pace_timer = _heat.roll_pace_interval(_rng)
	_complaint_timer = _heat.complaint_cooldown
	_npc_service_pending = false
	_heat_active = true
	_sync_heat_visual()
	_apply_station()


func _stop_heat() -> void:
	_heat_active = false
	_npc_service_pending = false
	_garage.set_hookah_heat(1, "")
	_apply_station()


func _heat_puff() -> void:
	if _heat == null or not _heat_active:
		return
	var changed := _heat.puff()
	if changed != "":
		_on_heat_state_changed(changed)


func _on_player_inhaled() -> void:
	_heat_puff()


## Жар меняется со временем; жалобы гостя и штраф зависят от состояния кальяна.
func _tick_session(delta: float) -> void:
	if _redo_requested and not _ui_paused() and _heat != null:
		_redo_timer -= delta
		if _redo_timer <= 0.0:
			_redo_requested = false
			_redo_used = true
			_service_penalty += _heat.redo_ignored
			_garage.say(_session_guest_id, "Ладно, не надо... Но осадочек остался.")
			_apply_station()
	if _heat == null or not _heat_active or _ui_paused() or _servicing:
		return
	if _autopilot:
		# Режим NPC: темп то «суета», то «спокойствие».
		_pace_timer -= delta
		if _pace_timer <= 0.0:
			_heat.pace = _heat.roll_npc_pace(_rng)
			_pace_timer = _heat.roll_pace_interval(_rng)
	var changed := _heat.tick(delta)
	if changed != "":
		_on_heat_state_changed(changed)
	_complaint_timer -= delta
	if _heat.needs_service() and _complaint_timer <= 0.0:
		_complain()


func _on_heat_state_changed(new_state: String) -> void:
	_sync_heat_visual()
	_apply_station()
	_refresh_guide()
	# Жар на пределе (от 95): гость перестаёт курить, пока не сменят угли.
	if new_state == HeatModel.STATE_BURNED and _session_guest_id != "":
		_garage.set_friend_smoking(_session_guest_id, false)
	if new_state != HeatModel.STATE_NORMAL:
		_stats.bump("heat_" + new_state)
		_complain()


## Гость жалуется на жар; автопилот замечает жалобу не всегда (иногда «забывает»).
func _complain() -> void:
	if _heat == null:
		return
	_stats.bump("complaints")
	_complaint_timer = _heat.complaint_cooldown
	var line := _heat.random_line(_heat.state, _rng)
	if line != "":
		_garage.say(_session_guest_id, line)
	if _autopilot and _rng.randf() < _heat.npc_notice_chance:
		_npc_service_pending = true


func _sync_heat_visual() -> void:
	if _heat == null or not _heat_active:
		_garage.set_hookah_heat(1, "")
		return
	var coal := 1
	var badge := ""
	match _heat.state:
		HeatModel.STATE_COLD:
			coal = 0
			badge = "🧊"
		HeatModel.STATE_HOT:
			coal = 2
			badge = "🔥"
		HeatModel.STATE_BURNED:
			coal = 3
			badge = "💀"
	# В режиме NPC эмодзи тоже виден, но мельче и полупрозрачный.
	_garage.set_hookah_heat(coal, badge, _autopilot)


## Замена углей: кальянщик подходит к кальяну гостя, меняет угли; жар возвращается к норме.
func _replace_coals() -> void:
	if _servicing or _heat == null or not _heat_active:
		return
	_servicing = true
	_carrying = true
	_stats.bump("coal_service")
	_state.set_flag("coals_replaced_once", true)
	_mark_beat("coals_replaced")
	_refresh_guide()
	if _autopilot:
		_stats.bump("coal_service_npc")
	_update_input_lock()
	_apply_station()
	await _garage.service_coals(_heat.service_seconds)
	_servicing = false
	_carrying = false
	if _economy != null:
		var coal_paid := _economy.charge_coals()
		if coal_paid > 0:
			_stats.bump("spent", coal_paid)
			_stats.bump("spent_coals", coal_paid)
			_notify("Новые угли: −%d 💰" % coal_paid)
	if _heat_active:
		_heat.service()
		if _session_guest_id != "" and _station.guest_smokes():
			_garage.set_friend_smoking(_session_guest_id, true, "")
		_npc_service_pending = false
		_complaint_timer = _heat.complaint_cooldown
		_sync_heat_visual()
		var line := _heat.random_line("thanks", _rng)
		if line != "":
			_garage.say(_session_guest_id, line)
	_apply_station()
	_update_input_lock()


## Гость попросил перезабить: кальянщик забирает кальян на стол для кальянов, и приготовление идёт заново.
func _request_redo(guest_id: String) -> void:
	if _heat == null:
		return
	_stats.bump("redo_requested")
	_redo_requested = true
	_redo_timer = _heat.redo_timeout
	_garage.say(guest_id, _heat.random_line("redo", _rng))
	_notify("%s просит перезабить кальян." % str(GuestCatalog.load_guest(guest_id).get("name", "Гость")))
	_apply_station()


func _do_redo() -> void:
	if not _redo_requested or _servicing or _redoing or _heat == null:
		return
	_stats.bump("redo")
	_redoing = true
	_redo_requested = false
	_redo_used = true
	_service_penalty += _heat.redo_cost
	_session_token += 1
	_carrying = true
	_update_input_lock()
	_stop_heat()
	var guest_id := _session_guest_id
	_garage.set_friend_smoking(guest_id, false)
	_garage.say("player", "Сейчас перезабью.")
	await _garage.carry_hookah_to_prep_table()
	_hookah_on_prep_table = true
	_station.reset()
	_last_verdict = {}
	_smoke_permission = false
	_ask_blocked = false
	_carrying = false
	_redoing = false
	_apply_station()
	_update_input_lock()
	_refresh_objective()


## Курение гостя после реакции: считает затяжки, ведёт запрос redo и в конце применяет штраф за жар.
## Возвращает итог (с учётом штрафов); если пришла перезабивка (token сменился) — исходный итог.
func _run_smoking_phase(guest_id: String, verdict: Dictionary, token: int) -> Dictionary:
	var likes := bool(verdict["likes"])
	_session_puffs = 0
	var goal := randi_range(6, 12) if likes else 0
	var redo_at := -1
	if _heat != null and not _redo_used and _rng.randf() < _heat.redo_chance:
		# Просить перезабить можно только в течение 4–7 затяжек после оценки; курим как минимум до запроса.
		redo_at = 0 if goal == 0 else randi_range(_heat.redo_min_puff, _heat.redo_max_puff)
		goal = maxi(goal, redo_at + 1)
	while token == _session_token:
		if redo_at >= 0 and not _redo_requested and not _redo_used and _session_puffs >= redo_at:
			_request_redo(guest_id)
		if _session_puffs >= goal and not _redo_requested and not _servicing and not _redoing:
			break
		await get_tree().process_frame
	if token != _session_token:
		return verdict
	var heat_penalty := _heat.heat_penalty() if _heat != null else 0.0
	_stop_heat()
	if (heat_penalty > 0.04 or _service_penalty > 0.0) and _scoring != null:
		var revised := _scoring.rescore(verdict, heat_penalty, _service_penalty)
		_recipes.revise_last(str(revised.get("recipe_id", "")), float(revised["final_score"]), int(revised["payment"]))
		_last_verdict = revised
		_notify("Штраф: жар −%.1f, перезабивка −%.1f. Итог %.1f, оплата %d." % [heat_penalty, _service_penalty, float(revised["final_score"]), int(revised["payment"])])
		GameLog.info("session", "Штрафы: жар %.1f, сервис %.1f → %.1f" % [heat_penalty, _service_penalty, float(revised["final_score"])])
		return revised
	return verdict


## Ждёт, пока игрок закончит диалог/закроет окна (чтобы прощание не легло поверх них).
func _wait_until_free() -> void:
	while _runner.is_active or _mixer.visible or _book.visible or _preparation_screen.visible or _furniture_open() \
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
	elif _redo_requested:
		_garage.configure_interaction("table_guest", "Перезабить кальян", "redo_hookah")
	elif _heat_active and _heat != null and _heat.needs_service():
		_garage.configure_interaction("table_guest", "Заменить угли", "replace_coals")
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
	_refresh_guide()
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
	if on and not _autopilot_allowed():
		if _autopilot_button != null:
			_autopilot_button.set_pressed_no_signal(false)
		_notify("🔒 Автопилот откроется после третьего гостя: двух обслужи вручную, третьего — в быстром режиме.")
		return
	_autopilot = on
	if _autopilot_button != null:
		_autopilot_button.set_pressed_no_signal(on)
		_autopilot_button.modulate = Color(0.55, 1.0, 0.6) if on else Color.WHITE
	# Режим NPC: камера по умолчанию следует за кальянщиком (кнопка 🎥 отключает следование и ставит камеру по центру); вручную — как раньше.
	_camera_follow = true
	if _heat != null and _heat_active:
		_heat.pace = _heat.roll_npc_pace(_rng) if on else _heat.pace_manual
	_sync_heat_visual()
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
	if _carrying or _guest_departing or _runner.is_active or _mixer.visible or _book.visible or _furniture_open() \
			or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _summary.visible:
		return
	if _redo_requested:
		await _do_redo()
		return
	if _heat_active and _npc_service_pending and _heat != null and _heat.needs_service():
		await _replace_coals()
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
	"sign_neon": ["💡", "🤨", "🔧"],
}
## Что кальянщик делает у объекта (выбирается случайно, шансы равные): действие -> эмодзи над головой.
## Анимации — в GarageWorld.play_idle_action.
## Вес действия при выборе (по умолчанию 1): перестановка кальянов чуть чаще остальных.
const IDLE_WEIGHTS := {"swap": 2.0}
const IDLE_ACTIONS := {
	"sink_wash": {"wash": ["💦", "🫧", "🧽"], "gaze": ["💧", "🤔", "😌"]},
	"shelf_hookah": {"look_mask": ["🎭", "🧐"], "look_book": ["📕", "🧐"], "swap": ["🔄", "🧐"], "juggle": ["🤹", "✨", "🌿"]},
	"recipe_book": {"think": ["🤔", "💭"], "read": ["📖", "🧐"]},
	"sign_neon": {"look": ["💡", "🤨"], "pat": ["🔧", "👋", "🤨"]},
	"table_hookah": {"stand": ["🔥", "🧰", "💨"], "drink": ["🥛", "😌", "🤍"], "juggle": ["🤹", "✨", "🌿"]},
}
## Гости приходят по кругу: когда прогресс доходит до LOOP_END_PROGRESS, он сбрасывается на LOOP_RESTART_PROGRESS.
const LOOP_END_PROGRESS := "friend_03_done"
const LOOP_RESTART_PROGRESS := "intro_start"
const IDLE_MIN_SECONDS := 9.0
const IDLE_MAX_SECONDS := 16.0
var _idle_walking := false
var _idle_acting := false
var _idle_last := ""


## Есть ли у кальянщика реальное дело: новый гость без заказа или заказ, ожидающий кальяна.
func _autopilot_needs_action() -> bool:
	if _redo_requested or (_heat_active and _npc_service_pending and _heat != null and _heat.needs_service()):
		return true
	if _garage.ready_friend_id() == "":
		return false
	if not _order_known():
		return true
	return _station.state == HookahStation.STATE_EMPTY and not _order.is_empty()


func _autopilot_busy() -> bool:
	return _carrying or _guest_departing or _runner.is_active or _mixer.visible or _book.visible \
		or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _summary.visible \
		or (_viewer != null and _viewer.visible) or _furniture_open()


## Один «заход» простоя: идёт к случайному объекту (не к тому же, что в прошлый раз) и 3–6 с делает вид, что работает.
## Прерывается, как только появляется настоящее дело.
func _autopilot_idle() -> void:
	if _autopilot_furnish():
		return
	# Мундштуков в коробке мало — докладываем их прямо в простое, не дожидаясь нового заказа.
	if _garage.mouthpieces_low(2):
		await _autopilot_refill_mouthpieces()
		return
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
	_idle_walking = true
	_idle_walk(target)
	# Идём, но бросаем всё, как только появилось настоящее дело (перезабивка, заказ, угли).
	while _idle_walking:
		if not _autopilot or _autopilot_needs_action():
			_garage.cancel_walk()
		await get_tree().process_frame
	_carrying = false
	_update_input_lock()
	if not _autopilot or _autopilot_needs_action():
		return
	var emojis: Array = IDLE_TARGETS[target]
	var action := "stand"
	var actions: Variant = IDLE_ACTIONS.get(target)
	if actions is Dictionary and not (actions as Dictionary).is_empty():
		action = _pick_idle_action(actions as Dictionary)
		emojis = (actions as Dictionary)[action]
	var duration := randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)
	var elapsed := 0.0
	var next_emoji := 0.0
	_stats.bump("idle_" + action)
	if action == "drink":
		_garage.say("player", MILK_LINES.pick_random())
	_idle_acting = true
	_idle_act(target, action, duration)
	while _idle_acting:
		if _autopilot_idle_should_stop():
			# Ходьба внутри действия (например, перестановка кальянов) прерывается сразу.
			_garage.cancel_walk()
		elif elapsed >= next_emoji:
			_garage.set_chips("player", [{"emoji": str(emojis.pick_random()), "state": "pick"}])
			next_emoji += 1.1
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	_garage.clear_chips("player")


## Простой: идёт к коробке у стола гостя и докладывает мундштуки (прерывается настоящим делом).
## Докладывает мундштуки в коробку (если их меньше 2) и списывает стоимость новых. true — докладывал.
func _top_up_mouthpieces() -> bool:
	var before := _garage.mouthpiece_count()
	if not _garage.top_up_mouthpieces(2):
		return false
	if _economy != null:
		var paid := _economy.charge_mouthpieces(_garage.mouthpiece_count() - before)
		if paid > 0:
			_stats.bump("spent", paid)
			_stats.bump("spent_pieces", paid)
			_notify("Мундштуки: −%d 💰" % paid)
	return true


func _autopilot_refill_mouthpieces() -> void:
	_carrying = true
	_update_input_lock()
	_idle_walking = true
	_idle_walk_box()
	while _idle_walking:
		if _autopilot_idle_should_stop():
			_garage.cancel_walk()
		await get_tree().process_frame
	_carrying = false
	_update_input_lock()
	if _autopilot_idle_should_stop():
		return
	_garage.say("player", "Докладываю мундштуки в коробку.")
	var waited := 0.0
	while waited < 1.4 and not _autopilot_idle_should_stop():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if _autopilot_idle_should_stop():
		return
	if _top_up_mouthpieces():
		_stats.bump("mouthpiece_refill")
		_stats.bump("mouthpiece_refill_idle")


func _idle_walk_box() -> void:
	await _garage.walk_to_mouthpiece_box()
	_idle_walking = false


## Выбор действия простоя: по умолчанию шансы равные, у action из IDLE_WEIGHTS — свой вес.
func _pick_idle_action(actions: Dictionary) -> String:
	var total := 0.0
	for key in actions:
		total += float(IDLE_WEIGHTS.get(key, 1.0))
	var roll := randf() * total
	for key in actions:
		roll -= float(IDLE_WEIGHTS.get(key, 1.0))
		if roll <= 0.0:
			return str(key)
	return str(actions.keys()[0])


func _autopilot_idle_should_stop() -> bool:
	return not _autopilot or _autopilot_busy() or _autopilot_needs_action()


func _idle_act(target: String, action: String, duration: float) -> void:
	await _garage.play_idle_action(target, action, duration, _autopilot_idle_should_stop)
	_idle_acting = false


func _idle_walk(target: String) -> void:
	await _garage.walk_to_object(target)
	_idle_walking = false


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
		if _top_up_mouthpieces():
			_stats.bump("mouthpiece_refill")
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
	var affordable: Array[Dictionary] = []
	for candidate_recipe in _recipes.all_recipes():
		if _economy == null or _economy.can_afford_recipe(candidate_recipe, _recipes.config.total_units):
			affordable.append(candidate_recipe)
	var recipe_id := ""
	# Цель «сильные рецепты»: пока она не выполнена, сначала пробуем повторить рецепт, который уже был сильным при другом тренде.
	if _goal != null and _trends != null and not _goal.is_complete(_state.recipes):
		var hunt: Array[Dictionary] = []
		for candidate_recipe in affordable:
			var strong_trends: Array = candidate_recipe.get("strong_trends", [])
			if strong_trends.size() >= 1 and not _goal.is_strong(candidate_recipe) and not strong_trends.has(_trends.current_id):
				hunt.append(candidate_recipe)
		recipe_id = AutoCook.find_fitting_recipe(hunt, _recipes.catalog, _recipes.config, _scoring, taste, STRONG_HUNT_MIN_FIT)
	if recipe_id == "":
		recipe_id = AutoCook.find_fitting_recipe(affordable, _recipes.catalog, _recipes.config, _scoring, taste, AutoCook.FIT_MIN_FOR_EXISTING)
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
		if _economy != null and not _mix_affordable(candidate):
			candidate = AutoCook.pick_mix(_recipes.catalog, _order["preferences"], _rng, noise, _economy.free_ingredients)
		if not candidate["selection"].is_empty() and _recipes.evaluate(candidate["selection"], candidate["modifiers"])["ok"]:
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
	_game_seconds += delta
	if _modal_dim != null:
		_modal_dim.visible = _mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible)
	if _notice_overlay != null and _autopilot:
		_notice_timer += delta
		if _notice_timer >= NOTICE_AUTOPILOT_DELAY:
			_notice_closed.emit()
	_tick_session(delta)
	_tick_hud(delta)
	_tick_wait_line(delta)
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_toggle_stats_panel()
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
	box.offset_left = -470.0
	box.offset_right = -264.0
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


## Кнопка 📊 и окно статистики для ручного тестирования (есть в любой сборке).
func _add_stats_panel() -> void:
	_stats_button = Button.new()
	_stats_button.text = "📊"
	_stats_button.tooltip_text = "Статистика теста (F8)"
	_stats_button.focus_mode = Control.FOCUS_NONE
	_stats_button.add_theme_font_size_override("font_size", 28)
	_stats_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats_button.offset_left = -252.0
	_stats_button.offset_right = -196.0
	_stats_button.offset_top = 16.0
	_stats_button.offset_bottom = 68.0
	_stats_button.pressed.connect(_toggle_stats_panel)
	$UI/Root.add_child(_stats_button)
	_stats_panel = StatsPanel.new()
	_stats_panel.provider = _stats_lines
	_stats_panel.reset_requested.connect(func() -> void: _stats.reset())
	_stats_panel.speed_selected.connect(_set_game_speed)
	_stats_panel.trend_next_requested.connect(_debug_next_trend)
	_stats_panel.money_requested.connect(_debug_add_money)
	_stats_panel.goal_reset_requested.connect(_debug_reset_goal)
	_stats_panel.money_zero_requested.connect(_debug_zero_money)
	$UI/Root.add_child(_stats_panel)
	_stats_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats_panel.offset_left = -420.0
	_stats_panel.offset_right = -16.0
	_stats_panel.offset_top = 76.0
	_stats_panel.anchor_bottom = 1.0
	_stats_panel.offset_bottom = -16.0
	_stats_panel.grow_vertical = Control.GROW_DIRECTION_END
	_stats_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN


## M8: системы трендов, экономики и цели MVP, панель статуса, провайдеры для экранов.
func _setup_m8() -> void:
	_trends = TrendSystem.load_default(_scoring)
	for message in _trends.errors:
		GameLog.error("trends", message)
	if _trends.is_valid():
		var start_id: String = _state.current_trend_id if _state.current_trend_id != "" else _trends.current_id
		_trends.restore(start_id, int(_state.trend_visits_left) if _state.trend_visits_left > 0 else _trends.duration_sessions)
		_sync_trend_state()
		_trends.trend_changed.connect(_on_trend_changed)
	_economy = EconomySystem.load_default(_state, _recipes.catalog)
	for message in _economy.errors:
		GameLog.error("economy", message)
	_economy.grant_start_money()
	_goal = ProgressionGoal.load_default()
	for message in _goal.errors:
		GameLog.error("progression", message)
	_hud = StatusHud.new()
	$UI/Root.add_child(_hud)
	_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.offset_left = 16.0
	_hud.offset_top = 16.0
	_preparation_screen.cost_info = _cost_info
	_book.trend_info = _trend_info
	_tick_hud(1.0)


func _sync_trend_state() -> void:
	_state.current_trend_id = _trends.current_id
	_state.trend_visits_left = _trends.visits_left


func _on_trend_changed(trend_id: String) -> void:
	_sync_trend_state()
	_stats.bump("trend_changes")
	GameLog.info("trends", "Новый тренд: %s" % _trends.name_of(trend_id))
	_notify("📈 Новый тренд: %s" % _trends.name_of(trend_id))


## Гость ушёл: отсчёт визитов до смены тренда.
func _advance_trend() -> void:
	if _trends == null or not _trends.is_valid():
		return
	_trends.advance_visit()
	_sync_trend_state()


func _tick_hud(delta: float) -> void:
	if _hud == null or _goal == null:
		return
	_hud_timer += delta
	if _hud_timer < 0.25:
		return
	_hud_timer = 0.0
	var trend_name := _trends.current_name() if _trends != null else ""
	var left := _trends.visits_left if _trends != null else 0
	_hud.show_text(StatusHud.format_lines(int(_state.money), int(_state.reputation), trend_name, left, _goal.progress_text(_state.recipes), _goal.is_complete(_state.recipes)))


func _mix_affordable(mix: Dictionary) -> bool:
	if mix.is_empty() or mix["selection"].is_empty():
		return true
	var evaluation := _recipes.evaluate(mix["selection"], mix["modifiers"])
	if not evaluation["ok"]:
		return true
	var canonical: Dictionary = evaluation["canonical"]
	return _economy.can_afford_recipe({"ingredients": canonical["ingredients"], "modifiers": canonical["modifiers"]}, _recipes.config.total_units)


func _cost_info(recipe: Dictionary) -> Dictionary:
	if _economy == null:
		return {"cost": 0, "affordable": true}
	var total: int = _recipes.config.total_units
	return {"cost": _economy.recipe_cost(recipe, total), "affordable": _economy.can_afford_recipe(recipe, total)}


## Иконка и подробности «как рецепт ложится в тренд» для книги рецептов.
func _trend_info(recipe: Dictionary) -> Dictionary:
	if _trends == null or not _trends.is_valid() or _scoring == null:
		return {"icon": "", "detail": ""}
	var profile := RecipeScoring.taste_profile({"ingredients": recipe["ingredients"], "modifiers": recipe["modifiers"]}, _recipes.catalog, _recipes.config)
	var fit := _trends.trend_fit(profile)
	var icon := "📈" if fit >= 65.0 else ("📉" if fit <= 40.0 else "➖")
	var strong := ""
	if _goal != null and _goal.is_strong(recipe):
		strong = " ⭐ Сильный рецепт"
	var seen: Array = recipe.get("strong_trends", [])
	return {"icon": icon + (" ⭐" if strong != "" else ""), "detail": "Тренд «%s»: попадание %.0f%s (сильных трендов: %d)" % [_trends.current_name(), fit, strong, seen.size()]}


## При подаче кальяна списываем стоимость платных ингредиентов (бесплатные — без списания; не хватает денег — списываем остаток).
func _charge_pending_cost() -> void:
	var cost := _pending_cost
	_pending_cost = 0
	if _economy == null or cost <= 0:
		return
	var charged := mini(cost, _economy.balance())
	if _economy.spend(charged):
		_stats.bump("spent", charged)
		if _redo_used:
			_stats.bump("spent_redo", charged)
		_notify("Ингредиенты: −%d 💰" % charged)


## Оплата и репутация за гостя, учёт «сильного рецепта».
func _apply_session_economy(verdict: Dictionary) -> void:
	if _economy == null:
		return
	var payment := int(verdict["payment"])
	_economy.earn(payment)
	_stats.bump("earned", payment)
	var delta := int(verdict["reputation_delta"])
	_economy.add_reputation(delta)
	if payment > 0:
		_notify("Оплата: +%d 💰" % payment)
	if delta != 0:
		_notify("Репутация %s%d" % ["+" if delta > 0 else "", delta])
	if _goal == null:
		return
	var recipe := _recipes.get_recipe(str(verdict["recipe_id"]))
	if recipe.is_empty():
		return
	if _goal.record(recipe, str(verdict.get("trend_id", "")), float(verdict["final_score"])):
		_stats.bump("strong_recipes")
		var trend_names: Array = []
		for trend_id in recipe.get("strong_trends", []):
			trend_names.append(_trends.name_of(str(trend_id)) if _trends != null else str(trend_id))
		_stats.add_strong(_recipes.display_name(recipe), trend_names)
		_strong_count += 1
		_mark_beat("strong_%d" % _strong_count)
		_notify("⭐ Сильный рецепт! Цель: %s" % _goal.progress_text(_state.recipes))


## Цель MVP выполнена — один раз показываем финальный диалог (намёк на будущих гостей).
func _maybe_play_ending() -> void:
	if _goal == null or not _goal.is_complete(_state.recipes) or _state.get_flag(ProgressionGoal.ENDING_SEEN_FLAG, false) == true:
		return
	_state.set_flag(ProgressionGoal.DONE_FLAG, true)
	_stats.bump("goal_done")
	_mark_beat("goal_done")
	var dialogue := _library.get_dialogue(_goal.ending_dialogue)
	if dialogue.is_empty():
		GameLog.error("progression", "Нет финального диалога '%s'" % _goal.ending_dialogue)
		return
	_notify("🎯 Цель выполнена: сильный рецепт собран!")
	await get_tree().create_timer(1.0).timeout
	if _runner.is_active:
		return
	_update_input_lock()
	_open_dialogue_ui(dialogue["speakers"])
	if _runner.start(dialogue, _effects.check):
		await _runner.finished
	else:
		_dialogue_box.close()
	_update_input_lock()
	if _intro != null:
		await _show_notice(_intro.ending_notice)


## M9: окно мебели (кнопка 🛋️): магазин, расстановка, перемещение и уборка предметов.
func _setup_m9() -> void:
	_furniture = FurnitureSystem.load_default(_state, _economy)
	for message in _furniture.errors:
		GameLog.error("furniture", message)
	if not _furniture.is_valid():
		return
	_garage.setup_furniture(_furniture)
	var layer := _garage.furniture_layer()
	if layer == null:
		return
	if not _furniture.base_layout_connected():
		GameLog.error("furniture", "Базовая планировка гаража: не все рабочие клетки достижимы от двери (проверьте room.required_cells)")
	_furniture_screen = FurnitureScreen.new()
	$UI/Root.add_child(_furniture_screen)
	_furniture_screen.setup(_furniture, _economy)
	_furniture_screen.closed.connect(_on_furniture_closed)
	_furniture_screen.buy_requested.connect(_on_furniture_buy)
	_furniture_screen.place_requested.connect(_on_furniture_place_requested)
	_furniture_screen.remove_requested.connect(_on_furniture_remove)
	_furniture_screen.drag_started.connect(_on_furniture_drag_started)
	_furniture_screen.sell_requested.connect(_on_furniture_sell)
	_furniture_screen.preview_requested.connect(func(path: String, title: String) -> void: _on_image_requested(path, title, ""))
	layer.ui_blocker = _furniture_pointer_over_ui
	layer.drag_started.connect(_on_furniture_drag_started)
	_furniture_screen.placement_cancel_requested.connect(func() -> void: layer.cancel_placement())
	_furniture_menu = FurnitureContextMenu.new()
	$UI/Root.add_child(_furniture_menu)
	_furniture_menu.move_requested.connect(_on_furniture_place_requested)
	_furniture_menu.rotate_requested.connect(_on_furniture_rotate)
	_furniture_menu.remove_requested.connect(_on_furniture_remove)
	layer.item_clicked.connect(_on_furniture_item_clicked)
	layer.placement_confirmed.connect(_on_furniture_placed)
	layer.placement_cancelled.connect(_on_furniture_placement_cancelled)
	layer.hint_changed.connect(_furniture_screen.show_problem)
	_furniture_button = Button.new()
	_furniture_button.text = "🛋️"
	_furniture_button.tooltip_text = "Мебель: магазин и расстановка"
	_furniture_button.focus_mode = Control.FOCUS_NONE
	_furniture_button.add_theme_font_size_override("font_size", 28)
	_furniture_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_furniture_button.offset_left = 16.0
	_furniture_button.offset_top = 126.0
	_furniture_button.offset_right = 72.0
	_furniture_button.offset_bottom = 178.0
	_furniture_button.pressed.connect(_toggle_furniture_screen)
	$UI/Root.add_child(_furniture_button)


## Мышь над панелью мебели или меню предмета.
func _furniture_pointer_over_ui() -> bool:
	if _furniture_screen == null:
		return false
	var mouse := _furniture_screen.get_global_mouse_position()
	if _furniture_screen.visible and _furniture_screen.get_global_rect().has_point(mouse):
		return true
	return _furniture_menu != null and _furniture_menu.visible and _furniture_menu.get_global_rect().has_point(mouse)


## Режим мебели: камера двигается зажатым колесом мыши (экранная дельта).
func _input(event: InputEvent) -> void:
	if not _furniture_open():
		return
	var motion := event as InputEventMouseMotion
	if motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		_garage.pan_camera(motion.relative)


func _furniture_open() -> bool:
	return _furniture_screen != null and _furniture_screen.visible


func _toggle_furniture_screen() -> void:
	if _furniture_screen == null:
		return
	if _furniture_screen.visible:
		_furniture_screen.close()
		return
	if not _furniture_unlocked():
		_notify("🔒 Мебель откроется после первого гостя.")
		return
	_furniture_screen.open()
	if _guide_panel != null:
		_guide_panel.visible = false
	_garage.begin_free_camera()
	if _furniture_button != null:
		_furniture_button.visible = false
	var layer := _garage.furniture_layer()
	if layer != null:
		layer.set_selection_enabled(true)
	_set_furniture_pause(true)
	_update_input_lock()


func _on_furniture_closed() -> void:
	var layer := _garage.furniture_layer()
	if layer != null:
		layer.cancel_placement(false)
		layer.set_selection_enabled(false)
	if _furniture_menu != null:
		_furniture_menu.close()
	_garage.end_free_camera()
	if _furniture_button != null:
		_furniture_button.visible = _furniture_unlocked()
	if _guide_panel != null:
		_guide_panel.visible = true
	_set_furniture_pause(false)
	_update_input_lock()


## Пока окно мебели открыто, вся игра стоит (время почти останавливается), а диалоги и облачка полупрозрачны.
func _set_furniture_pause(on: bool) -> void:
	if on and not _furniture_paused:
		_saved_time_scale = Engine.time_scale
		Engine.time_scale = FURNITURE_PAUSE_SCALE
		_furniture_paused = true
	elif not on and _furniture_paused:
		Engine.time_scale = _saved_time_scale
		_furniture_paused = false
	_dialogue_box.modulate.a = 0.2 if on else 1.0
	_garage.set_head_labels_alpha(0.25 if on else 1.0)


func _on_furniture_item_clicked(uid: String, screen_position: Vector2) -> void:
	if uid == "":
		_furniture_menu.close()
		return
	var entry := _furniture.entry_of(uid)
	if entry.is_empty():
		return
	var data := _furniture.item(str(entry["item"]))
	_furniture_menu.open_for(uid, "%s %s" % [str(data.get("icon", "")), str(data["name"])], bool(data["rotation_allowed"]), screen_position)


func _on_furniture_rotate(uid: String) -> void:
	var result := _furniture.rotate_in_place(uid)
	if result["ok"]:
		_stats.bump("furniture_rotated")
		_furniture_screen.notify("Повернули. ПКМ по мебели — меню.")
		_furniture_menu.close()
	else:
		_furniture_screen.notify("⛔ %s" % str(result["error"]))


func _on_furniture_buy(item_id: String) -> void:
	var result := _furniture.buy(item_id)
	if result["ok"]:
		var price := int(_furniture.item(item_id)["price"])
		_stats.bump("furniture_bought")
		_stats.bump("furniture_spent", price)
		_furniture_screen.notify("Куплено: %s (−%d 💰). Он во вкладке «В наличии»: потяните его в гараж." % [str(_furniture.item(item_id)["name"]), price])
		_furniture_screen.show_toast("🛒 Куплено: %s (−%d 💰)" % [str(_furniture.item(item_id)["name"]), price])
	else:
		_furniture_screen.notify("⛔ %s" % str(result["error"]))


func _on_furniture_place_requested(uid: String) -> void:
	_start_furniture_placement(uid, false)


## Предмет потянули мышью (из списка «В наличии» или прямо в мире): ставится по отпусканию кнопки.
func _on_furniture_drag_started(uid: String) -> void:
	_start_furniture_placement(uid, true)


func _start_furniture_placement(uid: String, dragging: bool) -> void:
	var entry := _furniture.entry_of(uid)
	if entry.is_empty():
		return
	var layer := _garage.furniture_layer()
	_furniture_menu.close()
	_furniture_screen.set_placing(true, str(_furniture.item(str(entry["item"]))["name"]))
	layer.begin_placement(uid, dragging)


func _on_furniture_placed(cell: Vector2, rotation: int) -> void:
	var layer := _garage.furniture_layer()
	var uid := layer.placing_uid()
	var result := _furniture.place(uid, cell, rotation)
	if result["ok"]:
		_stats.bump("furniture_placed")
		if _furniture.placed_non_gift_count() >= 1:
			_mark_beat("decorated")
		layer.cancel_placement(false)
		_furniture_screen.set_placing(false)
		var detached := int(result.get("detached", 0))
		_furniture_screen.notify("Поставили." if detached == 0 else "Поставили. Предметы со стола вернулись на склад: %d." % detached)
		_furniture_screen.refresh()
	else:
		_furniture_screen.notify("⛔ %s" % str(result["error"]))


func _on_furniture_placement_cancelled() -> void:
	_furniture_screen.set_placing(false)
	_furniture_screen.refresh()


func _on_furniture_sell(uid: String) -> void:
	var layer := _garage.furniture_layer()
	if layer != null and layer.placing_uid() == uid:
		layer.cancel_placement(false)
		_furniture_screen.set_placing(false)
	var entry := _furniture.entry_of(uid)
	if entry.is_empty():
		return
	var item_name := str(_furniture.item(str(entry["item"]))["name"])
	var result := _furniture.sell(uid)
	if result["ok"]:
		_stats.bump("furniture_sold")
		_stats.bump("furniture_sold_income", int(result["price"]))
		_furniture_screen.notify("Продано: %s (+%d 💰)." % [item_name, int(result["price"])])
		_furniture_screen.show_toast("💰 Продано: %s (+%d 💰)" % [item_name, int(result["price"])])
	else:
		_furniture_screen.notify("⛔ %s" % str(result["error"]))


func _on_furniture_remove(uid: String) -> void:
	if _furniture.remove(uid):
		_stats.bump("furniture_removed")
		_furniture_screen.notify("Убрали на склад." if _furniture.last_detached == 0 else "Убрали на склад вместе с предметами сверху (%d)." % _furniture.last_detached)


func _debug_next_trend() -> void:
	if _trends != null and _trends.is_valid():
		_trends.set_trend(_trends.next_id())
		_sync_trend_state()


func _debug_add_money() -> void:
	if _economy != null:
		_economy.earn(1000)


func _debug_zero_money() -> void:
	_state.set_money(0)
	GameLog.info("test", "Деньги обнулены (тест)")


func _debug_reset_goal() -> void:
	if _goal == null:
		return
	for recipe_id in _state.recipes:
		_state.recipes[recipe_id].erase("strong_trends")
	_state.set_flag(ProgressionGoal.DONE_FLAG, false)
	_state.set_flag(ProgressionGoal.ENDING_SEEN_FLAG, false)
	GameLog.info("test", "Цель MVP сброшена")


## Ускорение всей игры для тестов (Engine.time_scale): таймеры, твины, ходьба, жар, анимации.
func _set_game_speed(value: float) -> void:
	var scale := clampf(value, 0.1, 10.0)
	if _furniture_paused:
		_saved_time_scale = scale
	else:
		Engine.time_scale = scale
	if _stats_panel != null:
		_stats_panel.show_speed(scale)
	GameLog.info("test", "Скорость игры ×%.0f" % scale)


# --- M10: интро-срез (ворота, Бэн, цель в углу, концовка-уведомление) ------------------------------

func _setup_m10() -> void:
	_intro = IntroGuide.load_default()
	for message in _intro.errors:
		GameLog.error("intro", message)
	_build_guide_panel()
	if _furniture != null:
		_furniture.changed.connect(_on_furniture_changed)
	_build_milk_button()
	_setup_modal_dim()
	_apply_unlocks()
	_restore_ben.call_deferred()


## Затемнение под окнами смешивания, книги рецептов и забивки: HUD, цель и кнопки уходят под него и не залезают на окна.
func _setup_modal_dim() -> void:
	var root := $UI/Root as Control
	_modal_dim = ColorRect.new()
	_modal_dim.color = Color(0, 0, 0, 0.6)
	_modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_dim.visible = false
	root.add_child(_modal_dim)
	_modal_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.move_child(_modal_dim, _mixer.get_index())
	for node in [_hud, _guide_panel, _objective_label, _furniture_button, _milk_button, _autopilot_button, _camera_button, _stats_button]:
		if node != null and (node as Node).get_parent() == root:
			root.move_child(node as Node, _modal_dim.get_index())


## Кнопка 🥛: кальянщик вручную пьёт молоко и говорит что-нибудь про кайф и свободу.
func _build_milk_button() -> void:
	_milk_button = Button.new()
	_milk_button.text = "🥛"
	_milk_button.tooltip_text = "Выпить молока"
	_milk_button.focus_mode = Control.FOCUS_NONE
	_milk_button.add_theme_font_size_override("font_size", 28)
	_milk_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_milk_button.offset_left = 84.0
	_milk_button.offset_top = 126.0
	_milk_button.offset_right = 140.0
	_milk_button.offset_bottom = 178.0
	_milk_button.pressed.connect(_drink_milk)
	$UI/Root.add_child(_milk_button)


func _drink_milk() -> void:
	if _autopilot or _drinking or _carrying or _ui_paused() or _furniture_open():
		return
	_drinking = true
	_carrying = true
	_update_input_lock()
	_stats.bump("milk_drunk")
	_garage.set_chips("player", [{"emoji": "🥛", "state": "pick"}])
	await _garage.play_drink(2.6, MILK_LINES.pick_random())
	_garage.clear_chips("player")
	_carrying = false
	_drinking = false
	_update_input_lock()


func _sessions_done() -> int:
	return int(_state.get_flag("sessions_done", 0)) if _state != null else 0


func _mark_beat(key: String) -> void:
	_stats.mark_beat(key, _game_seconds)


func _autopilot_allowed() -> bool:
	return _intro == null or _sessions_done() >= AUTOPILOT_AFTER_SESSIONS


func _furniture_unlocked() -> bool:
	return _intro == null or _intro.is_furniture_unlocked(_sessions_done())


## Применяет ворота: быстрый режим и мебель открываются после нужного числа гостей.
func _apply_unlocks() -> void:
	if _intro == null:
		return
	var count := _sessions_done()
	var quick := _intro.is_quick_unlocked(count)
	_preparation_screen.set_quick_locked(not quick, "Быстрый режим откроется после %d-го гостя" % _intro.quick_after_sessions)
	if quick and _state.get_flag("quick_unlock_seen", false) != true and _intro.quick_after_sessions > 0:
		_state.set_flag("quick_unlock_seen", true)
		_mark_beat("quick_unlocked")
		_notify("🎚 Открыт быстрый режим приготовления!")
	var furniture := _intro.is_furniture_unlocked(count)
	if _furniture_button != null and not _furniture_open():
		_furniture_button.visible = furniture
	if furniture and _state.get_flag("furniture_unlock_seen", false) != true and _intro.furniture_after_sessions > 0:
		_state.set_flag("furniture_unlock_seen", true)
		_mark_beat("furniture_unlocked")
		_notify("🛋️ Открыта мебель: кнопка слева вверху!")
	if _autopilot_button != null:
		_autopilot_button.disabled = not _autopilot_allowed()
		_autopilot_button.tooltip_text = "Автопилот кальянщика (F10)" if _autopilot_allowed() else "Автопилот откроется после третьего гостя"
	_refresh_guide()


# --- Цель в углу экрана ---

func _build_guide_panel() -> void:
	_guide_panel = PanelContainer.new()
	_guide_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_guide_panel.offset_left = -346.0
	_guide_panel.offset_right = -16.0
	_guide_panel.offset_top = 76.0
	_guide_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_guide_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_panel.add_child(box)
	_guide_header = Label.new()
	_guide_header.add_theme_font_size_override("font_size", 15)
	_guide_header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_guide_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_guide_header)
	_guide_label = Label.new()
	_guide_label.add_theme_font_size_override("font_size", 16)
	_guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_label.custom_minimum_size = Vector2(290, 0)
	_guide_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_guide_label)
	$UI/Root.add_child(_guide_panel)
	_guide_panel.visible = false
	# Окно статистики (F8) лежит поверх цели.
	if _stats_panel != null and _stats_panel.get_parent() == $UI/Root:
		$UI/Root.move_child(_guide_panel, _stats_panel.get_index())


func _refresh_guide() -> void:
	if _guide_label == null or _intro == null or _state == null:
		return
	var count := _sessions_done()
	var couch: Dictionary = _furniture.gift_entry("couch") if _furniture != null else {}
	var ctx := {
		"sessions": count,
		"ben_here": _state.get_flag("ben_here", false) == true,
		"couch_placed": not couch.is_empty() and bool(couch.get("placed", false)),
		"recipe_count": _state.recipes.size(),
		"coals_replaced": _state.get_flag("coals_replaced_once", false) == true,
		"heat_warn": _heat != null and _heat_active and (_heat.needs_service() or _npc_service_pending),
		"furniture_unlocked": _intro.is_furniture_unlocked(count),
		"extra_furniture_placed": _furniture.placed_non_gift_count() if _furniture != null else 0,
		"goal_done": _state.get_flag(ProgressionGoal.DONE_FLAG, false) == true,
		"progress_text": _goal.progress_text(_state.recipes) if _goal != null else "",
	}
	var step := _intro.current_step(ctx)
	if str(step["id"]) == "done":
		_guide_header.text = "🎯 Цель выполнена"
	else:
		_guide_header.text = "🎯 Цель (%d/%d)" % [int(step["done_count"]) + 1, int(step["total"])]
	_guide_label.text = str(step["text"])
	_guide_panel.visible = not _furniture_open()


# --- Бэн ---

func _bind_buddy() -> void:
	if _buddy == null:
		return
	_buddy.sat_down.connect(func() -> void: _mark_beat("ben_sat"))


## Бэн приходит после первого гостя, приносит диван (подарок: его нужно поставить самому).
func _maybe_ben_arrival() -> void:
	if _intro == null or _furniture == null or _buddy != null or _state == null:
		return
	if not _intro.ben_should_arrive(_sessions_done(), _state.get_flag("ben_here", false) == true):
		return
	var guest := GuestCatalog.load_guest(BEN_ID)
	if guest.is_empty():
		return
	_state.set_flag("ben_here", true)
	_carrying = true
	_update_input_lock()
	_buddy = _garage.spawn_buddy(guest, BEN_ENTRY_POSITION, BEN_ENTRY_CELL, BEN_WAIT_CELL, _intro)
	if _buddy == null:
		_carrying = false
		_update_input_lock()
		return
	_bind_buddy()
	_mark_beat("ben_arrives")
	await _buddy.friend.arrived
	await get_tree().create_timer(0.6).timeout
	await _play_dialogue("ben_couch")
	_ensure_ben_gift()
	_notify("🎁 Бэн подарил диван! Открой 🛋️ → «В наличии» и поставь его.")
	_buddy.start()
	_sync_buddy_couch()
	_carrying = false
	_update_input_lock()
	_refresh_objective()


func _ensure_ben_gift() -> void:
	if _furniture != null and _furniture.gift_entry("couch").is_empty():
		_furniture.grant_gift("couch")


## Бэн уже приходил (загрузка): возвращаем его в гараж без двери.
func _restore_ben() -> void:
	if _intro == null or _furniture == null or _buddy != null or _state == null:
		return
	if _state.get_flag("ben_here", false) != true:
		return
	var guest := GuestCatalog.load_guest(BEN_ID)
	if guest.is_empty():
		return
	_ensure_ben_gift()
	_buddy = _garage.spawn_buddy(guest, BEN_ENTRY_POSITION, BEN_ENTRY_CELL, BEN_WAIT_CELL, _intro, false)
	if _buddy == null:
		return
	_bind_buddy()
	await _buddy.friend.arrived
	_sync_buddy_couch()
	_buddy.sit_immediately()
	_buddy.start()


func _on_furniture_changed() -> void:
	_sync_buddy_couch()
	_refresh_guide()


## Диван Бэна поставили/передвинули/убрали: Бэн это замечает.
func _sync_buddy_couch() -> void:
	if _furniture == null or _state == null:
		return
	var entry := _furniture.gift_entry("couch")
	var placed := not entry.is_empty() and bool(entry.get("placed", false))
	if _buddy != null:
		if placed:
			var rect := _furniture.entry_rect(entry)
			_buddy.set_couch(rect, rect.size.x >= rect.size.y)
		else:
			_buddy.clear_couch()
	if placed and _state.get_flag("couch_placed_once", false) != true:
		_state.set_flag("couch_placed_once", true)
		_mark_beat("couch_placed")
		if _buddy != null and is_instance_valid(_buddy.friend):
			_buddy.friend.say("Диван! Ты лучший, бро! 🛋️")


func _play_dialogue(dialogue_id: String) -> void:
	var dialogue := _library.get_dialogue(dialogue_id)
	if dialogue.is_empty():
		GameLog.error("story", "Нет диалога '%s'" % dialogue_id)
		return
	_update_input_lock()
	_open_dialogue_ui(dialogue["speakers"])
	if _runner.start(dialogue, _effects.check):
		await _runner.finished
	else:
		_dialogue_box.close()
	_update_input_lock()


# --- Уведомление (открытая концовка) ---

func _show_notice(text: String) -> void:
	if text.is_empty():
		return
	_carrying = true
	_update_input_lock()
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var button := Button.new()
	button.text = "Продолжить"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size = Vector2(200, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void: _notice_closed.emit())
	box.add_child(button)
	$UI/Root.add_child(overlay)
	_notice_overlay = overlay
	_notice_timer = 0.0
	await _notice_closed
	overlay.queue_free()
	_notice_overlay = null
	_carrying = false
	_update_input_lock()


# --- Автопилот: расстановка мебели ---

## Автопилот ставит подаренный диван и один-два купленных предмета. true — что-то сделал.
func _autopilot_furnish() -> bool:
	if _furniture == null or _intro == null or _economy == null or _furniture_open() or not _furniture_unlocked():
		return false
	if _game_seconds < _furnish_next_try:
		return false
	var uid := ""
	for entry in _furniture.stored_entries():
		if bool(entry.get("gift", false)):
			uid = str(entry["uid"])
			break
	if uid == "" and not _furniture.stored_entries().is_empty():
		uid = str(_furniture.stored_entries()[0]["uid"])
	if uid == "" and _furniture.placed_non_gift_count() < 2:
		var best := ""
		var best_price := 1 << 30
		for item_id in _furniture.items:
			var price := int(_furniture.items[item_id]["price"])
			if price < best_price:
				best_price = price
				best = str(item_id)
		if best != "" and _economy.balance() >= best_price + 150:
			var bought := _furniture.buy(best)
			if bought["ok"]:
				_stats.bump("furniture_bought")
				_stats.bump("furniture_spent", best_price)
				_notify("🛒 Куплено: %s (−%d 💰)" % [str(_furniture.item(best)["name"]), best_price])
				uid = str(bought["uid"])
	if uid == "":
		return false
	if _autopilot_place(uid):
		_stats.bump("furniture_placed")
		if _furniture.placed_non_gift_count() >= 1:
			_mark_beat("decorated")
		return true
	_furnish_next_try = _game_seconds + 60.0
	return false


func _autopilot_place(uid: String) -> bool:
	var entry := _furniture.entry_of(uid)
	if entry.is_empty():
		return false
	var item_id := str(entry["item"])
	var layer := _garage.furniture_layer()
	var cells: Array[Vector2i] = []
	for x in range(_furniture.room_size.x):
		for y in range(_furniture.room_size.y):
			cells.append(Vector2i(x, y))
	cells.shuffle()
	for rotation in [0, 1]:
		for cell in cells:
			var at := Vector2(cell)
			if _furniture.check_placement(item_id, at, rotation, uid) != "":
				continue
			if layer != null and layer.validator.is_valid() and str(layer.validator.call(item_id, at, rotation, uid)) != "":
				continue
			if bool(_furniture.place(uid, at, rotation)["ok"]):
				return true
	return false


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _toggle_stats_panel() -> void:
	if _stats_panel != null:
		_stats_panel.toggle()


## Строки окна статистики: сначала «живые» значения, затем итоги за запуск.
func _stats_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("— СЕЙЧАС —")
	lines.append("Режим: %s, скорость ×%.0f%s" % ["NPC (автопилот)" if _autopilot else "ручной", _saved_time_scale if _furniture_paused else Engine.time_scale, " (пауза: мебель)" if _furniture_paused else ""])
	lines.append("Сюжет: %s" % _state.story_progress)
	var guest_id := _garage.ready_friend_id()
	var guest_name := str(GuestCatalog.load_guest(guest_id).get("name", guest_id)) if guest_id != "" else "—"
	lines.append("Гость: %s%s" % [guest_name, " (уходит)" if _guest_departing else ""])
	lines.append("Заказ: %s" % (str(_order.get("id", "?")) if not _order.is_empty() else "—"))
	lines.append("Стол: %s" % str(_station.state))
	if _heat != null and _heat_active:
		lines.append("Жар: %.0f (%s), темп %.2f, затяжек %d" % [_heat.heat, _heat.state, _heat.pace, _session_puffs])
		lines.append("Штраф: жар %.1f, сервис %.1f" % [_heat.heat_penalty(), _service_penalty])
		lines.append("Угли: %s, перезабивка: %s" % ["ждут замены" if (_heat.needs_service() or _npc_service_pending) else "ок", "просит" if _redo_requested else ("использована" if _redo_used else "нет")])
	else:
		lines.append("Жар: — (гость не курит)")
	lines.append("Мундштуков в коробке: %d" % _garage.mouthpiece_count())
	lines.append("Деньги: %d, репутация: %d" % [_state.money, _state.reputation])
	if _furniture != null and _furniture.is_valid():
		var furniture_totals := _furniture.totals()
		lines.append("Мебель: расставлено %d из %d, комфорт %d, атмосфера %d, бонус к оценке +%.1f" % [int(furniture_totals["placed"]), _furniture.owned_count(), int(furniture_totals["comfort"]), int(furniture_totals["atmosphere"]), float(furniture_totals["bonus"])])
	if _trends != null and _goal != null:
		lines.append("Тренд: %s (ещё %d виз.), далее: %s" % [_trends.current_name(), _trends.visits_left, _trends.name_of(_trends.next_id())])
		lines.append("Цель: сильных рецептов %s%s" % [_goal.progress_text(_state.recipes), " — ВЫПОЛНЕНА" if _goal.is_complete(_state.recipes) else ""])
	lines.append("FPS: %d" % int(Engine.get_frames_per_second()))
	lines.append("")
	lines.append("— ЗА ЗАПУСК —")
	lines.append_array(_stats.summary_lines())
	lines.append_array(_stats.visit_lines())
	lines.append_array(_stats.beat_lines())
	return lines


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
