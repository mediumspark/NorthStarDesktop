class_name TutorialLessonBase
extends Control

## Shared step-through UI; each lesson scene instances [lesson_common.tscn](res://scenes/tutorials/lesson_common.tscn) and overrides this script.

const SCENE_HUB := "res://scenes/tutorials/tutorial_hub.tscn"
const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"

@export var lesson_id: String = ""

var _step: int = 0
var _steps: Array = []
var _next_locked: bool = false


func _game_menu() -> Node:
	return get_node("/root/GameMenu")


func _ready() -> void:
	var menu := _game_menu()
	menu.register_context(menu.Context.IN_MATCH, _go_main_menu)
	%BackHub.pressed.connect(_go_hub)
	%MainMenuButton.pressed.connect(_go_main_menu)
	%NextButton.pressed.connect(_on_next_pressed)
	_steps = TutorialText.steps_for_lesson_id(lesson_id)
	if _steps.is_empty():
		%StepTitle.text = "Tutorial"
		%LessonBody.text = "[color=red]Missing lesson data for id: %s[/color]" % lesson_id
		%NextButton.disabled = true
		return
	_sync_step()


func _exit_tree() -> void:
	_game_menu().clear_context()


func _go_hub() -> void:
	get_tree().change_scene_to_file(SCENE_HUB)


func _go_main_menu() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)


func _on_next_pressed() -> void:
	if %NextButton.disabled:
		return
	_advance()


func _advance() -> void:
	_step += 1
	if _step >= _steps.size():
		TutorialProgress.mark_completed(lesson_id)
		_go_hub()
		return
	_sync_step()


func allow_next() -> void:
	_next_locked = false
	%NextButton.disabled = false


func lock_next() -> void:
	_next_locked = true
	%NextButton.disabled = true


func _sync_step() -> void:
	var s: Dictionary = _steps[_step] as Dictionary
	%StepTitle.text = str(s.get("title", ""))
	%LessonBody.text = str(s.get("body", ""))
	_next_locked = false
	%NextButton.disabled = false
	TutorialVisuals.fill_default_band(lesson_id, _step, %VisualBand)
	_after_sync_step()


## Override in lessons for interactive steps (e.g. disable Next until a quiz).
func _after_sync_step() -> void:
	pass
