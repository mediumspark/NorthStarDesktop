extends RefCounted
class_name TutorialText

const PATH := "res://data/tutorials/lesson_text.json"


static func load_root() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func hub_blurb() -> String:
	var root := load_root()
	var hub: Variant = root.get("hub", {})
	if typeof(hub) != TYPE_DICTIONARY:
		return ""
	return str((hub as Dictionary).get("blurb", ""))


static func lessons_list() -> Array:
	var root := load_root()
	var ls: Variant = root.get("lessons", [])
	if typeof(ls) != TYPE_ARRAY:
		return []
	return ls as Array


static func steps_for_lesson_id(lesson_id: String) -> Array:
	for item in lessons_list():
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		if str(d.get("id", "")) == lesson_id:
			var st: Variant = d.get("steps", [])
			if typeof(st) == TYPE_ARRAY:
				return st as Array
	return []


static func lesson_meta_by_id(lesson_id: String) -> Dictionary:
	for item in lessons_list():
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		if str(d.get("id", "")) == lesson_id:
			return d
	return {}
