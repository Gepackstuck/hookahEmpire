extends TestCase

const GameStateScript := preload("res://scripts/core/game_state.gd")
const SaveServiceScript := preload("res://scripts/core/save_service.gd")


func test_game_state_defaults() -> void:
	var state := GameStateScript.new()
	assert_eq(state.money, GameStateScript.DEFAULT_MONEY)
	assert_eq(state.reputation, GameStateScript.DEFAULT_REPUTATION)
	assert_eq(state.story_progress, GameStateScript.DEFAULT_STORY_PROGRESS)
	state.free()


func test_money_signal_reports_delta() -> void:
	var state := GameStateScript.new()
	var deltas: Array[int] = []
	state.money_changed.connect(func(delta: int) -> void: deltas.append(delta))
	state.set_money(50)
	state.set_money(50) # без изменения — сигнала быть не должно
	state.set_money(20)
	assert_eq(deltas, [50, -30])
	state.free()


func test_reset_to_defaults() -> void:
	var state := GameStateScript.new()
	state.set_money(99)
	state.set_reputation(7)
	state.set_story_progress("heat_intro")
	state.reset_to_defaults()
	var fresh := GameStateScript.new()
	assert_eq(state.to_dict(), fresh.to_dict())
	fresh.free()
	state.free()


func test_save_round_trip() -> void:
	var service := SaveServiceScript.new()
	var source := GameStateScript.new()
	source.set_money(250)
	source.set_reputation(21)
	source.set_story_progress("heat_intro")
	var data := service.build_save_data(source)
	assert_eq(data["save_version"], SaveServiceScript.SAVE_VERSION)

	var target := GameStateScript.new()
	assert_eq(service.apply_save_data(target, data), OK)
	assert_eq(target.to_dict(), source.to_dict())
	source.free()
	target.free()
	service.free()


func test_save_rejects_bad_version() -> void:
	var service := SaveServiceScript.new()
	var state := GameStateScript.new()
	state.set_money(10)
	GameLog.muted = true # ожидаемые ошибки не должны засорять вывод
	assert_eq(service.apply_save_data(state, {"money": 1}), ERR_INVALID_DATA)
	assert_eq(service.apply_save_data(state, {"save_version": 999, "money": 1}), ERR_INVALID_DATA)
	GameLog.muted = false
	assert_eq(state.money, 10, "state не должен меняться при ошибке")
	state.free()
	service.free()


func test_log_format() -> void:
	assert_eq(GameLog.format_message("INFO", "main", "hi"), "[INFO][main] hi")
