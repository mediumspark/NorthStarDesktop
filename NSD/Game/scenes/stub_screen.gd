extends Control

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)
