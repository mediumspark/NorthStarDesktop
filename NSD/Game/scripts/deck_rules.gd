class_name DeckRules
extends RefCounted

const SAVE_VERSION := 1
const LOADOUT_PATH := "user://deck_loadout.json"

const MAIN_DECK_SIZE := 30
const MAX_COPIES_PER_CARD := 3
const RESTAURANT_MIN := 3
const RESTAURANT_MAX := 10

const CHEF_TABLE := "chef_cards"
const RESTAURANT_TABLE := "restaurant_cards"

const MAIN_TABLES: Array[String] = [
	"staff_cards",
	"meal_cards",
	"event_cards",
	"support_cards",
]


static func row_id(row: Dictionary) -> String:
	# Supabase tables in this project use `code` as the stable card identifier (see catalog_cache.json).
	var keys_try: Array[String] = [
		"id", "uuid", "UUID", "Id", "ID",
		"code", "Code", "CODE",
		"card_id", "cardId", "CardId", "CARD_ID",
		"chef_id", "ChefId", "CHEF_ID",
	]
	for k in keys_try:
		if row.has(k):
			var v: Variant = row[k]
			if v != null:
				var s := str(v).strip_edges()
				if not s.is_empty():
					return s
	# Last resort: any key whose name looks like a primary key
	for k in row.keys():
		var ks := str(k)
		var lower := ks.to_lower()
		if lower == "id" or lower == "code" or lower.ends_with("_id") or lower == "uuid":
			var v2: Variant = row[k]
			if v2 != null:
				var s2 := str(v2).strip_edges()
				if not s2.is_empty():
					return s2
	return ""


## Human-readable label for catalog/deck UI. Chef rows prefer chef_name when set.
static func display_name_for_row(table_name: String, row: Dictionary) -> String:
	if table_name == CHEF_TABLE:
		for ck in ["chef_name", "ChefName", "name", "Name"]:
			if not row.has(ck):
				continue
			var sc := str(row[ck]).strip_edges()
			if not sc.is_empty():
				return sc
	for nk in [
		"name",
		"Name",
		"card_name",
		"CardName",
		"display_name",
		"DisplayName",
		"title",
		"Title",
	]:
		if not row.has(nk):
			continue
		var s := str(row[nk]).strip_edges()
		if not s.is_empty():
			return s
	var id_str := row_id(row)
	if not id_str.is_empty():
		return "(unnamed) [%s]" % id_str
	return "(unnamed)"


static func identity_key(table: String, id: String) -> String:
	return "%s:%s" % [table, id]


static func is_main_table(table_name: String) -> bool:
	return table_name in MAIN_TABLES


static func validate_entry_shape(entry: Variant, context: String) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if typeof(entry) != TYPE_DICTIONARY:
		errs.append("%s: entry must be an object." % context)
		return errs
	var d: Dictionary = entry
	var t := str(d.get("table", ""))
	var id := str(d.get("id", ""))
	if t.is_empty() or id.is_empty():
		errs.append("%s: each entry needs \"table\" and \"id\"." % context)
	return errs


static func validate_main(entries: Variant) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if typeof(entries) != TYPE_ARRAY:
		errs.append("Main deck must be an array.")
		return errs
	var arr: Array = entries
	if arr.size() != MAIN_DECK_SIZE:
		errs.append("Main deck must have exactly %d cards (got %d)." % [MAIN_DECK_SIZE, arr.size()])
		return errs
	var counts: Dictionary = {}  # identity_key -> int
	for i in arr.size():
		var entry: Variant = arr[i]
		errs.append_array(validate_entry_shape(entry, "Main deck"))
		if errs.size() > 0:
			return errs
		var d: Dictionary = entry
		var t := str(d.get("table", ""))
		var id := str(d.get("id", ""))
		if not is_main_table(t):
			errs.append("Main deck card has invalid table: %s" % t)
			return errs
		var k := identity_key(t, id)
		var n: int = int(counts.get(k, 0)) + 1
		counts[k] = n
		if n > MAX_COPIES_PER_CARD:
			errs.append("More than %d copies of the same card: %s" % [MAX_COPIES_PER_CARD, k])
			return errs
	return errs


static func validate_restaurant(entries: Variant) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if typeof(entries) != TYPE_ARRAY:
		errs.append("Restaurant deck must be an array.")
		return errs
	var arr: Array = entries
	var n := arr.size()
	if n < RESTAURANT_MIN or n > RESTAURANT_MAX:
		errs.append("Restaurant deck must have between %d and %d cards (got %d)." % [RESTAURANT_MIN, RESTAURANT_MAX, n])
		return errs
	for entry in arr:
		errs.append_array(validate_entry_shape(entry, "Restaurant deck"))
		if errs.size() > 0:
			return errs
		var d: Dictionary = entry
		var t := str(d.get("table", ""))
		var id := str(d.get("id", ""))
		if t != RESTAURANT_TABLE:
			errs.append("Restaurant deck cards must use table \"%s\"." % RESTAURANT_TABLE)
			return errs
		if id.is_empty():
			errs.append("Restaurant deck card id is empty.")
			return errs
	return errs


static func validate_chef(entry: Variant) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if typeof(entry) != TYPE_DICTIONARY:
		errs.append("Chef must be an object with \"table\" and \"id\".")
		return errs
	var d: Dictionary = entry
	var t := str(d.get("table", ""))
	var id := str(d.get("id", ""))
	if t != CHEF_TABLE:
		errs.append("Chef must use table \"%s\"." % CHEF_TABLE)
	if id.is_empty():
		errs.append("Chef id is missing.")
	return errs


static func validate_loadout(data: Variant) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if typeof(data) != TYPE_DICTIONARY:
		errs.append("Loadout root must be an object.")
		return errs
	var root: Dictionary = data
	var ver: Variant = root.get("version", 0)
	if int(ver) != SAVE_VERSION:
		errs.append("Unsupported loadout version (expected %d)." % SAVE_VERSION)
		return errs
	errs.append_array(validate_main(root.get("main_deck", null)))
	if errs.size() > 0:
		return errs
	errs.append_array(validate_restaurant(root.get("restaurant_deck", null)))
	if errs.size() > 0:
		return errs
	errs.append_array(validate_chef(root.get("chef", null)))
	return errs


static func loadout_to_dict(
	main_deck: Array,
	restaurant_deck: Array,
	chef: Dictionary
) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"main_deck": main_deck.duplicate(),
		"restaurant_deck": restaurant_deck.duplicate(),
		"chef": chef.duplicate(),
	}


static func parse_stored_json(text: String) -> Variant:
	if text.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(text)
	return parsed
