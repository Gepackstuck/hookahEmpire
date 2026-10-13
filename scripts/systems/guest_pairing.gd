class_name GuestPairing
extends RefCounted
## M12: двое за одним столом. Если вкусы похожи — знакомятся, болтают и курят вместе (+респект кальянке).
## Чистая логика: схожесть вкусов двух гостей (косинус по предпочтениям) и реплики знакомства.

const MIN_SIMILARITY := 0.5
## Гость без выраженных вкусов подходит к любому соседу.
const NEUTRAL_SIMILARITY := 0.6
const REPUTATION_BONUS := 2
const CHAT_LINES: Array[String] = [
	"О, ты тоже такое любишь?",
	"Классное место, правда?",
	"Давно куришь кальян?",
	"Мне тут нравится, кальянщик молодец!",
	"Надо будет сюда ещё зайти вдвоём.",
]


## Профиль вкусов гостя: его общие предпочтения плюс средние предпочтения его заказов.
static func taste_profile(guest: Dictionary) -> Dictionary:
	var profile: Dictionary = {}
	var base: Dictionary = guest.get("preferences", {})
	for key in base:
		profile[key] = float(profile.get(key, 0.0)) + float(base[key])
	var orders: Array = guest.get("orders", [])
	for order: Dictionary in orders:
		var prefs: Dictionary = order.get("preferences", {})
		for key in prefs:
			profile[key] = float(profile.get(key, 0.0)) + float(prefs[key]) / float(orders.size())
	return profile


## Схожесть вкусов двух гостей (0..1, косинус по профилям). Если у одного из гостей нет выраженных вкусов,
## он уживается с кем угодно (NEUTRAL_SIMILARITY).
static func similarity(a: Dictionary, b: Dictionary) -> float:
	var pa := taste_profile(a)
	var pb := taste_profile(b)
	if pa.is_empty() or pb.is_empty():
		return NEUTRAL_SIMILARITY
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for key in pa:
		var x := float(pa[key])
		na += x * x
		if pb.has(key):
			dot += x * float(pb[key])
	for key in pb:
		var y := float(pb[key])
		nb += y * y
	if na <= 0.0 or nb <= 0.0:
		return NEUTRAL_SIMILARITY
	return clampf(dot / (sqrt(na) * sqrt(nb)), 0.0, 1.0)


static func are_compatible(a: Dictionary, b: Dictionary) -> bool:
	return similarity(a, b) >= MIN_SIMILARITY


## Из кандидатов выбирает лучшего по схожести с соседом; без соседа — null-значение "".
static func best_match(neighbor: Dictionary, candidates: Array[Dictionary]) -> int:
	var best := -1
	var best_value := -1.0
	for i in candidates.size():
		var value := similarity(neighbor, candidates[i])
		if value > best_value:
			best_value = value
			best = i
	return best
