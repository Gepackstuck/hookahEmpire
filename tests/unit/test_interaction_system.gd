extends TestCase


func _make_item(item_id: String, rect: Rect2, radius: float = 1.0) -> InteractableData:
	var data := InteractableData.new()
	data.id = item_id
	data.rect = rect
	data.radius = radius
	return data


func test_distance_to_rect() -> void:
	var data := _make_item("t", Rect2(4, 4, 2, 1))
	assert_eq(data.distance_to(Vector2(5, 4.5)), 0.0, "внутри")
	assert_true(is_equal_approx(data.distance_to(Vector2(3, 4.5)), 1.0))
	assert_true(is_equal_approx(data.distance_to(Vector2(7, 6)), sqrt(2.0)))


func test_focus_changes_with_distance() -> void:
	var system := InteractionSystem.new()
	system.register(_make_item("table", Rect2(4, 4, 2, 1)))
	var focus_ids: Array[String] = []
	system.focus_changed.connect(func(data: InteractableData) -> void: focus_ids.append(data.id if data != null else ""))
	system.update_focus(Vector2(1, 1)) # далеко
	system.update_focus(Vector2(4.5, 5.6)) # рядом
	system.update_focus(Vector2(4.6, 5.7)) # всё ещё рядом — сигнала нет
	system.update_focus(Vector2(9, 9)) # ушёл
	assert_eq(focus_ids, ["table", ""])


func test_picks_nearest() -> void:
	var system := InteractionSystem.new()
	system.register(_make_item("far", Rect2(6, 4, 1, 1), 2.0))
	system.register(_make_item("near", Rect2(4, 4, 1, 1), 2.0))
	system.update_focus(Vector2(4.5, 5.2))
	assert_eq(system.focus.id, "near")


func test_interact_emits_only_with_focus() -> void:
	var system := InteractionSystem.new()
	system.register(_make_item("hookah", Rect2(4, 4, 1, 1)))
	var fired: Array[String] = []
	system.player_interacted.connect(func(interactable_id: String) -> void: fired.append(interactable_id))
	assert_true(not system.interact(), "без фокуса взаимодействовать не с чем")
	system.update_focus(Vector2(4.5, 5.3))
	assert_true(system.interact())
	assert_eq(fired, ["hookah"])


func test_focus_hysteresis_prevents_flicker() -> void:
	var system := InteractionSystem.new()
	system.register(_make_item("a", Rect2(0, 0, 1, 1), 1.0))
	system.register(_make_item("b", Rect2(2, 0, 1, 1), 1.0))
	system.update_focus(Vector2(0.9, 0.5))
	assert_eq(system.focus.id, "a")
	# Середина между объектами: b чуть ближе, но разница меньше запаса — фокус остаётся на a.
	system.update_focus(Vector2(1.55, 0.5))
	assert_eq(system.focus.id, "a")
	# Заметно ближе к b — фокус переключается.
	system.update_focus(Vector2(1.9, 0.5))
	assert_eq(system.focus.id, "b")
