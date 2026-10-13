extends TestCase
## Новый вид графики: переключатель, безликие гости и выделенные друзья.


func test_default_is_classic() -> void:
	assert_true(not VisualStyle.modern, "по умолчанию — классический вид")


func test_generic_guest_is_blob_only_in_modern() -> void:
	var figure := CharacterFigure.make("denis")
	figure.generic = true
	figure.apply_look({"skin": "#112233", "shirt": "#445566"})
	VisualStyle.set_modern(false)
	assert_true(not figure._blob(), "классика: не болванчик")
	VisualStyle.set_modern(true)
	assert_true(figure._blob(), "новый вид: безликий")
	figure._sync_palette()
	assert_eq(figure.skin, VisualStyle.GUEST_BLOB)
	VisualStyle.set_modern(false)
	figure._sync_palette()
	assert_eq(figure.skin, Color("#112233"))
	figure.free()


func test_friend_keeps_look_in_modern() -> void:
	var figure := CharacterFigure.make("denis")
	figure.generic = false
	figure.apply_look({"shirt": "#445566"})
	VisualStyle.set_modern(true)
	assert_true(not figure._blob(), "друг остаётся со своей внешностью")
	VisualStyle.set_modern(false)
	figure.free()
