extends Control

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
## Shipped sample loadout (proto IDs). Resolves to real names when catalog is synced.
const BUNDLED_DEMO_LOADOUT := "res://data/bundled_sample_loadout.json"

const CARD_OPTS := {"display_w": 132.0, "display_h": 218.0}

const COLOR_VALID := Color(0.32, 0.72, 0.42, 1)
const COLOR_INVALID := Color(0.82, 0.35, 0.32, 1)
const COLOR_NEUTRAL := Color(0.88, 0.9, 0.93, 1)
const COLOR_WARN := Color(0.9, 0.62, 0.28, 1)

@onready var _catalog_summary: Label = %CatalogSummaryLabel
@onready var _validation: Label = %ValidationLabel
@onready var _toast: Label = %ToastLabel
@onready var _toast_timer: Timer = %ToastTimer
@onready var _save_button: Button = %SaveButton

@onready var _chef_option: OptionButton = %ChefOption
@onready var _main_count: Label = %MainCountLabel
@onready var _main_progress: ProgressBar = %MainProgress
@onready var _main_deck_list: GridContainer = %MainDeckList
@onready var _rest_count: Label = %RestaurantCountLabel
@onready var _rest_deck_list: GridContainer = %RestaurantDeckList
@onready var _all_cards_grid: GridContainer = %AllCardsGrid

@onready var _show_staff: CheckButton = %ShowStaff
@onready var _show_meal: CheckButton = %ShowMeal
@onready var _show_event: CheckButton = %ShowEvent
@onready var _show_support: CheckButton = %ShowSupport
@onready var _show_restaurant: CheckButton = %ShowRestaurant
@onready var _show_chef: CheckButton = %ShowChef

var _tables_data: Dictionary = {}
var _main_deck: Array = []
var _restaurant_deck: Array = []
var _chef: Dictionary = {}

## Parallel to OptionButton items: id string per index (index 0 empty string).
var _chef_ids: Array = []

var _catalog_ready: bool = false
var _catalog_summary_text: String = ""

var _preview: CardPreviewSidebar


func _game_menu() -> Node:
	return get_node("/root/GameMenu")


