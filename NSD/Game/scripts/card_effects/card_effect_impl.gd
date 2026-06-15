class_name CardEffectImpl
extends RefCounted

## Gameplay implementations keyed by card id. Called from catalog_generated effect scripts.


static func on_reveal(fx: CardEffectBase, ctx: MatchEffectContext, owner: int, slot: int) -> void:
	match fx.id_str:
		"PROTOMBSEVEN052":
			_discard_celebrity_staff_after_slot(ctx, owner, slot)
		"PROTOMBSEVEN054":
			var n := CardEffectHelpers.discard_hand_cards_with_tag(ctx, owner, "bbq")
			if n > 0:
				CardEffectHelpers.draw_cards(ctx, owner, n)
				ctx.log("%s discarded %d BBQ and drew %d." % [ctx.player_name(owner), n, n])
		"PROTOMBSEVEN056":
			_play_celebrity_from_hand_trash_rest(ctx, owner)
		"PROTOMBSEVEN057":
			var v := _sum_hand_meal_tag_value(ctx, owner, "bev")
			if v > 0:
				CardEffectHelpers.discard_hand_cards_with_tag(ctx, owner, "bev")
				ctx.add_score(owner, v)
				ctx.log("%s added %d from discarded Bevs." % [ctx.player_name(owner), v])
		"PROTOMBSEVEN058":
			ctx.staff_silenced_this_round = true
			ctx.log("All staff silenced for the rest of the round.")
		"PROTOFNFEVEN083":
			_add_to_all_foods(ctx, owner, 1, true)
		"PROTOFNFEVEN084":
			if ctx.is_mobile_restaurant(owner):
				_zero_all_foods(ctx, owner)
				ctx.log("%s food truck: all food set to 0." % ctx.player_name(owner))
			else:
				_add_to_all_foods(ctx, owner, 2, false)
		"PROTOFNFEVEN087":
			var heads := ctx.rng.randi_range(0, 1) == 1
			ctx.coin_flip_winner_takes_all = 0 if heads else 1
			ctx.log("Coin flip: %s." % ("heads — both gain a star" if heads else "tails — neither gains a star"))
		"PROTOFNFEVEN088":
			if slot == 0:
				ctx.log("%s wagered influence on winning this faceoff (simplified)." % ctx.player_name(owner))
		"PROTOFNFEVEN089":
			if slot == ctx.line_for(owner).size() - 1:
				_trade_food_discard(ctx, owner)
		"PROTOMBSSTAF047":
			var bbq := CardEffectHelpers.count_line_cards(ctx, owner, "staff_cards", "bbq")
			bbq += CardEffectHelpers.count_meals_with_tag(ctx, owner, "bbq")
			if bbq > 0:
				var d := CardEffectHelpers.draw_cards(ctx, owner, bbq)
				ctx.log("%s drew %d (BBQ in play)." % [ctx.player_name(owner), d])
		"PROTOFNFSTAF076":
			var drawn := 0
			var guard := 0
			while guard < 5:
				guard += 1
				if CardEffectHelpers.draw_cards(ctx, owner, 1) <= 0:
					break
				drawn += 1
				var hand: Array = ctx.match_ref.get_hand(owner)
				if hand.is_empty():
					break
				var c: Dictionary = hand[hand.size() - 1]
				var t := str(c.get("table", ""))
				if t in ["event_cards", "support_cards"]:
					break
			if drawn > 0:
				ctx.log("%s drew %d card(s)." % [ctx.player_name(owner), drawn])
		"PROTOFNFSTAF077":
			var d1 := CardEffectHelpers.draw_cards(ctx, owner, 1)
			var d2 := CardEffectHelpers.draw_cards(ctx, ctx.opponent(owner), 1)
			if d1 > 0 and d2 > 0:
				var h1: Array = ctx.match_ref.get_hand(owner)
				var h2: Array = ctx.match_ref.get_hand(ctx.opponent(owner))
				if not h1.is_empty() and not h2.is_empty():
					var t1 := str((h1[h1.size() - 1] as Dictionary).get("table", ""))
					var t2 := str((h2[h2.size() - 1] as Dictionary).get("table", ""))
					if t1 == t2:
						ctx.match_ref.discard_card(owner, h1[h1.size() - 1])
						h1.pop_back()
						ctx.match_ref.discard_card(ctx.opponent(owner), h2[h2.size() - 1])
						h2.pop_back()
						ctx.match_ref.set_hand(owner, h1)
						ctx.match_ref.set_hand(ctx.opponent(owner), h2)
						ctx.log("Matching types discarded.")
		"PROTOFNFSTAF079":
			var hand_sz: Array = ctx.match_ref.get_hand(owner)
			var food_n: int = ctx.foods[owner].size()
			if not hand_sz.is_empty() and food_n > 0:
				for c in hand_sz:
					ctx.match_ref.discard_card(owner, c)
				ctx.match_ref.set_hand(owner, [])
				ctx.foods[owner] = []
				ctx.log("%s discarded hand and cleared all food in play." % ctx.player_name(owner))
		"PROTOMBSSUPP059":
			if CardEffectHelpers.move_bbq_from_discard_to_hand(ctx, owner):
				ctx.log("%s returned a BBQ from discard." % ctx.player_name(owner))
		"PROTOMBSSUPP062":
			ctx.silenced_chef[ctx.opponent(owner)] = true
			ctx.log("Opposing chef silenced this round.")
		"PROTOMBSSUPP063":
			ctx.silenced_restaurant[ctx.opponent(owner)] = true
			ctx.log("Opposing restaurant silenced this round.")
		"PROTOMBSSUPP064":
			if not ctx.foods[owner].is_empty():
				var meal: Dictionary = ctx.foods[owner].pop_back()
				ctx.match_ref.get_hand(owner) # ensure array exists
				var h: Array = ctx.match_ref.get_hand(owner)
				h.append({"table": "meal_cards", "id": DeckRules.row_id(meal)})
				ctx.match_ref.set_hand(owner, h)
				ctx.log("%s returned a meal to hand." % ctx.player_name(owner))
		"PROTOMBSSUPP061":
			var h1 := ctx.rng.randi_range(0, 1) == 1
			var h2 := ctx.rng.randi_range(0, 1) == 1
			if h1 and h2:
				ctx.log("Support: double heads — extra star on win (simplified).")
			else:
				ctx.silenced_all_cards[owner] = true
				ctx.log("Support: any tails — your cards silenced.")


