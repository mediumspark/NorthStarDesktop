extends Node

## Persists and applies audio, brightness, and menu preferences.

const SETTINGS_PATH := "user://settings.json"

const DEFAULTS := {
	"master_volume": 100,
	"music_volume": 80,
	"sfx_volume": 100,
	"brightness": 100,
	"confirm_exit": true,
	"fullscreen": true,
}

var master_volume: int = 100
var music_volume: int = 80
var sfx_volume: int = 100
var brightness: int = 100
var confirm_exit: bool = true
var fullscreen: bool = true

var _brightness_layer: CanvasLayer
var _brightness_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	load_settings()
	_apply_all()
	_setup_brightness_overlay()


func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, "Music")
		AudioServer.set_bus_send(1, &"Master")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus(2)
		AudioServer.set_bus_name(2, "SFX")
		AudioServer.set_bus_send(2, &"Master")


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	master_volume = int(d.get("master_volume", DEFAULTS["master_volume"]))
	music_volume = int(d.get("music_volume", DEFAULTS["music_volume"]))
	sfx_volume = int(d.get("sfx_volume", DEFAULTS["sfx_volume"]))
	brightness = int(d.get("brightness", DEFAULTS["brightness"]))
	confirm_exit = bool(d.get("confirm_exit", DEFAULTS["confirm_exit"]))
	fullscreen = bool(d.get("fullscreen", DEFAULTS["fullscreen"]))


func save_settings() -> void:
	var data := {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"brightness": brightness,
		"confirm_exit": confirm_exit,
		"fullscreen": fullscreen,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func set_master_volume(value: int) -> void:
	master_volume = clampi(value, 0, 100)
	_apply_master_volume()
	save_settings()


func set_music_volume(value: int) -> void:
	music_volume = clampi(value, 0, 100)
	_apply_music_volume()
	save_settings()


func set_sfx_volume(value: int) -> void:
	sfx_volume = clampi(value, 0, 100)
	_apply_sfx_volume()
	save_settings()


func set_brightness(value: int) -> void:
	brightness = clampi(value, 0, 100)
	_apply_brightness()
	save_settings()


func set_confirm_exit(value: bool) -> void:
	confirm_exit = value
	save_settings()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_fullscreen()
	save_settings()


func _apply_all() -> void:
	_apply_master_volume()
	_apply_music_volume()
	_apply_sfx_volume()
	_apply_brightness()
	_apply_fullscreen()


func _apply_master_volume() -> void:
	_set_bus_volume(&"Master", master_volume)


func _apply_music_volume() -> void:
	_set_bus_volume(&"Music", music_volume)


func _apply_sfx_volume() -> void:
	_set_bus_volume(&"SFX", sfx_volume)


func _set_bus_volume(bus_name: StringName, percent: int) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear := float(percent) / 100.0
	if percent <= 0:
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _apply_brightness() -> void:
	if _brightness_rect == null:
		return
	var dim := 1.0 - (float(brightness) / 100.0)
	_brightness_rect.color = Color(0.0, 0.0, 0.0, dim * 0.85)


func _apply_fullscreen() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _setup_brightness_overlay() -> void:
	_brightness_layer = CanvasLayer.new()
	_brightness_layer.name = "BrightnessOverlay"
	_brightness_layer.layer = 200
	_brightness_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_brightness_layer)
	_brightness_rect = ColorRect.new()
	_brightness_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brightness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brightness_layer.add_child(_brightness_rect)
	_apply_brightness()
