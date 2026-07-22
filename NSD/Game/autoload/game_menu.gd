extends Node

## Global Escape pause menu — context-aware actions and settings access.

enum Context {
	MAIN_MENU = 0,
	IN_MATCH = 1,
	SCREEN = 2,
}

const OVERLAY_SCENE_PATH := "res://ui/menu/game_menu_overlay.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var _overlay
var _context: int = Context.SCREEN
var _surrender_callback: Callable = Callable()
var _surrender_allowed: Callable = Callable()
var _pending_confirm: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = load(OVERLAY_SCENE_PATH).instantiate()
	add_child(_overlay)
	_overlay.visible = false
	_overlay.resume_pressed.connect(_on_resume)
	_overlay.surrender_pressed.connect(_on_surrender)
	_overlay.exit_game_pressed.connect(_on_exit_game)
	_overlay.confirm_yes.connect(_on_confirm_yes)
	_overlay.confirm_no.connect(_on_confirm_no)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE and key_event.physical_keycode != KEY_ESCAPE:
		return
	if _overlay == null:
		return
	if _overlay.is_confirm_visible():
		_overlay.show_pause_panel()
		get_viewport().set_input_as_handled()
		return
	if _overlay.is_settings_visible():
		_overlay.show_pause_panel()
		get_viewport().set_input_as_handled()
		return
	if _overlay.is_open():
		close_menu()
	else:
		open_menu()
	get_viewport().set_input_as_handled()


func register_context(
	context: int,
	surrender_callback: Callable = Callable(),
	surrender_allowed: Callable = Callable()
) -> void:
	_context = context
	_surrender_callback = surrender_callback
	_surrender_allowed = surrender_allowed


func clear_context() -> void:
	if _overlay.is_open():
		close_menu()
	_context = Context.SCREEN
	_surrender_callback = Callable()
	_surrender_allowed = Callable()


func open_menu() -> void:
	_overlay.configure_for_context(_context)
	if _context == Context.IN_MATCH and _surrender_allowed.is_valid():
		_overlay.set_surrender_enabled(bool(_surrender_allowed.call()))
	else:
		_overlay.set_surrender_enabled(_context == Context.IN_MATCH)
	_overlay.open_menu()
	get_tree().paused = true


func close_menu() -> void:
	_overlay.close_menu()
	get_tree().paused = false
	_pending_confirm = ""


func is_open() -> bool:
	return _overlay.is_open()


func _settings() -> Node:
	return get_node("/root/GameSettings")


func request_exit_game() -> void:
	if bool(_settings().confirm_exit):
		_pending_confirm = "exit"
		if not _overlay.is_open():
			open_menu()
		_overlay.show_confirm("Exit the game?")
	else:
		get_tree().quit()


func request_surrender() -> void:
	if _context != Context.IN_MATCH:
		return
	if bool(_settings().confirm_exit):
		_pending_confirm = "surrender"
		if not _overlay.is_open():
			open_menu()
		_overlay.show_confirm("Surrender and return to main menu?")
	else:
		_do_surrender()


func _on_resume() -> void:
	close_menu()


func _on_surrender() -> void:
	request_surrender()


func _on_exit_game() -> void:
	request_exit_game()


func _on_confirm_yes() -> void:
	var kind := _pending_confirm
	_pending_confirm = ""
	_overlay.show_pause_panel()
	match kind:
		"exit":
			close_menu()
			get_tree().quit()
		"surrender":
			close_menu()
			_do_surrender()
		_:
			pass


func _on_confirm_no() -> void:
	_pending_confirm = ""
	_overlay.show_pause_panel()


func _do_surrender() -> void:
	if _surrender_callback.is_valid():
		_surrender_callback.call()
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
