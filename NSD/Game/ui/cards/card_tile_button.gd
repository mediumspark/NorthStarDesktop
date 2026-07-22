extends Button
class_name CardTileButton

## Clickable card tile wrapping [CardView] for catalog, deck builder, and match UI.

signal activated
signal preview_requested(table: String, row: Dictionary, opts: Dictionary)

const CARD_VIEW_SCENE := preload("res://ui/cards/card_view.tscn")

var _card_view: CardView
var _on_activate: Callable = Callable()
var _table: String = ""
var _row: Dictionary = {}
var _opts: Dictionary = {}


func setup_card(
	table: String,
	row: Dictionary,
	opts: Dictionary = {},
	on_pressed: Callable = Callable()
) -> void:
	_table = table
	_row = row.duplicate()
	_opts = opts.duplicate()
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

	var dw: float = float(opts.get("display_w", CardVisualConfig.DISPLAY_W))
	var dh: float = float(opts.get("display_h", CardVisualConfig.DISPLAY_H))
	custom_minimum_size = Vector2(dw, dh)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	for c in get_children():
		c.queue_free()

	var targetable: bool = bool(opts.get("targetable", false))
	var normal := _stylebox(false, targetable)
	var hover := _stylebox(true, targetable)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	add_theme_stylebox_override("focus", normal)

	_card_view = CARD_VIEW_SCENE.instantiate() as CardView
	_card_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_view)
	_card_view.setup(table, row, opts)

	_on_activate = on_pressed
	if not pressed.is_connected(_on_button_pressed):
		pressed.connect(_on_button_pressed)


func set_tooltip(text: String) -> void:
	tooltip_text = text


func _on_button_pressed() -> void:
	preview_requested.emit(_table, _row, _opts)
	if _on_activate.is_valid():
		_on_activate.call()
	else:
		activated.emit()


func _stylebox(bright: bool, targetable: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	if targetable:
		sb.border_color = Color(0.95, 0.82, 0.25, 0.95) if bright else Color(0.85, 0.72, 0.18, 0.85)
		sb.set_border_width_all(3 if bright else 2)
	else:
		sb.border_color = Color(0.38, 0.42, 0.52, 0.6) if bright else Color(0, 0, 0, 0)
		sb.set_border_width_all(2 if bright else 0)
	sb.set_corner_radius_all(8)
	return sb
