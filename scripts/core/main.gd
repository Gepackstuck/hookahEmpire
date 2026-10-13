extends Node
## Корень игры. Держит мир (WorldRoot) и UI-слой и связывает системы между собой:
## гараж <-> диалоги <-> сюжетные эффекты <-> GameState.

## Сессия гостя закончилась: хук для репутации/экономики (M8–M9). result — итог оценки + guest_id, recipe_id.
signal session_finished(result: Dictionary)

const DIALOGUES_DIR := "res://data/dialogues"
const BEATS_PATH := "res://data/story/intro_beats.json"
const SaveServiceScript := preload("res://scripts/core/save_service.gd")

var _save: SaveServiceScript = null

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
var _summary: SessionSummaryScreen = null
var _viewer: ImageViewer = null
## Текущий визит (гость, с которым сейчас работает кальянщик): заказ, кальян, жар, перезабивка. См. GuestVisit.
var _v: GuestVisit = GuestVisit.create()
## M12: визит основного стола (s1) и второго (s2). `_v` — «текущий» визит (рабочий регистр): каждая точка входа
## (действие у стола, затяжка, тик, продолжение корутины после await) сама выставляет `_v`, не полагаясь на прошлое значение.
var _visit_main: GuestVisit = null
var _visit_extra: GuestVisit = null
var _visit_extra2: GuestVisit = null
var _visit_extra3: GuestVisit = null
## Визиты дополнительных столов s5…s8 (потоком с ростом числа гостей).
var _more_visits: Dictionary = {}
## station_id -> игровое время, с которого место ждёт внимания кальянщика (для справедливой очереди автопилота).
var _need_since: Dictionary = {}
## Пары гостей за одним столом, которые уже познакомились (ключ "idA|idB").
var _paired: Dictionary = {}
var _pair_chat_timer := 0.0
## Визит, для которого сейчас открыто приготовление (кальян на столе для кальянов один).
var _prep_visit: GuestVisit = null
## Чей кальян стоит на столе для кальянов после перезабивки: у каждого гостя свой кальян, подать его можно только ему.
var _prep_owner: GuestVisit = null
var _station_refresh_timer := 0.0
## Случайные гости: со какого по счёту визита (7–10) начинаются, пул ожидающих и уже приходившие.
var _gen_start := 0
var _gen_pool: Array[String] = []
var _gen_used: Dictionary = {}
const GEN_POOL_SIZE := 4
## Компании: шанс прихода пары, смена курящего, пары ждущих на диване (лидер <-> спутник).
const COMPANY_CHANCE := 0.4
## Одиночка садится к незнакомцу: всегда при сходстве ≥ NEIGHBOR_LIKE, иначе с шансом NEIGHBOR_ACCEPT (ждущий — когда терпение на исходе).
const NEIGHBOR_LIKE := 0.8
const NEIGHBOR_ACCEPT := 0.3
const COMPANY_TURN_SECONDS := 9.0
var _company_partner: Dictionary = {}
var _company_turn: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Вкусы предыдущего гостя: следующий гость со случайным вкусом старается отличаться от них.
var _last_order_prefs: Dictionary = {}
## guest_id -> тексты заказов, которые гость уже делал (чтобы заказы не повторялись и книга рецептов росла).
var _used_orders: Dictionary = {}
var _stats := PlaytestStats.new()
var _stats_panel: StatsPanel = null
var _stats_button: Button = null
var _book_from_mixer := false
var _carrying := false
## Кальян стоит на столе для кальянов (взят с полки или принесён на перезабивку).
var _hookah_on_prep_table := false
var _objective_label: Label = null
## Автопилот: кальянщик сам принимает заказ, смешивает рецепт, готовит и подаёт (затравка под нанятых работников).
var _autopilot := false
var _autopilot_running := false
var _autopilot_button: Button = null
## Тест-прогон (только в отладочной сборке, галочка рядом с 🤖): автопилот сразу, первые рецепты засчитываются сильными,
## мебель автопилот ставит парой «стол + стул» и только после того, как второй гость ушёл рассерженным (когда он появится, M12).
var _test_run := false
var _test_run_check: CheckBox = null
var _test_angry_seen := false
## Планировщик одновременных гостей (создаётся на шаге 3 M12); пока null — тест-прогон не ждёт ухода второго гостя.
var _scheduler: VisitScheduler = null
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
const QUICK_SERVED_FLAG := "quick_served"
## Минимальное совпадение рецепта с заказом, чтобы автопилот повторил «почти сильный» рецепт при новом тренде.
const STRONG_HUNT_MIN_FIT := 55.0
var _intro: IntroGuide = null
var _buddy: Buddy = null
var _guide_panel: PanelContainer = null
var _guide_header: Label = null
## Кнопка со счётчиком шагов цели: сворачивает и разворачивает панель цели.
var _guide_button: Button = null
var _guide_expanded := false
var _guide_label: Label = null
var _game_seconds := 0.0
var _strong_count := 0
var _notice_overlay: Control = null
## Окно, которое автопилот не закрывает сам: игра на паузе, пока игрок не нажмёт кнопку.
var _notice_hold := false
var _notice_timer := 0.0
var _notice_opened_msec := 0
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
	_visit_main = _v
	_visit_extra = GuestVisit.create()
	_visit_extra.station_id = GuestStation.EXTRA_ID
	_visit_extra2 = GuestVisit.create()
	_visit_extra2.station_id = GuestStation.EXTRA2_ID
	_visit_extra3 = GuestVisit.create()
	_visit_extra3.station_id = GuestStation.MAIN2_ID
	for station_id in GuestStation.EXTRA_IDS:
		if station_id != GuestStation.EXTRA_ID and station_id != GuestStation.EXTRA2_ID:
			var more := GuestVisit.create()
			more.station_id = station_id
			_more_visits[station_id] = more
	# GameState/SaveService — autoload; проверяем через путь, чтобы не падать при их отсутствии.
	for autoload_name in ["GameState", "SaveService"]:
		if get_node_or_null("/root/%s" % autoload_name) == null:
			GameLog.error("main", "Autoload не найден: %s" % autoload_name)

	_save = get_node_or_null("/root/SaveService") as SaveServiceScript
	_apply_saved_volume()
	_apply_saved_graphics()
	# M11: пока профиль не выбран, показываем только список профилей.
	if _save != null and _save.needs_profile_choice():
		_show_profile_gate()
		return

	_add_debug_button()
	_add_stats_panel()
	_add_fps_counter()
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
	if _save != null and _save.autosave_enabled:
		_save.load_game()
	_recipes = RecipeSystem.create(_state)
	if _recipes != null:
		_mixer.setup(_recipes)
		_book.setup(_recipes)
		_mixer.recipe_committed.connect(_on_recipe_committed)
		_scoring = SessionScoring.load_default()
		for message in _v.heat.errors:
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
		_setup_m12()
	_effects = StoryEffects.new(_state)
	_runner.effect_requested.connect(_effects.apply)
	_refresh_objective()

	_library.load_directory(DIALOGUES_DIR)
	for message in _library.errors:
		GameLog.error("dialogue", message)
	_beats = StoryBeats.load_file(BEATS_PATH)
	for message in _beats.errors:
		GameLog.error("story", message)
	# Загруженный прогресс «гость в середине визита» откатываем к его приходу.
	_state.set_story_progress(_beats.rewind_progress(_state.story_progress))
	_apply_station()
	_start_story()
	_setup_profiles()
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
	# Этот гость сейчас сидит за вторым столом: ждём, пока уйдёт.
	while _garage.has_guest(str(beat["guest"])):
		await get_tree().create_timer(2.0).timeout
	var guest := GuestCatalog.load_guest(beat["guest"])
	if guest.is_empty():
		return
	if not _garage.spawn_friend(guest, beat["entry_position"], beat["entry_cell"], beat["stand_cell"], beat["dialogue"], beat["seat"]):
		return
	if not str(beat["sets_progress"]).is_empty():
		_state.set_story_progress(beat["sets_progress"])


## Друг пришёл: кидаем его заказ (случайный вкус; гость со случайным вкусом отличается от предыдущего).
func _on_friend_arrived(guest_id: String) -> void:
	if _garage.is_companion(guest_id):
		return
	var arrived_visit := _visit_of_guest(guest_id)
	if arrived_visit != null:
		_v = arrived_visit
	_mark_beat("arrive_%s" % guest_id)
	if _intro != null and _intro.is_trends_unlocked(_sessions_done()):
		_unlock_trends()
	if _v.order.is_empty():
		var guest := GuestCatalog.load_guest(guest_id)
		if not guest.is_empty():
			_rng.randomize()
			var used: Array = _used_orders.get(guest_id, [])
			_v.order = GuestCatalog.roll_order(guest, _rng, _last_order_prefs, used)
			# Список «уже было» у гостя: когда он заказал всё, начинаем сначала.
			if used.size() >= int(guest.get("orders", []).size()) and guest.has("orders"):
				used = []
			used.append(str(_v.order["text"]))
			while used.size() > 8:
				used.pop_front()
			_used_orders[guest_id] = used
			_last_order_prefs = _v.order["preferences"]
			GameLog.info("guests", "Заказ %s: %s %s" % [guest_id, str(_v.order["id"]), str(_v.order["preferences"])])
			if _recipes != null:
				_mixer.set_order_hint("💡 Заказ %s: %s" % [str(guest["name"]), OrderHint.suggest(_recipes.catalog, _v.order["preferences"], 2, _rng)])
				_mixer.set_order_taste(_v.order["preferences"], _v.order.get("dislikes", {}))
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


func _on_friend_inhaled(guest_id: String) -> void:
	var inhaling := _visit_of_guest(guest_id)
	if inhaling != null:
		_v = inhaling
	_v.session_puffs += 1
	_heat_puff()
	if not _v.ask_blocked:
		return
	_v.puffs_until_ask -= 1
	if _v.puffs_until_ask <= 0:
		_v.ask_blocked = false
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
	var guest_id := _ready_guest()
	return guest_id if guest_id != "" else _v.station.guest_id


func _on_dialogue_requested(dialogue_id: String) -> void:
	for visit in _visits():
		var seated := _garage.station_guest_id(visit.station_id)
		if seated != "" and dialogue_id.begins_with(seated):
			_v = visit
			break
	# Кальян уже подан: гость говорит, что о нём думает (а не повторяет приветствие).
	if _talk_about_hookah(dialogue_id):
		return
	# Подошли к гостю: если в коробке мало мундштуков, кальянщик докладывает новые.
	if dialogue_id.begins_with("friend_") and not _autopilot and _top_up_mouthpieces():
		_stats.bump("mouthpiece_refill")
		_notify("Кальянщик докладывает мундштуки в коробку.")
	var dialogue := _library.get_dialogue(dialogue_id)
	if not dialogue.is_empty() and not _v.order.is_empty():
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
	if _v.last_verdict.is_empty() or _runner.is_active:
		return false
	if _v.station.state != HookahStation.STATE_LIKED and _v.station.state != HookahStation.STATE_DISLIKED:
		return false
	var guest_id := str(_v.last_verdict["guest_id"])
	if _ready_guest() != guest_id or not dialogue_id.begins_with(guest_id):
		return false
	_garage.friend_react(guest_id, str(_v.last_verdict["emoji"]))
	_talk_about_hookah_async(guest_id)
	return true


func _talk_about_hookah_async(guest_id: String) -> void:
	_update_input_lock()
	await _play_verdict_dialogue(guest_id, _v.last_verdict)
	_update_input_lock()
	_refresh_objective()


## Копия диалога, где {order} заменён текстом текущего заказа.
func _with_order_text(dialogue: Dictionary) -> Dictionary:
	var copy: Dictionary = dialogue.duplicate(true)
	var nodes: Dictionary = copy.get("nodes", {})
	for node_id in nodes:
		var node: Dictionary = nodes[node_id]
		if node.has("text"):
			node["text"] = str(node["text"]).replace("{order}", str(_v.order["text"]))
	return copy


## Игра "заморожена" для мира, пока открыт любой экран или идёт диалог.
func _update_input_lock() -> void:
	# Мышь (маски, книги, свиток) работает, пока не открыто окно или диалог.
	_garage.set_pointer_enabled(not (_mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _furniture_open() or _profile_menu_open() \
		or (_summary != null and _summary.visible) or (_viewer != null and _viewer.visible) or (_runner.is_active and not _autopilot)))
	_garage.set_input_locked(_carrying or _garage.is_action_busy() or _mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _furniture_open() or _profile_menu_open() or (_summary != null and _summary.visible) or _runner.is_active or _autopilot)


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
		"replace_coals", "redo_hookah", "smoke_hookah", "ask_to_smoke":
			_v = _visit_of_station(_garage.last_action_station_id())
		"take_order":
			var asker := _visit_of_guest(_garage.last_interacted_id())
			if asker != null:
				_v = asker
				await _take_order(asker.station_id)
				_v = asker
		"open_preparation":
			var target := _prep_target_visit()
			if target != null:
				_v = target
			_prep_visit = _v
	match action_id:
		"open_mixer":
			_mixer.open()
		"open_preparation":
			if _preparation == null:
				_notify("Приготовление недоступно (ошибка данных, см. лог).")
			elif not _order_known():
				_notify("Сначала узнай, чего хочет гость.")
			else:
				var prep_for := _v
				await _ensure_hookah_on_prep_table()
				_v = prep_for
				_prep_visit = prep_for
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


## Второй гость без диалога: кальянщик подошёл, гость называет заказ.
func _take_order(station_id: String) -> void:
	var v := _visit_of_station(station_id)
	var guest_id := _garage.station_ready_guest(station_id)
	if guest_id == "" or _runner.is_active or v.order.is_empty():
		return
	_v = v
	var guest := GuestCatalog.load_guest(guest_id)
	if guest.is_empty():
		return
	if not _autopilot and _top_up_mouthpieces():
		_stats.bump("mouthpiece_refill")
		_notify("Кальянщик докладывает мундштуки в коробку.")
	_update_input_lock()
	await _play_lines(guest, [["guest", "Сделаешь мне кальян? %s" % str(v.order["text"])]])
	_v = v
	_state.set_flag("%s_order_known" % guest_id.trim_prefix("friend_"), true)
	_garage.configure_interaction(guest_id, "", "", "", "", false)
	_apply_station()
	_update_input_lock()
	_refresh_objective()


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


func _on_prepared(result: Dictionary, for_visit: GuestVisit = null) -> void:
	if for_visit != null:
		_v = for_visit
	elif _prep_visit != null:
		_v = _prep_visit
	var verdict := {}
	var guest_id := _ready_guest()
	if guest_id != "" and _scoring != null and _scoring.is_valid():
		var guest := GuestCatalog.load_guest(guest_id)
		if not guest.is_empty():
			var taste := {"preferences": guest.get("preferences", {}), "dislikes": guest.get("dislikes", {})}
			if not _v.order.is_empty():
				taste["preferences"] = _v.order["preferences"]
				taste["dislikes"] = _v.order.get("dislikes", taste["dislikes"])
			# Компания: оценка средняя между заказом первого и вкусами спутника.
			var buddy_id := _garage.companion_at(_v.station_id)
			if buddy_id != "":
				var buddy_taste := GuestPairing.taste_profile(GuestCatalog.load_guest(buddy_id))
				if not buddy_taste.is_empty():
					var merged: Dictionary = {}
					var own: Dictionary = taste["preferences"]
					for dimension in IngredientCatalog.DIMENSIONS:
						var value := (float(own.get(dimension, 0.0)) + float(buddy_taste.get(dimension, 0.0))) * 0.5
						if value > 0.0:
							merged[dimension] = value
					taste["preferences"] = merged
			var recipe := _recipes.get_recipe(result["recipe_id"])
			verdict = _scoring.evaluate(taste, recipe, float(result["execution_score"]), _recipes.catalog, _recipes.config, {"furniture_bonus": _furniture.score_bonus() if _furniture != null else 0.0})
			verdict["guest_id"] = guest_id
			verdict["recipe_id"] = str(result["recipe_id"])
			if str(result.get("mode", "")) == "manual" and str(result.get("preparer", "player")) == "player":
				_scoring.apply_manual_bonus(verdict)
			if str(result.get("mode", "")) == "quick" and str(result.get("preparer", "player")) == "player" and not _autopilot:
				_state.set_flag(QUICK_SERVED_FLAG, true)
			_recipes.record_session(str(result["recipe_id"]), float(verdict["final_score"]), guest_id, int(verdict["payment"]))
	_v.station.apply_result(result, verdict)
	_v.pending_verdict = verdict
	_v.pending_cost = 0
	if _economy != null:
		_v.pending_cost = _economy.recipe_cost(_recipes.get_recipe(str(result["recipe_id"])), _recipes.config.total_units)
	_v.pending_serve = true


## После подачи: игрок несёт кальян к столу гостя и ставит его; затем гость реагирует.
func _on_preparation_closed() -> void:
	if _prep_visit != null:
		_v = _prep_visit
	var v := _v
	_update_input_lock()
	if not v.pending_serve:
		_prep_visit = null
		_refresh_objective()
		return
	v.pending_serve = false
	_charge_pending_cost()
	v.smoke_permission = false
	v.ask_blocked = false
	_carrying = true
	_update_input_lock()
	_refresh_objective()
	await _garage.carry_hookah_to_guest_table(v.station_id)
	_v = v
	_prep_visit = null
	_prep_owner = null
	_hookah_on_prep_table = false
	_update_input_lock()
	var finished_guest := ""
	var finished_verdict := {}
	if v.pending_verdict.is_empty():
		_carrying = false
		_update_input_lock()
	else:
		var verdict := v.pending_verdict
		v.pending_verdict = {}
		v.last_verdict = verdict
		var guest_id := str(verdict["guest_id"])
		_start_heat(guest_id)
		# Гость сначала делает 3–5 затяжек и только потом выдаёт реакцию.
		_garage.set_friend_smoking(guest_id, true, "")
		await _garage.wait_for_friend_puffs(guest_id, randi_range(3, 5))
		_v = v
		_carrying = false
		_update_input_lock()
		_clear_wants_badge()
		if not _autopilot:
			_garage.friend_react(guest_id, str(verdict["emoji"]))
		_garage.set_friend_smoking(guest_id, v.station.guest_smokes(), str(verdict["emoji"]))
		GameLog.info("reaction", "%s: %s (score %.1f)" % [guest_id, str(verdict["emotion_id"]), float(verdict["score"])])
		verdict["phrase"] = await _play_verdict_dialogue(guest_id, verdict)
		_v = v
		await _show_summary(guest_id, verdict)
		_v = v
		finished_guest = guest_id
		finished_verdict = verdict
	_apply_station()
	_update_input_lock()
	_refresh_objective()
	if finished_guest != "":
		_finish_session(finished_guest, finished_verdict)


