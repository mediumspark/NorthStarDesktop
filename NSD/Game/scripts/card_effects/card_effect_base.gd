extends RefCounted
class_name CardEffectBase

## Scriptable card logic for match rules + UI. Override hooks for gameplay; defaults are no-ops.

var table: String = ""
var id_str: String = ""
var row: Dictionary = {}


func configure(p_table: String, p_id: String, p_row: Dictionary) -> void:
	table = p_table
	id_str = p_id
	row = p_row.duplicate()


func title() -> String:
	if row.is_empty():
		return id_str if not id_str.is_empty() else "Card"
	return DeckRules.display_name_for_row(table, row)


func ability_text() -> String:
	return CardRowText.ability_from_row(row)


func effect_text() -> String:
	return CardRowText.effect_from_row(row)


func cost_line() -> String:
	return CardRowText.cost_line_for_row(table, row)


## Optional CPU-match banner on the hand card preview.
func cpu_match_hook_log() -> String:
	return ""


func is_silenced(ctx: MatchEffectContext, owner: int) -> bool:
	return ctx.is_card_silenced(owner, table)


## Called when this card is revealed left-to-right during faceoff (setup line).
func on_faceoff_reveal(ctx: MatchEffectContext, owner: int, _slot: int) -> void:
	pass


## Adjust a single meal's contribution before it is summed into score.
func modify_meal_value(ctx: MatchEffectContext, owner: int, meal_row: Dictionary, base_value: int) -> int:
	return base_value


## Adjust player's total after restaurant + meals are summed.
func modify_total_score(ctx: MatchEffectContext, owner: int, base_total: int) -> int:
	return base_total


## Called once per card on the line after meals are collected, before final totals.
func on_faceoff_before_score(ctx: MatchEffectContext, owner: int) -> void:
	pass


## Called at end of faceoff resolution for cards still on the line.
func on_round_end(ctx: MatchEffectContext, owner: int) -> void:
	pass
