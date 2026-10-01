class_name SessionSummaryScreen
extends Control
## Карточка итогов гостевой сессии (M6): оценка, полоса удовлетворения, из чего она сложилась,
## фраза гостя, оплата и кнопка «Дальше». Экран только показывает уже посчитанные данные.

signal continued

const SCORE_COLORS := {
	"love": Color(0.55, 0.95, 0.6, 1),
	"like": Color(0.7, 0.92, 0.55, 1),
	"okay": Color(0.96, 0.85, 0.55, 1),
	"meh": Color(1.0, 0.7, 0.4, 1),
	"dislike": Color(1.0, 0.5, 0.45, 1),
}

var _column: VBoxContainer
var _guest_label: Label
var _recipe_label: Label
var _composition_label: Label
var _score_label: Label
var _band_label: Label
var _bar: ProgressBar
var _grid: GridContainer
var _phrase_label: Label
var _payment_label: Label
var _next_button: Button


func _ready() -> void:
	visible = false
	_build()


## Строки разбора для карточки: [название, значение, вес или ""] — отдельно от UI, чтобы тестировать.
static func breakdown_rows(verdict: Dictionary, weights: Dictionary) -> Array[Array]:
	var rows: Array[Array] = []
	rows.append(["Качество рецепта", "%.1f" % float(verdict["recipe_quality"]), _percent(weights.get("recipe_quality", 0.0))])
	rows.append(["Вкус гостя", "%.1f" % float(verdict["guest_fit"]), _percent(weights.get("guest_fit", 0.0))])
	var trend_title := "Тренд"
	if not str(verdict.get("trend_name", "")).is_empty():
		trend_title = "Тренд: %s" % str(verdict["trend_name"])
	rows.append([trend_title, "%.1f" % float(verdict["trend_fit"]), _percent(weights.get("trend_fit", 0.0))])
	rows.append(["Исполнение", "%.1f" % float(verdict["execution"]), _percent(weights.get("execution", 0.0))])
	if float(verdict.get("heat_penalty", 0.0)) > 0.0:
		rows.append(["Штраф за жар", "−%.1f" % float(verdict["heat_penalty"]), ""])
	if float(verdict.get("service_penalty", 0.0)) > 0.0:
		rows.append(["Штраф за сервис", "−%.1f" % float(verdict["service_penalty"]), ""])
	return rows


static func _percent(weight: Variant) -> String:
	return "×%d%%" % int(round(float(weight) * 100.0))


## summary: {"guest_name", "guest_emoji", "recipe_name", "composition", "verdict", "phrase", "weights"}.
func open(summary: Dictionary) -> void:
	if _column == null:
		_build()
	var verdict: Dictionary = summary["verdict"]
	_guest_label.text = "%s %s" % [str(summary.get("guest_emoji", "")), str(summary["guest_name"])]
	_recipe_label.text = "Кальян: %s" % str(summary["recipe_name"])
	_composition_label.text = str(summary.get("composition", ""))
	var band_id := str(verdict["band_id"])
	var color: Color = SCORE_COLORS.get(band_id, Color.WHITE)
	_score_label.text = "%.1f" % float(verdict["final_score"])
	_score_label.add_theme_color_override("font_color", color)
	_band_label.text = "%s %s" % [str(verdict["emoji"]), str(verdict["band_name"])]
	_band_label.add_theme_color_override("font_color", color)
	_bar.value = float(verdict["final_score"])
	for child in _grid.get_children():
		child.queue_free()
	for row in breakdown_rows(verdict, summary.get("weights", {})):
		_grid.add_child(UiStyle.label(str(row[0]), 22, UiStyle.MUTED))
		var value := UiStyle.label(str(row[1]), 22)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(value)
		_grid.add_child(UiStyle.label(str(row[2]), 20, UiStyle.MUTED))
	_phrase_label.text = "«%s»" % str(summary.get("phrase", ""))
	_payment_label.text = "Оплата: +%d ₽" % int(verdict["payment"])
	visible = true
	_next_button.grab_focus()


## Нажатие «Дальше» кодом (автопилот).
func press_next() -> void:
	_on_next_pressed()


func _on_next_pressed() -> void:
	if not visible:
		return
	visible = false
	continued.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_next_pressed()


func _build() -> void:
	var panel := UiStyle.build_frame(self, Vector2(760, 0))
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	panel.add_child(_column)
	var title := UiStyle.label("Итоги сессии", 30, UiStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(title)
	_guest_label = UiStyle.label("", 26)
	_guest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_guest_label)
	_recipe_label = UiStyle.label("", 24, UiStyle.GOLD)
	_recipe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_recipe_label)
	_composition_label = UiStyle.label("", 20, UiStyle.MUTED)
	_composition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_composition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_composition_label)
	_score_label = UiStyle.label("", 64)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_score_label)
	_band_label = UiStyle.label("", 30)
	_band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_band_label)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	_column.add_child(_bar)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(_grid)
	_phrase_label = UiStyle.label("", 24)
	_phrase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phrase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_phrase_label)
	_payment_label = UiStyle.label("", 34, Color(0.6, 0.95, 0.6))
	_payment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_payment_label)
	_next_button = Button.new()
	_next_button.text = "Дальше"
	_next_button.custom_minimum_size = Vector2(0, 52)
	_next_button.add_theme_font_size_override("font_size", 26)
	_next_button.pressed.connect(_on_next_pressed)
	_column.add_child(_next_button)