## Просим у гостя разрешения покурить с ним: он случайно соглашается или отказывает.
func _ask_to_smoke() -> void:
	var v := _v
	var guest_id := _v.station.guest_id
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
	_v = v
	_garage.friend_react(guest_id, "👍" if allowed else "🙅")
	if allowed:
		_v.smoke_permission = true
	else:
		_v.ask_blocked = true
		_v.puffs_until_ask = randi_range(3, 5)
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
	var v := _v
	var story_guest: bool = v.station_id == GuestStation.MAIN_ID
	var token := _v.session_token
	# Гость курит, пока идёт жар/обслуживание; он может попросить перезабить (тогда сессию продолжит новая подача).
	verdict = await _run_smoking_phase(guest_id, verdict, token)
	_v = v
	if token != _v.session_token:
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
		"prefs": _v.order.get("preferences", {}), "dislikes": _v.order.get("dislikes", {}), "trend_name": str(verdict.get("trend_name", "")),
		"recipe_name": _recipes.display_name(visit_recipe) if not visit_recipe.is_empty() else "",
		"name": _gname(guest_id), "station": v.station_id, "companion": _gname(_garage.companion_at(v.station_id)) if _garage.companion_at(v.station_id) != "" else "",
		"neighbor": _gname(_neighbor_guest(v.station_id)) if _neighbor_guest(v.station_id) != "" else ""})
	GameLog.info("session", "%s: %.1f (%s), оплата %d" % [guest_id, float(verdict["final_score"]), str(verdict["band_id"]), payment])
	_garage.set_friend_smoking(guest_id, false)
	await _wait_until_free()
	_v = v
	_rng.randomize()
	if not guest.is_empty():
		var line := GuestCatalog.farewell_text(guest, str(verdict["emotion_id"]), likes, payment, _rng)
		await _play_lines(guest, [["guest", line]])
		_v = v
	_v.departing = true
	_v.redo_used = false
	_v.redo_requested = false
	_v.service_penalty = 0.0
	_v.station.reset()
	_v.last_verdict = {}
	_v.smoke_permission = false
	_v.ask_blocked = false
	_apply_station()
	await _garage.friend_leave(guest_id)
	_v = v
	_v.order = {}
	_mixer.set_order_hint("")
	_mixer.set_order_taste({}, {})
	var progress: String = _state.story_progress
	# Гость обслужен: заказ снова неизвестен (при следующем визите он опять сделает заказ),
	# а сюжет переходит к «обслужен» даже если разговор при визите был пропущен.
	_state.set_flag("%s_order_known" % guest_id.trim_prefix("friend_"), false)
	if story_guest and _beats != null and _beats.is_in_progress_of(guest_id, progress):
		_state.set_story_progress(_beats.done_progress_for(guest_id))
	elif story_guest and progress.ends_with("_intro_done"):
		_state.set_story_progress(progress.replace("_intro_done", "_done"))
	# Гости ходят по кругу: после последнего (Макс) снова приходит первый (Ден).
	if story_guest and _state.story_progress == LOOP_END_PROGRESS and _second_seat_ready() and _beats != null and _beats.find_for_progress(LERA_PROGRESS).size() > 0:
		# Второе место для гостя готово: после Ивана приходит четвёртый гость (Лера).
		_state.set_story_progress(LERA_PROGRESS)
	elif story_guest and (_state.story_progress == LOOP_END_PROGRESS or _state.story_progress == LERA_END_PROGRESS) and _beats != null and _beats.find_for_progress(LOOP_RESTART_PROGRESS).size() > 0:
		_state.set_story_progress(LOOP_RESTART_PROGRESS)
		_stats.bump("guest_cycles")
	_v.departing = false
	_apply_station()
	_advance_trend()
	await _maybe_play_ending()
	_v = v
	await _maybe_ben_arrival()
	_v = v
	# Новый гость приходит и садится, пока кальянщик моет кальян и убирает его на полку.
	if story_guest:
		_start_story()
	# Автопилот мог уйти «работать» у объектов: ждём, пока он закончит, иначе два движения кальянщика наложатся.
	while _idle_walking or _idle_acting:
		if _idle_walking:
			_garage.cancel_walk()
		await get_tree().process_frame
	_v = v
	_carrying = true
	_update_input_lock()
	_refresh_objective()
	await _garage.wash_hookah_and_shelve(v.station_id)
	_v = v
	_carrying = false
	_update_input_lock()
	_apply_station()
	_refresh_objective()
	_autosave()


# --- M7: жар, замена углей, перезабивка ------------------------------------------------------

const WAIT_LINE_DELAY := 2.0
const WAIT_LINES: Array[String] = ["Я сейчас!", "Секунду, я сейчас!", "Минутку, сейчас подойду!"]
var _wait_timer := 0.0
var _wait_guest_id := ""


## Гость пришёл и ждёт заказа, а кальянщик занят: один раз за приход говорим «я сейчас».
func _tick_wait_line(delta: float) -> void:
	var guest_id := ""
	if _garage != null:
		for visit in _visits():
			var seated := _garage.station_ready_guest(visit.station_id)
			if seated != "" and not _order_known_for(visit):
				guest_id = seated
				break
	if guest_id == "" or _runner.is_active or (_summary != null and _summary.visible):
		_wait_timer = 0.0
		if guest_id == "":
			_wait_guest_id = ""
		return
	if _wait_guest_id == guest_id:
		return
	var busy := _visit_main.servicing or _any_servicing() or _carrying or _mixer.visible or _book.visible or _preparation_screen.visible \
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
	if _v.heat == null:
		return
	_v.guest_id = guest_id
	_v.session_puffs = 0
	_v.heat.begin(_v.heat.roll_npc_pace(_rng) if _autopilot else -1.0)
	_v.pace_timer = _v.heat.roll_pace_interval(_rng)
	_v.complaint_timer = _v.heat.complaint_cooldown
	_v.npc_service_pending = false
	_v.heat_active = true
	_sync_heat_visual()
	_apply_station()


func _stop_heat() -> void:
	_v.heat_active = false
	_v.npc_service_pending = false
	_garage.set_hookah_heat(1, "", false, _v.station_id)
	_apply_station()


func _heat_puff() -> void:
	if _v.heat == null or not _v.heat_active:
		return
	var changed := _v.heat.puff()
	if changed != "":
		_on_heat_state_changed(changed)


func _on_player_inhaled() -> void:
	_v = _visit_of_station(_garage.player_station_id())
	_heat_puff()


## Жар меняется со временем; жалобы гостя и штраф зависят от состояния кальяна.
func _tick_session(delta: float) -> void:
	var saved := _v
	for visit in _visits():
		_v = visit
		_tick_visit(delta)
	_v = saved


func _tick_visit(delta: float) -> void:
	if _v.redo_requested and not _ui_paused() and _v.heat != null:
		_v.redo_timer -= delta
		if _v.redo_timer <= 0.0:
			_v.redo_requested = false
			_v.redo_used = true
			_v.service_penalty += _v.heat.redo_ignored
			_garage.say(_v.guest_id, "Ладно, не надо... Но осадочек остался.")
			_apply_station()
	if _v.heat == null or not _v.heat_active or _ui_paused() or _v.servicing:
		return
	if _autopilot:
		# Режим NPC: темп то «суета», то «спокойствие».
		_v.pace_timer -= delta
		if _v.pace_timer <= 0.0:
			_v.heat.pace = _v.heat.roll_npc_pace(_rng)
			_v.pace_timer = _v.heat.roll_pace_interval(_rng)
	var changed := _v.heat.tick(delta)
	if changed != "":
		_on_heat_state_changed(changed)
	_v.complaint_timer -= delta
	if _v.heat.needs_service() and _v.complaint_timer <= 0.0:
		_complain()


func _on_heat_state_changed(new_state: String) -> void:
	_sync_heat_visual()
	_apply_station()
	_refresh_guide()
	# Жар на пределе (от 95): гость перестаёт курить, пока не сменят угли.
	if new_state == HeatModel.STATE_BURNED and _v.guest_id != "":
		_garage.set_friend_smoking(_v.guest_id, false)
	if new_state != HeatModel.STATE_NORMAL:
		_stats.bump("heat_" + new_state)
		_complain()


## Гость жалуется на жар; автопилот замечает жалобу не всегда (иногда «забывает»).
func _complain() -> void:
	if _v.heat == null:
		return
	_stats.bump("complaints")
	_v.complaint_timer = _v.heat.complaint_cooldown
	var line := _v.heat.random_line(_v.heat.state, _rng)
	if line != "":
		_garage.say(_v.guest_id, line)
	if _autopilot and _rng.randf() < _v.heat.npc_notice_chance:
		_v.npc_service_pending = true


func _sync_heat_visual() -> void:
	if _v.heat == null or not _v.heat_active:
		_garage.set_hookah_heat(1, "", false, _v.station_id)
		return
	var coal := 1
	var badge := ""
	match _v.heat.state:
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
	_garage.set_hookah_heat(coal, badge, _autopilot, _v.station_id)


## Замена углей: кальянщик подходит к кальяну гостя, меняет угли; жар возвращается к норме.
func _replace_coals() -> void:
	var v := _v
	if _v.servicing or _v.heat == null or not _v.heat_active:
		return
	_v.servicing = true
	_carrying = true
	_stats.bump("coal_service")
	_state.set_flag("coals_replaced_once", true)
	_mark_beat("coals_replaced")
	_refresh_guide()
	if _autopilot:
		_stats.bump("coal_service_npc")
	_update_input_lock()
	_apply_station()
	# Пока кальянщик меняет угли, гость не курит (в любом состоянии жара); после замены курение возобновится.
	if _v.guest_id != "":
		_garage.set_friend_smoking(_v.guest_id, false)
	await _garage.service_coals(_v.heat.service_seconds, v.station_id)
	_v = v
	_v.servicing = false
	_carrying = false
	if _economy != null:
		var coal_paid := _economy.charge_coals()
		if coal_paid > 0:
			_stats.bump("spent", coal_paid)
			_stats.bump("spent_coals", coal_paid)
			_notify("Новые угли: −%d 💰" % coal_paid)
	if _v.heat_active:
		_v.heat.service()
		if _v.guest_id != "" and _v.station.guest_smokes():
			_garage.set_friend_smoking(_v.guest_id, true, "")
		_v.npc_service_pending = false
		_v.complaint_timer = _v.heat.complaint_cooldown
		_sync_heat_visual()
		var line := _v.heat.random_line("thanks", _rng)
		if line != "":
			_garage.say(_v.guest_id, line)
	_apply_station()
	_update_input_lock()


## Гость попросил перезабить: кальянщик забирает кальян на стол для кальянов, и приготовление идёт заново.
func _request_redo(guest_id: String) -> void:
	if _v.heat == null:
		return
	_stats.bump("redo_requested")
	_v.redo_requested = true
	_v.redo_timer = _v.heat.redo_timeout
	_garage.say(guest_id, _v.heat.random_line("redo", _rng))
	_notify("%s просит перезабить кальян." % str(GuestCatalog.load_guest(guest_id).get("name", "Гость")))
	_apply_station()


func _do_redo() -> void:
	var v := _v
	if not _v.redo_requested or _v.servicing or _v.redoing or _v.heat == null:
		return
	if _hookah_on_prep_table:
		_notify("Стол для кальянов занят: сначала подай готовый кальян.")
		return
	_stats.bump("redo")
	_v.redoing = true
	_v.redo_requested = false
	_v.redo_used = true
	_v.service_penalty += _v.heat.redo_cost
	_v.session_token += 1
	_carrying = true
	_update_input_lock()
	_stop_heat()
	var guest_id := _v.guest_id
	_garage.set_friend_smoking(guest_id, false)
	_garage.say("player", "Сейчас перезабью.")
	await _garage.carry_hookah_to_prep_table(v.station_id)
	_v = v
	_hookah_on_prep_table = true
	_prep_owner = v
	_v.station.reset()
	_v.last_verdict = {}
	_v.smoke_permission = false
	_v.ask_blocked = false
	_carrying = false
	_v.redoing = false
	_apply_station()
	_update_input_lock()
	_refresh_objective()


## Курение гостя после реакции: считает затяжки, ведёт запрос redo и в конце применяет штраф за жар.
## Возвращает итог (с учётом штрафов); если пришла перезабивка (token сменился) — исходный итог.
func _run_smoking_phase(guest_id: String, verdict: Dictionary, token: int) -> Dictionary:
	var v := _v
	var likes := bool(verdict["likes"])
	_v.session_puffs = 0
	var goal := randi_range(6, 12) if likes else 0
	var redo_at := -1
	if _v.heat != null and not _v.redo_used and _rng.randf() < _v.heat.redo_chance:
		# Просить перезабить можно только в течение 4–7 затяжек после оценки; курим как минимум до запроса.
		redo_at = 0 if goal == 0 else randi_range(_v.heat.redo_min_puff, _v.heat.redo_max_puff)
		goal = maxi(goal, redo_at + 1)
	while token == v.session_token:
		_v = v
		if redo_at >= 0 and not _v.redo_requested and not _v.redo_used and _v.session_puffs >= redo_at:
			_request_redo(guest_id)
		if _v.session_puffs >= goal and not _v.redo_requested and not _v.servicing and not _v.redoing:
			break
		await get_tree().process_frame
	_v = v
	if token != _v.session_token:
		return verdict
	var heat_penalty := _v.heat.heat_penalty() if _v.heat != null else 0.0
	_stop_heat()
	if (heat_penalty > 0.04 or _v.service_penalty > 0.0) and _scoring != null:
		var revised := _scoring.rescore(verdict, heat_penalty, _v.service_penalty)
		if bool(revised.get("manual", false)):
			_scoring.apply_manual_bonus(revised)
		_recipes.revise_last(str(revised.get("recipe_id", "")), float(revised["final_score"]), int(revised["payment"]))
		_v.last_verdict = revised
		_notify("Штраф: жар −%.1f, перезабивка −%.1f. Итог %.1f, оплата %d." % [heat_penalty, _v.service_penalty, float(revised["final_score"]), int(revised["payment"])])
		GameLog.info("session", "Штрафы: жар %.1f, сервис %.1f → %.1f" % [heat_penalty, _v.service_penalty, float(revised["final_score"])])
		return revised
	return verdict


## Ждёт, пока игрок закончит диалог/закроет окна (чтобы прощание не легло поверх них).
func _wait_until_free() -> void:
	while _runner.is_active or _mixer.visible or _book.visible or _preparation_screen.visible or _furniture_open() \
			or (_manual_screen != null and _manual_screen.visible) or (_summary != null and _summary.visible):
		await get_tree().process_frame


## Стол для кальянов и стол гостя: подсказки и действия зависят от состояния кальяна.
func _apply_station() -> void:
	var prep_target := _prep_target_visit()
	if prep_target != null and not _garage.station_guest_id(prep_target.station_id).is_empty():
		var prompt := prep_target.station.prompt()
		var seated_count := 0
		for visit in _visits():
			if not _garage.station_guest_id(visit.station_id).is_empty():
				seated_count += 1
		if seated_count > 1:
			var guest := GuestCatalog.load_guest(_garage.station_guest_id(prep_target.station_id))
			prompt += " (%s)" % str(guest.get("name", ""))
		_garage.configure_interaction("table_hookah", prompt, "open_preparation")
	else:
		_garage.configure_interaction("table_hookah", "", "", "", "", false)
	for visit in _visits():
		_apply_table(visit)


## Стол гостя этого визита: подсказка и действие зависят от кальяна, жара и просьб гостя.
func _apply_table(v: GuestVisit) -> void:
	var table_id := _garage.station_table_id(v.station_id)
	if table_id == "":
		return
	if v.departing:
		_garage.configure_interaction(table_id, "", "", "", "", false)
	elif v.redo_requested:
		_garage.configure_interaction(table_id, "Перезабить кальян", "redo_hookah")
	elif v.heat_active and v.heat != null and v.heat.needs_service():
		_garage.configure_interaction(table_id, "Заменить угли", "replace_coals")
	elif v.station.can_smoke() and (v.smoke_permission or v.station.guest_id == ""):
		_garage.configure_interaction(table_id, "Покурить", "smoke_hookah", v.station.player_emoji(), v.station.message())
	elif v.station.can_smoke() and not v.ask_blocked:
		_garage.configure_interaction(table_id, "Попросить покурить", "ask_to_smoke")
	else:
		_garage.configure_interaction(table_id, "", "", "", "", false)


## Известен ли заказ гостя, который сейчас у стола (диалог ставит флаг "<имя>_order_known").
func _order_known() -> bool:
	return _order_known_for(_v)


