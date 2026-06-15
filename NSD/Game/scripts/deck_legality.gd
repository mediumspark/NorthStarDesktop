class_name DeckLegality
extends RefCounted

## Pre-match validation: `DeckRules` + schema-based chef/restaurant typing.


static func validate_for_match(tables_data: Dictionary, loadout: Dictionary) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()
	errors.append_array(DeckRules.validate_loadout(loadout))
	if errors.size() > 0:
		return {"ok": false, "errors": errors, "warnings": warnings}

	var rest: Variant = loadout.get("restaurant_deck", [])
	if typeof(rest) != TYPE_ARRAY:
		errors.append("Internal: restaurant_deck not an array.")
		return {"ok": false, "errors": errors, "warnings": warnings}
	var seen: Dictionary = {}
	for entry in rest:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		var id_str := str(d.get("id", ""))
		if id_str.is_empty():
			continue
		if seen.has(id_str):
			errors.append("Restaurant deck must not contain duplicates (id: %s)." % id_str)
			return {"ok": false, "errors": errors, "warnings": warnings}
		seen[id_str] = true

	var chef_entry: Variant = loadout.get("chef", {})
	if typeof(chef_entry) != TYPE_DICTIONARY:
		errors.append("Chef entry missing.")
		return {"ok": false, "errors": errors, "warnings": warnings}
	var chef_id := str((chef_entry as Dictionary).get("id", ""))
	var chef_row := _resolve_row(tables_data, DeckRules.CHEF_TABLE, chef_id)
	if chef_row.is_empty():
		errors.append("Chef id not found in catalog: %s" % chef_id)
		return {"ok": false, "errors": errors, "warnings": warnings}

	var bi := SchemaKeys.get_base_influence_chef(chef_row)
	if bi < 0:
		errors.append(
			"Chef row missing base influence (tried keys: %s)." % ", ".join(SchemaKeys.BASE_INFLUENCE_KEYS)
		)
		return {"ok": false, "errors": errors, "warnings": warnings}

	var allowed := _chef_allowed_canonicals(chef_row)
	if allowed.is_empty():
		errors.append(
			"Chef row missing allowed restaurant types (tried keys: %s / string keys: %s)."
			% [", ".join(SchemaKeys.CHEF_ALLOWED_TYPES_KEYS), ", ".join(SchemaKeys.CHEF_ALLOWED_TYPES_STRING_KEYS)]
		)
		return {"ok": false, "errors": errors, "warnings": warnings}

	for entry in rest:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		var rid := str(d.get("id", ""))
		var row := _resolve_row(tables_data, DeckRules.RESTAURANT_TABLE, rid)
		if row.is_empty():
			errors.append("Restaurant id not found in catalog: %s" % rid)
			return {"ok": false, "errors": errors, "warnings": warnings}
		var raw_rt := SchemaKeys.get_r_type(row)
		if raw_rt.is_empty():
			errors.append(
				"Restaurant \"%s\" missing R-Type (tried keys: %s)." % [DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, row), ", ".join(SchemaKeys.R_TYPE_KEYS)]
			)
			return {"ok": false, "errors": errors, "warnings": warnings}
		if str(raw_rt).strip_edges() == RestaurantRTypes.TYPELESS_SENTINEL:
			errors.append("Restaurant \"%s\" cannot be typeless." % DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, row))
			return {"ok": false, "errors": errors, "warnings": warnings}
		var norm := RestaurantRTypes.normalize_token(raw_rt)
		if not RestaurantRTypes.is_known_restaurant_type(norm):
			errors.append(
				"Restaurant \"%s\" has unknown R-Type \"%s\" (allowed: %s)."
				% [DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, row), raw_rt, RestaurantRTypes.canonical_list_pretty()]
			)
			return {"ok": false, "errors": errors, "warnings": warnings}
		if not allowed.has(norm):
			errors.append(
				"Restaurant \"%s\" (R-Type %s) is not allowed by this Chef."
				% [DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, row), norm]
			)
			return {"ok": false, "errors": errors, "warnings": warnings}

	var main: Variant = loadout.get("main_deck", [])
	if typeof(main) == TYPE_ARRAY:
		for entry in main:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = entry
			var t := str(d.get("table", ""))
			var cid := str(d.get("id", ""))
			if not DeckRules.is_main_table(t):
				continue
			var mrow := _resolve_row(tables_data, t, cid)
			if mrow.is_empty():
				continue
			var rt_raw := SchemaKeys.get_r_type(mrow)
			if rt_raw.is_empty():
				warnings.append("Main-deck card %s:%s missing R-Type (allowed for v1; fix data later)." % [t, cid])
				continue
			if str(rt_raw).strip_edges() == RestaurantRTypes.TYPELESS_SENTINEL:
				continue
			var cn := RestaurantRTypes.normalize_token(rt_raw)
			if cn.is_empty() or not RestaurantRTypes.is_known_restaurant_type(cn):
				warnings.append("Main-deck card %s:%s has unknown R-Type \"%s\" (allowed for v1)." % [t, cid, rt_raw])

	return {"ok": true, "errors": errors, "warnings": warnings}


static func _resolve_row(tables_data: Dictionary, table: String, id_str: String) -> Dictionary:
	var rows: Variant = tables_data.get(table, [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = row
		if DeckRules.row_id(r) == id_str:
			return r
	return {}


static func _chef_allowed_canonicals(chef_row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in SchemaKeys.CHEF_ALLOWED_TYPES_KEYS:
		if not chef_row.has(k):
			continue
		var v: Variant = chef_row[k]
		_append_allowed_variant(v, out)
	for k in SchemaKeys.CHEF_ALLOWED_TYPES_STRING_KEYS:
		if not chef_row.has(k):
			continue
		var v: Variant = chef_row[k]
		if typeof(v) == TYPE_STRING:
			var s := str(v).strip_edges()
			if s.begins_with("["):
				var parsed: Variant = JSON.parse_string(s)
				_append_allowed_variant(parsed, out)
			else:
				for part in s.replace("|", ",").split(","):
					var p := part.strip_edges()
					if not p.is_empty():
						var cn := RestaurantRTypes.normalize_token(p)
						if not cn.is_empty():
							out[cn] = true
	return out


static func _append_allowed_variant(v: Variant, out: Dictionary) -> void:
	if v == null:
		return
	match typeof(v):
		TYPE_ARRAY:
			for item in v:
				var cn := RestaurantRTypes.normalize_token(str(item))
				if not cn.is_empty():
					out[cn] = true
		TYPE_STRING:
			var s := str(v).strip_edges()
			if s.begins_with("["):
				var parsed: Variant = JSON.parse_string(s)
				_append_allowed_variant(parsed, out)
			else:
				for part in s.replace("|", ",").split(","):
					var p := part.strip_edges()
					if not p.is_empty():
						var cn2 := RestaurantRTypes.normalize_token(p)
						if not cn2.is_empty():
							out[cn2] = true
		_:
			var cn3 := RestaurantRTypes.normalize_token(str(v))
			if not cn3.is_empty():
				out[cn3] = true
