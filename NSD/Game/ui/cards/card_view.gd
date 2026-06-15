extends Control
class_name CardView

## Visual card face: SVG frame + bound catalog row text.

const FRAME_W := 375.0
const FRAME_H := 525.0

var _inner: Control
var _background: TextureRect
var _cost_badge: Label
var _food_rating_badge: Label
var _star_row: HBoxContainer
var _type_banner: Label
var _name_label: Label
var _effect_label: Label
var _extra_banner: Label
var _display_w: float = CardVisualConfig.DISPLAY_W
var _display_h: float = CardVisualConfig.DISPLAY_H


func _ready() -> void:
	_bind_refs()
	_ignore_mouse_recursive(self)
	custom_minimum_size = Vector2(_display_w, _display_h)
	_apply_frame_scale()


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse_recursive(child)


func _bind_refs() -> void:
	if _background != null:
		return
	_inner = %Inner
	_background = %Background
	_cost_badge = %CostBadge
	_food_rating_badge = %FoodRatingBadge
	_star_row = %StarRow
	_type_banner = %TypeBanner
	_name_label = %NameLabel
	_effect_label = %EffectLabel
	_extra_banner = %ExtraBanner


func _apply_frame_scale() -> void:
	var s := Vector2(_display_w / FRAME_W, _display_h / FRAME_H)
	_inner.scale = s
	_inner.custom_minimum_size = Vector2(FRAME_W, FRAME_H)
	_inner.size = Vector2(FRAME_W, FRAME_H)
	custom_minimum_size = Vector2(_display_w, _display_h)


func setup(table: String, row: Dictionary, opts: Dictionary = {}) -> void:
	_bind_refs()
	_display_w = float(opts.get("display_w", CardVisualConfig.DISPLAY_W))
	_display_h = float(opts.get("display_h", CardVisualConfig.DISPLAY_H))
	_apply_frame_scale()

	if opts.get("face_down", false):
		_apply_face_down()
		return

	var path := CardVisualConfig.template_path_for(table)
	var tex := load(path) as Texture2D
	if tex != null:
		_background.texture = tex

	_name_label.visible = true
	_effect_label.visible = true

	var layout := CardVisualConfig.layout_for(table)
	_apply_layout(layout)

	var name_text := DeckRules.display_name_for_row(table, row)
	var rules_text := CardRowText.primary_rules_text(table, row)
	var type_text := RestaurantRTypes.format_banner_from_row(table, row)

	_name_label.text = name_text
	_effect_label.text = rules_text
	_type_banner.text = type_text

	_cost_badge.visible = CardVisualConfig.show_cost(table)
	if _cost_badge.visible:
		_cost_badge.text = str(SchemaKeys.get_influence_cost(row))

	_food_rating_badge.visible = CardVisualConfig.show_food_rating(table)
	if _food_rating_badge.visible:
		_food_rating_badge.text = str(SchemaKeys.get_food_rating(row))

	_type_banner.visible = CardVisualConfig.show_type_banner(table) and not type_text.is_empty()

	_populate_stars(table, row)

	var extra := str(opts.get("extra_banner", "")).strip_edges()
	_extra_banner.visible = not extra.is_empty()
	_extra_banner.text = extra

	var hook := str(opts.get("hook_log", "")).strip_edges()
	if not hook.is_empty():
		_effect_label.text = "%s\n\n[%s]" % [rules_text, hook]
	_ignore_mouse_recursive(self)


func _apply_face_down() -> void:
	var tex := load("res://ui/cards/templates/card_back.svg") as Texture2D
	if tex != null:
		_background.texture = tex
	_cost_badge.visible = false
	_food_rating_badge.visible = false
	_star_row.visible = false
	_type_banner.visible = false
	_name_label.visible = false
	_effect_label.visible = false
	_extra_banner.visible = false
	_ignore_mouse_recursive(self)


func _apply_layout(layout: CardVisualConfig.LayoutKind) -> void:
	match layout:
		CardVisualConfig.LayoutKind.STAFF:
			_position(_cost_badge, 22, 22, 60, 60)
			_position(_type_banner, 98, 32, 220, 44)
			_position(_name_label, 48, 292, 279, 38)
			_position(_effect_label, 24, 358, 327, 140)
			_type_banner.visible = false
			_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_name_label.add_theme_font_size_override("font_size", 16)
			_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_effect_label.add_theme_font_size_override("font_size", 11)
		CardVisualConfig.LayoutKind.MAIN_DECK:
			_position(_cost_badge, 22, 22, 60, 60)
			_position(_name_label, 92, 32, 232, 44)
			_position(_type_banner, 118, 302, 140, 36)
			_position(_effect_label, 24, 372, 327, 130)
			_style_main_deck_labels()
		CardVisualConfig.LayoutKind.MEAL:
			_position(_cost_badge, 22, 22, 60, 60)
			_position(_food_rating_badge, 293, 22, 60, 60)
			_position(_name_label, 92, 32, 192, 44)
			_position(_type_banner, 118, 302, 140, 36)
			_position(_effect_label, 24, 372, 327, 130)
			_style_main_deck_labels()
		CardVisualConfig.LayoutKind.CHEF, CardVisualConfig.LayoutKind.RESTAURANT:
			_position(_type_banner, 22, 24, 196, 36)
			_position(_star_row, 258, 26, 96, 32)
			_position(_effect_label, 40, 288, 295, 88)
			_position(_name_label, 78, 424, 219, 72)
			_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_name_label.add_theme_font_size_override("font_size", 15)
			_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_effect_label.add_theme_font_size_override("font_size", 10)


func _style_main_deck_labels() -> void:
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 13)
	_type_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_banner.add_theme_font_size_override("font_size", 11)
	_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effect_label.add_theme_font_size_override("font_size", 10)


func _position(node: Control, x: float, y: float, w: float, h: float) -> void:
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.offset_left = x
	node.offset_top = y
	node.offset_right = x + w
	node.offset_bottom = y + h


func _populate_stars(table: String, row: Dictionary) -> void:
	for c in _star_row.get_children():
		c.queue_free()
	_star_row.visible = CardVisualConfig.show_stars(table)
	if not _star_row.visible:
		return
	var count := CardVisualConfig.star_count(table, row)
	var star_color := Color(0.95, 0.78, 0.1)
	if table == DeckRules.RESTAURANT_TABLE:
		star_color = Color(0.92, 0.28, 0.32)
	for i in count:
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 22)
		star.add_theme_color_override("font_color", star_color)
		_star_row.add_child(star)