func _order_known_for(v: GuestVisit) -> bool:
	var guest_id := _garage.station_ready_guest(v.station_id)
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
	var av := _attention_visit()
	var friend_id := _garage.station_ready_guest(av.station_id)
	var goal := ObjectiveTracker.current({
		"busy": _carrying,
		"friend_ready": friend_id != "",
		"friend_id": friend_id,
		"friend_name": str(GuestCatalog.load_guest(friend_id).get("name", "")) if friend_id != "" else "",
		"has_friend": _garage.has_friend(),
		"day_over": _beats != null and _beats.find_for_progress(_state.story_progress).is_empty(),
		"order_known": _order_known_for(av),
		"recipe_count": _state.recipes.size(),
		"station_state": av.station.state,
		"smoked_once": _state.has_flag("hookah_smoked_once"),
	})
	_objective_label.text = str(goal["text"])
	_objective_label.visible = not _objective_label.text.is_empty()
	var target := str(goal["target"])
	if av.station_id != GuestStation.MAIN_ID and target == "table_guest":
		target = _garage.station_table_id(av.station_id)
	_garage.set_marker(target)


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
		_notify("🔒 Автопилот откроется, когда ты обслужишь друга в режиме «Быстрая готовка» ⚡.")
		return
	_autopilot = on
	if _autopilot_button != null:
		_autopilot_button.set_pressed_no_signal(on)
		_autopilot_button.modulate = Color(0.55, 1.0, 0.6) if on else Color.WHITE
	# Режим NPC: камера по умолчанию следует за кальянщиком (кнопка 🎥 отключает следование и ставит камеру по центру); вручную — как раньше.
	_camera_follow = true
	var saved_visit := _v
	for visit in _visits():
		if visit.heat != null and visit.heat_active:
			visit.heat.pace = visit.heat.roll_npc_pace(_rng) if on else visit.heat.pace_manual
		_v = visit
		_sync_heat_visual()
	_v = saved_visit
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


## Тест-прогон выключает следование камеры за кальянщиком (видна вся комната), выключение прогона включает его обратно.
func _set_test_camera(follow: bool) -> void:
	if _camera_button != null:
		_camera_button.set_pressed_no_signal(follow)
	_on_camera_button_toggled(follow)


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
	if _carrying or _runner.is_active or _mixer.visible or _book.visible or _furniture_open() \
			or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible) or _summary.visible:
		return
	if _garage.is_action_busy():
		return
	# Рост заведения (столы, стулья, полка) не ждёт простоя: при потоке гостей простоя у кальянщика почти не бывает.
	if _state.get_flag(ProgressionGoal.DONE_FLAG, false) == true and _autopilot_furnish():
		return
	var visit := _autopilot_pick_visit()
	if visit == null:
		# Делать нечего (гости курят или ждём нового): изображаем работу у объектов гаража.
		await _autopilot_idle()
		return
	_v = visit
	var started := _game_seconds
	if visit.redo_requested:
		await _do_redo()
		_record_phase("redo", _game_seconds - started)
		return
	if visit.heat_active and visit.npc_service_pending and visit.heat != null and visit.heat.needs_service():
		await _replace_coals()
		_record_phase("coals", _game_seconds - started)
		return
	var guest_id := _ready_guest()
	if not _order_known():
		await _autopilot_talk(guest_id)
		_record_phase("talk", _game_seconds - started)
	elif visit.station.state == HookahStation.STATE_EMPTY and not visit.order.is_empty():
		if _wants_guest_id != guest_id:
			_show_wants_badge(guest_id)
		visit.cooking_by = "master"
		await _autopilot_serve()
		if visit.cooking_by == "master":
			visit.cooking_by = ""
		_record_phase("serve", _game_seconds - started)


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
const LERA_PROGRESS := "friend_03_lera"
const LERA_END_PROGRESS := "friend_04_done"
const LERA_ID := "friend_lera"
const SECOND_SEAT_FLAG := "second_seat_done"
const TRENDS_FLAG := "trends_unlocked"


# --- M12: одновременные гости ---

## Гость без места уже приходил и ушёл рассерженным (сюжетная подсказка «купи стол и стул» показана один раз).
const SECOND_GUEST_DEMO_FLAG := "second_guest_demo_done"
## Гости, которые могут прийти вторыми (по очереди с уже сидящим они не повторяются).
const EXTRA_GUEST_IDS: Array[String] = ["friend_denis", "friend_max", "friend_ivan", "friend_lera"]
## guest_id -> true, если ожидающий уже ворчал (чтобы не повторять).
var _waiting_warned: Dictionary = {}


func _visits() -> Array[GuestVisit]:
	var result: Array[GuestVisit] = [_visit_main, _visit_extra, _visit_extra2, _visit_extra3]
	for more: GuestVisit in _more_visits.values():
		result.append(more)
	return result


func _any_servicing() -> bool:
	for visit in _visits():
		if visit.servicing:
			return true
	return false


func _visit_of_station(station_id: String) -> GuestVisit:
	if station_id == GuestStation.EXTRA_ID:
		return _visit_extra
	if station_id == GuestStation.EXTRA2_ID:
		return _visit_extra2
	if station_id == GuestStation.MAIN2_ID:
		return _visit_extra3
	if _more_visits.has(station_id):
		return _more_visits[station_id]
	return _visit_main


## Визит гостя, который сидит (или идёт) за одним из столов; null — такого гостя нет.
func _visit_of_guest(guest_id: String) -> GuestVisit:
	for visit in _visits():
		if _garage.station_guest_id(visit.station_id) == guest_id:
			return visit
	return null


## Гость текущего визита, который уже дошёл до своего места ("" — никого).
func _ready_guest() -> String:
	return _garage.station_ready_guest(_v.station_id)


## Кому сейчас можно готовить: сначала гость, чей заказ известен, затем любой сидящий с пустым кальяном.
func _prep_target_visit() -> GuestVisit:
	if _hookah_on_prep_table and _prep_owner != null and not _prep_owner.departing:
		return _prep_owner
	for visit in _visits():
		if visit.station.can_prepare() and not visit.departing and visit.cooking_by != "ben" and _order_known_for(visit):
			return visit
	for visit in _visits():
		if visit.station.can_prepare() and not visit.departing and visit.cooking_by != "ben" and not _garage.station_guest_id(visit.station_id).is_empty():
			return visit
	return null


## На кого смотрит подсказка цели: гость без заказа или с пустым кальяном, иначе любой сидящий.
func _attention_visit() -> GuestVisit:
	for visit in _visits():
		if _garage.station_ready_guest(visit.station_id) != "" and (not _order_known_for(visit) or visit.station.state == HookahStation.STATE_EMPTY):
			return visit
	for visit in _visits():
		if _garage.station_ready_guest(visit.station_id) != "":
			return visit
	return _visit_main


func _any_heat_warn() -> bool:
	for visit in _visits():
		if visit.heat != null and visit.heat_active and (visit.heat.needs_service() or visit.npc_service_pending):
			return true
	return false


func _setup_m12() -> void:
	_scheduler = VisitScheduler.load_default()
	for message in _scheduler.errors:
		GameLog.error("visits", message)
	_garage.waiting_guest_arrived.connect(_on_waiting_guest_arrived)


## Идёт время: ждущие места теряют терпение; после цели, пока идёт визит, приходит второй гость.
## Шаг 1 M12: пока рабочего второго стола нет, второй гость приходит один раз, видит, что сесть негде, и уходит рассерженным.
func _tick_extra_guests(delta: float) -> void:
	if _scheduler == null or _state == null or _garage == null or _ui_paused() or _notice_overlay != null:
		return
	_station_refresh_timer -= delta
	if _station_refresh_timer <= 0.0:
		_station_refresh_timer = 1.5
		_garage.refresh_extra_station()
	for guest_id in _scheduler.tick_waiting(delta):
		_guest_leaves_angry(guest_id)
	for guest_id in _scheduler.waiting_ids():
		if not _waiting_warned.has(guest_id) and _scheduler.seconds_left(guest_id) < _scheduler.wait_seconds * 0.5:
			_waiting_warned[guest_id] = true
			_garage.say(guest_id, "Долго мне ещё стоять?", "😤")
	_scheduler.apply_progress(_sessions_done())
	_stats.set_max("peak_guests", _garage.guests_present())
	_tick_pairs(delta)
	var goal_done: bool = _state.get_flag(ProgressionGoal.DONE_FLAG, false) == true
	var ending_seen: bool = _state.get_flag(ProgressionGoal.ENDING_SEEN_FLAG, false) == true
	var demo_pending: bool = _state.get_flag(SECOND_GUEST_DEMO_FLAG, false) != true
	var free_station := _free_extra_station()
	_tick_company(delta)
	# Диван: ждущая компания садится на два места одного стола, одиночка — за свободное место (рядом с соседом — при схожих вкусах).
	var seated_pair := false
	for guest_id in _scheduler.waiting_ids():
		var partner := str(_company_partner.get(guest_id, ""))
		if partner != "":
			if _garage.is_companion(guest_id) or _waiting_is_follower(guest_id):
				continue
			var pair := _free_pair()
			if pair.size() == 2 and _garage.has_guest(guest_id) and _garage.has_guest(partner):
				_visit_of_station(pair[0]).clear_after_departure()
				_stats.bump("seat_sofa_company")
				_stats.log_event(_game_seconds, "С ДИВАНА садится компания %s + %s → %s/%s" % [_gname(guest_id), _gname(partner), pair[0], pair[1]])
				_garage.seat_waiting_guest(guest_id, pair[0])
				_garage.seat_waiting_guest(partner, pair[1], pair[0])
				for id in [guest_id, partner]:
					_scheduler.seat_found(id)
					_waiting_warned.erase(id)
				_company_partner.erase(guest_id)
				_company_partner.erase(partner)
				_company_turn.erase("follower:%s" % partner)
				free_station = _free_extra_station()
				seated_pair = true
				break
			continue
		var seat_for := _free_extra_station(guest_id)
		if seat_for != "" and _garage.has_guest(guest_id):
			_visit_of_station(seat_for).clear_after_departure()
			_stats.bump("seat_sofa_single")
			_stats.log_event(_game_seconds, "С ДИВАНА садится одиночка %s → %s%s" % [_gname(guest_id), seat_for, (", сосед " + _gname(_neighbor_guest(seat_for))) if _neighbor_guest(seat_for) != "" else ""])
			_garage.seat_waiting_guest(guest_id, seat_for)
			_scheduler.seat_found(guest_id)
			_waiting_warned.erase(guest_id)
			free_station = _free_extra_station()
			break
	# Пока поток не вырос, второй гость приходит только к сидящему главному; потом гости приходят сами.
	var main_ready: bool = (_garage.station_ready_guest(GuestStation.MAIN_ID) != "" and not _visit_main.departing) or _scheduler.level > 0
	var possible := false
	if free_station != "":
		possible = goal_done and ending_seen and main_ready \
				and _scheduler.can_admit(goal_done, _garage.guests_present())
	else:
		var may_wait: bool = (demo_pending and not _second_seat_ready()) \
				or (not demo_pending and _scheduler.waiting_ids().size() < 2 and _has_extra_station())
		possible = goal_done and may_wait and main_ready and ending_seen \
				and _scheduler.can_admit(goal_done, _garage.guests_present())
	var reason := "ok"
	if not goal_done:
		reason = "нет_цели"
	elif not ending_seen:
		reason = "нет_финала"
	elif not main_ready:
		reason = "главный_гость_не_сидит"
	elif not _scheduler.can_admit(goal_done, _garage.guests_present()):
		reason = "лимит_гостей"
	elif free_station == "" and not (demo_pending and not _second_seat_ready()) and not (not demo_pending and _scheduler.waiting_ids().size() < 2 and _has_extra_station()):
		reason = "нет_места_и_ждут"
	elif free_station == "":
		reason = "нет_свободного_места"
	if not possible:
		_stats.add_arrival_blocked(reason, delta)
	if _scheduler.tick_arrival(delta, possible, _rng):
		var pair_now := _free_pair()
		var roll := _rng.randf()
		if pair_now.size() == 2:
			_stats.bump("company_roll_pair_free")
		else:
			_stats.bump("company_no_pair")
		var company := pair_now.size() == 2 and roll < COMPANY_CHANCE
		if pair_now.size() == 2:
			_stats.bump("company_roll_yes" if company else "company_roll_no")
		_stats.log_event(_game_seconds, "ПРИХОД: свободно %s, пара %s, бросок %.2f (<%.2f = компания) → %s" % [
			str(_free_stations()), str(pair_now), roll, COMPANY_CHANCE, "компания" if company else ("одиночка" if free_station != "" else "ждать")])
		if company:
			_spawn_company(pair_now)
		elif free_station != "":
			_spawn_seated_guest(free_station)
		elif _has_pair_table() and not seated_pair and _rng.randf() < COMPANY_CHANCE:
			_spawn_waiting_company()
		else:
			_spawn_extra_guest()


## Спутник из ждущей пары (у лидера и спутника общий ключ; лидер — тот, кто пришёл первым).
func _waiting_is_follower(guest_id: String) -> bool:
	return _company_turn.has("follower:%s" % guest_id)


## Два свободных места одного стола (оба из купленной мебели) — туда может сесть компания.
func _free_pair() -> Array[String]:
	var free := _free_stations()
	for i in free.size():
		for j in range(i + 1, free.size()):
			var uid := _garage.station_table_uid(free[i])
			if uid != "" and uid != "table_guest" and uid == _garage.station_table_uid(free[j]):
				return [free[i], free[j]]
	return []


## За одним столом из купленной мебели есть два места (можно ждать компанию).
func _has_pair_table() -> bool:
	var seen: Dictionary = {}
	for station_id in GuestStation.EXTRA_IDS:
		if not _garage.has_station(station_id):
			continue
		var uid := _garage.station_table_uid(station_id)
		if seen.has(uid):
			return true
		seen[uid] = true
	return false


func _two_guest_options() -> Array[String]:
	var options := _extra_guest_options()
	options.shuffle()
	return options


## Компания приходит сразу на два места одного стола: один заказ (первого) и один кальян по очереди.
func _spawn_company(pair: Array[String]) -> void:
	var options := _two_guest_options()
	if options.size() < 2:
		return
	var leader := GuestCatalog.load_guest(options[0])
	var buddy := GuestCatalog.load_guest(options[1])
	var leader_cell := _garage.station_guest_cell(pair[0])
	var buddy_cell := _garage.station_guest_cell(pair[1])
	if leader.is_empty() or buddy.is_empty() or leader_cell.x < 0 or buddy_cell.x < 0:
		return
	_visit_of_station(pair[0]).clear_after_departure()
	_visit_of_station(pair[1]).clear_after_departure()
	_stats.bump("companies")
	_stats.bump("seat_company")
	_stats.log_event(_game_seconds, "САДИТСЯ компания %s + %s → %s/%s" % [_gname(options[0]), _gname(options[1]), pair[0], pair[1]])
	_garage.reserve_station(pair[1])
	if not _garage.spawn_friend(leader, BEN_ENTRY_POSITION, BEN_ENTRY_CELL, leader_cell, "", _garage.station_seat(pair[0]), pair[0]):
		_garage.release_station(pair[1])
		return
	await get_tree().create_timer(1.4).timeout
	if not is_inside_tree():
		return
	if not _garage.spawn_friend(buddy, BEN_ENTRY_POSITION, BEN_ENTRY_CELL, buddy_cell, "", _garage.station_seat(pair[1]), pair[1], pair[0]):
		_garage.release_station(pair[1])
		return
	_notify("👫 Пришла компания: %s и %s" % [str(leader.get("name", "Гость")), str(buddy.get("name", "Гость"))])


## Компания пришла, а двух свободных мест за одним столом нет: ждёт на диване именно пару стульев.
func _spawn_waiting_company() -> void:
	var options := _two_guest_options()
	if options.size() < 2:
		return
	var leader := GuestCatalog.load_guest(options[0])
	var buddy := GuestCatalog.load_guest(options[1])
	if leader.is_empty() or buddy.is_empty():
		return
	_stats.bump("wait_company")
	_stats.log_event(_game_seconds, "ЖДЁТ на диване компания %s + %s (нет двух мест за одним столом)" % [_gname(options[0]), _gname(options[1])])
	_company_partner[options[0]] = options[1]
	_company_partner[options[1]] = options[0]
	_company_turn["follower:%s" % options[1]] = true
	_garage.spawn_waiting_guest(leader, BEN_ENTRY_POSITION, BEN_ENTRY_CELL)
	await get_tree().create_timer(1.4).timeout
	if not is_inside_tree():
		return
	_garage.spawn_waiting_guest(buddy, BEN_ENTRY_POSITION, BEN_ENTRY_CELL)


## Компания курит один кальян по очереди: каждые COMPANY_TURN_SECONDS затяжки переходят к другому.
func _tick_company(delta: float) -> void:
	for visit in _visits():
		var buddy := _garage.companion_ready(visit.station_id)
		var guest_id := _garage.station_ready_guest(visit.station_id)
		if buddy == "" or guest_id == "":
			continue
		if not visit.heat_active or _carrying or not visit.station.guest_smokes():
			_garage.set_friend_smoking(buddy, false, "")
			_company_turn.erase(visit.station_id)
			continue
		var turn: Dictionary = _company_turn.get(visit.station_id, {"t": COMPANY_TURN_SECONDS, "buddy": false})
		turn["t"] = float(turn["t"]) - delta
		if float(turn["t"]) <= 0.0:
			turn["t"] = COMPANY_TURN_SECONDS
			turn["buddy"] = not bool(turn["buddy"])
			_garage.set_friend_smoking(guest_id, not bool(turn["buddy"]), "")
			_garage.set_friend_smoking(buddy, bool(turn["buddy"]), "")
		_company_turn[visit.station_id] = turn


## Двое за одним столом: при схожих вкусах знакомятся (+респект кальянке) и потом болтают, пока курят.
func _tick_pairs(delta: float) -> void:
	var seated: Array[GuestVisit] = []
	for visit in _visits():
		if _garage.station_ready_guest(visit.station_id) != "" and not visit.departing:
			seated.append(visit)
	_pair_chat_timer -= delta
	for i in seated.size():
		for j in range(i + 1, seated.size()):
			var a := seated[i]
			var b := seated[j]
			var uid := _garage.station_table_uid(a.station_id)
			if uid == "" or uid != _garage.station_table_uid(b.station_id):
				continue
			var ga := _garage.station_ready_guest(a.station_id)
			var gb := _garage.station_ready_guest(b.station_id)
			var key := "%s|%s" % [ga, gb]
			if not _paired.has(key):
				if GuestPairing.are_compatible(GuestCatalog.load_guest(ga), GuestCatalog.load_guest(gb)):
					_paired[key] = true
					_on_guests_paired(ga, gb)
				else:
					_paired[key] = false
			elif _paired[key] == true and _pair_chat_timer <= 0.0 and a.heat_active and b.heat_active:
				_pair_chat_timer = 14.0
				var lines := GuestPairing.CHAT_LINES
				_garage.say(ga if _rng.randi() % 2 == 0 else gb, lines[_rng.randi() % lines.size()], "💬")


