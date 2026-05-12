class_name SampleDeckBuilder
extends RefCounted

## Builds a valid test loadout from whatever is in the synced catalog.
## Fails if there is no chef, no restaurant row, or not enough distinct main-deck cards
## to reach 30 with the 3-copy rule (needs at least 10 distinct main-pool identities).


static func try_build_loadout(tables_data: Dictionary) -> Dictionary:
	var chef_id := _first_row_id(tables_data, DeckRules.CHEF_TABLE)
	if chef_id.is_empty():
		return {"ok": false, "error": "No chef card in catalog — run launcher Sync again, or open Card Catalog; if Chef is still empty, check data/catalog_cache.json next to the Godot project."}
	var rest := _build_restaurant_deck(tables_data)
	if rest.is_empty():
		return {"ok": false, "error": "No restaurant cards in catalog (sync data first)."}
	var main := _build_main_deck(tables_data)
	if main.size() != DeckRules.MAIN_DECK_SIZE:
		return {
			"ok": false,
			"error": "Not enough distinct main-deck cards to build 30 (max 3 each). Need at least 10 different cards across Staff/Meal/Event/Support.",
		}
	var loadout := DeckRules.loadout_to_dict(
		main,
		rest,
		{"table": DeckRules.CHEF_TABLE, "id": chef_id}
	)
	var errs := DeckRules.validate_loadout(loadout)
	if not errs.is_empty():
		return {"ok": false, "error": "; ".join(errs)}
	return {"ok": true, "loadout": loadout}


static func _first_row_id(tables_data: Dictionary, table: String) -> String:
	var rows: Variant = tables_data.get(table, [])
	if typeof(rows) != TYPE_ARRAY:
		return ""
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var id_str := DeckRules.row_id(row)
		if not id_str.is_empty():
			return id_str
	return ""


static func _build_restaurant_deck(tables_data: Dictionary) -> Array:
	var ids: Array = []
	var rows: Variant = tables_data.get(DeckRules.RESTAURANT_TABLE, [])
	if typeof(rows) != TYPE_ARRAY:
		return []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var id_str := DeckRules.row_id(row)
		if id_str.is_empty():
			continue
		ids.append(id_str)
	if ids.is_empty():
		return []
	var out: Array = []
	var i := 0
	while out.size() < DeckRules.RESTAURANT_MIN:
		var pick: String = ids[i % ids.size()]
		out.append({"table": DeckRules.RESTAURANT_TABLE, "id": pick})
		i += 1
	return out


static func _build_main_deck(tables_data: Dictionary) -> Array:
	var pool: Array = []
	for table in DeckRules.MAIN_TABLES:
		var rows: Variant = tables_data.get(table, [])
		if typeof(rows) != TYPE_ARRAY:
			continue
		for row in rows:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var id_str := DeckRules.row_id(row)
			if id_str.is_empty():
				continue
			pool.append({"table": table, "id": id_str})
	if pool.is_empty():
		return []
	var counts: Dictionary = {}
	var main: Array = []
	var pool_i := 0
	var guard := 0
	while main.size() < DeckRules.MAIN_DECK_SIZE and guard < 10000:
		guard += 1
		var e: Dictionary = pool[pool_i % pool.size()]
		pool_i += 1
		var t := str(e.get("table", ""))
		var id_str := str(e.get("id", ""))
		var k := DeckRules.identity_key(t, id_str)
		var c: int = int(counts.get(k, 0))
		if c >= DeckRules.MAX_COPIES_PER_CARD:
			continue
		main.append({"table": t, "id": id_str})
		counts[k] = c + 1
	return main
