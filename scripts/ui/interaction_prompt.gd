class_name InteractionPrompt
extends PanelContainer
## Подсказка над объектом: клавиша "E" в рамке и название действия.

## Подсказка в мире рисуется под зумом камеры, поэтому уменьшена вдвое.
const PROMPT_SCALE := 0.5

@onready var _action_label: Label = %ActionLabel


func _ready() -> void:
	scale = Vector2(PROMPT_SCALE, PROMPT_SCALE)


func show_for(action_text: String, anchor_position: Vector2) -> void:
	_action_label.text = action_text
	reset_size()
	position = anchor_position - Vector2(size.x * 0.5, size.y) * PROMPT_SCALE
	visible = true


func hide_prompt() -> void:
	visible = false