func _on_guests_paired(guest_a: String, guest_b: String) -> void:
	var name_a := str(GuestCatalog.load_guest(guest_a).get("name", "Гость"))
	var name_b := str(GuestCatalog.load_guest(guest_b).get("name", "Гость"))
	_garage.say(guest_a, "Слушай, а у нас вкусы схожи!", "😄")
	_garage.say(guest_b, "Точно! Давай вместе покурим.", "🤝")
	if _economy != null:
		_economy.add_reputation(GuestPairing.REPUTATION_BONUS)
	_stats.bump("guest_pairs")
	_stats.log_event(_game_seconds, "ЗНАКОМСТВО за столом: %s и %s" % [name_a, name_b])
	_notify("🤝 %s и %s подружились за столом: +%d респекта нашей кальянке" % [name_a, name_b, GuestPairing.REPUTATION_BONUS])


## Сосед по столу: гость другого места того же стола ("" — соседа нет).
func _neighbor_guest(station_id: String) -> String:
	var uid := _garage.station_table_uid(station_id)
	if uid == "":
		return ""
	for visit in _visits():
		if visit.station_id != station_id and _garage.station_table_uid(visit.station_id) == uid:
			var seated := _garage.station_ready_guest(visit.station_id)
			if seated != "" and not visit.departing:
				return seated
	return ""


## Подходит ли гость к месту: если за столом уже кто-то сидит, вкусы должны совпадать.
func _fits_station(station_id: String, guest_id: String) -> bool:
	var neighbor := _neighbor_guest(station_id)
	if neighbor == "":
		return true
	return GuestPairing.are_compatible(GuestCatalog.load_guest(neighbor), GuestCatalog.load_guest(guest_id))


## Ждущий на диване одиночка соглашается сесть к незнакомцу: сходство высокое или терпение уже на исходе.
func _waiting_accepts_neighbor(guest_id: String, neighbor_id: String) -> bool:
	var similarity := GuestPairing.similarity(GuestCatalog.load_guest(neighbor_id), GuestCatalog.load_guest(guest_id))
	if similarity >= NEIGHBOR_LIKE:
		return true
	return _scheduler.is_waiting(guest_id) and _scheduler.seconds_left(guest_id) < _scheduler.wait_seconds * 0.5


## Все места, куда сейчас можно посадить гостя (стол и стул есть, никто не сидит, кальянщик не занят).
func _free_stations() -> Array[String]:
	var result: Array[String] = []
	for station_id in GuestStation.EXTRA_IDS:
		if _garage.has_station(station_id) and _garage.station_guest_id(station_id).is_empty() and not _garage.station_busy(station_id):
			result.append(station_id)
	var main2 := GuestStation.MAIN2_ID
	if _garage.has_station(main2) and _garage.station_guest_id(main2).is_empty() and not _garage.station_busy(main2) \
			and _garage.seat_cell_free() and not _visit_main.departing:
		result.append(main2)
	return result


## Свободное место для гостя guest_id (или для любого нового гостя, если id пуст). Сначала места без соседа.
func _free_extra_station(guest_id: String = "") -> String:
	var fallback := ""
	for station_id in _free_stations():
		if _reserved_for_company(station_id, guest_id):
			continue
		var neighbor := _neighbor_guest(station_id)
		if guest_id == "":
			if neighbor == "":
				return station_id
			var any_fit := false
			for option in _extra_guest_options():
				if _fits_station(station_id, option):
					any_fit = true
					break
			if any_fit and fallback == "":
				fallback = station_id
		else:
			if neighbor == "":
				return station_id
			var desperate := _scheduler.is_waiting(guest_id) and _scheduler.seconds_left(guest_id) < _scheduler.wait_seconds * 0.3
			if fallback == "" and ((_fits_station(station_id, guest_id) and _waiting_accepts_neighbor(guest_id, neighbor)) or desperate):
				fallback = station_id
	return fallback


## Столы из купленной мебели, у которых есть оба места: table_uid -> [station_id, ...].
func _pair_tables() -> Dictionary:
	var tables: Dictionary = {}
	for station_id in GuestStation.EXTRA_IDS:
		if not _garage.has_station(station_id):
			continue
		var uid := _garage.station_table_uid(station_id)
		if uid == "" or uid == "table_guest":
			continue
		if not tables.has(uid):
			tables[uid] = []
		(tables[uid] as Array).append(station_id)
	for uid in tables.keys():
		if (tables[uid] as Array).size() < 2:
			tables.erase(uid)
	return tables


## Последний полностью свободный стол на двоих держим для компании: одиночка за него не садится (если не ждёт слишком долго).
func _reserved_for_company(station_id: String, guest_id: String) -> bool:
	var tables := _pair_tables()
	if tables.size() < 2:
		return false
	var uid := _garage.station_table_uid(station_id)
	if not tables.has(uid):
		return false
	var free_tables := 0
	var this_table_free := false
	for table_uid in tables:
		var all_free := true
		for seat in tables[table_uid]:
			if not _garage.station_guest_id(str(seat)).is_empty() or _garage.station_busy(str(seat)):
				all_free = false
		if all_free:
			free_tables += 1
			if table_uid == uid:
				this_table_free = true
	if not this_table_free or free_tables > 1:
		return false
	if guest_id != "" and _scheduler.is_waiting(guest_id) and _scheduler.seconds_left(guest_id) < _scheduler.wait_seconds * 0.4:
		return false
	return true


func _has_extra_station() -> bool:
	for station_id in GuestStation.EXTRA_IDS:
		if _garage.has_station(station_id):
			return true
	return _garage.has_station(GuestStation.MAIN2_ID)


func _spawn_extra_guest() -> void:
	var options := _extra_guest_options()
	if options.is_empty():
		_stats.bump("no_guest_options")
		_stats.log_event(_game_seconds, "НЕТ ГОСТЕЙ: все именные гости уже в гараже или ждёт сюжет (случайные: %s)" % ("да" if _random_guests_on() else "ещё нет"))
		return
	var guest := GuestCatalog.load_guest(options[_rng.randi() % options.size()])
	if guest.is_empty():
		return
	_garage.spawn_waiting_guest(guest, BEN_ENTRY_POSITION, BEN_ENTRY_CELL)


## Гости, которые могут прийти вторыми: не те, что уже в гараже, и не тот, кого ждёт сюжет.
func _extra_guest_options() -> Array[String]:
	var story_ids: Array[String] = []
	if _beats != null and _state != null:
		var beat: Dictionary = _beats.find_for_progress(_state.story_progress)
		if not beat.is_empty():
			story_ids.append(str(beat["guest"]))
	var options: Array[String] = []
	if _random_guests_on():
		return _generated_options()
	for guest_id in EXTRA_GUEST_IDS:
		if not _garage.has_guest(guest_id) and not story_ids.has(guest_id):
			options.append(guest_id)
	return options


## С 7–10-го визита в кальянную приходят только случайные гости (имя, внешность, вкусы).
func _random_guests_on() -> bool:
	if _stats == null:
		return false
	if _gen_start <= 0:
		_gen_start = _rng.randi_range(7, 10)
	return _sessions_done() >= _gen_start


func _generated_options() -> Array[String]:
	var fresh: Array[String] = []
	for guest_id in _gen_pool:
		if _garage.has_guest(guest_id):
			_gen_used[guest_id] = true
		elif not _gen_used.has(guest_id):
			fresh.append(guest_id)
	while fresh.size() < GEN_POOL_SIZE:
		fresh.append(GuestGenerator.random_id(_rng))
	_gen_pool = fresh
	return fresh.duplicate()


## Второй гость заходит и садится за второй стол: заказ называет сам.
func _spawn_seated_guest(station_id: String) -> void:
	var options := _extra_guest_options()
	var cell := _garage.station_guest_cell(station_id)
	if options.is_empty() or cell.x < 0:
		_stats.bump("no_guest_options")
		_stats.log_event(_game_seconds, "НЕТ ГОСТЕЙ для места %s: все именные гости заняты (случайные: %s)" % [station_id, "да" if _random_guests_on() else "ещё нет"])
		return
	# Сосед по столу уже есть: берём только тех, у кого вкусы совпадают, лучшего по схожести.
	var neighbor_id := _neighbor_guest(station_id)
	var fitting: Array[String] = []
	for option in options:
		if _fits_station(station_id, option):
			fitting.append(option)
	if fitting.is_empty():
		_stats.bump("neighbor_rejected")
		_stats.log_event(_game_seconds, "ОТКАЗ: за столом %s сидит %s, подходящих по вкусам гостей нет" % [station_id, _gname(neighbor_id)])
		return
	var pick := fitting[_rng.randi() % fitting.size()]
	if neighbor_id != "":
		var cands: Array[Dictionary] = []
		for option in fitting:
			cands.append(GuestCatalog.load_guest(option))
		var best := GuestPairing.best_match(GuestCatalog.load_guest(neighbor_id), cands)
		if best >= 0:
			pick = fitting[best]
	var guest := GuestCatalog.load_guest(pick)
	if guest.is_empty():
		return
	if neighbor_id != "":
		var similarity := GuestPairing.similarity(GuestCatalog.load_guest(neighbor_id), guest)
		if similarity < NEIGHBOR_LIKE and _rng.randf() >= NEIGHBOR_ACCEPT:
			_stats.bump("neighbor_rejected")
			_stats.log_event(_game_seconds, "ОТКАЗ: %s не хочет сесть к %s (сходство %.2f), ждёт отдельный стол" % [_gname(pick), _gname(neighbor_id), similarity])
			_spawn_extra_guest()
			return
	_visit_of_station(station_id).clear_after_departure()
	_stats.bump("seat_single")
	if neighbor_id != "":
		_stats.bump("seat_single_neighbor")
	_stats.log_event(_game_seconds, "САДИТСЯ одиночка %s → %s%s" % [_gname(str(guest["id"])), station_id,
		(", сосед %s, сходство %.2f" % [_gname(neighbor_id), GuestPairing.similarity(GuestCatalog.load_guest(neighbor_id), guest)]) if neighbor_id != "" else ", соседа нет"])
	_garage.spawn_friend(guest, BEN_ENTRY_POSITION, BEN_ENTRY_CELL, cell, "", _garage.station_seat(station_id), station_id)


func _on_waiting_guest_arrived(guest_id: String) -> void:
	_scheduler.start_waiting(guest_id)
	if not _company_partner.has(guest_id):
		_stats.bump("wait_single")
		_stats.log_event(_game_seconds, "ЖДЁТ у входа/на диване одиночка %s" % _gname(guest_id))
	var guest := GuestCatalog.load_guest(guest_id)
	var guest_name := str(guest.get("name", "Гость"))
	_notify("🧍 Пришёл %s, но сесть негде — купи в 🛋️ магазине малый стол и стул!" % guest_name)
	_garage.say(guest_id, "А где тут сесть?", "🤨")


## Терпение кончилось: гость ругается, репутация падает, он уходит через дверь.
func _guest_leaves_angry(guest_id: String) -> void:
	_waiting_warned.erase(guest_id)
	var buddy := str(_company_partner.get(guest_id, ""))
	_company_partner.erase(guest_id)
	_company_turn.erase("follower:%s" % guest_id)
	# Ждущая компания уходит вместе, а штраф к репутации — один на компанию.
	var penalty_paid := _company_turn.has("angry_company:%s" % guest_id)
	_company_turn.erase("angry_company:%s" % guest_id)
	if buddy != "" and not penalty_paid:
		_company_turn["angry_company:%s" % buddy] = true
	_state.set_flag(SECOND_GUEST_DEMO_FLAG, true)
	_test_note_angry_departure()
	_garage.say(guest_id, _scheduler.angry_line, "😡")
	var free_notes: PackedStringArray = []
	for free_id in _free_stations():
		var note := free_id
		if _reserved_for_company(free_id, guest_id):
			note += " (резерв под компанию)"
		elif _neighbor_guest(free_id) != "":
			note += " (сосед %s)" % _gname(_neighbor_guest(free_id))
		free_notes.append(note)
	_stats.log_event(_game_seconds, "УШЁЛ ЗЛОЙ: %s%s; свободно: %s; репутация %d" % [_gname(guest_id), (" (компания с %s)" % _gname(buddy)) if buddy != "" else "", ", ".join(free_notes) if not free_notes.is_empty() else "нет", _economy.reputation() if _economy != null else 0])
	if not penalty_paid:
		_stats.bump("angry_leaves")
		_stats.bump("angry_companies" if buddy != "" else "angry_singles")
		if _economy != null:
			_economy.add_reputation(_scheduler.angry_reputation)
		_notify("😡 Гость ушёл рассерженным: репутация %d. Поставь малый стол и стул — тогда сможешь принимать двоих." % _scheduler.angry_reputation)
	await get_tree().create_timer(1.8).timeout
	await _garage.friend_leave(guest_id)
	_scheduler.forget(guest_id)


## Тренды открываются с приходом гостя номер intro.trends_at_guest (10-й).
func _trends_on() -> bool:
	return _state != null and _state.get_flag(TRENDS_FLAG, false) == true


## Куплены и поставлены стол и стул для второго места гостя (флаг остаётся, даже если мебель потом уберут).
func _second_seat_ready() -> bool:
	if _state == null:
		return false
	if _state.get_flag(SECOND_SEAT_FLAG, false) == true:
		return true
	if _furniture != null and _furniture.placed_count("small_table") >= 1 and _furniture.placed_count("chair") >= 1:
		_state.set_flag(SECOND_SEAT_FLAG, true)
		return true
	return false


func _unlock_trends() -> void:
	if _trends_on():
		return
	_state.set_flag(TRENDS_FLAG, true)
	if _scoring != null:
		_scoring.trend_enabled = true
	_notify("📈 Появились тренды: гости теперь следят за модой!")
	_refresh_guide()
const IDLE_MIN_SECONDS := 9.0
const IDLE_MAX_SECONDS := 16.0
var _idle_walking := false
var _idle_acting := false
var _idle_last := ""


## Есть ли у кальянщика реальное дело: новый гость без заказа или заказ, ожидающий кальяна.
func _autopilot_needs_action() -> bool:
	return _autopilot_pick_visit() != null


## Срочное дело у гостя: перезабивка или угли.
func _visit_needs_urgent(v: GuestVisit) -> bool:
	if v.departing:
		return false
	return v.redo_requested or (v.heat_active and v.npc_service_pending and v.heat != null and v.heat.needs_service())


func _visit_needs_action(v: GuestVisit) -> bool:
	if v.departing:
		return false
	if v.cooking_by == "ben":
		return false
	if _visit_needs_urgent(v):
		return true
	if _garage.station_ready_guest(v.station_id) == "":
		return false
	if not _order_known_for(v):
		return true
	if _prep_owner != null and _prep_owner != v and _hookah_on_prep_table:
		return false
	return v.station.state == HookahStation.STATE_EMPTY and not v.order.is_empty()


## Кому автопилот помогает первым: сначала срочное (перезабивка, угли), потом заказ и подача.
func _autopilot_pick_visit() -> GuestVisit:
	# Справедливо: берём того, кто ждёт дольше всех (иначе первые в списке мест вечно обгоняют последние).
	var now := _game_seconds
	var waiting_since: Dictionary = _need_since
	var urgent: GuestVisit = null
	var needy: GuestVisit = null
	var unordered: GuestVisit = null
	for visit in _visits():
		var urgent_now := _visit_needs_urgent(visit)
		var needs := urgent_now or _visit_needs_action(visit)
		if not needs:
			waiting_since.erase(visit.station_id)
			continue
		if not waiting_since.has(visit.station_id):
			waiting_since[visit.station_id] = now
		if urgent_now and (urgent == null or float(waiting_since[visit.station_id]) < float(waiting_since[urgent.station_id])):
			urgent = visit
		# Заказ принимается быстро (около 8 с), а готовится кальян долго (около 60 с): сначала выслушиваем всех сидящих.
		if not urgent_now and not _order_known_for(visit) and (unordered == null or float(waiting_since[visit.station_id]) < float(waiting_since[unordered.station_id])):
			unordered = visit
		if needy == null or float(waiting_since[visit.station_id]) < float(waiting_since[needy.station_id]):
			needy = visit
	if urgent != null:
		return urgent
	if unordered != null:
		needy = unordered
	if needy != null:
		_stats.set_max("max_wait_service", int(now - float(waiting_since[needy.station_id])))
	return needy


func _autopilot_busy() -> bool:
	return _carrying or _runner.is_active or _mixer.visible or _book.visible \
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
		if id != _idle_last and _garage.has_object(id) and _garage.is_object_visible(id):
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
	var v := _v
	var dialogue_id := _garage.friend_dialogue_id(guest_id)
	if dialogue_id == "" and v.station_id == GuestStation.MAIN_ID:
		return
	_carrying = true
	_update_input_lock()
	# Мало мундштуков — сначала к коробке, докладываем, и только потом к гостю за заказом.
	if _garage.mouthpieces_low(2):
		await _garage.walk_to_mouthpiece_box()
		_v = v
		if not _autopilot:
			_carrying = false
			return
		_garage.say("player", "Докладываю мундштуки в коробку.")
		await get_tree().create_timer(1.4).timeout
		_v = v
		if _top_up_mouthpieces():
			_stats.bump("mouthpiece_refill")
	await _garage.walk_to_friend(guest_id)
	_v = v
	_carrying = false
	if dialogue_id == "":
		await _take_order(v.station_id)
	else:
		_on_dialogue_requested(dialogue_id)
	while _runner.is_active and _autopilot:
		await get_tree().process_frame
	_v = v
	if _autopilot and _order_known() and not _v.order.is_empty():
		_show_wants_badge(guest_id)


