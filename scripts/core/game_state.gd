extends Node
## Autoload GameState: хранит персистентное игровое состояние в памяти.
##
## Только данные и сигналы — без игровой логики. Правила (экономика, репутация,
## сюжет) живут в соответствующих системах и меняют состояние через сеттеры.
## Файловый I/O принадлежит SaveService, а не GameState.

signal money_changed(delta: int)
signal reputation_changed(delta: int)
signal story_progress_changed(node_id: String)
signal story_flag_changed(flag: String, value: Variant)

const DEFAULT_MONEY := 0
const DEFAULT_REPUTATION := 0
const DEFAULT_STORY_PROGRESS := "intro_start"

var money: int = DEFAULT_MONEY
var reputation: int = DEFAULT_REPUTATION
var story_progress: String = DEFAULT_STORY_PROGRESS
## Сюжетные флаги: стабильный id флага -> значение (bool/число/строка).
var story_flags: Dictionary = {}
## Рецепты игрока: id рецепта -> запись (см. RecipeSystem).
var recipes: Dictionary = {}
## Монотонный счётчик событий с рецептами (порядок создания/использования).
var recipe_seq: int = 0


func set_money(value: int) -> void:
	if value == money:
		return
	var delta := value - money
	money = value
	money_changed.emit(delta)


func set_reputation(value: int) -> void:
	if value == reputation:
		return
	var delta := value - reputation
	reputation = value
	reputation_changed.emit(delta)


func set_story_progress(node_id: String) -> void:
	if node_id == story_progress:
		return
	story_progress = node_id
	story_progress_changed.emit(node_id)


func set_flag(flag: String, value: Variant = true) -> void:
	if story_flags.has(flag) and story_flags[flag] == value:
		return
	story_flags[flag] = value
	story_flag_changed.emit(flag, value)


func has_flag(flag: String) -> bool:
	return story_flags.has(flag)


func get_flag(flag: String, default_value: Variant = null) -> Variant:
	return story_flags.get(flag, default_value)


func next_recipe_seq() -> int:
	recipe_seq += 1
	return recipe_seq


func reset_to_defaults() -> void:
	set_money(DEFAULT_MONEY)
	set_reputation(DEFAULT_REPUTATION)
	set_story_progress(DEFAULT_STORY_PROGRESS)
	story_flags.clear()
	recipes.clear()
	recipe_seq = 0


## Снимок состояния для сохранения. Новые поля добавляются по мере милестоунов.
func to_dict() -> Dictionary:
	return {
		"money": money,
		"reputation": reputation,
		"story_progress": story_progress,
		"story_flags": story_flags.duplicate(true),
		"recipes": recipes.duplicate(true),
		"recipe_seq": recipe_seq,
	}


## Применяет снимок. Отсутствующие ключи получают значения по умолчанию.
func apply_dict(data: Dictionary) -> void:
	set_money(int(data.get("money", DEFAULT_MONEY)))
	set_reputation(int(data.get("reputation", DEFAULT_REPUTATION)))
	set_story_progress(str(data.get("story_progress", DEFAULT_STORY_PROGRESS)))
	var flags: Variant = data.get("story_flags", {})
	story_flags = (flags as Dictionary).duplicate(true) if flags is Dictionary else {}
	var rec: Variant = data.get("recipes", {})
	recipes = (rec as Dictionary).duplicate(true) if rec is Dictionary else {}
	recipe_seq = int(data.get("recipe_seq", 0))
