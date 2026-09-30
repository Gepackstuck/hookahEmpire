class_name ObjectiveTracker
extends RefCounted
## Подсказки "куда идти" для первого заказа: чистая логика без UI.
## Возвращает текст цели и id объекта, над которым показать стрелку ("" — без стрелки).
## Контекст: friend_ready, friend_id, order_known, recipe_count, station_state, smoked_once, busy, hookah_at_prep.


static func current(context: Dictionary) -> Dictionary:
	if bool(context.get("busy", false)):
		return _goal("", "")
	if not bool(context.get("friend_ready", false)):
		return _goal("⏳ Скоро придёт гость…", "")
	if not bool(context.get("order_known", false)):
		return _goal("➡ Поговори с Денисом", str(context.get("friend_id", "")))
	if int(context.get("recipe_count", 0)) == 0:
		return _goal("➡ Смешай рецепт за столом смешивания", "table_test")
	match str(context.get("station_state", HookahStation.STATE_EMPTY)):
		HookahStation.STATE_DISLIKED:
			if bool(context.get("hookah_at_prep", false)):
				return _goal("➡ Перезабей кальян на столе для кальянов", "table_hookah")
			return _goal("➡ Денису не понравилось — забери кальян со стола", "table_guest")
		HookahStation.STATE_LIKED, HookahStation.STATE_PREPARED:
			# Покурить вместе — не задание: игрок сам решает, просить ли разрешения.
			return _goal("", "")
		_:
			return _goal("➡ Забей кальян на столе для кальянов", "table_hookah")


static func _goal(text: String, target: String) -> Dictionary:
	return {"text": text, "target": target}