## Кальянщик сам выбирает рецепт под заказ. Подходящий рецепт есть в книге — сразу идёт за кальяном и забивает.
## Нет — сначала идёт к столу смешивания и подбирает вкус (над головой мелькают ингредиенты, не всегда удачно),
## и только потом берёт кальян, готовит с мелкими ошибками и подаёт гостю.
func _autopilot_serve() -> void:
	var v := _v
	_rng.randomize()
	var taste := {"preferences": _v.order["preferences"], "dislikes": _v.order.get("dislikes", {})}
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
		_v = v
	else:
		recipe_id = await _autopilot_mix_new_recipe()
		_v = v
		if recipe_id == "":
			return
	if not _autopilot:
		_garage.clear_chips("player")
		return
	_refresh_objective()
	await _ensure_hookah_on_prep_table()
	_v = v
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
	_v = v
	_prep_visit = v
	_garage.clear_chips("player")
	_on_prepared(result)
	await _on_preparation_closed()


## Идёт к столу смешивания, подбирает новый микс под заказ и сохраняет его в книгу. Возвращает id рецепта ("" — не вышло).
func _autopilot_mix_new_recipe() -> String:
	var v := _v
	var mix := {}
	for attempt in 6:
		var noise := AutoCook.DEFAULT_NOISE if attempt < 3 else 0.0
		var candidate := AutoCook.pick_mix(_recipes.catalog, _v.order["preferences"], _rng, noise)
		if _economy != null and not _mix_affordable(candidate):
			candidate = AutoCook.pick_mix(_recipes.catalog, _v.order["preferences"], _rng, noise, _economy.free_ingredients)
		if not candidate["selection"].is_empty() and _recipes.evaluate(candidate["selection"], candidate["modifiers"])["ok"]:
			mix = candidate
			break
	if mix.is_empty():
		GameLog.error("autopilot", "Не удалось составить микс под заказ %s" % str(_v.order.get("id", "")))
		return ""
	_carrying = true
	_update_input_lock()
	_refresh_objective()
	await _garage.walk_to_object("table_test")
	_v = v
	_garage.say("player", "Такого вкуса в книге нет — смешаю новый.")
	var items: Array = mix["selection"].keys()
	for modifier in mix["modifiers"]:
		items.append(modifier)
	await _autopilot_pick_animation(items)
	_v = v
	var committed := {}
	if _autopilot:
		committed = _recipes.commit(mix["selection"], mix["modifiers"])
	_carrying = false
	_update_input_lock()
	if not committed.get("ok", false):
		_garage.clear_chips("player")
		return ""
	GameLog.info("autopilot", "Заказ %s -> новый рецепт %s" % [str(_v.order.get("id", "")), str(committed["recipe_id"])])
	return str(committed["recipe_id"])


## Над кальянщиком по очереди мелькают эмодзи ингредиентов, пока он не остановится на выбранном;
## выбранные подсвечиваются зелёным (подходит гостю) или красным (нет), у гостя совпавшие вкусы зеленеют.
func _autopilot_pick_animation(items: Array) -> void:
	var v := _v
	var prefs: Dictionary = _v.order["preferences"]
	var dislikes: Dictionary = _v.order.get("dislikes", {})
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
			_v = v
		settled.append(item)
		_garage.set_chips("player", TasteIcons.cook_chips(_recipes.catalog, settled, prefs, dislikes))
		_update_wants_badge(settled, false)
		await get_tree().create_timer(0.35).timeout
		_v = v
	_update_wants_badge(settled, true)
	await get_tree().create_timer(1.0).timeout
	_v = v


## Вкусы, которые хочет гость, светятся у него над головой, пока он не попробует кальян.
func _show_wants_badge(guest_id: String) -> void:
	_wants_guest_id = guest_id
	_update_wants_badge([], false)


func _update_wants_badge(chosen: Array, final: bool) -> void:
	if _wants_guest_id == "" or _v.order.is_empty():
		return
	_garage.set_chips(_wants_guest_id, TasteIcons.guest_chips(_recipes.catalog, _v.order["preferences"], _v.order.get("dislikes", {}), chosen, final))


func _clear_wants_badge() -> void:
	if _wants_guest_id != "":
		_garage.clear_chips(_wants_guest_id)
	_wants_guest_id = ""


## Автопилот «нажимает» за игрока: листает диалоги и закрывает карточку итогов.
func _process(delta: float) -> void:
	_tick_fps(delta)
	_game_seconds += delta
	if _modal_dim != null:
		_modal_dim.visible = _mixer.visible or _book.visible or _preparation_screen.visible or (_manual_screen != null and _manual_screen.visible)
	# Тест-прогон сам закрывает сюжетные модалки (в том числе «удерживаемые») и придумывает название кальянной.
	if _notice_overlay != null and (_autopilot or _test_run):
		# Пока открыта «удерживаемая» модалка, время игры почти стоит (time_scale ≈ 0): считаем по часам системы.
		if Time.get_ticks_msec() - _notice_opened_msec >= int(NOTICE_AUTOPILOT_DELAY * 1000.0):
			_notice_opened_msec = Time.get_ticks_msec()
			GameLog.info("autopilot", "Тест-прогон закрывает модалку (%s)" % ("название кальянной" if _name_dialog != null else "уведомление"))
			if _name_dialog != null:
				_name_dialog.autosubmit(_random_bar_name())
			else:
				_notice_closed.emit()
	_tick_session(delta)
	_tick_hud(delta)
	_tick_wait_line(delta)
	_tick_autosave(delta)
	_tick_extra_guests(delta)
	_tick_ben(delta)
	_tick_walkers()
	_track_waits()
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_open_pause_menu()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_fullscreen()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_toggle_stats_panel()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_debug_reset_hookah()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_set_autopilot(not _autopilot)


func _debug_reset_hookah() -> void:
	var guest_id := _v.station.guest_id
	_v.station.reset()
	_v.last_verdict = {}
	_v.smoke_permission = false
	_v.ask_blocked = false
	_hookah_on_prep_table = false
	_prep_owner = null
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
const VOLUME_SETTING := "volume_percent"


## Громкость задаётся в настройках (главное меню / пауза) и запоминается; здесь — применяем сохранённую.
func _apply_saved_volume() -> void:
	var percent := DEFAULT_VOLUME_PERCENT
	if _save != null:
		percent = float(_save.load_setting(VOLUME_SETTING, DEFAULT_VOLUME_PERCENT))
	_set_volume_percent(percent)


## Вид графики: «как раньше» или новый; запоминается в настройках и применяется на лету.
func _apply_saved_graphics() -> void:
	var modern := false
	if _save != null:
		modern = bool(_save.load_setting(VisualStyle.SETTING_KEY, false))
	VisualStyle.set_modern(modern)
	if _save != null:
		VisualStyle.set_show_names(bool(_save.load_setting(VisualStyle.NAMES_KEY, true)))
	if _garage != null:
		_garage.refresh_visual_style()
	_apply_ui_theme()


func _on_friend_names_changed(show: bool) -> void:
	VisualStyle.set_show_names(show)
	if _save != null:
		_save.save_setting(VisualStyle.NAMES_KEY, show)


func _on_graphics_style_changed(modern: bool) -> void:
	VisualStyle.set_modern(modern)
	if _save != null:
		_save.save_setting(VisualStyle.SETTING_KEY, modern)
	if _garage != null:
		_garage.refresh_visual_style()
	_apply_ui_theme()


## Новый вид интерфейса: кнопки главного экрана и всех окон (окна берут тему при открытии).
func _apply_ui_theme() -> void:
	var root := get_node_or_null("UI/Root") as Control
	if root != null:
		root.theme = UiStyle.make_controls_theme() if VisualStyle.modern else null


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
	_test_run_check = CheckBox.new()
	_test_run_check.text = "🧪 Тест-прогон"
	_test_run_check.tooltip_text = "Автопилот включается сразу; первые рецепты засчитываются сильными; автопилот ставит стол со стулом парой (после ухода второго гостя) и обслуживает двух гостей. Лучше включать в новом профиле."
	_test_run_check.focus_mode = Control.FOCUS_NONE
	_test_run_check.add_theme_font_size_override("font_size", 20)
	_test_run_check.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_test_run_check.offset_left = -490.0
	_test_run_check.offset_right = -260.0
	_test_run_check.offset_top = 16.0
	_test_run_check.offset_bottom = 68.0
	# Галочки нет: включённость видна по подсветке плашки.
	var blank := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		_test_run_check.add_theme_icon_override(icon, blank)
	_test_run_check.add_theme_constant_override("h_separation", 0)
	_test_run_check.toggled.connect(func(on: bool) -> void: _test_run_check.modulate = Color(0.55, 1.0, 0.6) if on else Color.WHITE)
	_test_run_check.toggled.connect(_on_test_run_toggled)
	$UI/Root.add_child(_test_run_check)


func _on_test_run_toggled(on: bool) -> void:
	_test_run = on
	if not on:
		_notify("🧪 Тест-прогон выключен (автопилот остаётся как был), скорость ×1.")
		_set_game_speed(1.0)
		_set_test_camera(true)
		return
	_test_angry_seen = _state != null and _state.get_flag(SECOND_GUEST_DEMO_FLAG, false) == true
	if _economy != null:
		_economy.earn(1000)
	_notify("🧪 Тест-прогон: автопилот, сильные рецепты, мебель парой. +1000 💰 на покупки.")
	_set_autopilot(true)
	_set_game_speed(10.0)
	_set_test_camera(false)


## Второй гость ушёл рассерженным (вызывается планировщиком гостей): тест-прогон может ставить стол и стул.
func _test_note_angry_departure() -> void:
	_test_angry_seen = true


## Кнопка 📊 и окно статистики для ручного тестирования (есть в любой сборке).
func _add_stats_panel() -> void:
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
	# Кнопка 📊 (она же F8) рядом с кнопками автопилота; в релизной сборке — в углу.
	_stats_button = Button.new()
	_stats_button.text = "📊"
	_stats_button.tooltip_text = "Статистика прохождения (F8)"
	_stats_button.focus_mode = Control.FOCUS_NONE
	_stats_button.add_theme_font_size_override("font_size", 28)
	_stats_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats_button.offset_left = -252.0 if OS.is_debug_build() else -72.0
	_stats_button.offset_right = _stats_button.offset_left + 56.0
	_stats_button.offset_top = 16.0
	_stats_button.offset_bottom = 68.0
	_stats_button.pressed.connect(_toggle_stats_panel)
	$UI/Root.add_child(_stats_button)


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
	if _scoring != null:
		_scoring.trend_enabled = _trends_on()
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
	if _trends == null or not _trends.is_valid() or not _trends_on():
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
	_hud.show_text(StatusHud.format_lines(int(_state.money), int(_state.reputation), trend_name, left, _goal.progress_text(_state.recipes), _goal.is_complete(_state.recipes), _trends_on()))


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
	if not _trends_on() or _trends == null or not _trends.is_valid() or _scoring == null:
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
	var cost := _v.pending_cost
	_v.pending_cost = 0
	if _economy == null or cost <= 0:
		return
	var charged := mini(cost, _economy.balance())
	if _economy.spend(charged):
		_stats.bump("spent", charged)
		if _v.redo_used:
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
	var goal_score := float(verdict["final_score"])
	if _test_run and goal_score < _goal.strong_score:
		goal_score = _goal.strong_score
		GameLog.info("test_run", "Тест-прогон: оценка %.1f засчитана сильной" % float(verdict["final_score"]))
	if _goal.record(recipe, str(verdict.get("trend_id", "")), goal_score):
		_stats.bump("strong_recipes")
		var trend_names: Array = []
		for trend_id in recipe.get("strong_trends", []):
			var trend_label := _trends.name_of(str(trend_id)) if _trends != null else str(trend_id)
			trend_names.append(trend_label if not trend_label.is_empty() else "без трендов")
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
		await _show_notice(_intro.ending_notice, true)
	if _state.bar_name.is_empty() and _save != null and _save.autosave_enabled:
		await _prompt_bar_name()
	_autosave()


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
	_furniture_screen.shelf_offer = _shelf_offer
	_furniture_screen.shelf_upgrade_requested.connect(_on_shelf_upgrade_requested)
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
	if _guide_button != null:
		_guide_button.visible = false
	# Кнопки слева сверху не должны лезть на окно мебели.
	for node in [_profile_button, _milk_button]:
		if node != null:
			(node as Control).visible = false
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
		_guide_panel.visible = _guide_expanded
	if _guide_button != null:
		_guide_button.visible = true
	for node in [_profile_button, _milk_button]:
		if node != null:
			(node as Control).visible = true
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
		var placed_item := str(_furniture.entry_of(uid).get("item", ""))
		var hint := ""
		if (placed_item == "chair" or placed_item == "small_table") and not _furniture.has_seat_partner(uid):
			hint = " ⚠ Стул стоит не у стола — гость за него не сядет. Поставь стул вплотную к малому столу." if placed_item == "chair" \
				else " ⚠ Столу нужен стул вплотную, иначе гость не сядет."
		_furniture_screen.notify(("Поставили." if detached == 0 else "Поставили. Предметы со стола вернулись на склад: %d." % detached) + hint)
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
	_apply_shelf_level.call_deferred()


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
	for node in [_hud, _guide_panel, _guide_button, _objective_label, _furniture_button, _milk_button, _autopilot_button, _camera_button, _stats_button]:
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
	return _test_run or _intro == null or (_state != null and _state.get_flag(QUICK_SERVED_FLAG, false) == true)


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
		_notify("⚡ Открыта быстрая готовка!")
	var furniture := _intro.is_furniture_unlocked(count)
	if _furniture_button != null and not _furniture_open():
		_furniture_button.visible = furniture
	if furniture and _state.get_flag("furniture_unlock_seen", false) != true and _intro.furniture_after_sessions > 0:
		_state.set_flag("furniture_unlock_seen", true)
		_mark_beat("furniture_unlocked")
		_notify("🛋️ Открыта мебель: кнопка слева вверху!")
	if _autopilot_button != null:
		_autopilot_button.disabled = not _autopilot_allowed()
		_autopilot_button.tooltip_text = "Автопилот кальянщика (F10)" if _autopilot_allowed() else "Автопилот откроется после обслуживания друга в быстром режиме"
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
	_guide_button = Button.new()
	_guide_button.text = "🎯"
	_guide_button.tooltip_text = "Цель: показать / скрыть"
	_guide_button.focus_mode = Control.FOCUS_NONE
	_guide_button.add_theme_font_size_override("font_size", 22)
	_guide_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_guide_button.offset_left = -600.0
	_guide_button.offset_right = -500.0
	_guide_button.offset_top = 16.0
	_guide_button.offset_bottom = 68.0
	_guide_button.visible = false
	_guide_button.pressed.connect(func() -> void:
		_guide_expanded = not _guide_expanded
		_guide_panel.visible = _guide_expanded and not _furniture_open())
	$UI/Root.add_child(_guide_button)
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
		"heat_warn": _any_heat_warn(),
		"furniture_unlocked": _intro.is_furniture_unlocked(count),
		"extra_furniture_placed": _furniture.placed_non_gift_count() if _furniture != null else 0,
		"goal_done": _state.get_flag(ProgressionGoal.DONE_FLAG, false) == true,
		"second_seat_done": _second_seat_ready(),
		"quick_served": _state.get_flag(QUICK_SERVED_FLAG, false) == true,
		"new_guest_met": _trends_on(),
		"progress_text": _goal.progress_text(_state.recipes) if _goal != null else "",
	}
	var step := _intro.current_step(ctx)
	if str(step["id"]) == "done":
		_guide_header.text = "🎯 Цель выполнена"
	else:
		_guide_header.text = "🎯 Цель (%d/%d)" % [int(step["done_count"]) + 1, int(step["total"])]
	_guide_label.text = str(step["text"])
	_guide_panel.visible = _guide_expanded and not _furniture_open()
	if _guide_button != null:
		_guide_button.visible = not _furniture_open()
		_guide_button.text = "🎯 ✅" if str(step["id"]) == "done" else "🎯 %d/%d" % [int(step["done_count"]) + 1, int(step["total"])]


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
	if _garage != null:
		_garage.refresh_extra_station()
	_autosave()
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

func _show_notice(text: String, hold: bool = false) -> void:
	if text.is_empty():
		return
	_notice_hold = hold
	if hold:
		_set_furniture_pause(true)
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
	_notice_opened_msec = Time.get_ticks_msec()
	await _notice_closed
	overlay.queue_free()
	_notice_overlay = null
	if hold:
		_notice_hold = false
		_set_furniture_pause(false)
	_carrying = false
	_update_input_lock()


# --- Автопилот: расстановка мебели ---

