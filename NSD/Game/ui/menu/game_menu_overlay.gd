extends CanvasLayer
class_name GameMenuOverlay

signal resume_pressed
signal settings_pressed
signal surrender_pressed
signal exit_game_pressed
signal confirm_yes
signal confirm_no

@onready var _backdrop: ColorRect = %Backdrop
@onready var _pause_panel: PanelContainer = %PausePanel
@onready var _settings_panel = %SettingsPanel
@onready var _confirm_panel: PanelContainer = %ConfirmPanel
@onready var _title: Label = %PauseTitle
@onready var _resume_btn: Button = %ResumeButton
@onready var _settings_btn: Button = %SettingsButton
@onready var _surrender_btn: Button = %SurrenderButton
@onready var _exit_btn: Button = %ExitGameButton
@onready var _confirm_message: Label = %ConfirmMessage


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_btn.pressed.connect(func () -> void: resume_pressed.emit())
	_settings_btn.pressed.connect(_on_settings_pressed)
	_surrender_btn.pressed.connect(func () -> void: surrender_pressed.emit())
	_exit_btn.pressed.connect(func () -> void: exit_game_pressed.emit())
	%ConfirmYesButton.pressed.connect(func () -> void: confirm_yes.emit())
	%ConfirmNoButton.pressed.connect(func () -> void: confirm_no.emit())
	_settings_panel.back_pressed.connect(_on_settings_back)


func configure_for_context(context: int) -> void:
	match context:
		0: # MAIN_MENU
			_title.text = "Menu"
			_resume_btn.text = "Close"
			_surrender_btn.visible = false
		1: # IN_MATCH
			_title.text = "Paused"
			_resume_btn.text = "Resume"
			_surrender_btn.visible = true
		_:
			_title.text = "Menu"
			_resume_btn.text = "Close"
			_surrender_btn.visible = false


func set_surrender_enabled(enabled: bool) -> void:
	_surrender_btn.disabled = not enabled


func open_menu() -> void:
	_show_pause_panel()
	visible = true


func close_menu() -> void:
	_show_pause_panel()
	visible = false


func is_open() -> bool:
	return visible


func is_settings_visible() -> bool:
	return _settings_panel.visible


func is_confirm_visible() -> bool:
	return _confirm_panel.visible


func show_pause_panel() -> void:
	_show_pause_panel()


func show_settings() -> void:
	_pause_panel.visible = false
	_confirm_panel.visible = false
	_settings_panel.visible = true
	_settings_panel.sync_from_settings()


func show_confirm(message: String) -> void:
	_confirm_message.text = message
	_pause_panel.visible = false
	_settings_panel.visible = false
	_confirm_panel.visible = true


func _show_pause_panel() -> void:
	_pause_panel.visible = true
	_settings_panel.visible = false
	_confirm_panel.visible = false


func _on_settings_pressed() -> void:
	show_settings()


func _on_settings_back() -> void:
	_show_pause_panel()
