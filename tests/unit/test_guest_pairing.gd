extends TestCase
## M12: схожесть вкусов двух гостей за одним столом.


func test_same_tastes_are_compatible() -> void:
	var a := {"preferences": {"sweet": 1.0}}
	var b := {"preferences": {"sweet": 0.8, "fruit": 0.2}}
	assert_true(GuestPairing.are_compatible(a, b), "похожие вкусы")


func test_different_tastes_are_not() -> void:
	var a := {"preferences": {"sweet": 1.0}}
	var b := {"preferences": {"sour": 1.0}}
	assert_true(not GuestPairing.are_compatible(a, b), "разные вкусы")
	assert_true(GuestPairing.are_compatible(a, {}), "без выраженных вкусов подходит любому")


func test_best_match_picks_closest() -> void:
	var neighbor := {"preferences": {"fresh": 1.0}}
	var candidates: Array[Dictionary] = [{"preferences": {"sweet": 1.0}}, {"preferences": {"fresh": 1.0}}]
	assert_eq(GuestPairing.best_match(neighbor, candidates), 1)
