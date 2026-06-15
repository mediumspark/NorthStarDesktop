class_name CardEffectHelpers
extends RefCounted


static func meal_id(table: String, row: Dictionary) -> String:
	return "%s:%s" % [table, DeckRules.row_id(row)]


static func base_meal_value(row: Dictionary) -> int:
	return SchemaKeys.get_food_rating(row)


static func count_meals_with_tag(ctx: MatchEffectContext, player: int, tag: String) -> int:
	var n := 0
	for row in ctx.foods[player]:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if CardTags.has_tag("meal_cards", row, tag):
			n += 1
	return n


static func count_line_cards(ctx: MatchEffectContext, player: int, table: String, tag: String = "") -> int:
	var n := 0
	for card in ctx.line_for(player):
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		if str(d.get("table", "")) != table:
			continue
		if tag.is_empty():
			n += 1
			continue
		var row := ctx.card_row(d)
		if CardTags.has_tag(table, row, tag):
			n += 1
	return n


static func sum_meals_with_tag(ctx: MatchEffectContext, player: int, tag: String) -> int:
	var total := 0
	for row in ctx.foods[player]:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if CardTags.has_tag("meal_cards", row, tag):
			total += base_meal_value(row)
	return total


static func sum_staff_cost_on_line(ctx: MatchEffectContext, player: int) -> int:
	var total := 0
	for card in ctx.line_for(player):
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		if str(d.get("table", "")) != "staff_cards":
			continue
		total += SchemaKeys.get_influence_cost(ctx.card_row(d))
	return total


static func only_staff_on_line(ctx: MatchEffectContext, player: int) -> bool:
	var has_staff := false
	for card in ctx.line_for(player):
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var t := str((card as Dictionary).get("table", ""))
		if t == "staff_cards":
			has_staff = true
		elif t in ["meal_cards", "event_cards"]:
			return false
	return has_staff


static func only_meal_on_field(ctx: MatchEffectContext, player: int) -> bool:
	return ctx.foods[player].size() == 1


static func barista_count_on_line(ctx: MatchEffectContext, player: int) -> int:
	var n := 0
	for card in ctx.line_for(player):
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		if str(d.get("table", "")) != "staff_cards":
			continue
		var name := DeckRules.display_name_for_row("staff_cards", ctx.card_row(d)).to_lower()
		if name.contains("barista"):
			n += 1
	return n


static func discard_hand_cards_with_tag(ctx: MatchEffectContext, player: int, tag: String) -> int:
	var hand: Array = ctx.match_ref.get_hand(player)
	var removed := 0
	var keep: Array = []
	for card in hand:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		var row := ctx.card_row(d)
		if CardTags.has_tag(str(d.get("table", "")), row, tag):
			ctx.match_ref.discard_card(player, d)
			removed += 1
		else:
			keep.append(d)
	ctx.match_ref.set_hand(player, keep)
	return removed


static func draw_cards(ctx: MatchEffectContext, player: int, count: int) -> int:
	return ctx.match_ref.draw_cards(player, count)


static func move_bbq_from_discard_to_hand(ctx: MatchEffectContext, player: int) -> bool:
	return ctx.match_ref.move_tagged_from_discard_to_hand(player, "bbq")


static func remove_foods_with_tag(ctx: MatchEffectContext, player: int, tag: String) -> int:
	var kept: Array = []
	var removed := 0
	for row in ctx.foods[player]:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if CardTags.has_tag("meal_cards", row, tag):
			removed += 1
		else:
			kept.append(row)
	ctx.foods[player] = kept
	return removed


static func resolve_meal_value(ctx: MatchEffectContext, player: int, meal_row: Dictionary) -> int:
	var mid := meal_id("meal_cards", meal_row)
	if ctx.meal_value_override.has(mid):
		return int(ctx.meal_value_override[mid])
	var card := {"table": "meal_cards", "id": DeckRules.row_id(meal_row)}
	var fx := ctx.effect_for(card)
	if fx == null:
		return base_meal_value(meal_row)
	return fx.modify_meal_value(ctx, player, meal_row, base_meal_value(meal_row))