## Автопилот ставит подаренный диван и один-два купленных предмета. true — что-то сделал.
func _autopilot_furnish() -> bool:
	if _furniture == null or _intro == null or _economy == null or _furniture_open() or not _furniture_unlocked():
		return false
	if _game_seconds < _furnish_next_try:
		return false
	if _autopilot_shelf():
		return true
	if _state.get_flag(ProgressionGoal.DONE_FLAG, false) == true:
		# Цель выполнена: ждём, пока второй гость уйдёт рассерженным (если планировщик гостей уже есть), затем ставим стол и стул вместе.
		var angry_seen: bool = _test_angry_seen or _state.get_flag(SECOND_GUEST_DEMO_FLAG, false) == true
		if _scheduler != null and not angry_seen:
			return false
		if _furnish_gap():
			return _autopilot_furnish_pair()
	var uid := ""
	for entry in _furniture.stored_entries():
		if bool(entry.get("gift", false)):
			uid = str(entry["uid"])
			break
	if uid == "" and not _furniture.stored_entries().is_empty():
		uid = str(_furniture.stored_entries()[0]["uid"])
	if uid == "":
		uid = _autopilot_buy_nook()
	if uid == "" and _furniture.placed_non_gift_count() < 2:
		# Каждый прогон покупает разное: случайный небольшой предмет декора, которого ещё нет (картины, торшер, растение...).
		var candidates: Array[String] = []
		for item_id in _furniture.items:
			var definition: Dictionary = _furniture.items[item_id]
			var size: Array = definition.get("grid_size", [1, 1])
			if str(item_id) == "small_table" or str(item_id) == "chair" or NOOK_ITEMS.has(str(item_id)) or int(size[0]) * int(size[1]) > 2:
				continue
			if _furniture.owned_count(str(item_id)) > 0 or int(definition["price"]) + 150 > _economy.balance():
				continue
			candidates.append(str(item_id))
		var best := ""
		var best_price := 1 << 30
		if not candidates.is_empty():
			_rng.randomize()
			best = candidates[_rng.randi() % candidates.size()]
			best_price = int(_furniture.items[best]["price"])
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


## Сколько столов и стульев нужно прогону: один стол с двумя стульями, с 7-го визита поток растёт — ещё стол и стулья.
func _furnish_targets() -> Dictionary:
	# Один стол с двумя стульями; с ростом потока (ступени из visits.json) — ещё по столу на ступень, не больше 4.
	var tables := 1
	if _scheduler != null:
		tables = mini(1 + _scheduler.level, 4)
	return {"small_table": tables, "chair": tables * 2}


func _furnish_gap() -> bool:
	var targets := _furnish_targets()
	for item_id in targets:
		if _furniture.placed_count(str(item_id)) < int(targets[item_id]):
			return true
	return false


## Тест-прогон: докупает и ставит столы и стулья до нужного числа (стол с двумя стульями). true — что-то сделал.
func _autopilot_furnish_pair() -> bool:
	var targets := _furnish_targets()
	var to_buy: Array[String] = []
	var total := 0
	for item_id in ["small_table", "chair"]:
		var stored := 0
		for entry in _furniture.stored_entries():
			if str(entry.get("item", "")) == item_id:
				stored += 1
		var need := int(targets[item_id]) - _furniture.placed_count(item_id) - stored
		for i in maxi(need, 0):
			to_buy.append(item_id)
			total += int(_furniture.item(item_id).get("price", 0))
	if to_buy.is_empty() and not _furnish_gap():
		return false
	if _economy.balance() < total:
		_furnish_next_try = _game_seconds + 20.0
		return false
	for item_id in to_buy:
		var bought := _furniture.buy(item_id)
		if bool(bought["ok"]):
			var price := int(_furniture.item(item_id).get("price", 0))
			_stats.bump("furniture_bought")
			_stats.bump("furniture_spent", price)
			_notify("🛒 Куплено: %s (−%d 💰)" % [str(_furniture.item(item_id)["name"]), price])
	var placed_any := false
	# Сначала столы, потом стулья (стул ставится вплотную к столу).
	for item_id in ["small_table", "chair"]:
		while _furniture.placed_count(item_id) < int(targets[item_id]):
			var uid := _stored_uid_of(item_id)
			if uid == "" or not _autopilot_place(uid):
				break
			_stats.bump("furniture_placed")
			placed_any = true
	if placed_any:
		_mark_beat("decorated")
		return true
	_furnish_next_try = _game_seconds + 60.0
	_stats.bump("furnish_fail")
	_stats.log_event(_game_seconds, "МЕБЕЛЬ: не нашёл места (столов %d из %d, стульев %d из %d)" % [_furniture.placed_count("small_table"), int(targets["small_table"]), _furniture.placed_count("chair"), int(targets["chair"])])
	return false


func _stored_uid_of(item_id: String) -> String:
	for entry in _furniture.stored_entries():
		if str(entry.get("item", "")) == item_id:
			return str(entry["uid"])
	return ""


const NOOK_ITEMS: Array[String] = ["rug_big", "lamp", "plant"]


## Прямоугольник поставленного дивана (пустой, если диван ещё не стоит).
func _nook_couch_rect() -> Rect2:
	var couch: Dictionary = _furniture.gift_entry("couch")
	if couch.is_empty() or not bool(couch.get("placed", false)):
		return Rect2()
	return _furniture.entry_rect(couch)


## Уголок отдыха у дивана: большой ковёр под ним, торшер и растение по краям. Покупает следующее недостающее; "" — нечего или не хватает денег.
func _autopilot_buy_nook() -> String:
	if not _nook_couch_rect().has_area():
		return ""
	for item_id in NOOK_ITEMS:
		if _furniture.owned_count(item_id) > 0:
			continue
		var price := int(_furniture.item(item_id).get("price", 0))
		if _economy.balance() < price + 150:
			return ""
		var bought := _furniture.buy(item_id)
		if not bool(bought["ok"]):
			return ""
		_stats.bump("furniture_bought")
		_stats.bump("furniture_spent", price)
		_notify("🛒 Куплено: %s (−%d 💰)" % [str(_furniture.item(item_id)["name"]), price])
		return str(bought["uid"])
	return ""


## Ставит предмет уголка у дивана. true — поставлен.
func _autopilot_place_nook(uid: String, item_id: String, couch: Rect2) -> bool:
	var layer := _garage.furniture_layer()
	var along_x := couch.size.x >= couch.size.y
	var spots: Array = []
	if item_id == "rug_big":
		# Ковёр обнимает диван целиком: перебираем полуклеточные сдвиги.
		for rotation in [0, 1]:
			var size := Vector2(4, 3) if rotation == 0 else Vector2(3, 4)
			for dx in range(-8, 3):
				for dy in range(-8, 3):
					var at := couch.position + Vector2(float(dx) * 0.5, float(dy) * 0.5)
					if Rect2(at, size).encloses(couch):
						spots.append([at, rotation])
	else:
		# Торшер и растение — у торцов дивана, в одном ряду с ним.
		var x0 := roundi(couch.position.x)
		var y0 := roundi(couch.position.y)
		var x1 := roundi(couch.end.x)
		var y1 := roundi(couch.end.y)
		if along_x:
			spots = [[Vector2(x1, y0), 0], [Vector2(x0 - 1, y0), 0]]
		else:
			spots = [[Vector2(x0, y1), 0], [Vector2(x0, y0 - 1), 0]]
	for spot: Array in spots:
		var at: Vector2 = spot[0]
		var rotation: int = spot[1]
		if _furniture.check_placement(item_id, at, rotation, uid) != "":
			continue
		if layer != null and layer.validator.is_valid() and str(layer.validator.call(item_id, at, rotation, uid)) != "":
			continue
		if bool(_furniture.place(uid, at, rotation)["ok"]):
			return true
	return false


func _autopilot_place(uid: String) -> bool:
	var entry := _furniture.entry_of(uid)
	if entry.is_empty():
		return false
	var item_id := str(entry["item"])
	var couch_rect := _nook_couch_rect()
	if NOOK_ITEMS.has(item_id) and couch_rect.has_area() and _autopilot_place_nook(uid, item_id, couch_rect):
		return true
	var layer := _garage.furniture_layer()
	var cells: Array[Vector2i] = []
	for x in range(_furniture.room_size.x):
		for y in range(_furniture.room_size.y):
			cells.append(Vector2i(x, y))
	cells.shuffle()
	if item_id == "chair":
		cells = _chair_cells(cells)
	for rotation in [0, 1]:
		for cell in cells:
			var at := Vector2(cell)
			if _furniture.check_placement(item_id, at, rotation, uid) != "":
				continue
			if item_id == "small_table" and not _table_spot_ok(_furniture.rect_of(item_id, at, rotation), uid):
				continue
			if layer != null and layer.validator.is_valid() and str(layer.validator.call(item_id, at, rotation, uid)) != "":
				continue
			if bool(_furniture.place(uid, at, rotation)["ok"]):
				return true
	return false


## Стол не вплотную к другим столам и стенам, и вокруг него есть хотя бы два места под стулья с проходом.
func _table_spot_ok(rect: Rect2, uid: String) -> bool:
	# Столы не вплотную (между ними минимум клетка), от постоянных объектов (раковина, полка) — тоже клетка.
	# Достаточно ли места под стулья, проверяет подсчёт ниже: каждый стул должен иметь вокруг проход.
	if not _furniture.ring_is_free(rect, [uid], 1.0, 1.0):
		return false
	var good := 0
	for cell in _cells_around(rect):
		if _furniture.ring_is_free(Rect2(Vector2(cell), Vector2.ONE), [uid], 1.0, 1.0):
			good += 1
	return good >= 2


