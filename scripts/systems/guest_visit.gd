class_name GuestVisit
extends RefCounted
## Состояние визита одного гостя: заказ, кальян на его столе, жар и перезабивка.
## До этого всё лежало отдельными полями в main.gd (гость был один). Теперь каждый гость — свой объект,
## чтобы одновременно обслуживать двух гостей (у каждого свой заказ, кальян, жар и таймеры).

## Место, за которым идёт этот визит ("s1" — основной стол, "s2" — второй стол из мебели).
var station_id := "s1"
## Кто это ("" — визит пуст).
var guest_id := ""
## Заказ гостя (предпочтения, антипредпочтения, текст).
var order: Dictionary = {}
## Кальян на столе гостя.
var station := HookahStation.new()
## M7: жар кальяна (у каждого гостя свой счётчик).
var heat: HeatModel = null
var heat_active := false
## Меняется при перезабивке: старый цикл курения видит, что токен устарел, и выходит.
var session_token := 0
var session_puffs := 0
var pace_timer := 0.0
var complaint_timer := 0.0
var npc_service_pending := false
var servicing := false
var redoing := false
var redo_requested := false
var redo_used := false
var redo_timer := 0.0
var service_penalty := 0.0
var pending_verdict: Dictionary = {}
## Последняя оценка кальяна гостем — чтобы он мог высказаться и при обычном разговоре.
var last_verdict: Dictionary = {}
## Гость разрешил покурить вместе (сбрасывается при каждой новой подаче).
var smoke_permission := false
## После отказа просить снова можно только через несколько затяжек гостя.
var ask_blocked := false
var puffs_until_ask := 0
## Гость попрощался и уходит: стол и кальян недоступны.
var departing := false
## Кальян приготовлен и ждёт, пока его отнесут гостю.
var pending_serve := false
## Стоимость ингредиентов, которая спишется при подаче.
var pending_cost := 0
## Метки времени ожидания гостя (игровые секунды, -1 — ещё не было): сел, заказ принят, кальян подан.
var ready_at := -1.0
var order_at := -1.0
var served_at := -1.0
## Бэн уже помогал с этим заказом (его оплата за заказ списана).
var ben_helped := false
## Кто сейчас готовит кальян этому гостю ("" — никто, "master" — кальянщик, "ben" — Бэн).
var cooking_by := ""


## Новый визит со своей моделью жара (из data/config/heat.json). Ошибки загрузки жара — в heat.errors.
static func create(for_guest_id: String = "") -> GuestVisit:
	var visit := GuestVisit.new()
	visit.guest_id = for_guest_id
	visit.heat = HeatModel.load_default()
	return visit


## Гость ещё в гараже и кальян можно готовить/подавать.
func is_active() -> bool:
	return guest_id != "" and not departing


## Сброс после ухода гостя (токен и жар сохраняются: модель переиспользуется следующим гостем).
func clear_after_departure() -> void:
	order = {}
	station.reset()
	last_verdict = {}
	pending_verdict = {}
	smoke_permission = false
	ask_blocked = false
	puffs_until_ask = 0
	redo_requested = false
	redo_used = false
	redoing = false
	servicing = false
	service_penalty = 0.0
	npc_service_pending = false
	heat_active = false
	pending_serve = false
	pending_cost = 0
	ben_helped = false
	cooking_by = ""
	ready_at = -1.0
	order_at = -1.0
	served_at = -1.0
	departing = false
	guest_id = ""
