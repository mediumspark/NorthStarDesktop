extends RefCounted
class_name TutorialProgress

const SAVE_PATH := "user://tutorial_progress.json"


static func load_completed() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func is_completed(lesson_id: String) -> bool:
	var d := load_completed()
	var arr: Variant = d.get("completed", [])
	if typeof(arr) != TYPE_ARRAY:
		return false
	for v in arr:
		if str(v) == lesson_id:
			return true
	return false


static func mark_completed(lesson_id: String) -> void:
	if lesson_id.is_empty():
		return
	var d := load_completed()
	var out: Array = []
	var arr: Variant = d.get("completed", [])
	if typeof(arr) == TYPE_ARRAY:
		for v in arr:
			out.append(str(v))
	if out.find(lesson_id) >= 0:
		return
	out.append(lesson_id)
	var save := {"completed": out}
	var text := JSON.stringify(save)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