static func before_score(fx: CardEffectBase, ctx: MatchEffectContext, owner: int) -> void:
	match fx.id_str:
		"PROTOMBSEVEN053":
			_halve_foods(ctx, owner)
			_halve_foods(ctx, ctx.opponent(owner))
			ctx.log("All meals halved this round.")
		"PROTOMBSSTAF046":
			_breakfast_to_highest_bev(ctx, owner)
		"PROTOMBSSTAF048":
			_set_tagged_meals_value(ctx, owner, "whole_hog", 28)
		"PROTOMBSSTAF049":
			var bbq := CardEffectHelpers.sum_meals_with_tag(ctx, owner, "bbq")
			if bbq > 0:
				ctx.add_score(ctx.opponent(owner), -bbq)
				ctx.log("%s subtracted %d BBQ from opponent." % [ctx.player_name(owner), bbq])
		"PROTOMBSSUPP060":
			ctx.add_score(MatchEffectContext.P_HUMAN, CardEffectHelpers.sum_staff_cost_on_line(ctx, MatchEffectContext.P_HUMAN))
			ctx.add_score(MatchEffectContext.P_CPU, CardEffectHelpers.sum_staff_cost_on_line(ctx, MatchEffectContext.P_CPU))
			ctx.log("Both players add staff influence costs to score.")
		"PROTOMBSSTAF044":
			var mult := 3 if CardEffectHelpers.barista_count_on_line(ctx, owner) >= 2 else 2
			for meal_row in ctx.foods[owner]:
				if typeof(meal_row) != TYPE_DICTIONARY:
					continue
				if not CardTags.has_tag("meal_cards", meal_row, "bev") and not CardTags.has_tag("meal_cards", meal_row, "coffee"):
					continue
				var mid := CardEffectHelpers.meal_id("meal_cards", meal_row)
				var v := CardEffectHelpers.base_meal_value(meal_row)
				var meal_fx := ctx.effect_for({"table": "meal_cards", "id": DeckRules.row_id(meal_row)})
				if meal_fx != null:
					v = meal_fx.modify_meal_value(ctx, owner, meal_row, v)
				ctx.set_meal_value(mid, v * mult)
			ctx.log("%s: Bevs x%d." % [ctx.player_name(owner), mult])
		"PROTOMBSSTAF050":
			if CardEffectHelpers.only_staff_on_line(ctx, owner):
				var hand: Array = ctx.match_ref.get_hand(owner)
				if not hand.is_empty():
					ctx.match_ref.discard_card(owner, hand[0])
					hand.remove_at(0)
					ctx.match_ref.set_hand(owner, hand)
				if not ctx.foods[ctx.opponent(owner)].is_empty():
					ctx.foods[ctx.opponent(owner)].pop_back()
					ctx.log("%s trashed a hand card and removed opponent meal." % [ctx.player_name(owner)])
		"PROTOMBSSTAF051":
			if CardEffectHelpers.only_staff_on_line(ctx, owner):
				var hand: Array = ctx.match_ref.get_hand(owner)
				if not hand.is_empty():
					ctx.match_ref.discard_card(owner, hand[0])
					hand.remove_at(0)
					ctx.match_ref.set_hand(owner, hand)
				ctx.add_score(owner, 3)
				ctx.log("%s trashed a hand card to empower Bevs (+3)." % [ctx.player_name(owner)])
		"PROTOMBSMEAL033":
			_double_tagged_meals(ctx, owner, "rib")
		"PROTOMBSMEAL036":
			_add_to_other_meals(ctx, owner, fx, 3, "coffee")


