class_name VisualStyle
extends RefCounted
## Вид графики: классический (как раньше) или новый (мягкие безликие гости, тёплый пол и стены, свет).
## Флаг общий для всей игры; переключается в настройках и запоминается (SaveService.save_setting).

const SETTING_KEY := "modern_graphics"
## Цвет безликих гостей нового вида.
const GUEST_BLOB := Color("#f2992e")

## Цвета безликих гостей: у каждого свой, по id гостя.
const BLOB_COLORS: Array[Color] = [
	Color("#f2992e"), Color("#e86a5a"), Color("#4fb3a8"), Color("#8f7be0"),
	Color("#8fbf3f"), Color("#e8c13c"), Color("#4f9be0"), Color("#e07bb0"),
]

const NAMES_KEY := "show_friend_names"

static var modern := false
## Имена над головами друзей (только в новом виде).
static var show_names := true


static func blob_color_for(guest_id: String) -> Color:
	return BLOB_COLORS[absi(guest_id.hash()) % BLOB_COLORS.size()]


static func set_show_names(value: bool) -> void:
	show_names = value


static func set_modern(value: bool) -> void:
	modern = value


static var _soft_disc: GradientTexture2D


## Общая мягкая радиальная текстура (белая, края прозрачные): вместо стопки полупрозрачных кругов — один вызов отрисовки.
static func soft_disc() -> GradientTexture2D:
	if _soft_disc == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
		_soft_disc = GradientTexture2D.new()
		_soft_disc.gradient = gradient
		_soft_disc.fill = GradientTexture2D.FILL_RADIAL
		_soft_disc.fill_from = Vector2(0.5, 0.5)
		_soft_disc.fill_to = Vector2(1.0, 0.5)
		_soft_disc.width = 64
		_soft_disc.height = 64
	return _soft_disc
