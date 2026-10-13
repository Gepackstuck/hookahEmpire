extends TestCase
## M12: логика одновременных гостей — допуск второго гостя и терпение гостя без места.


func test_default_config_loads() -> void:
	var scheduler := VisitScheduler.load_default()
	assert_eq(scheduler.errors.size(), 0, "конфиг visits.json без ошибок")
	assert_eq(scheduler.max_guests, 3)
	assert_true(scheduler.wait_seconds > 0.0)
	assert_true(scheduler.angry_reputation < 0, "уход рассерженным снижает репутацию")


func test_bad_config_is_reported_and_fixed() -> void:
	var scheduler := VisitScheduler.from_dict({"max_guests": 0, "wait_seconds": -5, "second_guest_delay_seconds": [30, 10]})
	assert_true(scheduler.errors.size() >= 3)
	assert_eq(scheduler.max_guests, 1)
	assert_true(scheduler.wait_seconds > 0.0)
	assert_true(float(scheduler.delay_range[0]) <= float(scheduler.delay_range[1]))


func test_admission_needs_goal_and_free_slot() -> void:
	var scheduler := VisitScheduler.from_dict({"max_guests": 2})
	assert_true(not scheduler.can_admit(false, 1), "пока цель не выполнена, второго гостя нет")
	assert_true(scheduler.can_admit(true, 1), "цель выполнена и слот свободен")
	assert_true(not scheduler.can_admit(true, 2), "слотов больше нет")


func test_arrival_timer_fires_once_after_delay() -> void:
	var scheduler := VisitScheduler.from_dict({"second_guest_delay_seconds": [10, 10]})
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_true(not scheduler.tick_arrival(1.0, true, rng), "первый тик только запускает таймер")
	assert_true(scheduler.arrival_timer_running())
	assert_true(not scheduler.tick_arrival(9.0, true, rng))
	assert_true(scheduler.tick_arrival(1.5, true, rng), "через 10 секунд гость приходит")
	assert_true(not scheduler.arrival_timer_running(), "после прихода таймер сброшен")
	scheduler.tick_arrival(1.0, true, rng)
	assert_true(not scheduler.tick_arrival(1.0, false, rng), "если впускать нельзя — таймер сброшен")
	assert_true(not scheduler.arrival_timer_running())


func test_waiting_guest_leaves_angry_when_patience_runs_out() -> void:
	var scheduler := VisitScheduler.from_dict({"wait_seconds": 20})
	scheduler.start_waiting("friend_lera")
	assert_true(scheduler.is_waiting("friend_lera"))
	assert_eq(scheduler.tick_waiting(15.0).size(), 0, "ещё терпит")
	assert_true(absf(scheduler.seconds_left("friend_lera") - 5.0) < 0.01)
	var gone := scheduler.tick_waiting(6.0)
	assert_eq(gone, ["friend_lera"] as Array[String], "терпение кончилось — уходит")
	assert_true(not scheduler.is_waiting("friend_lera"), "после ухода больше не ждёт")


func test_found_seat_cancels_waiting() -> void:
	var scheduler := VisitScheduler.from_dict({"wait_seconds": 20})
	scheduler.start_waiting("friend_lera")
	scheduler.tick_waiting(10.0)
	scheduler.seat_found("friend_lera")
	assert_eq(scheduler.tick_waiting(100.0).size(), 0, "место нашлось — не уходит")


func test_two_guests_wait_independently() -> void:
	var scheduler := VisitScheduler.from_dict({"wait_seconds": 10})
	scheduler.start_waiting("a")
	scheduler.tick_waiting(6.0)
	scheduler.start_waiting("b")
	var gone := scheduler.tick_waiting(5.0)
	assert_eq(gone, ["a"] as Array[String])
	assert_true(scheduler.is_waiting("b"))
	scheduler.forget("b")
	assert_eq(scheduler.waiting_ids().size(), 0)


func test_guest_visit_state_is_independent_per_guest() -> void:
	var first := GuestVisit.create("friend_denis")
	var second := GuestVisit.create("friend_lera")
	first.order = {"text": "кисленькое"}
	first.redo_used = true
	first.station.state = HookahStation.STATE_LIKED
	assert_true(second.order.is_empty(), "заказ второго гостя не зависит от первого")
	assert_true(not second.redo_used)
	assert_true(second.station.can_prepare(), "у второго гостя свой пустой кальян")
	assert_true(first.heat != second.heat, "у каждого гостя своя модель жара")
	first.departing = true
	assert_true(not first.is_active() and second.is_active())
	first.clear_after_departure()
	assert_eq(first.guest_id, "")
	assert_true(first.station.can_prepare() and first.order.is_empty())


func test_growth_raises_limit_and_shortens_delay() -> void:
	var scheduler := VisitScheduler.from_dict({"max_guests": 3, "second_guest_delay_seconds": [12, 25],
		"growth": [{"sessions": 7, "max_guests": 5, "delay": [8, 16]}, {"sessions": 14, "max_guests": 7, "delay": [6, 12]}]})
	assert_eq(scheduler.errors.size(), 0)
	assert_eq(scheduler.apply_progress(3), 0)
	assert_eq(scheduler.max_guests, 3)
	assert_eq(scheduler.apply_progress(7), 1)
	assert_eq(scheduler.max_guests, 5)
	assert_eq(float(scheduler.delay_range[0]), 8.0)
	assert_eq(scheduler.apply_progress(20), 2)
	assert_eq(scheduler.max_guests, 7)
	assert_eq(scheduler.apply_progress(0), 0)
	assert_eq(scheduler.max_guests, 3)
