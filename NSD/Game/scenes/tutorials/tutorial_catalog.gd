extends RefCounted
class_name TutorialCatalog

const MIN_PATH := "res://data/tutorials/tutorials_min_catalog.json"


static func load_tables() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(MIN_PATH):
		return out
	var f := FileAccess.open(MIN_PATH, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	return parsed as Dictionary


static func row_by_code(tables: Dictionary, table: String, code: String) -> Dictionary:
	var rows: Variant = tables.get(table, [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = row
		if DeckRules.row_id(r) == code:
			return r
	return {}
