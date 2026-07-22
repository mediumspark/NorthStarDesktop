extends PanelContainer
class_name GameSettingsPanel

signal back_pressed

@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _brightness_slider: HSlider = %BrightnessSlider
@onready var _fullscreen_check: CheckBox = %FullscreenCheck
@onready var _confirm_exit_check: CheckBox = %ConfirmExitCheck


func _ready() -> void:
	%BackButton.pressed.connect(func () -> void: back_pressed.emit())
	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_brightness_slider.value_changed.connect(_on_brightness_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_confirm_exit_check.toggled.connect(_on_confirm_exit_toggled)
	_sync_from_settings()


func _settings() -> Node:
	return get_node("/root/GameSettings")


func sync_from_settings() -> void:
	_sync_from_settings()


func _sync_from_settings() -> void:
	var gs := _settings()
	_master_slider.set_value_no_signal(float(gs.master_volume))
	_music_slider.set_value_no_signal(float(gs.music_volume))
	_sfx_slider.set_value_no_signal(float(gs.sfx_volume))
	_brightness_slider.set_value_no_signal(float(gs.brightness))
	_fullscreen_check.set_pressed_no_signal(bool(gs.fullscreen))
	_confirm_exit_check.set_pressed_no_signal(bool(gs.confirm_exit))
	_update_labels()


func _update_labels() -> void:
	%MasterValue.text = "%d%%" % int(_master_slider.value)
	%MusicValue.text = "%d%%" % int(_music_slider.value)
	%SfxValue.text = "%d%%" % int(_sfx_slider.value)
	%BrightnessValue.text = "%d%%" % int(_brightness_slider.value)


func _on_master_changed(v: float) -> void:
	_settings().set_master_volume(int(v))
	_update_labels()


func _on_music_changed(v: float) -> void:
	_settings().set_music_volume(int(v))
	_update_labels()


func _on_sfx_changed(v: float) -> void:
	_settings().set_sfx_volume(int(v))
	_update_labels()


func _on_brightness_changed(v: float) -> void:
	_settings().set_brightness(int(v))
	_update_labels()


func _on_fullscreen_toggled(on: bool) -> void:
	_settings().set_fullscreen(on)


func _on_confirm_exit_toggled(on: bool) -> void:
	_settings().set_confirm_exit(on)
