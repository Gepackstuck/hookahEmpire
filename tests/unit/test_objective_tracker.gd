extends TestCase


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		"busy": false, "friend_ready": true, "friend_id": "friend_denis", "order_known": true,
		"recipe_count": 1, "station_state": HookahStation.STATE_EMPTY, "smoked_once": false,
	}
	ctx.merge(overrides, true)
	return ctx


func test_goal_sequence() -> void:
	assert_eq(ObjectiveTracker.current(_ctx({"friend_ready": false}))["target"], "")
	assert_eq(ObjectiveTracker.current(_ctx({"order_known": false}))["target"], "friend_denis")
	assert_eq(ObjectiveTracker.current(_ctx({"recipe_count": 0}))["target"], "table_test")
	assert_eq(ObjectiveTracker.current(_ctx())["target"], "table_hookah")
	assert_eq(ObjectiveTracker.current(_ctx({"station_state": HookahStation.STATE_LIKED}))["text"], "", "покурить вместе — не задание")
	assert_eq(ObjectiveTracker.current(_ctx({"station_state": HookahStation.STATE_DISLIKED}))["target"], "table_guest")
	assert_eq(ObjectiveTracker.current(_ctx({"station_state": HookahStation.STATE_DISLIKED, "hookah_at_prep": true}))["target"], "table_hookah")


func test_no_goal_when_busy_or_done() -> void:
	assert_eq(ObjectiveTracker.current(_ctx({"busy": true}))["text"], "")
	var done := _ctx({"station_state": HookahStation.STATE_LIKED, "smoked_once": true})
	assert_eq(ObjectiveTracker.current(done)["text"], "")


func test_disabled_interaction_is_not_focused() -> void:
	var system := InteractionSystem.new()
	var data := InteractableData.new()
	data.id = "t"
	data.rect = Rect2(4, 4, 2, 1)
	data.radius = 1.0
	data.enabled = false
	system.register(data)
	system.update_focus(Vector2(4.5, 4.5))
	assert_true(system.focus == null, "отключённый объект не должен получать фокус")