func _ready() -> void:
	var menu := _game_menu()
	menu.register_context(menu.Context.SCREEN)
	_toast_timer.timeout.connect(_on_toast_timeout)
	_catalog_summary.text = ""
	_toast.text = ""

	SupabaseClient.batch_progress.connect(_on_batch_progress)
	SupabaseClient.batch_finished.connect(_on_catalog_batch_finished)
	%BackButton.pressed.connect(_on_back_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	%LoadButton.pressed.connect(_on_load_pressed)
	%SampleDeckButton.pressed.connect(_on_sample_deck_pressed)
	%OfflineDemoButton.pressed.connect(_on_offline_demo_pressed)
	_chef_option.item_selected.connect(_on_chef_item_selected)
	_show_staff.toggled.connect(_on_filters_changed)
	_show_meal.toggled.connect(_on_filters_changed)
	_show_event.toggled.connect(_on_filters_changed)
	_show_support.toggled.connect(_on_filters_changed)
	_show_restaurant.toggled.connect(_on_filters_changed)
	_show_chef.toggled.connect(_on_filters_changed)
	call_deferred("_ensure_preview")

	_tables_data.clear()
	_set_validation("Loading catalog…", false, true)
	_save_button.disabled = true
	if SupabaseClient.load_catalog_from_cache():
		return
	if not SupabaseClient.load_config():
		_set_validation(
			"Missing cache and config: run ../launcher (Sync) or add res://secrets/supabase.local.json — copy secrets/supabase.local.example.json.",
			false,
			false
		)
		return
	_set_validation("Fetching catalog…", false, true)
	SupabaseClient.fetch_all_tables()


func _ensure_preview() -> void:
	if _preview != null:
		return
	_preview = CardPreviewSidebar.attach_to_host(self, $Margin)


func _on_toast_timeout() -> void:
	_toast.text = ""


func _clear_toast() -> void:
	_toast_timer.stop()
	_toast.text = ""


func _toast_msg(msg: String) -> void:
	_toast.text = msg
	_toast_timer.start()


func _set_catalog_summary(text: String) -> void:
	_catalog_summary_text = text
	_catalog_summary.text = text


func _set_validation(text: String, is_ok: bool, is_neutral: bool) -> void:
	_validation.text = text
	_validation.remove_theme_color_override("font_color")
	if is_neutral:
		_validation.add_theme_color_override("font_color", COLOR_NEUTRAL)
	elif is_ok:
		_validation.add_theme_color_override("font_color", COLOR_VALID)
	else:
		_validation.add_theme_color_override("font_color", COLOR_INVALID)


func _update_save_enabled() -> void:
	var d := _current_loadout_dict()
	var errs := DeckRules.validate_loadout(d)
	_save_button.disabled = (not _catalog_ready) or (not errs.is_empty())


func _on_batch_progress(table_name: String, ok: bool, rows: Array, err_msg: String) -> void:
	if ok:
		_tables_data[table_name] = rows
	else:
		_tables_data[table_name] = []
		push_warning("Deck building: table %s failed: %s" % [table_name, err_msg])


func _on_catalog_batch_finished() -> void:
	_clear_toast()
	_catalog_ready = true
	var parts: PackedStringArray = PackedStringArray()
	parts.append("cache" if SupabaseClient.used_cache_for_last_load else "network")
	for table in SupabaseClient.TABLE_ORDER:
		var rows: Variant = _tables_data.get(table, [])
		var n := 0
		if typeof(rows) == TYPE_ARRAY:
			n = rows.size()
		var title: String = SupabaseClient.TABLE_LABELS.get(table, table)
		parts.append("%s: %d" % [title, n])
	_catalog_summary_text = "Catalog (%s) — %s" % [parts[0], " — ".join(parts.slice(1))]
	_set_catalog_summary(_catalog_summary_text)

	_build_chef_option()
	_rebuild_all_cards_grid()
	_refresh_main_deck_list()
	_refresh_restaurant_deck_list()
	_sync_chef_selection()
	_refresh_validation_status()
	_try_autoload()


func _on_filters_changed(_pressed: bool) -> void:
	if not _catalog_ready:
		return
	_rebuild_all_cards_grid()


func _selected_tables_for_top_grid() -> Array[String]:
	var out: Array[String] = []
	if _show_staff.button_pressed:
		out.append("staff_cards")
	if _show_meal.button_pressed:
		out.append("meal_cards")
	if _show_event.button_pressed:
		out.append("event_cards")
	if _show_support.button_pressed:
		out.append("support_cards")
	if _show_restaurant.button_pressed:
		out.append("restaurant_cards")
	if _show_chef.button_pressed:
		out.append("chef_cards")
	return out


func _tooltip_for_catalog_table(table: String) -> String:
	if table == DeckRules.CHEF_TABLE:
		return "Sets your chef for this loadout."
	if table == DeckRules.RESTAURANT_TABLE:
		return "Adds to restaurant deck (need %d–%d cards)." % [DeckRules.RESTAURANT_MIN, DeckRules.RESTAURANT_MAX]
	if DeckRules.is_main_table(table):
		return "Adds to main deck (%d cards, max %d copies each)." % [DeckRules.MAIN_DECK_SIZE, DeckRules.MAX_COPIES_PER_CARD]
	return "Add card"


func _make_catalog_tile_button(table: String, id_str: String, row: Dictionary) -> CardTileButton:
	_ensure_preview()
	var tile := CardTileButton.new()
	tile.setup_card(table, row, CARD_OPTS, _on_card_tile_pressed.bind(table, id_str))
	tile.set_tooltip(_tooltip_for_catalog_table(table))
	CardPreviewSidebar.wire_tile(tile, _preview)
	return tile


func _make_deck_row_button(table: String, id_str: String, remove_tooltip: String, on_pressed: Callable) -> CardTileButton:
	_ensure_preview()
	var row := _resolve_row(table, id_str)
	if row.is_empty():
		row = {"name": id_str}
	var tile := CardTileButton.new()
	tile.setup_card(table, row, CARD_OPTS, on_pressed)
	tile.set_tooltip(remove_tooltip)
	CardPreviewSidebar.wire_tile(tile, _preview)
	return tile


func _resolve_row(table: String, id_str: String) -> Dictionary:
	var rows: Variant = _tables_data.get(table, [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = item
		if DeckRules.row_id(r) == id_str:
			return r
	return {}


func _rebuild_all_cards_grid() -> void:
	for c in _all_cards_grid.get_children():
		c.queue_free()
	if not _catalog_ready:
		return
	var tables := _selected_tables_for_top_grid()
	if tables.is_empty():
		var empty := Label.new()
		empty.text = "No filters selected."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_all_cards_grid.add_child(empty)
		return
	for table in tables:
		var rows: Variant = _tables_data.get(table, [])
		if typeof(rows) != TYPE_ARRAY:
			continue
		for row in rows:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var r: Dictionary = row
			var id_str := DeckRules.row_id(r)
			if id_str.is_empty():
				continue
			_all_cards_grid.add_child(_make_catalog_tile_button(table, id_str, r))


func _on_card_tile_pressed(table: String, id_str: String) -> void:
	if table == DeckRules.CHEF_TABLE:
		_chef = {"table": DeckRules.CHEF_TABLE, "id": id_str}
		_chef_option.set_block_signals(true)
		_sync_chef_selection()
		_chef_option.set_block_signals(false)
		_refresh_validation_status()
		return
	if table == DeckRules.RESTAURANT_TABLE:
		_try_add_restaurant(id_str)
		return
	if DeckRules.is_main_table(table):
		_try_add_main(table, id_str)
		return


func _try_autoload() -> void:
	if not FileAccess.file_exists(DeckRules.LOADOUT_PATH):
		_refresh_validation_status()
		return
	if _load_from_disk(false):
		_toast_msg("Auto-loaded valid save from disk.")


func _build_chef_option() -> void:
	_chef_option.clear()
	_chef_ids.clear()
	_chef_option.add_item("(none)")
	_chef_ids.append("")
	var rows: Variant = _tables_data.get(DeckRules.CHEF_TABLE, [])
	if typeof(rows) != TYPE_ARRAY:
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = row
		var id_str := DeckRules.row_id(r)
		if id_str.is_empty():
			continue
		_chef_option.add_item(DeckRules.display_name_for_row(DeckRules.CHEF_TABLE, r))
		_chef_ids.append(id_str)
	_chef_option.set_block_signals(true)
	_sync_chef_selection()
	_chef_option.set_block_signals(false)


func _sync_chef_selection() -> void:
	var want := str(_chef.get("id", ""))
	var pick := 0
	if not want.is_empty():
		for i in range(_chef_ids.size()):
			if str(_chef_ids[i]) == want:
				pick = i
				break
	_chef_option.select(pick)


func _on_chef_item_selected(index: int) -> void:
	if index <= 0 or index >= _chef_ids.size():
		_chef = {}
	else:
		var id_str: String = str(_chef_ids[index])
		_chef = {"table": DeckRules.CHEF_TABLE, "id": id_str}
	_refresh_validation_status()


func _try_add_main(table: String, id_str: String) -> void:
	if not _catalog_ready:
		return
	if _main_deck.size() >= DeckRules.MAIN_DECK_SIZE:
		_toast_msg("Main deck is full (30).")
		return
	var k := DeckRules.identity_key(table, id_str)
	var n := 0
	for e in _main_deck:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if DeckRules.identity_key(str(d.get("table", "")), str(d.get("id", ""))) == k:
			n += 1
	if n >= DeckRules.MAX_COPIES_PER_CARD:
		_toast_msg("You can have at most %d copies of the same card." % DeckRules.MAX_COPIES_PER_CARD)
		return
	_main_deck.append({"table": table, "id": id_str})
	_refresh_main_deck_list()
	_refresh_validation_status()


func _remove_main_at(index: int) -> void:
	if index < 0 or index >= _main_deck.size():
		return
	_main_deck.remove_at(index)
	_refresh_main_deck_list()
	_refresh_validation_status()


func _refresh_main_progress() -> void:
	var n := _main_deck.size()
	_main_progress.max_value = float(DeckRules.MAIN_DECK_SIZE)
	_main_progress.value = float(n)
	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_VALID if n >= DeckRules.MAIN_DECK_SIZE else Color(0.28, 0.52, 0.78, 1)
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_right = 3
	fill.corner_radius_bottom_left = 3
	_main_progress.add_theme_stylebox_override("fill", fill)


func _refresh_main_deck_list() -> void:
	for c in _main_deck_list.get_children():
		c.queue_free()
	_main_count.text = "%d / %d" % [_main_deck.size(), DeckRules.MAIN_DECK_SIZE]
	_refresh_main_progress()
	for i in range(_main_deck.size()):
		var e: Dictionary = _main_deck[i]
		var table := str(e.get("table", ""))
		var id_str := str(e.get("id", ""))
		var idx := i
		var btn := _make_deck_row_button(table, id_str, "Remove from main deck", func () -> void:
			_remove_main_at(idx)
		)
		_main_deck_list.add_child(btn)


func _bump_status(detail: String) -> void:
	_toast_msg(detail)


func _try_add_restaurant(id_str: String) -> void:
	if not _catalog_ready:
		return
	if _restaurant_deck.size() >= DeckRules.RESTAURANT_MAX:
		_toast_msg("Restaurant deck is full (%d)." % DeckRules.RESTAURANT_MAX)
		return
	_restaurant_deck.append({"table": DeckRules.RESTAURANT_TABLE, "id": id_str})
	_refresh_restaurant_deck_list()
	_refresh_validation_status()


func _remove_restaurant_at(index: int) -> void:
	if index < 0 or index >= _restaurant_deck.size():
		return
	_restaurant_deck.remove_at(index)
	_refresh_restaurant_deck_list()
	_refresh_validation_status()


func _restaurant_count_style(n: int) -> void:
	_rest_count.remove_theme_color_override("font_color")
	if n >= DeckRules.RESTAURANT_MIN and n <= DeckRules.RESTAURANT_MAX:
		_rest_count.add_theme_color_override("font_color", COLOR_VALID)
	elif n > 0:
		_rest_count.add_theme_color_override("font_color", COLOR_WARN)


func _refresh_restaurant_deck_list() -> void:
	for c in _rest_deck_list.get_children():
		c.queue_free()
	var n := _restaurant_deck.size()
	_rest_count.text = "%d (need %d–%d)%s" % [n, DeckRules.RESTAURANT_MIN, DeckRules.RESTAURANT_MAX, " ✓" if (n >= DeckRules.RESTAURANT_MIN and n <= DeckRules.RESTAURANT_MAX) else ""]
	_restaurant_count_style(n)
	for i in range(_restaurant_deck.size()):
		var e: Dictionary = _restaurant_deck[i]
		var id_str := str(e.get("id", ""))
		var idx := i
		var btn := _make_deck_row_button(DeckRules.RESTAURANT_TABLE, id_str, "Remove from restaurant deck", func () -> void:
			_remove_restaurant_at(idx)
		)
		_rest_deck_list.add_child(btn)


func _current_loadout_dict() -> Dictionary:
	return DeckRules.loadout_to_dict(_main_deck, _restaurant_deck, _chef)


func _refresh_validation_status() -> void:
	var d := _current_loadout_dict()
	var errs := DeckRules.validate_loadout(d)
	var line2 := "Loadout is valid." if errs.is_empty() else "Invalid: %s" % "; ".join(errs)
	_set_validation(line2, errs.is_empty(), false)
	_update_save_enabled()


func _on_save_pressed() -> void:
	var d := _current_loadout_dict()
	var errs := DeckRules.validate_loadout(d)
	if not errs.is_empty():
		_set_validation("Cannot save — %s" % "; ".join(errs), false, false)
		return
	var text := JSON.stringify(d)
	var path := DeckRules.LOADOUT_PATH
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_validation("Could not write save file.", false, false)
		return
	f.store_string(text)
	f.close()
	_refresh_validation_status()
	_toast_msg("Saved to %s." % path)


func _load_from_disk(show_errors: bool) -> bool:
	var path := DeckRules.LOADOUT_PATH
	if not FileAccess.file_exists(path):
		if show_errors:
			_set_validation("No save file at %s yet." % path, false, false)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		if show_errors:
			_set_validation("Could not read save file.", false, false)
		return false
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = DeckRules.parse_stored_json(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		if show_errors:
			_set_validation("Save file is not valid JSON.", false, false)
		return false
	var root: Dictionary = parsed
	var errs := DeckRules.validate_loadout(root)
	if not errs.is_empty():
		if show_errors:
			_set_validation("Save file invalid — %s" % "; ".join(errs), false, false)
		return false
	_apply_loadout_dict(root)
	return true


func _apply_loadout_dict(root: Dictionary) -> void:
	_main_deck = _clone_entry_array(root.get("main_deck", []))
	_restaurant_deck = _clone_entry_array(root.get("restaurant_deck", []))
	var ch: Variant = root.get("chef", {})
	if typeof(ch) == TYPE_DICTIONARY:
		_chef = (ch as Dictionary).duplicate()
	else:
		_chef = {}
	_refresh_main_deck_list()
	_refresh_restaurant_deck_list()
	_chef_option.set_block_signals(true)
	_sync_chef_selection()
	_chef_option.set_block_signals(false)
	_refresh_validation_status()


func _on_sample_deck_pressed() -> void:
	if not _catalog_ready:
		_toast_msg("Catalog not loaded yet — wait or fix sync/config.")
		return
	var r: Dictionary = SampleDeckBuilder.try_build_loadout(_tables_data)
	if not r.get("ok", false):
		_toast_msg("Sample deck: %s" % str(r.get("error", "Unknown error.")))
		return
	var loadout: Variant = r.get("loadout", {})
	if typeof(loadout) != TYPE_DICTIONARY:
		_toast_msg("Sample deck: internal error.")
		return
	_apply_loadout_dict(loadout as Dictionary)
	_toast_msg("Sample deck loaded — edit or Save.")


func _on_offline_demo_pressed() -> void:
	if not FileAccess.file_exists(BUNDLED_DEMO_LOADOUT):
		_toast_msg("Missing file: %s" % BUNDLED_DEMO_LOADOUT)
		return
	var f := FileAccess.open(BUNDLED_DEMO_LOADOUT, FileAccess.READ)
	if f == null:
		_toast_msg("Could not read bundled offline demo.")
		return
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = DeckRules.parse_stored_json(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_toast_msg("Bundled demo is not valid JSON.")
		return
	var root: Dictionary = parsed
	var errs := DeckRules.validate_loadout(root)
	if not errs.is_empty():
		_toast_msg("Bundled demo invalid: %s" % "; ".join(errs))
		return
	_apply_loadout_dict(root)
	_toast_msg("Offline demo loaded (sync catalog for real names).")


func _clone_entry_array(src: Variant) -> Array:
	var out: Array = []
	if typeof(src) != TYPE_ARRAY:
		return out
	for item in src:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		out.append({"table": str(d.get("table", "")), "id": str(d.get("id", ""))})
	return out


func _on_load_pressed() -> void:
	if _load_from_disk(true):
		_toast_msg("Loaded valid save from %s." % DeckRules.LOADOUT_PATH)


func _exit_tree() -> void:
	_game_menu().clear_context()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)
