class_name CardTarget
extends RefCounted

## Identifies where a card target lives during effect resolution.

const ZONE_HAND := "hand"
const ZONE_FOODS := "foods"
const ZONE_OPPONENT_FOODS := "opponent_foods"
const ZONE_SETUP_LINE := "setup_line"
const ZONE_OPPONENT_SETUP_LINE := "opponent_setup_line"


static func candidates_from_hand(
	ctx: MatchEffectContext,
	player: int,
	table_filter: String = "",
	tag_filter: String = ""
) -> Array:
	var out: Array = []
	var hand: Array = ctx.match_ref.get_hand(player)
	for i in range(hand.size()):
		var card: Variant = hand[i]
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		var table := str(d.get("table", ""))
		if not table_filter.is_empty() and table != table_filter:
			continue
		var row := ctx.card_row(d)
		if not tag_filter.is_empty() and not CardTags.has_tag(table, row, tag_filter):
			continue
		out.append(_candidate(ZONE_HAND, player, i, table, str(d.get("id", "")), _label(ctx, table, row)))
	return out


static func candidates_from_foods(
	ctx: MatchEffectContext,
	player: int,
	tag_filter: String = ""
) -> Array:
	var out: Array = []
	for i in range(ctx.foods[player].size()):
		var meal_row: Variant = ctx.foods[player][i]
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = meal_row
		if not tag_filter.is_empty() and not CardTags.has_tag("meal_cards", row, tag_filter):
			continue
		var id_str := DeckRules.row_id(row)
		out.append(_candidate(ZONE_FOODS, player, i, "meal_cards", id_str, _label(ctx, "meal_cards", row)))
	return out


static func candidates_from_opponent_foods(ctx: MatchEffectContext, owner: int, tag_filter: String = "") -> Array:
	return candidates_from_foods(ctx, ctx.opponent(owner), tag_filter)


static func candidates_from_setup_line(
	ctx: MatchEffectContext,
	player: int,
	table_filter: String = "",
	tag_filter: String = ""
) -> Array:
	var out: Array = []
	var line: Array = ctx.line_for(player)
	for i in range(line.size()):
		var card: Variant = line[i]
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		var table := str(d.get("table", ""))
		if not table_filter.is_empty() and table != table_filter:
			continue
		var row := ctx.card_row(d)
		if not tag_filter.is_empty() and not CardTags.has_tag(table, row, tag_filter):
			continue
		out.append(
			_candidate(ZONE_SETUP_LINE, player, i, table, str(d.get("id", "")), _label(ctx, table, row))
		)
	return out


static func cpu_pick_index(candidates: Array, rng: RandomNumberGenerator) -> int:
	if candidates.is_empty():
		return -1
	return rng.randi_range(0, candidates.size() - 1)


static func apply_candidate(ctx: MatchEffectContext, candidate: Dictionary) -> void:
	var zone := str(candidate.get("zone", ""))
	var player := int(candidate.get("player", 0))
	var index := int(candidate.get("index", -1))
	match zone:
		ZONE_HAND:
			var hand: Array = ctx.match_ref.get_hand(player)
			if index < 0 or index >= hand.size():
				return
			var card: Dictionary = hand[index] as Dictionary
			ctx.match_ref.discard_card(player, card)
			hand.remove_at(index)
			ctx.match_ref.set_hand(player, hand)
		ZONE_FOODS:
			var foods: Array = ctx.foods[player]
			if index < 0 or index >= foods.size():
				return
			foods.remove_at(index)
			ctx.foods[player] = foods
		ZONE_SETUP_LINE:
			var line: Array = ctx.line_for(player)
			if index < 0 or index >= line.size():
				return
			var card: Dictionary = line[index] as Dictionary
			ctx.match_ref.discard_card(player, card)
			line.remove_at(index)
			ctx.match_ref.set_setup_line(player, line)


static func move_food_to_hand(ctx: MatchEffectContext, candidate: Dictionary) -> void:
	var player := int(candidate.get("player", 0))
	var index := int(candidate.get("index", -1))
	var foods: Array = ctx.foods[player]
	if index < 0 or index >= foods.size():
		return
	var meal_row: Dictionary = foods[index] as Dictionary
	foods.remove_at(index)
	ctx.foods[player] = foods
	var hand: Array = ctx.match_ref.get_hand(player)
	hand.append({"table": "meal_cards", "id": DeckRules.row_id(meal_row)})
	ctx.match_ref.set_hand(player, hand)


static func play_hand_card_to_setup_line(ctx: MatchEffectContext, candidate: Dictionary) -> void:
	var player := int(candidate.get("player", 0))
	var index := int(candidate.get("index", -1))
	var hand: Array = ctx.match_ref.get_hand(player)
	if index < 0 or index >= hand.size():
		return
	var card: Dictionary = hand[index] as Dictionary
	hand.remove_at(index)
	ctx.match_ref.set_hand(player, hand)
	ctx.match_ref.append_setup_line(player, card)


static func _candidate(
	zone: String,
	player: int,
	index: int,
	table: String,
	id_str: String,
	label: String
) -> Dictionary:
	return {
		"zone": zone,
		"player": player,
		"index": index,
		"table": table,
		"id": id_str,
		"label": label,
	}


static func _label(ctx: MatchEffectContext, table: String, row: Dictionary) -> String:
	if row.is_empty():
		return table
	return DeckRules.display_name_for_row(table, row)
