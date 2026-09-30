class_name MessageToast
extends PanelContainer
## Короткое сообщение внизу экрана, само исчезает.

@onready var _label: Label = %MessageLabel

var _tween: Tween = null


func _ready() -> void:
	visible = false


func show_message(text: String, duration: float = 2.5) -> void:
	_label.text = text
	visible = true
	modulate.a = 1.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(duration)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(hide)
