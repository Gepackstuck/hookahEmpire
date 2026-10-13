class_name StatusHud
extends PanelContainer
## M8: компактная панель слева вверху — деньги, репутация, тренд и прогресс цели «сильный рецепт».

var _label: Label


var _styled_modern := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_style()
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## Плашка: классическая тёмная или новая (фиолетовый фон, тёплая рамка, мягкая тень).
func _apply_style() -> void:
	_styled_modern = VisualStyle.modern
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.1, 0.72)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	style.border_color = Color(0.9, 0.75, 0.3, 0.55)
	style.set_border_width_all(1)
	if VisualStyle.modern:
		style.bg_color = Color(0.085, 0.05, 0.11, 0.86)
		style.set_corner_radius_all(16)
		style.content_margin_left = 14.0
		style.content_margin_right = 14.0
		style.border_color = Color(0.95, 0.78, 0.5, 0.7)
		style.shadow_size = 8
		style.shadow_color = Color(0, 0, 0, 0.4)
	add_theme_stylebox_override("panel", style)


## Строки панели: деньги/репутация, тренд, цель.
static func format_lines(money: int, reputation: int, trend_name: String, trend_visits_left: int, goal_text: String, goal_done: bool, show_trend: bool = true) -> String:
	var trend := "📈 %s" % trend_name if trend_name != "" else "📈 —"
	if trend_name != "" and trend_visits_left > 0:
		trend += " (ещё %d виз.)" % trend_visits_left
	var goal := "🎯 Сильных рецептов: %s%s" % [goal_text, " ✅" if goal_done else ""]
	if not show_trend:
		return "💰 %d    ⭐ %d\n%s" % [money, reputation, goal]
	return "💰 %d    ⭐ %d\n%s\n%s" % [money, reputation, trend, goal]


func show_text(text: String) -> void:
	if _styled_modern != VisualStyle.modern:
		_apply_style()
	if _label != null and _label.text != text:
		_label.text = text
