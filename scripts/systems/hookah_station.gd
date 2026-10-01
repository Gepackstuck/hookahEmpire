class_name HookahStation
extends RefCounted
## Состояние кальяна на столе: пустой -> забит -> гость оценил. Кальян забивается один раз за сессию:
## перезабить недовольному гостю нельзя (M6: он уходит с низкой оплатой; повтор — по плану M7).
## Забитый кальян можно курить (игроку и, если гостю понравилось, ему тоже).

const STATE_EMPTY := "empty"
const STATE_PREPARED := "prepared" # забит, гостя рядом не было
const STATE_LIKED := "liked"
const STATE_DISLIKED := "disliked"

var state: String = STATE_EMPTY
var last_result: Dictionary = {}
## Гость, оценивавший кальян ("" — никого не было).
var guest_id: String = ""
## Эмоция гостя (love/like/okay/…), от неё зависит надпись при курении.
var last_emotion: String = ""


## result — результат PreparationService, verdict — результат SessionScoring.evaluate (пустой, если гостя нет).
func apply_result(result: Dictionary, verdict: Dictionary) -> void:
	last_result = result
	last_emotion = ""
	if verdict.is_empty():
		state = STATE_PREPARED
		guest_id = ""
		return
	guest_id = str(verdict.get("guest_id", ""))
	last_emotion = str(verdict.get("emotion_id", ""))
	state = STATE_LIKED if verdict["likes"] else STATE_DISLIKED


func reset() -> void:
	state = STATE_EMPTY
	last_result = {}
	guest_id = ""
	last_emotion = ""


func can_prepare() -> bool:
	return state == STATE_EMPTY


func can_smoke() -> bool:
	return state == STATE_PREPARED or state == STATE_LIKED


## Курит ли гость (дым из гостя).
func guest_smokes() -> bool:
	return state == STATE_LIKED


func prompt() -> String:
	match state:
		STATE_EMPTY:
			return "Приготовить кальян"
		_:
			return "Покурить"


func action() -> String:
	return "open_preparation" if can_prepare() else "smoke_hookah"


func player_emoji() -> String:
	return "😶‍🌫️" if can_smoke() else ""


func message() -> String:
	if not can_smoke():
		return ""
	match last_emotion:
		"love":
			return "Вау! Густой, ароматный дым — это идеально. 😍"
		"like":
			return "Кальян приятно тянется."
		"okay":
			return "Нормально тянется, но чего-то не хватает."
		_:
			return "Кальян приятно тянется."
