class_name DialogueBox
extends Control
## Окно диалога: портрет и имя говорящего, текст "по буквам", кнопки выбора.
## Ничего не знает про сюжет: получает узлы от DialogueRunner (через Main) и шлёт сигналы.
## Управление: E / Пробел / Enter — пропустить печать и идти дальше; 1–9 или мышь — выбор.

signal advance_requested
signal choice_selected(index: int)

const CHARS_PER_SECOND := 45.0

var _speakers: Dictionary = {}
var _choices: Array = []
var _chars: float = 0.0
var _typing := false
var _choices_visible := false
var _opened_frame := -1

@onready var _portrait: Label = %PortraitLabel
@onready var _name_label: Label = %NameLabel
@onready var _text_label: Label = %TextLabel
@onready var _choices_box: VBoxContainer = %ChoicesBox
@onready var _hint: Label = %HintLabel


func _ready() -> void:
	visible = false


## speakers: {speaker_id: {"name", "portrait"}} из файла диалога.
func open(speakers: Dictionary) -> void:
	_speakers = speakers
	_opened_frame = Engine.get_process_frames()
	visible = true


func close() -> void:
	visible = false
	_typing = false
	_choices_visible = false
	_clear_choices()


func show_node(node: Dictionary, choices: Array) -> void:
	var speaker: Dictionary = _speakers.get(str(node.get("speaker", "")), {})
	_portrait.text = str(speaker.get("portrait", "❓"))
	_name_label.text = str(speaker.get("name", "???"))
	_text_label.text = str(node.get("text", ""))
	_text_label.visible_characters = 0
	_chars = 0.0
	_typing = true
	_choices = choices
	_choices_visible = false
	_hint.visible = false
	_clear_choices()


func finish_typing() -> void:
	_chars = float(_text_label.text.length())
	_text_label.visible_characters = -1
	_typing = false
	if _choices.is_empty():
		_hint.text = "E / Пробел — дальше"
		_hint.visible = true
	else:
		_build_choice_buttons()


func _process(delta: float) -> void:
	if not visible or not _typing:
		return
	_chars += CHARS_PER_SECOND * delta
	if _chars >= float(_text_label.text.length()):
		finish_typing()
	else:
		_text_label.visible_characters = int(_chars)


func _unhandled_input(event: InputEvent) -> void:
	# Нажатие E, открывшее диалог, не должно сразу же его пролистнуть.
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _typing:
			finish_typing()
		elif _choices.is_empty():
			advance_requested.emit()
		return
	if _choices_visible and event is InputEventKey and event.pressed and not event.echo:
		var index: int = event.physical_keycode - KEY_1
		if index >= 0 and index < _choices.size():
			get_viewport().set_input_as_handled()
			_pick(index)


func _build_choice_buttons() -> void:
	for index in _choices.size():
		var button := Button.new()
		button.text = "%d. %s" % [index + 1, str(_choices[index]["text"])]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE # иначе Пробел нажимал бы сфокусированную кнопку
		button.add_theme_font_size_override("font_size", 26)
		button.pressed.connect(_pick.bind(index))
		_choices_box.add_child(button)
	_choices_visible = true


func _pick(index: int) -> void:
	if not _choices_visible:
		return
	_choices_visible = false
	choice_selected.emit(index)


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()
