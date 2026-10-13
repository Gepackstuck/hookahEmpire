class_name MessageToast
extends PanelContainer
## Короткое сообщение внизу экрана, само исчезает.

@onready var _label: Label = %MessageLabel

var _tween: Tween = null


var _classic: StyleBox


func _ready() -> void:
	_classic = get_theme_stylebox("panel")
	visible = false


func show_message(text: String, duration: float = 2.5) -> void:
	add_theme_stylebox_override("panel", UiStyle.plate_style(_classic, 18, 22.0, 10.0))
	_label.text = text
	visible = true
	modulate.a = 1.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(duration)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(hide)
