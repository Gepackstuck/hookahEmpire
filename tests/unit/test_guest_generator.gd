extends TestCase
## Случайные гости: воспроизводимость по id и корректность данных.


func test_same_id_gives_same_guest() -> void:
	var a := GuestGenerator.make("guest_gen_12345")
	var b := GuestGenerator.make("guest_gen_12345")
	assert_true(not a.is_empty())
	assert_eq(str(a["name"]), str(b["name"]))
	assert_eq(str(a["look"]), str(b["look"]))
	assert_eq(str(a["preferences"]), str(b["preferences"]))


func test_ids_are_recognised() -> void:
	assert_true(GuestGenerator.is_generated("guest_gen_77"))
	assert_true(not GuestGenerator.is_generated("friend_lera"))
	assert_true(not GuestGenerator.is_generated("guest_gen_x"))
	assert_true(GuestGenerator.make("friend_denis").is_empty())


func test_generated_guest_has_valid_orders_and_loads_via_catalog() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 20:
		var guest := GuestCatalog.load_guest(GuestGenerator.random_id(rng))
		assert_true(not guest.is_empty(), "гость загружается через каталог")
		assert_true(not str(guest["name"]).is_empty())
		assert_eq((guest["orders"] as Array).size(), 6)
		for order: Dictionary in guest["orders"]:
			assert_true(not str(order["text"]).is_empty())
			assert_true(not (order["preferences"] as Dictionary).is_empty())
		var order := GuestCatalog.roll_order(guest, rng)
		assert_true(order.has("preferences"))


func test_guests_differ() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var looks: Dictionary = {}
	for i in 12:
		looks[str(GuestGenerator.make(GuestGenerator.random_id(rng))["look"])] = true
	assert_true(looks.size() > 6, "внешность разнообразна")
