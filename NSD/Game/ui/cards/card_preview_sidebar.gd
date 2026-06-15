extends PanelContainer
class_name CardPreviewSidebar

## Right-side magnified card preview. Call [method show_card] when a tile is clicked.

const SIDEBAR_SCENE_PATH := "res://ui/cards/card_preview_sidebar.tscn"
const CARD_VIEW_SCENE := preload("res://ui/cards/card_view.tscn")
const PREVIEW_W := 220.0
const PREVIEW_H := 364.0
const SIDEBAR_WIDTH := 292

@onready var _close_button: Button = %CloseButton
@onready var _placeholder: Label = %PlaceholderLabel
@onready var _content: VBoxContainer = %PreviewContent
@onready var _type_label: Label = %TypeLabel
@onready var _name_label: Label = %NameLabel
@onready var _rules_label: Label = %RulesLabel
@onready var _card_slot: CenterContainer = %CardSlot


func _ready() -> void:
	custom_minimum_size = Vector2(280, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.pressed.connect(_on_close_pressed)
	show_empty()


func show_card(table: String, row: Dictionary, opts: Dictionary = {}) -> void:
	if row.is_empty() and table.is_empty():
		show_empty()
		return
	_placeholder.visible = false
	_content.visible = true
	_type_label.text = SupabaseClient.TABLE_LABELS.get(table, table)
	_name_label.text = DeckRules.display_name_for_row(table, row)
	_rules_label.text = CardRowText.primary_rules_text(table, row)
	for c in _card_slot.get_children():
		c.queue_free()
	var preview_opts: Dictionary = opts.duplicate()
	preview_opts["display_w"] = PREVIEW_W
	preview_opts["display_h"] = PREVIEW_H
	var cv := CARD_VIEW_SCENE.instantiate() as CardView
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_slot.add_child(cv)
	cv.setup(table, row, preview_opts)


static func wire_tile(tile: CardTileButton, sidebar: CardPreviewSidebar) -> void:
	if sidebar == null or tile == null:
		return
	if tile.preview_requested.is_connected(sidebar.show_card):
		return
	tile.preview_requested.connect(sidebar.show_card)


## Adds a right-docked preview panel without reparenting scene content (preserves [code]%[/code] names).
static func attach_to_host(host: Control, margin: MarginContainer) -> CardPreviewSidebar:
	var existing: Node = host.get_node_or_null("CardPreviewSidebar")
	if existing is CardPreviewSidebar:
		return existing as CardPreviewSidebar
	var sidebar := load(SIDEBAR_SCENE_PATH).instantiate() as CardPreviewSidebar
	sidebar.name = "CardPreviewSidebar"
	sidebar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sidebar.anchor_left = 1.0
	sidebar.anchor_top = 0.0
	sidebar.anchor_right = 1.0
	sidebar.anchor_bottom = 1.0
	sidebar.offset_left = -float(SIDEBAR_WIDTH)
	sidebar.offset_top = 0.0
	sidebar.offset_right = 0.0
	sidebar.offset_bottom = 0.0
	host.add_child(sidebar)
	var margin_right: int = margin.get_theme_constant("margin_right")
	margin.add_theme_constant_override("margin_right", margin_right + SIDEBAR_WIDTH)
	return sidebar


static func attach_to_margin(margin: MarginContainer) -> CardPreviewSidebar:
	var host := margin.get_parent() as Control
	return attach_to_host(host, margin)


func show_empty() -> void:
	_placeholder.visible = true
	_content.visible = false


func _on_close_pressed() -> void:
	show_empty()
