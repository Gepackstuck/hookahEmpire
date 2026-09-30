extends TestCase


func _valid() -> Dictionary:
	return {"beats": [{
		"id": "b1", "requires_progress": "intro_start", "delay": 1.5, "action": "spawn_friend",
		"guest": "friend_denis", "entry_position": [0.3, 7.5], "entry_cell": [1, 7], "stand_cell": [9, 9],
		"dialogue": "friend_denis_intro", "sets_progress": "friend_01_arrives",
	}]}


func test_real_beats_valid_and_reference_existing_content() -> void:
	var beats := StoryBeats.load_file("res://data/story/intro_beats.json")
	assert_true(beats.is_valid(), str(beats.errors))
	var beat := beats.find_for_progress("intro_start")
	assert_true(not beat.is_empty())
	# Гость и диалог из бита действительно существуют, а точка остановки проходима.
	GameLog.muted = true
	assert_true(not GuestCatalog.load_guest(beat["guest"]).is_empty(), "нет гостя")
	GameLog.muted = false
	var library := DialogueLibrary.new()
	library.load_directory("res://data/dialogues")
	assert_true(library.has_dialogue(beat["dialogue"]), "нет диалога")
	var layout := GarageLayout.load_file("res://data/garage/garage_main.json")
	var grid := GarageGrid.new(layout.size)
	for object in layout.objects:
		if object["blocks"]:
			grid.set_blocked_rect(Rect2i(object["cell"], object["size"]), true)
	assert_true(not grid.find_path(beat["entry_cell"], beat["stand_cell"]).is_empty(), "друг не дойдёт до точки")


func test_valid_dict_and_lookup() -> void:
	var beats := StoryBeats.from_dict(_valid())
	assert_true(beats.is_valid(), str(beats.errors))
	assert_eq(beats.find_for_progress("intro_start")["delay"], 1.5)
	assert_eq(beats.find_for_progress("other"), {})


func test_rejects_bad_beats() -> void:
	var data := _valid()
	data["beats"][0]["action"] = "teleport"
	assert_true(not StoryBeats.from_dict(data).is_valid())
	data = _valid()
	data["beats"][0]["stand_cell"] = "9,9"
	assert_true(not StoryBeats.from_dict(data).is_valid())
	data = _valid()
	data["beats"][0]["delay"] = -1
	assert_true(not StoryBeats.from_dict(data).is_valid())
	assert_true(not StoryBeats.from_dict({}).is_valid())
