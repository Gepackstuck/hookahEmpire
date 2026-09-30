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
var _book_from_mixer := false

@onready var _garage: GarageWorld = %Garage
@onready var _toast: MessageToast = %MessageToast
@onready var _dialogue_box: DialogueBox = %DialogueBox
@onready var _mixer: MixerScreen = %MixerScreen
@onready var _book: RecipeBookScreen = %RecipeBookScreen


func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	GameLog.info("main", "Boot OK, version %s" % version)
	# GameState/SaveService — autoload; проверяем через путь, чтобы не падать при их отсутствии.
	for autoload_name in ["GameState", "SaveService"]:
		if get_node_or_null("/root/%s" % autoload_name) == null:
			GameLog.error("main", "Autoload не найден: %s" % autoload_name)

	_garage.message_requested.connect(_toast.show_message)
	_garage.dialogue_requested.connect(_on_dialogue_requested)
	_garage.action_requested.connect(_on_action_requested)
	_mixer.closed.connect(_update_input_lock)
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
	_effects = StoryEffects.new(_state)
	_runner.effect_requested.connect(_effects.apply)

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
	if not _garage.spawn_friend(guest, beat["entry_position"], beat["entry_cell"], beat["stand_cell"], beat["dialogue"]):
		return
	if not str(beat["sets_progress"]).is_empty():
		_state.set_story_progress(beat["sets_progress"])


func _on_dialogue_requested(dialogue_id: String) -> void:
	var dialogue := _library.get_dialogue(dialogue_id)
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


## Игра "заморожена" для мира, пока открыт любой экран или идёт диалог.
func _update_input_lock() -> void:
	_garage.set_input_locked(_mixer.visible or _book.visible or _runner.is_active)


func _on_action_requested(action_id: String) -> void:
	if _recipes == null:
		_toast.show_message("Система рецептов недоступна (ошибка данных, см. лог).")
		return
	match action_id:
		"open_mixer":
			_mixer.open()
		"open_recipe_book":
			_book_from_mixer = false
			_book.open()
		_:
			GameLog.error("main", "Неизвестное действие: %s" % action_id)
	_update_input_lock()


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
	GameLog.info("recipes", "Рецепт '%s' %s" % [result["recipe_id"], "создан" if result["is_new"] else "использован повторно"])