static func modify_meal(fx: CardEffectBase, ctx: MatchEffectContext, owner: int, meal_row: Dictionary, base: int) -> int:
	match fx.id_str:
		"PROTOMBSMEAL031", "PROTOMBSMEAL032":
			return base + 2 * CardEffectHelpers.count_meals_with_tag(ctx, owner, "rib")
		"PROTOMBSMEAL035":
			if CardEffectHelpers.only_meal_on_field(ctx, owner):
				return 15
		"PROTOMBSMEAL039":
			if CardEffectHelpers.only_meal_on_field(ctx, owner):
				return 28
		"PROTOMBSMEAL036":
			return base # self; others handled in before_score
		"PROTOMBSMEAL033":
			return base # doubling applied globally
	return base


static func modify_total(fx: CardEffectBase, ctx: MatchEffectContext, owner: int, base: int) -> int:
	return base


static func on_round_end(fx: CardEffectBase, ctx: MatchEffectContext, owner: int) -> void:
	match fx.id_str:
		"PROTOMBSSTAF045":
			ctx.next_round_bev_cost_zero[owner] = true
			ctx.log("%s: next setup Bevs cost 0 influence." % ctx.player_name(owner))
		"PROTOMBSSUPP065":
			var h: Array = ctx.match_ref.get_hand(owner)
			for meal_row in ctx.foods[owner]:
				if typeof(meal_row) == TYPE_DICTIONARY:
					h.append({"table": "meal_cards", "id": DeckRules.row_id(meal_row)})
			ctx.match_ref.set_hand(owner, h)
			ctx.foods[owner] = []
			ctx.log("%s returned all meals to hand." % ctx.player_name(owner))
		"PROTOFNFEVEN082":
			pass # win-triggered; simplified in star rules via score


# --- helpers ---


static func _discard_celebrity_staff_after_slot(ctx: MatchEffectContext, owner: int, slot: int) -> void:
	var line: Array = ctx.line_for(owner)
	var trimmed: Array = []
	for i in range(line.size()):
		var card: Dictionary = line[i] as Dictionary
		if i <= slot:
			trimmed.append(card)
			continue
		if str(card.get("table", "")) != "staff_cards":
			trimmed.append(card)
			continue
		if CardTags.has_tag("staff_cards", ctx.card_row(card), "celebrity"):
			ctx.log("Celebrity staff after event discarded.")
			continue
		trimmed.append(card)
	ctx.match_ref.set_setup_line(owner, trimmed)


static func _play_celebrity_from_hand_trash_rest(ctx: MatchEffectContext, owner: int) -> void:
	var hand: Array = ctx.match_ref.get_hand(owner)
	var kept: Array = []
	var played := false
	for card in hand:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		if not played and str(d.get("table", "")) == "staff_cards" and CardTags.has_tag("staff_cards", ctx.card_row(d), "celebrity"):
			ctx.match_ref.append_setup_line(owner, d)
			played = true
		else:
			ctx.match_ref.discard_card(owner, d)
	ctx.match_ref.set_hand(owner, kept if played else hand)
	if played:
		ctx.log("%s played a celebrity staff and trashed hand." % ctx.player_name(owner))


static func _sum_hand_meal_tag_value(ctx: MatchEffectContext, player: int, tag: String) -> int:
	var total := 0
	for card in ctx.match_ref.get_hand(player):
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = card
		if str(d.get("table", "")) != "meal_cards":
			continue
		var row := ctx.card_row(d)
		if CardTags.has_tag("meal_cards", row, tag):
			total += CardEffectHelpers.base_meal_value(row)
	return total


static func _add_to_all_foods(ctx: MatchEffectContext, owner: int, amount: int, double_if_truck: bool) -> void:
	var mult := 2 if (double_if_truck and ctx.is_mobile_restaurant(owner)) else 1
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		var mid := CardEffectHelpers.meal_id("meal_cards", meal_row)
		var cur := CardEffectHelpers.base_meal_value(meal_row)
		if ctx.meal_value_override.has(mid):
			cur = int(ctx.meal_value_override[mid])
		ctx.set_meal_value(mid, cur + amount * mult)
	ctx.log("%s: %+d to all food%s." % [ctx.player_name(owner), amount * mult, " (doubled)" if mult == 2 else ""])


