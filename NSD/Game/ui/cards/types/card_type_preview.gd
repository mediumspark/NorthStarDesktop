extends CardView

## Editor / dev preview: binds a sample row from tutorials_min_catalog.json.

@export var table: String = "staff_cards"


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_bind_sample_row()


func _bind_sample_row() -> void:
	var tables := TutorialCatalog.load_tables()
	var rows: Variant = tables.get(table, [])
	if typeof(rows) != TYPE_ARRAY or rows.is_empty():
		return
	setup(table, rows[0] as Dictionary)
