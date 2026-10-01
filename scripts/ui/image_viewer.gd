class_name ImageViewer
extends Control
## Просмотр картинки на весь экран (маски и книги на полке): клик или Esc закрывают.

signal closed

var _dim: ColorRect
var _picture: TextureRect
var _title: Label
var _hint: Label
var _description: Label
var _time := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.82)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	_picture.anchor_left = 0.1
	_picture.anchor_right = 0.9
	_picture.anchor_top = 0.1
	_picture.anchor_bottom = 0.82
	_picture.offset_left = 0.0
	_picture.offset_right = 0.0
	_picture.offset_top = 0.0
	_picture.offset_bottom = 0.0
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 24.0
	_title.offset_bottom = 70.0
	_description = Label.new()
	_description.add_theme_font_size_override("font_size", 20)
	# Курсив: наклон шрифта по умолчанию (отдельного italic-шрифта в проекте нет).
	var italic := FontVariation.new()
	italic.base_font = ThemeDB.fallback_font
	italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
	_description.add_theme_font_override("font", italic)
	_description.add_theme_constant_override("outline_size", 6)
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_description)
	_description.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_description.offset_top = -92.0
	_description.offset_bottom = -52.0
	_hint = Label.new()
	_hint.text = "Клик или Esc — закрыть"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.modulate = Color(1, 1, 1, 0.65)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -44.0
	_hint.offset_bottom = -12.0


func open(path: String, title: String = "", description: String = "") -> bool:
	var texture := load_texture(path)
	if texture == null:
		return false
	_picture.texture = texture
	_title.text = title
	_description.text = description
	_description.visible = description != ""
	visible = true
	return true


## Описание мигает золотым светом: цвет текста и мягкое свечение вокруг пульсируют.
func _process(delta: float) -> void:
	if not visible or not _description.visible:
		return
	_time += delta
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	_description.add_theme_color_override("font_color", Color("#c9993a").lerp(Color("#ffe58a"), pulse))
	_description.add_theme_color_override("font_outline_color", Color(1.0, 0.78, 0.25, 0.1 + 0.4 * pulse))


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Загружает PNG: через импорт Godot, а если файл ещё не импортирован — напрямую с диска.
static func load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)
