class_name TrendSystem
extends RefCounted
## M8: тренды. Текущий тренд меняется по авторской ротации каждые duration_sessions визитов гостей.
## Определения трендов (веса вкусов) лежат в SessionScoring (session_scoring.json), здесь — только расписание.
## Тренд влияет на TrendFit через SessionScoring.trend_current. Чистая логика без UI.

signal trend_changed(trend_id: String)

const CONFIG_PATH := "res://data/config/trends.json"

var errors: Array[String] = []
var rotation: Array[String] = []
var duration_sessions: int = 3
var current_id: String = ""
## Сколько визитов гостей осталось до смены.
var visits_left: int = 3
## Сколько раз тренд менялся за запуск (статистика).
var changes: int = 0

var _scoring: SessionScoring = null


static func load_default(scoring: SessionScoring) -> TrendSystem:
	var system := TrendSystem.new()
	if not FileAccess.file_exists(CONFIG_PATH):
		system.errors.append("Файл не найден: %s" % CONFIG_PATH)
		return system
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		system.errors.append("%s: не JSON-объект" % CONFIG_PATH)
		return system
	system._setup(parsed, scoring)
	return system


static func from_dict(data: Dictionary, scoring: SessionScoring) -> TrendSystem:
	var system := TrendSystem.new()
	system._setup(data, scoring)
	return system


func is_valid() -> bool:
	return errors.is_empty()


func current_name() -> String:
	return _scoring.trend_name(current_id) if _scoring != null else ""


func name_of(trend_id: String) -> String:
	return _scoring.trend_name(trend_id) if _scoring != null else ""


## Тренд, который наступит после текущего.
func next_id() -> String:
	if rotation.is_empty():
		return current_id
	var index := rotation.find(current_id)
	return rotation[(index + 1) % rotation.size()]


## Прошёл визит гостя. true — тренд сменился.
func advance_visit() -> bool:
	visits_left -= 1
	if visits_left > 0:
		return false
	set_trend(next_id())
	return true


## Принудительно ставит тренд (кнопка теста, загрузка сохранения). Отсчёт визитов начинается заново.
func set_trend(trend_id: String) -> bool:
	if _scoring == null or not _scoring.trends.has(trend_id):
		return false
	var changed := trend_id != current_id
	current_id = trend_id
	visits_left = duration_sessions
	_scoring.trend_current = trend_id
	if changed:
		changes += 1
		trend_changed.emit(trend_id)
	return true


## Восстановление из сохранения (без счётчика смен и сигнала).
func restore(trend_id: String, left: int) -> void:
	if _scoring == null or not _scoring.trends.has(trend_id):
		return
	current_id = trend_id
	visits_left = clampi(left, 1, duration_sessions)
	_scoring.trend_current = trend_id


## TrendFit рецепта (вкусовой профиль) под указанным или текущим трендом.
func trend_fit(profile: Dictionary, trend_id: String = "") -> float:
	return _scoring.trend_fit(profile, trend_id if not trend_id.is_empty() else current_id) if _scoring != null else 50.0


func _setup(data: Dictionary, scoring: SessionScoring) -> void:
	_scoring = scoring
	if scoring == null:
		errors.append("trends: нет SessionScoring")
		return
	var raw_duration: Variant = data.get("duration_sessions", duration_sessions)
	if not (raw_duration is int or raw_duration is float) or int(raw_duration) < 1:
		errors.append("trends: duration_sessions должен быть числом >= 1")
	else:
		duration_sessions = int(raw_duration)
	var raw_rotation: Variant = data.get("rotation")
	if not (raw_rotation is Array) or raw_rotation.size() < 2:
		errors.append("trends: rotation должен быть массивом минимум из 2 трендов")
		return
	for entry in raw_rotation:
		var id := str(entry)
		if not scoring.trends.has(id):
			errors.append("trends: тренд '%s' из rotation не описан в session_scoring.json" % id)
		elif rotation.has(id):
			errors.append("trends: тренд '%s' повторяется в rotation" % id)
		else:
			rotation.append(id)
	var start := str(data.get("start", rotation[0] if not rotation.is_empty() else ""))
	if not rotation.has(start):
		errors.append("trends: start '%s' должен быть в rotation" % start)
		return
	if errors.is_empty():
		set_trend(start)
		changes = 0
