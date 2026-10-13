class_name GuestGenerator
extends RefCounted
## Случайные гости: после нескольких визитов в кальянную приходят незнакомцы со случайными именем, внешностью и вкусами.
## Гость полностью определяется числом-зерном, закодированным в id ("guest_gen_<seed>"), поэтому его можно
## воссоздать по id в любой момент (загрузка, пара за столом, диван).

const PREFIX := "guest_gen_"
## Шаблон текстов (фразы заказов, реакции, прощания, диалоги курения) — берём у Леры.
const TEMPLATE_ID := "friend_lera"

const MALE_NAMES: Array[String] = [
	"Артём", "Глеб", "Тимур", "Савва", "Руслан", "Костя", "Эмиль", "Игнат", "Фёдор", "Богдан",
	"Влад", "Назар", "Ярик", "Антон", "Лёва", "Платон", "Стас", "Марк", "Роман", "Гоша",
]
const FEMALE_NAMES: Array[String] = [
	"Алиса", "Вика", "Зоя", "Тата", "Мила", "Ника", "Рита", "Соня", "Яна", "Дана",
	"Полина", "Эля", "Катя", "Злата", "Оля", "Кира", "Мира", "Лиза", "Нина", "Ася",
]
const MALE_EMOJI: Array[String] = ["👨", "🧔", "👨‍🦱", "🧑"]
const FEMALE_EMOJI: Array[String] = ["👩", "👩‍🦰", "👱‍♀️", "🧑‍🦱"]
const PERSONALITIES: Array[String] = ["gourmet", "dreamer", "skeptic", "partygoer", "loner", "romantic", "geek"]
const SKIN: Array[String] = ["#f0c9a6", "#e6b68f", "#d9a77a", "#c68b5e", "#a56b43", "#7d4a2d", "#f6d5bd"]
const HAIR: Array[String] = ["#2b1b12", "#4a2e1c", "#7a4a2a", "#b5793a", "#d8b45a", "#a43b2a", "#7a2e5a", "#1f3a5a", "#8d8d94", "#101010"]
const SHIRT: Array[String] = ["#e0556f", "#7a4bd1", "#2fa36b", "#d98a2b", "#3a78c9", "#c9c9d1", "#1f2a44", "#b03a3a", "#4fb3b3", "#a2c43a", "#f2d04a", "#8a5ad6"]
const PANTS: Array[String] = ["#2c3a4f", "#3b4468", "#202020", "#5a4632", "#3d5a3d", "#6a6a74", "#1d2d5a"]
const SHOES: Array[String] = ["#f2f2f2", "#e0e0e0", "#202020", "#8a5a3c", "#b03a3a"]


## id случайного гостя из зерна.
static func id_for(seed_value: int) -> String:
	return "%s%d" % [PREFIX, seed_value]


static func is_generated(guest_id: String) -> bool:
	return guest_id.begins_with(PREFIX) and guest_id.trim_prefix(PREFIX).is_valid_int()


## Новое случайное зерно (id гостя).
static func random_id(rng: RandomNumberGenerator) -> String:
	return id_for(rng.randi_range(100000, 999999999))


## Полное описание гостя в формате data/guests/*.json (пустой словарь, если id не от генератора).
static func make(guest_id: String) -> Dictionary:
	if not is_generated(guest_id):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(guest_id.trim_prefix(PREFIX))
	var female := rng.randf() < 0.5
	var names := FEMALE_NAMES if female else MALE_NAMES
	var emojis := FEMALE_EMOJI if female else MALE_EMOJI
	var template := GuestCatalog.load_guest(TEMPLATE_ID)
	var guest: Dictionary = template.duplicate(true)
	guest["id"] = guest_id
	guest["name"] = names[rng.randi_range(0, names.size() - 1)]
	guest["emoji"] = emojis[rng.randi_range(0, emojis.size() - 1)]
	guest["personality"] = PERSONALITIES[rng.randi_range(0, PERSONALITIES.size() - 1)]
	guest["sprite_faces"] = "left" if rng.randf() < 0.5 else "right"
	guest["look"] = {
		"skin": SKIN[rng.randi_range(0, SKIN.size() - 1)],
		"hair": HAIR[rng.randi_range(0, HAIR.size() - 1)],
		"shirt": SHIRT[rng.randi_range(0, SHIRT.size() - 1)],
		"pants": PANTS[rng.randi_range(0, PANTS.size() - 1)],
		"shoes": SHOES[rng.randi_range(0, SHOES.size() - 1)],
	}
	guest["smoke_permission_chance"] = snappedf(rng.randf_range(0.4, 0.95), 0.05)
	# Вкусы: любимое измерение (и иногда второе), заказы крутятся вокруг них.
	var dims: Array[String] = []
	for dimension in IngredientCatalog.DIMENSIONS:
		dims.append(dimension)
	var favorite := dims[rng.randi_range(0, dims.size() - 1)]
	dims.erase(favorite)
	var preferences := {favorite: 1.0}
	var second := ""
	if rng.randf() < 0.55:
		second = dims[rng.randi_range(0, dims.size() - 1)]
		preferences[second] = snappedf(rng.randf_range(0.3, 0.6), 0.1)
	guest["preferences"] = preferences
	guest["orders"] = _make_orders(guest.get("random_taste", {}), favorite, second, rng)
	guest.erase("random_taste")
	return guest


static func _make_orders(taste: Dictionary, favorite: String, second: String, rng: RandomNumberGenerator) -> Array:
	var phrases: Dictionary = taste.get("phrases", {})
	var also: Dictionary = taste.get("also_phrases", {})
	var orders: Array = []
	var dims: Array[String] = []
	for dimension in IngredientCatalog.DIMENSIONS:
		dims.append(dimension)
	for i in 6:
		# Чаще всего просит своё любимое, иногда — настроение «на что-нибудь другое».
		var primary := favorite
		if i >= 3 or (i == 2 and second != ""):
			primary = second if (i == 2 and second != "") else dims[rng.randi_range(0, dims.size() - 1)]
		var prefs := {primary: 1.0}
		var text := str(phrases.get(primary, "Сделай мне кальян на свой вкус."))
		var extra := favorite if primary != favorite else second
		if extra != "" and extra != primary and rng.randf() < 0.6:
			prefs[extra] = 0.5
			text += " " + str(also.get(extra, ""))
		orders.append({"id": "%s_%d" % [primary, i], "text": text.strip_edges(), "preferences": prefs})
	return orders
