class_name InteractionPrompt
extends PanelContainer
## Подсказка над объектом: клавиша "E" в рамке и название действия.

## Подсказка в мире рисуется под зумом камеры, поэтому уменьшена вдвое.
const PROMPT_SCALE := 0.5

@onready var _action_label: Label = %ActionLabel


@onready var _key_frame: PanelContainer = $Row/KeyFrame
@onready var _key_label: Label = $Row/KeyFrame/KeyLabel

var _classic_panel: StyleBox
var _classic_key: StyleBox


func _ready() -> void:
	_classic_panel = get_theme_stylebox("panel")
	_classic_key = _key_frame.get_theme_stylebox("panel")
	scale = Vector2(PROMPT_SCALE, PROMPT_SCALE)


func show_for(action_text: String, anchor_position: Vector2) -> void:
	add_theme_stylebox_override("panel", UiStyle.plate_style(_classic_panel, 14, 10.0, 5.0, 1.0))
	_key_frame.add_theme_stylebox_override("panel", UiStyle.key_style(_classic_key))
	_key_label.add_theme_color_override("font_color", Color(0.14, 0.07, 0.1) if VisualStyle.modern else Color(0.98, 0.92, 0.75))
	_action_label.text = action_text
	reset_size()
	position = anchor_position - Vector2(size.x * 0.5, size.y) * PROMPT_SCALE
	visible = true


func hide_prompt() -> void:
	visible = false