## Клетки, которые касаются сторон прямоугольника (куда можно поставить стул).
func _cells_around(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := roundi(rect.position.x)
	var y0 := roundi(rect.position.y)
	var x1 := roundi(rect.end.x)
	var y1 := roundi(rect.end.y)
	for x in range(x0, x1):
		result.append(Vector2i(x, y0 - 1))
		result.append(Vector2i(x, y1))
	for y in range(y0, y1):
		result.append(Vector2i(x0 - 1, y))
		result.append(Vector2i(x1, y))
	return result


## Для стула: только клетки вплотную к столу, где ещё нет двух стульев, и где вокруг стула можно ходить.
func _chair_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var good: Array[Vector2i] = []
	var placed := _furniture.placed_entries()
	for table: Dictionary in placed:
		if str(table["item"]) != "small_table":
			continue
		var trect := _furniture.entry_rect(table)
		var siblings: Array = [str(table["uid"])]
		var chairs := 0
		for other: Dictionary in placed:
			if str(other["item"]) == "chair" and FurnitureSystem._touching_side(trect, _furniture.entry_rect(other)) != "":
				siblings.append(str(other["uid"]))
				chairs += 1
		if chairs >= 2:
			continue
		for cell in cells:
			if FurnitureSystem._touching_side(trect, Rect2(Vector2(cell), Vector2.ONE)) == "":
				continue
			if good.has(cell):
				continue
			# Ещё один стул этого же стола рядом — не помеха; чужой стол или стена — помеха.
			if _furniture.ring_is_free(Rect2(Vector2(cell), Vector2.ONE), siblings, 1.0, 1.0):
				good.append(cell)
	return good


## (не используется) прежний выбор клеток для стула.
func _cells_next_to_table(cells: Array[Vector2i]) -> Array[Vector2i]:
	var rects: Array[Rect2] = []
	for entry: Dictionary in _furniture.placed_entries():
		if str(entry["item"]) == "small_table":
			rects.append(_furniture.entry_rect(entry))
	var near: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for cell in cells:
		var adjacent := false
		for rect in rects:
			if FurnitureSystem._touching_side(rect, Rect2(Vector2(cell), Vector2.ONE)) != "":
				adjacent = true
		if adjacent:
			near.append(cell)
		else:
			rest.append(cell)
	return near + rest


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()


func _toggle_stats_panel() -> void:
	if _stats_panel != null:
		_stats_panel.toggle()


## Строки окна статистики: сначала «живые» значения, затем итоги за запуск.
func _stats_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("— СЕЙЧАС —")
	lines.append("Режим: %s, скорость ×%.0f%s" % ["NPC (автопилот)" if _autopilot else "ручной", _saved_time_scale if _furniture_paused else Engine.time_scale, " (пауза: мебель)" if _furniture_paused else ""])
	lines.append("Сюжет: %s" % _state.story_progress)
	var guest_id := _ready_guest()
	var guest_name := str(GuestCatalog.load_guest(guest_id).get("name", guest_id)) if guest_id != "" else "—"
	lines.append("Гость: %s%s" % [guest_name, " (уходит)" if _v.departing else ""])
	lines.append("Заказ: %s" % (str(_v.order.get("id", "?")) if not _v.order.is_empty() else "—"))
	lines.append("Стол: %s" % str(_v.station.state))
	if _v.heat != null and _v.heat_active:
		lines.append("Жар: %.0f (%s), темп %.2f, затяжек %d" % [_v.heat.heat, _v.heat.state, _v.heat.pace, _v.session_puffs])
		lines.append("Штраф: жар %.1f, сервис %.1f" % [_v.heat.heat_penalty(), _v.service_penalty])
		lines.append("Угли: %s, перезабивка: %s" % ["ждут замены" if (_v.heat.needs_service() or _v.npc_service_pending) else "ок", "просит" if _v.redo_requested else ("использована" if _v.redo_used else "нет")])
	else:
		lines.append("Жар: — (гость не курит)")
	lines.append("Мундштуков в коробке: %d" % _garage.mouthpiece_count())
	lines.append("Деньги: %d, репутация: %d" % [_state.money, _state.reputation])
	if _furniture != null and _furniture.is_valid():
		var furniture_totals := _furniture.totals()
		lines.append("Мебель: расставлено %d из %d, комфорт %d, атмосфера %d, бонус к оценке +%.1f" % [int(furniture_totals["placed"]), _furniture.owned_count(), int(furniture_totals["comfort"]), int(furniture_totals["atmosphere"]), float(furniture_totals["bonus"])])
	if _trends != null and _goal != null:
		if _trends_on():
			lines.append("Тренд: %s (ещё %d виз.), далее: %s" % [_trends.current_name(), _trends.visits_left, _trends.name_of(_trends.next_id())])
		else:
			lines.append("Тренд: ещё не открыты (откроются с %d-го гостя)" % (_intro.trends_at_guest if _intro != null else 10))
		lines.append("Цель: сильных рецептов %s%s" % [_goal.progress_text(_state.recipes), " — ВЫПОЛНЕНА" if _goal.is_complete(_state.recipes) else ""])
	lines.append("FPS: %d" % int(Engine.get_frames_per_second()))
	lines.append("")
	lines.append("— ЗА ЗАПУСК —")
	lines.append_array(_stats.summary_lines())
	lines.append_array(_stats.visit_lines())
	lines.append_array(_seats_now_lines())
	lines.append_array(_stats.seating_lines())
	lines.append_array(_stats.beat_lines())
	return lines


func _gname(guest_id: String) -> String:
	if guest_id == "":
		return ""
	return str(GuestCatalog.load_guest(guest_id).get("name", guest_id))


## Кто где сидит прямо сейчас: места, спутники, ждущие на диване.
func _seats_now_lines() -> Array[String]:
	var lines: Array[String] = ["", "— МЕСТА СЕЙЧАС —"]
	var ids: Array[String] = [GuestStation.MAIN_ID]
	ids.append(GuestStation.MAIN2_ID)
	ids.append_array(GuestStation.EXTRA_IDS)
	for station_id in ids:
		if not _garage.has_station(station_id):
			lines.append("%s: нет (стол/стул не поставлены)" % station_id)
			continue
		var uid := _garage.station_table_uid(station_id)
		var guest_id := _garage.station_guest_id(station_id)
		var text := "%s: стол %s, гость %s" % [station_id, uid.right(6) if uid != "" else "—", _gname(guest_id) if guest_id != "" else "свободно"]
		var buddy := _garage.companion_at(station_id)
		if buddy != "":
			text += ", спутник %s" % _gname(buddy)
		if guest_id != "" and _garage.station_ready_guest(station_id) == "":
			text += " (идёт)"
		lines.append(text)
	var waiting: PackedStringArray = []
	for waiting_id in _scheduler.waiting_ids():
		var partner := str(_company_partner.get(waiting_id, ""))
		waiting.append("%s (%.0f с)%s" % [_gname(waiting_id), _scheduler.seconds_left(waiting_id), " [компания с %s]" % _gname(partner) if partner != "" else ""])
	lines.append("Ждут: " + (", ".join(waiting) if not waiting.is_empty() else "—"))
	lines.append("Гостей в гараже: %d (максимум %d, ступень роста %d, пик за запуск %d); случайные гости: %s" % [_garage.guests_present(), _scheduler.max_guests, _scheduler.level, _stats.count("peak_guests"), ("с %d-го визита" % _gen_start) if _gen_start > 0 else "не начались"])
	lines.append("Ушли рассерженными (−%d репутации каждый): всего %d, одиночек %d, компаний %d; мебель: не нашлось места %d раз, столов %d, стульев %d" % [absi(_scheduler.angry_reputation), _stats.count("angry_leaves"), _stats.count("angry_singles"), _stats.count("angry_companies"), _stats.count("furnish_fail"), _furniture.placed_count("small_table"), _furniture.placed_count("chair")])
	lines.append_array(_wait_lines())
	lines.append("Полка: уровень %d, кальянов на полке %d, расширений куплено %d (потрачено %d ₽)" % [_shelf_level(), _garage.shelf_hookah_total(), _stats.count("shelf_upgrades"), _stats.count("spent_shelf")])
	if _ben_hired() or _ben_offered():
		lines.append("Бэн: %s; смен углей %d, перезабивок %d, мундштуков %d, залипал в телефоне %d раз, отруган %d, убрано кальянов %d, приготовил кальянов %d, выплачено %d ₽" % ["нанят" if _ben_hired() else "ждёт найма", _stats.count("coal_service_ben"), _stats.count("redo_ben"), _stats.count("mouthpiece_refill_ben"), _stats.count("ben_slacked"), _stats.count("ben_scolded"), _stats.count("wash_ben"), _stats.count("cook_ben"), _stats.count("spent_ben")])
	else:
		lines.append("Бэн: ещё не предлагал помощь (нужно %d+ гостей одновременно, пик за запуск %d)" % [BEN_HIRE_GUESTS, _stats.count("peak_guests")])
	return lines


# --- Бэн-помощник (второй кальянщик) ---

const BEN_HIRE_FLAG := "ben_hired"
const BEN_OFFER_FLAG := "ben_hire_offered"
## Сколько гостей одновременно должно быть, чтобы Бэн «созрел» помогать.
const BEN_HIRE_GUESTS := 5
## Плата Бэну за каждый заказ, в котором он помог.
const BEN_PAY := 15
## Сколько секунд игрового времени кальянщик может не замечать дело, прежде чем Бэн возьмётся сам.
const BEN_REACT_SECONDS := 4.0
## Через сколько секунд после ухода гостя Бэн сам уберёт оставшийся кальян (кальянщик успевает раньше).
const BEN_WASH_SECONDS := 12.0
## Не чаще раза в столько секунд Бэн пробует докладывать мундштуки.
## Бэн сам готовит кальян гостю, который ждёт его дольше (игровых секунд с момента заказа).
const BEN_COOK_WAIT := 25.0
const BEN_COOK_COOLDOWN := 15.0
const BEN_COOK_MISTAKE_CHANCE := 0.35
var _ben_cook_next := 0.0
const BEN_PIECES_COOLDOWN := 25.0
## Шанс, что Бэн «залипнет» в рилсах на диване и не пойдёт сразу; за это его ругают и не платят за заказ.
const BEN_SLACK_CHANCE := 0.3
const BEN_SLACK_SECONDS := Vector2(9.0, 14.0)
const BEN_SCOLD_LINES: Array[String] = [
	"Бэн, хватит листать рилсы, работай!",
	"Эй, раздолбай, угли сами не поменяются!",
	"Бэн! Ты вообще слышишь? Я тебе плачу!",
	"Опять завис в телефоне... Бэн, ну сколько можно?",
]
const BEN_EXCUSE_LINES: Array[String] = [
	"Да иду-иду, там просто видос дорассказывал! 😅",
	"Бро, ну не ори, я уже бегу!",
	"Всё-всё, вижу! Лечу! 🏃",
]
var _ben_running := false
var _ben_seen: Dictionary = {}
var _ben_pieces_next := 0.0
var _ben_auto_timer := 0.0
var _ben_hire_shown := false


func _ben_hired() -> bool:
	return _state != null and _state.get_flag(BEN_HIRE_FLAG, false) == true


func _ben_offered() -> bool:
	return _state != null and _state.get_flag(BEN_OFFER_FLAG, false) == true


## Каждый кадр: предлагает нанять Бэна, а когда он нанят — ищет, чем помочь.
func _tick_ben(delta: float) -> void:
	if _state == null or _garage == null or not _garage.buddy_ready():
		return
	if _ben_hired():
		if _ben_offered() or _ben_hire_shown:
			_state.set_flag(BEN_OFFER_FLAG, false)
			_ben_hire_shown = false
			_garage.set_buddy_hire(false)
		_tick_ben_work()
		return
	if not _ben_offered():
		if _garage.guests_present() >= BEN_HIRE_GUESTS:
			_state.set_flag(BEN_OFFER_FLAG, true)
			_ben_hire_shown = true
			_garage.set_buddy_hire(true)
			_garage.buddy_say("Бро, у тебя тут аншлаг! Подойди, есть разговор.", "")
			_notify("👋 Гостей много, а Бэн скучает на диване. Подойди и поговори с ним.")
			_stats.log_event(_game_seconds, "БЭН: гостей %d, Бэн ждёт разговора о найме" % _garage.guests_present())
		return
	if not _ben_hire_shown:
		_ben_hire_shown = true
		_garage.set_buddy_hire(true)
	# Тест-прогон нанимает Бэна сам, без разговора.
	if _autopilot or _test_run:
		_ben_auto_timer += delta
		if _ben_auto_timer >= 3.0:
			_ben_auto_timer = 0.0
			_state.set_flag(BEN_HIRE_FLAG, true)
			_notify("🤝 Бэн теперь помогает: угли, перезабивка, мундштуки (%d ₽ за заказ)." % BEN_PAY)
			_stats.log_event(_game_seconds, "БЭН: нанят (автоматически в тест-прогоне)")


## Страховка: гость закреплён за местом, но не доходит дольше WALK_TIMEOUT игровых секунд — садим его на место.
const WALK_TIMEOUT := 40.0
var _walking_since: Dictionary = {}


## Ожидание гостей: от «сел» до принятого заказа и от заказа до поданного кальяна. Копится в статистике.
func _track_waits() -> void:
	if _garage == null or _stats == null:
		return
	_stats.game_seconds = _game_seconds
	for visit in _visits():
		if visit.departing or _garage.station_ready_guest(visit.station_id) == "":
			visit.ready_at = -1.0
			visit.order_at = -1.0
			visit.served_at = -1.0
			continue
		if visit.ready_at < 0.0:
			visit.ready_at = _game_seconds
		if visit.order_at < 0.0 and _order_known_for(visit) and not visit.order.is_empty():
			visit.order_at = _game_seconds
			_record_wait("wait_order", _game_seconds - visit.ready_at)
		if visit.order_at >= 0.0 and visit.served_at < 0.0 and visit.station.state != HookahStation.STATE_EMPTY:
			visit.served_at = _game_seconds
			_record_wait("wait_hookah", _game_seconds - visit.order_at)


func _record_wait(prefix: String, seconds: float) -> void:
	var sec := int(seconds)
	_stats.bump(prefix + "_n")
	_stats.bump(prefix + "_sum", sec)
	_stats.set_max(prefix + "_max", sec)
	if sec > 60:
		_stats.bump(prefix + "_over60")
	if sec > 120:
		_stats.bump(prefix + "_over120")


## Сколько игровых секунд автопилот тратит на этапы работы (разговор, приготовление и подача, простой).
func _record_phase(phase: String, seconds: float) -> void:
	var sec := int(seconds)
	_stats.bump("phase_%s_n" % phase)
	_stats.bump("phase_%s_sum" % phase, sec)
	_stats.set_max("phase_%s_max" % phase, sec)


func _wait_lines() -> Array[String]:
	var lines: Array[String] = []
	for entry in [["wait_order", "Ожидание заказа (сел → заказ принят)"], ["wait_hookah", "Ожидание кальяна (заказ → подан)"]]:
		var prefix := str(entry[0])
		var n := _stats.count(prefix + "_n")
		if n > 0:
			lines.append("%s: среднее %d с, максимум %d с, дольше 60 с: %d из %d, дольше 120 с: %d" % [str(entry[1]), _stats.count(prefix + "_sum") / n, _stats.count(prefix + "_max"), _stats.count(prefix + "_over60"), n, _stats.count(prefix + "_over120")])
		else:
			lines.append("%s: данных пока нет" % str(entry[1]))
	var phases: PackedStringArray = []
	for entry in [["talk", "разговор и заказ"], ["serve", "рецепт, приготовление и подача"], ["redo", "перезабивка"], ["coals", "угли"]]:
		var n := _stats.count("phase_%s_n" % str(entry[0]))
		if n > 0:
			phases.append("%s: в среднем %d с, максимум %d с (%d раз)" % [str(entry[1]), _stats.count("phase_%s_sum" % str(entry[0])) / n, _stats.count("phase_%s_max" % str(entry[0])), n])
	if not phases.is_empty():
		lines.append("Работа кальянщика (автопилот), игровые секунды: " + "; ".join(phases))
	return lines


func _tick_walkers() -> void:
	if _garage == null or _ui_paused():
		return
	var walking := _garage.walking_guest_ids()
	for guest_id in _walking_since.keys():
		if not walking.has(guest_id):
			_walking_since.erase(guest_id)
	for guest_id in walking:
		if not _walking_since.has(guest_id):
			_walking_since[guest_id] = _game_seconds
		elif _game_seconds - float(_walking_since[guest_id]) > WALK_TIMEOUT:
			_walking_since.erase(guest_id)
			if _garage.force_seat(guest_id):
				_stats.bump("walkers_forced")
				_stats.log_event(_game_seconds, "ЗАСТРЯЛ: %s не дошёл до места за %d с — посажен принудительно" % [_gname(guest_id), int(WALK_TIMEOUT)])


func _tick_ben_work() -> void:
	if _ben_running or _ui_paused() or _garage.buddy_working():
		return
	var now := _game_seconds
	var chosen: GuestVisit = null
	var chosen_kind := ""
	var chosen_since := INF
	for visit in _visits():
		var kind := ""
		if not visit.departing and not visit.servicing and not visit.redoing and visit.heat != null \
				and _garage.station_ready_guest(visit.station_id) != "":
			if visit.redo_requested:
				kind = "redo"
			elif visit.heat_active and visit.heat.needs_service():
				kind = "coals"
		if kind == "":
			_ben_seen.erase(visit.station_id)
			continue
		if not _ben_seen.has(visit.station_id):
			_ben_seen[visit.station_id] = now
		var since := float(_ben_seen[visit.station_id])
		if now - since >= BEN_REACT_SECONDS and since < chosen_since:
			chosen = visit
			chosen_kind = kind
			chosen_since = since
	if chosen != null:
		_ben_seen.erase(chosen.station_id)
		_ben_run(chosen, chosen_kind)
		return
	var cook := _ben_pick_cook(now)
	if cook != null:
		_ben_run(cook, "cook")
		return
	# Брошенный кальян (гость ушёл, а кальянщик не убрал его) — Бэн моет и ставит на полку.
	if not _carrying and not _garage.is_action_busy():
		for visit in _visits():
			var key := "wash:" + visit.station_id
			var abandoned := _garage.station_guest_id(visit.station_id).is_empty() and _garage.station_has_hookah(visit.station_id) \
				and not visit.servicing and not visit.redoing
			if not abandoned:
				_ben_seen.erase(key)
				continue
			if not _ben_seen.has(key):
				_ben_seen[key] = now
			if now - float(_ben_seen[key]) >= BEN_WASH_SECONDS:
				_ben_seen.erase(key)
				_ben_run_wash(visit)
				return
	if now >= _ben_pieces_next and _garage.mouthpieces_low(2) and _economy != null and _economy.balance() >= 8:
		_ben_pieces_next = now + BEN_PIECES_COOLDOWN
		_ben_run(null, "pieces")


func _ben_run_wash(v: GuestVisit) -> void:
	if not _garage.claim_wash(v.station_id):
		return
	_ben_running = true
	v.servicing = true
	_garage.buddy_say("Уберу кальян!")
	await _garage.buddy_begin_job()
	if _garage.station_guest_id(v.station_id).is_empty():
		await _garage.buddy_wash_hookah(v.station_id)
		_stats.bump("wash_ben")
		_stats.log_event(_game_seconds, "БЭН: убрал и помыл кальян (%s)" % v.station_id)
	_garage.release_wash(v.station_id)
	v.servicing = false
	_garage.buddy_end_job()
	_ben_running = false


## Бэн выбирает гостя, которому пора готовить кальян самому: заказ известен, кальяна нет, ждёт дольше порога; сперва самые дальние места.
func _ben_pick_cook(now: float) -> GuestVisit:
	if now < _ben_cook_next or _recipes == null or _preparation == null:
		return null
	var best: GuestVisit = null
	var best_distance := -1.0
	for visit in _visits():
		if visit.departing or visit.cooking_by != "" or visit.servicing or visit.redoing or visit.pending_serve:
			continue
		if visit.order.is_empty() or visit.order_at < 0.0 or now - visit.order_at < BEN_COOK_WAIT:
			continue
		if visit.station.state != HookahStation.STATE_EMPTY or _garage.station_ready_guest(visit.station_id) == "" or _garage.station_has_hookah(visit.station_id):
			continue
		if visit == _prep_owner or visit == _prep_visit:
			continue
		if visit == _v and (_preparation_screen.visible or _mixer.visible or _book.visible or _carrying):
			continue
		var distance := _garage.serve_distance_from_prep(visit.station_id)
		if distance > best_distance:
			best = visit
			best_distance = distance
	return best


## Бэн готовит кальян целиком: рецепт из книги (без бонусов за ручную работу, исполнение средненькое), полка, колба, стол гостя.
func _ben_do_cook(v: GuestVisit, scolded: bool) -> void:
	var gid := v.guest_id
	var taste := {"preferences": v.order.get("preferences", {}), "dislikes": v.order.get("dislikes", {})}
	var affordable: Array[Dictionary] = []
	for candidate in _recipes.all_recipes():
		if _economy == null or _economy.can_afford_recipe(candidate, _recipes.config.total_units):
			affordable.append(candidate)
	var recipe_id := AutoCook.find_fitting_recipe(affordable, _recipes.catalog, _recipes.config, _scoring, taste, AutoCook.FIT_MIN_FOR_EXISTING)
	if recipe_id == "":
		recipe_id = AutoCook.find_fitting_recipe(affordable, _recipes.catalog, _recipes.config, _scoring, taste, 0.0)
	if recipe_id == "":
		_ben_cook_next = _game_seconds + BEN_COOK_COOLDOWN
		_garage.buddy_say("Не знаю, что ему намешать...")
		return
	_garage.buddy_say("Сам сделаю кальян!")
	await _garage.buddy_begin_job()
	var served := await _garage.buddy_serve_hookah(v.station_id)
	if not served or v.guest_id != gid or v.departing:
		_ben_cook_next = _game_seconds + BEN_COOK_COOLDOWN
		return
	var recipe := _recipes.get_recipe(recipe_id)
	var choices := AutoCook.pick_choices(_preparation.config, recipe, _recipes.catalog, _recipes.config, _rng, BEN_COOK_MISTAKE_CHANCE)
	var result := _preparation.preview(recipe_id, choices, "ben")
	if not result["ok"] or not _preparation.commit(result):
		GameLog.error("ben", "Бэн не смог приготовить %s" % recipe_id)
		return
	var saved := _v
	_on_prepared(result, v)
	_v = v
	v.pending_serve = false
	_charge_pending_cost()
	v.smoke_permission = false
	v.ask_blocked = false
	var verdict := v.pending_verdict
	v.pending_verdict = {}
	if verdict.is_empty():
		_v = saved
		return
	v.last_verdict = verdict
	_start_heat(gid)
	_v = saved
	_stats.bump("cook_ben")
	if scolded:
		_stats.log_event(_game_seconds, "БЭН: за кальян для %s не заплачено (залип в телефоне)" % _gname(gid))
	else:
		_ben_pay(v)
	_stats.log_event(_game_seconds, "БЭН: приготовил кальян %s для %s (%s), оценка %.1f" % [_recipes.display_name(recipe), _gname(gid), v.station_id, float(verdict["final_score"])])
	_ben_cook_tail(v, gid, verdict)


## Дальше гость курит и реагирует, а Бэн уже свободен (корутина не блокирует его работу).
func _ben_cook_tail(v: GuestVisit, gid: String, verdict: Dictionary) -> void:
	_garage.buddy_end_job()
	_ben_running = false
	_garage.set_friend_smoking(gid, true, "")
	await _garage.wait_for_friend_puffs(gid, randi_range(3, 5))
	if v.guest_id != gid or v.departing:
		return
	if _wants_guest_id == gid:
		_clear_wants_badge()
	_garage.friend_react(gid, str(verdict["emoji"]))
	_garage.set_friend_smoking(gid, v.station.guest_smokes(), str(verdict["emoji"]))
	var guest := GuestCatalog.load_guest(gid)
	if not guest.is_empty():
		_rng.randomize()
		var text := GuestCatalog.reaction_text(guest, str(verdict["emotion_id"]), bool(verdict["likes"]), _rng)
		verdict["phrase"] = text
		_garage.say(gid, text)
	var saved := _v
	_v = v
	_apply_station()
	_v = saved
	_finish_session(gid, verdict)


func _ben_pay(v: GuestVisit) -> void:
	if v == null or v.ben_helped:
		return
	v.ben_helped = true
	if _economy != null:
		var paid := mini(BEN_PAY, _economy.balance())
		if paid > 0 and _economy.spend(paid):
			_stats.bump("spent", paid)
			_stats.bump("spent_ben", paid)
			_notify("Бэну за помощь: −%d 💰" % paid)


func _ben_run(v: GuestVisit, kind: String) -> void:
	_ben_running = true
	var scolded := false
	if kind == "pieces":
		await _ben_do_pieces()
	elif kind == "cook":
		v.cooking_by = "ben"
		if _rng.randf() < BEN_SLACK_CHANCE:
			scolded = await _ben_slack(v, kind)
		if _ben_still_needed(v, kind):
			await _ben_do_cook(v, scolded)
		if v.cooking_by == "ben":
			v.cooking_by = ""
	else:
		if _rng.randf() < BEN_SLACK_CHANCE:
			scolded = await _ben_slack(v, kind)
		if _ben_still_needed(v, kind):
			await _ben_do_service(v, kind, scolded)
	_garage.buddy_end_job()
	_ben_running = false


func _ben_still_needed(v: GuestVisit, kind: String) -> bool:
	if kind == "cook":
		return not v.departing and v.guest_id != "" and v.cooking_by == "ben" and v.station.state == HookahStation.STATE_EMPTY
	if v.departing or v.servicing or v.redoing or v.heat == null or v.guest_id == "":
		return false
	if kind == "redo":
		return v.redo_requested
	return v.heat_active and v.heat.needs_service()


## Бэн залип в рилсах: кальянщик (или гость) его отчитывает. Возвращает true, если Бэна отругали.
## Если дело за это время сделал кто-то другой, Бэн ничего не делает.
func _ben_slack(v: GuestVisit, kind: String) -> bool:
	var gid := v.guest_id
	var total := _rng.randf_range(BEN_SLACK_SECONDS.x, BEN_SLACK_SECONDS.y)
	var scold_at := total * 0.55
	var elapsed := 0.0
	var scolded := false
	_stats.bump("ben_slacked")
	_garage.buddy_phone(true)
	_garage.buddy_emotion("📱", 3.0)
	_garage.buddy_say("Секунду, досмотрю одну штуку...")
	_stats.log_event(_game_seconds, "БЭН: залип в телефоне, у %s (%s) ждёт %s" % [_gname(gid), v.station_id, "перезабивка" if kind == "redo" else ("кальян" if kind == "cook" else "замена углей")])
	while elapsed < total:
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
		if not _ben_still_needed(v, kind) or v.guest_id != gid:
			_garage.buddy_phone(false)
			return scolded
		if not scolded and elapsed >= scold_at:
			scolded = true
			_stats.bump("ben_scolded")
			var line := BEN_SCOLD_LINES[_rng.randi_range(0, BEN_SCOLD_LINES.size() - 1)]
			if _rng.randf() < 0.5 and gid != "":
				_garage.say(gid, line)
			else:
				_garage.say("player", line)
			_notify("Бэна отчитали: залип в телефоне.")
			await get_tree().create_timer(0.8).timeout
			elapsed += 0.8
			_garage.buddy_emotion("😅", 2.5)
			_garage.buddy_say(BEN_EXCUSE_LINES[_rng.randi_range(0, BEN_EXCUSE_LINES.size() - 1)])
	_garage.buddy_phone(false)
	return scolded


func _ben_do_pieces() -> void:
	await _garage.buddy_begin_job()
	_garage.buddy_say("Мундштуки докладываю!")
	await _garage.buddy_walk_to_mouthpiece_box()
	await get_tree().create_timer(1.4).timeout
	if _top_up_mouthpieces():
		_stats.bump("mouthpiece_refill")
		_stats.bump("mouthpiece_refill_ben")
		_stats.log_event(_game_seconds, "БЭН: доложил мундштуки")


## Угли (kind == "coals") или перезабивка (kind == "redo"): Бэн всё делает сам и берёт плату за заказ.
func _ben_do_service(v: GuestVisit, kind: String, scolded: bool = false) -> void:
	var gid := v.guest_id
	var redo := kind == "redo"
	v.servicing = true
	if redo:
		v.redo_requested = false
		v.redo_used = true
		v.service_penalty += v.heat.redo_cost * 0.5
	_stats.bump("coal_service")
	_stats.bump("redo_ben" if redo else "coal_service_ben")
	_state.set_flag("coals_replaced_once", true)
	_mark_beat("coals_replaced")
	if gid != "":
		_garage.set_friend_smoking(gid, false)
	_garage.buddy_say("Сейчас перезабью!" if redo else "Сейчас поменяю угли!")
	await _garage.buddy_begin_job()
	await _garage.buddy_service_coals(v.heat.service_seconds * (2.0 if redo else 1.0), v.station_id)
	if v.guest_id != gid or v.departing:
		v.servicing = false
		return
	if _economy != null:
		var paid := _economy.charge_coals()
		if paid > 0:
			_stats.bump("spent", paid)
			_stats.bump("spent_coals", paid)
	if scolded:
		_stats.log_event(_game_seconds, "БЭН: за заказ у %s не заплачено (залип в телефоне)" % _gname(gid))
	else:
		_ben_pay(v)
	if v.heat_active:
		v.heat.service()
		v.npc_service_pending = false
		v.complaint_timer = v.heat.complaint_cooldown
		var saved := _v
		_v = v
		_sync_heat_visual()
		_apply_station()
		_v = saved
		if gid != "" and v.station.guest_smokes():
			_garage.set_friend_smoking(gid, true, "")
		var line := v.heat.random_line("thanks", _rng)
		if line != "":
			_garage.say(gid, line)
	v.servicing = false
	_stats.log_event(_game_seconds, "БЭН: %s у %s (%s)" % ["перезабил" if redo else "сменил угли", _gname(gid), v.station_id])


# --- Расширение кальянной полки ---

const SHELF_LEVEL_FLAG := "shelf_level"


func _shelf_level() -> int:
	return int(_state.get_flag(SHELF_LEVEL_FLAG, 0)) if _state != null else 0


## Следующее расширение полки: {"name", "price", "text", "extra"} или {}.
func _shelf_offer() -> Dictionary:
	if _economy == null:
		return {}
	var level := _shelf_level()
	if level >= _economy.shelf_upgrades.size():
		return {}
	var upgrade: Dictionary = _economy.shelf_upgrades[level]
	var before := int(_economy.shelf_upgrades[level - 1]["extra"]) if level > 0 else 0
	var extra := int(upgrade["extra"])
	return {"name": "Расширение кальянной полки", "price": int(upgrade["price"]), "extra": extra,
		"text": "+%d кальяна на полку (всего %d)" % [extra - before, 4 + extra]}


func _apply_shelf_level() -> void:
	if _economy == null or _garage == null:
		return
	var level := _shelf_level()
	var extra := 0
	if level > 0 and level <= _economy.shelf_upgrades.size():
		extra = int(_economy.shelf_upgrades[level - 1]["extra"])
	_garage.set_shelf_extra(extra)


func _buy_shelf_upgrade() -> bool:
	var offer := _shelf_offer()
	if offer.is_empty() or _economy == null or not _economy.spend(int(offer["price"])):
		return false
	_state.set_flag(SHELF_LEVEL_FLAG, _shelf_level() + 1)
	_apply_shelf_level()
	_stats.bump("shelf_upgrades")
	_stats.bump("spent", int(offer["price"]))
	_stats.bump("spent_shelf", int(offer["price"]))
	_stats.log_event(_game_seconds, "ПОЛКА: расширена, кальянов на полке %d (−%d ₽)" % [_garage.shelf_hookah_total(), int(offer["price"])])
	_autosave()
	return true


func _on_shelf_upgrade_requested() -> void:
	var offer := _shelf_offer()
	if _buy_shelf_upgrade():
		_furniture_screen.notify("Полка расширена: %s" % str(offer["text"]))
		_furniture_screen.show_toast("🗄️ Полка расширена (−%d 💰)" % int(offer["price"]))
		_furniture_screen.refresh()
	else:
		_furniture_screen.notify("⛔ Не хватает денег или расширять больше нечего.")


## Тест-прогон докупает кальяны по мере роста потока: уровень полки не ниже ступени роста гостей.
func _autopilot_shelf() -> bool:
	if _scheduler == null or _economy == null:
		return false
	var offer := _shelf_offer()
	if offer.is_empty() or _shelf_level() >= _scheduler.level:
		return false
	if _economy.balance() < int(offer["price"]) + 80:
		return false
	return _buy_shelf_upgrade()


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


# --- M11: профили, автосохранение, название кальянной ----------------------------------------

const AUTOSAVE_INTERVAL := 15.0
var _autosave_timer := 0.0
var _reloading := false
var _profile_menu: ProfileMenu = null
var _profile_button: Button = null
var _name_dialog: BarNameDialog = null
var _pause_menu: PauseMenu = null


## Профиль ещё не выбран: показываем главное меню со списком профилей.
func _show_profile_gate() -> void:
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	_show_main_menu()


## Главное меню: «Играть» открывает список профилей, «Выйти из игры» закрывает игру.
func _show_main_menu() -> void:
	var menu := MainMenu.new()
	menu.setup()
	menu.play_requested.connect(func() -> void: _open_profile_menu(false))
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	menu.embed_settings(_make_settings_page())
	$UI/Root.add_child(menu)


## Делает профиль активным и перезагружает сцену: Main при старте сам загрузит его в GameState.
func _enter_profile(id: String) -> void:
	if id.is_empty() or not _save.begin_profile(id):
		return
	_reloading = true
	get_tree().reload_current_scene.call_deferred()


func _setup_profiles() -> void:
	if _save == null or not _save.autosave_enabled:
		return
	_profile_button = Button.new()
	_profile_button.text = "☰"
	_profile_button.tooltip_text = "Профили и меню"
	_profile_button.focus_mode = Control.FOCUS_NONE
	_profile_button.add_theme_font_size_override("font_size", 28)
	_profile_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_profile_button.offset_left = 152.0
	_profile_button.offset_top = 126.0
	_profile_button.offset_right = 208.0
	_profile_button.offset_bottom = 178.0
	_profile_button.pressed.connect(func() -> void: _open_profile_menu(true))
	$UI/Root.add_child(_profile_button)
	_apply_bar_name()


func _profile_menu_open() -> bool:
	return _profile_menu != null or _pause_menu != null


func _open_profile_menu(in_game: bool) -> void:
	if _profile_menu != null:
		return
	if in_game:
		_autosave()
	var menu := ProfileMenu.new()
	menu.set_meta("can_rename", in_game and _state != null and _state.get_flag(ProgressionGoal.DONE_FLAG, false) == true)
	menu.setup(_save.store(), ProgressionGoal.load_default(), _save.active_profile_id(), true)
	menu.play_requested.connect(_on_profile_play)
	menu.create_requested.connect(_on_profile_create)
	menu.reset_requested.connect(_on_profile_reset)
	menu.delete_requested.connect(_on_profile_delete)
	menu.rename_requested.connect(func(_id: String) -> void:
		_close_profile_menu()
		_prompt_bar_name())
	menu.closed.connect(_close_profile_menu)
	$UI/Root.add_child(menu)
	_profile_menu = menu
	if in_game:
		_set_furniture_pause(true)
		_update_input_lock()


func _close_profile_menu() -> void:
	if _profile_menu == null:
		return
	_profile_menu.queue_free()
	_profile_menu = null
	_set_furniture_pause(false)
	_update_input_lock()


func _on_profile_play(id: String) -> void:
	_autosave()
	_enter_profile(id)


func _on_profile_create() -> void:
	var store := _save.store()
	if not store.can_create():
		return
	_autosave()
	_enter_profile(store.create())


## Очистка прогресса: профиль остаётся в списке. Активный профиль перезапускается с нуля.
func _on_profile_reset(id: String) -> void:
	_save.store().reset(id)
	if id == _save.active_profile_id():
		_reloading = true
		_enter_profile(id)
	elif _profile_menu != null:
		_profile_menu.refresh()


func _on_profile_delete(id: String) -> void:
	_save.store().delete(id)
	if id == _save.active_profile_id():
		_save.leave_profile()
		_reloading = true
		get_tree().reload_current_scene.call_deferred()
	elif _profile_menu != null:
		_profile_menu.refresh()


func _autosave() -> void:
	if _reloading or _state == null or _save == null:
		return
	_save.save_game()


## Счётчик кадров в секунду: в правом нижнем углу, обновляется раз в полсекунды.
var _fps_label: Label = null
var _fps_timer := 0.0


func _add_fps_counter() -> void:
	_fps_label = UiStyle.label("FPS: --", 18, UiStyle.MUTED)
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fps_label.offset_right = -14.0
	_fps_label.offset_bottom = -10.0
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI/Root.add_child(_fps_label)


func _tick_fps(delta: float) -> void:
	if _fps_label == null:
		return
	_fps_timer += delta
	if _fps_timer >= 0.5:
		_fps_timer = 0.0
		_fps_label.text = "FPS: %d" % int(Engine.get_frames_per_second())


func _tick_autosave(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		_autosave()


## Неоновая вывеска «Кальянная полка»: её вешает главный кальянщик, когда игрок называет кальянную.
const NEON_SIGN_ID := "sign_neon"
const NEON_SIGN_FLAG := "neon_sign_hung"
var _neon_hanging := false


## Показывает вывеску, если она уже висит (кальянная названа), иначе прячет.
func _apply_neon_sign() -> void:
	if _state == null or _garage == null or _neon_hanging or not _garage.has_object(NEON_SIGN_ID):
		return
	var hung: bool = _state.get_flag(NEON_SIGN_FLAG, false) == true or not _state.bar_name.is_empty()
	if hung:
		_state.set_flag(NEON_SIGN_FLAG, true)
	if hung and not _garage.is_object_visible(NEON_SIGN_ID):
		_garage.show_object(NEON_SIGN_ID)
	elif not hung:
		_garage.hide_object(NEON_SIGN_ID)


## Кальянщик идёт к стене, вешает вывеску, и она загорается.
func _hang_neon_sign() -> void:
	if _state == null or _garage == null or _state.get_flag(NEON_SIGN_FLAG, false) == true or not _garage.has_object(NEON_SIGN_ID):
		_neon_hanging = false
		_apply_neon_sign()
		return
	_carrying = true
	_update_input_lock()
	await _garage.walk_to_object(NEON_SIGN_ID)
	_garage.say("player", "Теперь всё по-настоящему: вешаю вывеску.")
	await get_tree().create_timer(1.2).timeout
	await _garage.hang_object(NEON_SIGN_ID)
	_state.set_flag(NEON_SIGN_FLAG, true)
	_notify("💡 Кальянщик повесил вывеску «Кальянная полка».")
	_stats.log_event(_game_seconds, "СЮЖЕТ: после названия кальянной повешена неоновая вывеска")
	_neon_hanging = false
	_carrying = false
	_update_input_lock()
	_autosave()


func _apply_bar_name() -> void:
	_apply_neon_sign()
	if _state == null or _save == null or not _save.persistence_enabled():
		return
	var title := "Hookah Empire"
	if not _state.bar_name.is_empty():
		title += " — " + _state.bar_name
	DisplayServer.window_set_title(title)


const BAR_NAME_ADJECTIVES: Array[String] = ["Дымный", "Мятный", "Ленивый", "Золотой", "Тихий", "Угольный", "Сладкий", "Бархатный", "Туманный", "Рыжий"]
const BAR_NAME_NOUNS: Array[String] = ["гараж", "дымок", "уголёк", "кальян", "клуб", "лаунж", "приют", "шалман", "облачко", "закуток"]


## Случайное название кальянной для тест-прогона.
func _random_bar_name() -> String:
	return "%s %s" % [BAR_NAME_ADJECTIVES[_rng.randi() % BAR_NAME_ADJECTIVES.size()], BAR_NAME_NOUNS[_rng.randi() % BAR_NAME_NOUNS.size()]]


## Окно «Назови кальянную»; результат запоминается в профиле и показывается в списке профилей.
func _prompt_bar_name() -> void:
	if _name_dialog != null or _state == null:
		return
	_carrying = true
	_update_input_lock()
	var dialog := BarNameDialog.new()
	dialog.setup(_state.bar_name)
	var result := {"name": ""}
	dialog.finished.connect(func(chosen: String) -> void:
		result["name"] = chosen
		_notice_closed.emit())
	$UI/Root.add_child(dialog)
	_name_dialog = dialog
	_notice_overlay = dialog
	_notice_timer = 0.0
	_notice_opened_msec = Time.get_ticks_msec()
	_notice_hold = true
	_set_furniture_pause(true)
	await _notice_closed
	dialog.queue_free()
	_name_dialog = null
	_notice_overlay = null
	_notice_hold = false
	_set_furniture_pause(false)
	_carrying = false
	_update_input_lock()
	var cleaned := ProfileStore.clean_name(str(result["name"]))
	if cleaned.is_empty():
		return
	_neon_hanging = _state.get_flag(NEON_SIGN_FLAG, false) != true
	_state.bar_name = cleaned
	_apply_bar_name()
	_notify("🪔 Твоя кальянная теперь называется «%s»" % cleaned)
	_autosave()
	if _neon_hanging:
		await _hang_neon_sign()


# --- Меню паузы (Esc) ---

func _open_pause_menu() -> void:
	if _pause_menu != null or _profile_menu != null or _save == null or not _save.persistence_enabled():
		return
	if _furniture_open() or _name_dialog != null or _notice_overlay != null or (_viewer != null and _viewer.visible):
		return
	var menu := PauseMenu.new()
	menu.setup()
	menu.resume_requested.connect(_close_pause_menu)
	menu.profiles_requested.connect(func() -> void:
		_remove_pause_menu()
		_open_profile_menu(true))
	menu.main_menu_requested.connect(_on_pause_main_menu)
	menu.embed_settings(_make_settings_page())
	menu.stats_requested.connect(_toggle_stats_over_pause)
	menu.quit_requested.connect(_on_pause_quit)
	$UI/Root.add_child(menu)
	_pause_menu = menu
	_autosave()
	_set_furniture_pause(true)
	_update_input_lock()


## Статистика из паузы: панель открывается поверх окна паузы (справа), повторное нажатие скрывает.
func _toggle_stats_over_pause() -> void:
	if _stats_panel == null:
		return
	_stats_panel.toggle()
	if _stats_panel.visible:
		_stats_panel.get_parent().move_child(_stats_panel, -1)
		_stats_panel.refresh()


func _remove_pause_menu() -> void:
	if _pause_menu == null:
		return
	if _stats_panel != null:
		_stats_panel.visible = false
	_pause_menu.queue_free()
	_pause_menu = null


func _close_pause_menu() -> void:
	_remove_pause_menu()
	_set_furniture_pause(false)
	_update_input_lock()


func _on_pause_main_menu() -> void:
	_autosave()
	_reloading = true
	_save.leave_profile()
	get_tree().reload_current_scene.call_deferred()


func _on_pause_quit() -> void:
	_autosave()
	_reloading = true
	get_tree().quit()


# --- Настройки ---

var _settings_menu: SettingsMenu = null


## Страница настроек для вставки в меню паузы / главное меню.
func _make_settings_page() -> SettingsPanel:
	var page := SettingsPanel.new()
	var current := DEFAULT_VOLUME_PERCENT
	if _save != null:
		current = float(_save.load_setting(VOLUME_SETTING, DEFAULT_VOLUME_PERCENT))
	page.setup(current, VisualStyle.modern, VisualStyle.show_names)
	page.names_changed.connect(_on_friend_names_changed)
	page.style_changed.connect(_on_graphics_style_changed)
	page.volume_changed.connect(_set_volume_percent)
	page.volume_committed.connect(func(percent: float) -> void:
		if _save != null:
			_save.save_setting(VOLUME_SETTING, percent))
	return page


func _open_settings() -> void:
	if _settings_menu != null:
		return
	var menu := SettingsMenu.new()
	var current := DEFAULT_VOLUME_PERCENT
	if _save != null:
		current = float(_save.load_setting(VOLUME_SETTING, DEFAULT_VOLUME_PERCENT))
	menu.setup(current, VisualStyle.modern, VisualStyle.show_names)
	menu.names_changed.connect(_on_friend_names_changed)
	menu.style_changed.connect(_on_graphics_style_changed)
	menu.volume_changed.connect(_set_volume_percent)
	menu.volume_committed.connect(func(percent: float) -> void:
		if _save != null:
			_save.save_setting(VOLUME_SETTING, percent))
	menu.closed.connect(func() -> void:
		menu.queue_free()
		_settings_menu = null)
	$UI/Root.add_child(menu)
	_settings_menu = menu
