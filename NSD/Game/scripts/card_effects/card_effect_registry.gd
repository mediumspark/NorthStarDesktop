extends RefCounted
class_name CardEffectRegistry

## Loads per-card scripts from `catalog_generated/` (see `tools/generate_card_effect_scripts.py`).
## One script exists for each catalog row whose Effect column is non-empty (same rules as CardRowText.effect_from_row).
## Any other card uses CardEffectGeneric.

const _GENERATED_DIR := "res://scripts/card_effects/catalog_generated/"


static func _script_path_for(table: String, id_str: String) -> String:
	return _GENERATED_DIR + "effect_%s_%s.gd" % [table, id_str]


static func make(table: String, id_str: String, row: Dictionary) -> CardEffectBase:
	var path := _script_path_for(table, id_str)
	var inst: CardEffectBase = null
	if ResourceLoader.exists(path):
		var scr: Script = load(path) as Script
		if scr != null:
			inst = scr.new() as CardEffectBase
	if inst == null:
		inst = CardEffectGeneric.new()
	inst.configure(table, id_str, row)
	return inst
