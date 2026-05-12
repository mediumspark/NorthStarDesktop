extends Control

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"

@onready var _status: Label = %StatusLabel
@onready var _tabs: TabContainer = %TabContainer

var _row_boxes: Dictionary = {}  # table_name -> VBoxContainer
var _counts: Dictionary = {}  # table_name -> int (-1 = error)


func _ready() -> void:
	%MainMenuButton.pressed.connect(_on_main_menu_pressed)
	_build_tabs()
	SupabaseClient.batch_progress.connect(_on_batch_progress)
	SupabaseClient.batch_finished.connect(_on_batch_finished)
	if SupabaseClient.load_catalog_from_cache():
		return
	if not SupabaseClient.load_config():
		_status.text = "Missing cache and config: run ../launcher (Sync) or add res://secrets/supabase.local.json — copy secrets/supabase.local.example.json."
		return
	_status.text = "Fetching…"
	SupabaseClient.fetch_all_tables()


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)


func _build_tabs() -> void:
	for table in SupabaseClient.TABLE_ORDER:
		var scroll := ScrollContainer.new()
		scroll.name = SupabaseClient.TABLE_LABELS[table]
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 12)
		scroll.add_child(vbox)
		_tabs.add_child(scroll)
		_row_boxes[table] = vbox


func _on_batch_progress(table_name: String, ok: bool, rows: Array, err_msg: String) -> void:
	var box: VBoxContainer = _row_boxes[table_name]
	if not ok:
		_counts[table_name] = -1
		var err_label := Label.new()
		err_label.text = "Error: %s" % err_msg
		err_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(err_label)
		return
	_counts[table_name] = rows.size()
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		box.add_child(_make_expandable_row(table_name, row))


func _on_batch_finished() -> void:
	var parts: PackedStringArray = PackedStringArray()
	if SupabaseClient.used_cache_for_last_load:
		parts.append("cache")
	for table in SupabaseClient.TABLE_ORDER:
		var n: Variant = _counts.get(table, 0)
		var title: String = SupabaseClient.TABLE_LABELS[table]
		if typeof(n) == TYPE_INT and n < 0:
			parts.append("%s: error" % title)
		elif typeof(n) == TYPE_INT:
			parts.append("%s: %d" % [title, n])
		else:
			parts.append("%s: 0" % title)
	_status.text = " — ".join(parts)


func _make_expandable_row(table_name: String, row: Dictionary) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 4)

	var title := DeckRules.display_name_for_row(table_name, row)
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("card_title", title)
	btn.text = "▶ %s" % title
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var details := Label.new()
	details.text = _row_to_text(row)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.visible = false
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	btn.pressed.connect(func () -> void:
		details.visible = not details.visible
		var open := details.visible
		var t: String = str(btn.get_meta("card_title"))
		btn.text = ("▼ %s" % t) if open else ("▶ %s" % t)
	)

	root.add_child(btn)
	root.add_child(details)
	return root


func _row_to_text(row: Dictionary) -> String:
	var keys: Array = row.keys()
	keys.sort()
	var lines: PackedStringArray = PackedStringArray()
	for k in keys:
		lines.append("%s: %s" % [k, str(row[k])])
	return "\n".join(lines)
