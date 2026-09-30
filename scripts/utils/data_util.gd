class_name DataUtil
extends RefCounted
## Общие помощники для разбора JSON-данных.


## [x, y] из JSON -> Vector2, иначе null.
static func vec2(value: Variant) -> Variant:
	if value is Array and value.size() == 2:
		var x: Variant = value[0]
		var y: Variant = value[1]
		if (x is int or x is float) and (y is int or y is float):
			return Vector2(float(x), float(y))
	return null
