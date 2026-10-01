class_name HeadLabels
extends Node2D
## Надписи над головой персонажа в режиме «NPC»: реплика-облачко и ряд эмодзи-чипов (вкусы).
## Чипы светятся (want), зеленеют (match) и краснеют (miss), см. TasteIcons.

const HEAD_Y := -86.0
const SPEECH_WIDTH := 120.0
const CHIP_COLORS := {
	"want": Color(1.0, 0.88, 0.4, 0.5),
	"match": Color(0.3, 0.85, 0.4, 0.8),
	"miss": Color(0.92, 0.3, 0.3, 0.8),
	"pick": Color(1.0, 1.0, 1.0, 0.3),
}

var _speech: PanelContainer
var _speech_label: Label
var _speech_emoji: Label
var _speech_left: float = 0.0
var _chips: HBoxContainer
var _chip_count: int = 0
var _pulse: bool = false
var _time: float = 0.0


func _ready() -> void:
	z_index = 20
	_speech = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.055, 0.045, 0.93)
	box.border_color = Color(0.96, 0.85, 0.55, 1)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 5.0
	box.content_margin_right = 5.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	_speech.add_theme_stylebox_override("panel", box)
	_speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech.visible = false
	_speech_label = Label.new()
	_speech_label.custom_minimum_size = Vector2(SPEECH_WIDTH, 0.0)
	_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech_label.add_theme_font_size_override("font_size", 10)
	_speech_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))
	_speech_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_emoji = Label.new()
	_speech_emoji.add_theme_font_size_override("font_size", 12)
	_speech_emoji.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_emoji.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_speech_emoji)
	row.add_child(_speech_label)
	_speech.add_child(row)
	add_child(_speech)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 3)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.visible = false
	add_child(_chips)


## Сколько секунд держать реплику (чем длиннее текст, тем дольше).
static func duration_for(text: String) -> float:
	return clampf(1.6 + 0.045 * float(text.length()), 1.8, 7.0)


## Реплика над головой; возвращает, сколько секунд она будет видна.
## emoji — маленькая реакция внутри рамки рядом с текстом (без текста — только эмодзи).
func say(text: String, seconds: float = -1.0, emoji: String = "") -> float:
	var duration := seconds if seconds > 0.0 else duration_for(text)
	_speech_emoji.text = emoji
	_speech_emoji.visible = not emoji.is_empty()
	_speech_label.text = text
	_speech_label.visible = not text.is_empty()
	_speech.reset_size()
	_speech.visible = true
	_speech_left = duration
	return duration


func clear_speech() -> void:
	_speech.visible = false
	_speech_left = 0.0


func is_speaking() -> bool:
	return _speech.visible


## chips: [{"emoji": String, "state": "want"|"match"|"miss"|"pick"}].
func set_chips(chips: Array) -> void:
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	_pulse = false
	_chip_count = chips.size()
	for chip in chips:
		var state := str(chip.get("state", "want"))
		if state == "want":
			_pulse = true
		_chips.add_child(_make_chip(str(chip["emoji"]), CHIP_COLORS.get(state, CHIP_COLORS["want"])))
	_chips.visible = _chip_count > 0
	_chips.reset_size()


func clear_chips() -> void:
	set_chips([])


func chip_count() -> int:
	return _chip_count


func clear_all() -> void:
	clear_chips()
	_speech.visible = false
	_speech_left = 0.0


func _make_chip(emoji: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color(color.r, color.g, color.b, 1.0)
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.content_margin_left = 3.0
	box.content_margin_right = 3.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = emoji
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


func _process(delta: float) -> void:
	_time += delta
	if _speech.visible:
		_speech_left -= delta
		if _speech_left <= 0.0:
			_speech.visible = false
	var chips_top := HEAD_Y
	if _chips.visible:
		_chips.position = Vector2(-_chips.size.x * 0.5, HEAD_Y - _chips.size.y)
		chips_top = HEAD_Y - _chips.size.y
		_chips.modulate.a = 0.75 + 0.25 * sin(_time * 4.0) if _pulse else 1.0
	if _speech.visible:
		_speech.position = Vector2(-_speech.size.x * 0.5, chips_top - 4.0 - _speech.size.y)
