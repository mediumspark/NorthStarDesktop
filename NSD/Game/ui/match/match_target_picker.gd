extends CanvasLayer
class_name MatchTargetPicker

## Clickable target card row shown above the faceoff overlay during effect targeting.

const SCENE_PATH := "res://ui/match/match_target_picker.tscn"

signal candidate_chosen(index: int)

@onready var _panel: PanelContainer = %Panel
@onready var _prompt: Label = %PromptLabel
@onready var _row: HBoxContainer = %CandidateRow


func _ready() -> void:
	layer = 95
	visible = false


static func attach(host: Node) -> MatchTargetPicker:
	var existing: Node = host.get_node_or_null("MatchTargetPicker")
	if existing is MatchTargetPicker:
		return existing as MatchTargetPicker
	var picker := load(SCENE_PATH).instantiate() as MatchTargetPicker
	picker.name = "MatchTargetPicker"
	host.add_child(picker)
	return picker


func show_candidates(prompt: String, candidates: Array, resolve_row: Callable, card_opts: Dictionary, preview: CardPreviewSidebar) -> void:
	for c in _row.get_children():
		c.queue_free()
	_prompt.text = prompt
	for i in range(candidates.size()):
		var candidate: Dictionary = candidates[i] as Dictionary
		var table := str(candidate.get("table", ""))
		var id_str := str(candidate.get("id", ""))
		var row: Dictionary = resolve_row.call(table, id_str) as Dictionary
		var opts: Dictionary = card_opts.duplicate()
		opts["targetable"] = true
		var tile := CardTileButton.new()
		tile.setup_card(table, row, opts)
		if preview != null:
			CardPreviewSidebar.wire_tile(tile, preview)
		var idx := i
		tile.pressed.connect(func () -> void:
			candidate_chosen.emit(idx)
		)
		_row.add_child(tile)
	visible = true


func hide_picker() -> void:
	visible = false
	for c in _row.get_children():
		c.queue_free()
