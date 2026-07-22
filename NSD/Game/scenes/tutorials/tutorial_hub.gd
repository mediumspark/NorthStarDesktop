extends Control

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"


func _game_menu() -> Node:
	return get_node("/root/GameMenu")


func _ready() -> void:
	var menu := _game_menu()
	menu.register_context(menu.Context.SCREEN)
	%BackButton.pressed.connect(_on_back)
	%StartButton.pressed.connect(_on_start)
	%BlurbLabel.text = TutorialText.hub_blurb()
	var lessons := TutorialText.lessons_list()
	var i := 0
	for item in lessons:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var lid := str(d.get("id", ""))
		var scene_path := str(d.get("scene", ""))
		if lid.is_empty() or scene_path.is_empty():
			continue
		var title := str(d.get("title", lid))
		if TutorialProgress.is_completed(lid):
			title = "%s  (done)" % title
		%LessonList.add_item(title)
		%LessonList.set_item_metadata(i, scene_path)
		i += 1
	if i == 0:
		%LessonList.add_item("(No lessons configured.)")
	elif %LessonList.item_count > 0:
		%LessonList.select(0)


func _exit_tree() -> void:
	_game_menu().clear_context()


func _on_back() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)


func _on_start() -> void:
	var sel: PackedInt32Array = %LessonList.get_selected_items()
	if sel.is_empty():
		return
	var idx := int(sel[0])
	var path: Variant = %LessonList.get_item_metadata(idx)
	var p := str(path)
	if p.is_empty():
		return
	get_tree().change_scene_to_file(p)
