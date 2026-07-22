extends Control

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"


func _game_menu() -> Node:
	return get_node("/root/GameMenu")


func _ready() -> void:
	var menu := _game_menu()
	menu.register_context(menu.Context.IN_MATCH, _on_back_pressed)
	%BackButton.pressed.connect(_on_back_pressed)


func _exit_tree() -> void:
	_game_menu().clear_context()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)
