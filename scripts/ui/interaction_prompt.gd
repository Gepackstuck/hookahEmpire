class_name InteractionPrompt
extends PanelContainer
## Подсказка над объектом: клавиша "E" в рамке и название действия.

@onready var _action_label: Label = %ActionLabel


func show_for(action_text: String, anchor_position: Vector2) -> void:
	_action_label.text = action_text
	reset_size()
	position = anchor_position - Vector2(size.x * 0.5, size.y)
	visible = true


func hide_prompt() -> void:
	visible = false
