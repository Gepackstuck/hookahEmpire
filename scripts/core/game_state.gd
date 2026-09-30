extends Node
## Autoload GameState: хранит персистентное игровое состояние в памяти.
##
## Только данные и сигналы — без игровой логики. Правила (экономика, репутация,
## сюжет) живут в соответствующих системах и меняют состояние через сеттеры.
## Файловый I/O принадлежит SaveService, а не GameState.

signal money_changed(delta: int)
signal reputation_changed(delta: int)
signal story_progress_changed(node_id: String)

const DEFAULT_MONEY := 0
const DEFAULT_REPUTATION := 0
const DEFAULT_STORY_PROGRESS := "intro_start"

var money: int = DEFAULT_MONEY
var reputation: int = DEFAULT_REPUTATION
var story_progress: String = DEFAULT_STORY_PROGRESS


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


func reset_to_defaults() -> void:
	set_money(DEFAULT_MONEY)
	set_reputation(DEFAULT_REPUTATION)
	set_story_progress(DEFAULT_STORY_PROGRESS)


## Снимок состояния для сохранения. Новые поля добавляются по мере милестоунов.
func to_dict() -> Dictionary:
	return {
		"money": money,
		"reputation": reputation,
		"story_progress": story_progress,
	}


## Применяет снимок. Отсутствующие ключи получают значения по умолчанию.
func apply_dict(data: Dictionary) -> void:
	set_money(int(data.get("money", DEFAULT_MONEY)))
	set_reputation(int(data.get("reputation", DEFAULT_REPUTATION)))
	set_story_progress(str(data.get("story_progress", DEFAULT_STORY_PROGRESS)))