static func _zero_all_foods(ctx: MatchEffectContext, owner: int) -> void:
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		ctx.set_meal_value(CardEffectHelpers.meal_id("meal_cards", meal_row), 0)


static func _halve_foods(ctx: MatchEffectContext, player: int) -> void:
	for meal_row in ctx.foods[player]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		var mid := CardEffectHelpers.meal_id("meal_cards", meal_row)
		var cur := CardEffectHelpers.resolve_meal_value(ctx, player, meal_row)
		ctx.set_meal_value(mid, cur / 2)


static func _double_tagged_meals(ctx: MatchEffectContext, owner: int, tag: String) -> void:
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		if not CardTags.has_tag("meal_cards", meal_row, tag):
			continue
		var mid := CardEffectHelpers.meal_id("meal_cards", meal_row)
		var cur := CardEffectHelpers.resolve_meal_value(ctx, owner, meal_row)
		ctx.set_meal_value(mid, cur * 2)


static func _add_to_other_meals(ctx: MatchEffectContext, owner: int, self_fx: CardEffectBase, amount: int, tag: String) -> void:
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		if DeckRules.row_id(meal_row) == self_fx.id_str:
			continue
		if not CardTags.has_tag("meal_cards", meal_row, tag):
			continue
		var mid := CardEffectHelpers.meal_id("meal_cards", meal_row)
		var cur := CardEffectHelpers.resolve_meal_value(ctx, owner, meal_row)
		ctx.set_meal_value(mid, cur + amount)


static func _set_tagged_meals_value(ctx: MatchEffectContext, owner: int, tag: String, value: int) -> void:
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		if CardTags.has_tag("meal_cards", meal_row, tag):
			ctx.set_meal_value(CardEffectHelpers.meal_id("meal_cards", meal_row), value)


static func _breakfast_to_highest_bev(ctx: MatchEffectContext, owner: int) -> void:
	var bonus := 0
	var kept: Array = []
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		if CardTags.has_tag("meal_cards", meal_row, "breakfast"):
			bonus += CardEffectHelpers.base_meal_value(meal_row)
		else:
			kept.append(meal_row)
	ctx.foods[owner] = kept
	if bonus <= 0:
		return
	var best := 0
	var best_mid := ""
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		if not CardTags.has_tag("meal_cards", meal_row, "bev") and not CardTags.has_tag("meal_cards", meal_row, "coffee"):
			continue
		var v := CardEffectHelpers.resolve_meal_value(ctx, owner, meal_row)
		if v >= best:
			best = v
			best_mid = CardEffectHelpers.meal_id("meal_cards", meal_row)
	if not best_mid.is_empty():
		ctx.set_meal_value(best_mid, best + bonus)
		ctx.log("%s merged Breakfast into highest Bev (+%d)." % [ctx.player_name(owner), bonus])


static func _multiply_bev_meals_on_field(ctx: MatchEffectContext, owner: int, base_total: int, mult: int) -> int:
	var rest := SchemaKeys.get_base_rating(ctx.restaurant_row(owner))
	var meal_sum := 0
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		var v := CardEffectHelpers.resolve_meal_value(ctx, owner, meal_row)
		if CardTags.has_tag("meal_cards", meal_row, "bev") or CardTags.has_tag("meal_cards", meal_row, "coffee"):
			v *= mult
		meal_sum += v
	return rest + meal_sum + (base_total - rest - _raw_meal_sum(ctx, owner))


static func _raw_meal_sum(ctx: MatchEffectContext, owner: int) -> int:
	var s := 0
	for meal_row in ctx.foods[owner]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		s += CardEffectHelpers.resolve_meal_value(ctx, owner, meal_row)
	return s


static func cpu_hook(fx: CardEffectBase) -> String:
	match fx.id_str:
		"PROTOMBSSTAF045":
			return "Next setup: Bevs cost 0 influence."
		"PROTOFNFEVEN085", "PROTOFNFEVEN086":
			return "Play from hand to counter (not in setup line)."
		"PROTOFNFSTAF078":
			return "Reactive hand play — partial sim."
	return ""


static func _trade_food_discard(ctx: MatchEffectContext, owner: int) -> void:
	var hand: Array = ctx.match_ref.get_hand(owner)
	for i in range(hand.size()):
		var d: Dictionary = hand[i]
		if str(d.get("table", "")) != "meal_cards":
			continue
		ctx.match_ref.discard_card(owner, d)
		hand.remove_at(i)
		ctx.match_ref.set_hand(owner, hand)
		if not ctx.foods[ctx.opponent(owner)].is_empty():
			ctx.foods[ctx.opponent(owner)].pop_back()
		ctx.log("%s traded a hand meal to discard opponent food." % ctx.player_name(owner))
		return
