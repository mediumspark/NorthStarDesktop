extends Control

const SCENE_CATALOG := "res://scenes/card_catalog.tscn"
const SCENE_DECK := "res://scenes/deck_building.tscn"
const SCENE_CPU := "res://scenes/cpu_matches.tscn"
const SCENE_PVP := "res://scenes/pvp_matches.tscn"
const SCENE_ACCOUNT := "res://scenes/account_settings.tscn"


func _ready() -> void:
	_start_intro_music()
	var icon_tex := load("res://icon.svg") as Texture2D
	if icon_tex:
		%AccountButton.texture_normal = icon_tex
	%AccountButton.tooltip_text = "Account and password"
	%AccountButton.pressed.connect(_go_account)
	%CatalogButton.pressed.connect(_go_catalog)
	%DeckBuildingButton.pressed.connect(_go_deck)
	%CpuMatchesButton.pressed.connect(_go_cpu)
	%PvpMatchesButton.pressed.connect(_go_pvp)


func _start_intro_music() -> void:
	(%IntroMusic as AudioStreamPlayer).play()


func _go_catalog() -> void:
	get_tree().change_scene_to_file(SCENE_CATALOG)


func _go_deck() -> void:
	get_tree().change_scene_to_file(SCENE_DECK)


func _go_cpu() -> void:
	get_tree().change_scene_to_file(SCENE_CPU)


func _go_pvp() -> void:
	get_tree().change_scene_to_file(SCENE_PVP)


func _go_account() -> void:
	get_tree().change_scene_to_file(SCENE_ACCOUNT)
