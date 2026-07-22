class_name MatchState
extends RefCounted

## Synchronous match model for CPU PvE with faceoff effect resolution.

const _MatchEffectContext := preload("res://scripts/card_effects/match_effect_context.gd")
const _CardEffectHelpers := preload("res://scripts/card_effects/card_effect_helpers.gd")
const _CardTags := preload("res://scripts/card_effects/card_tags.gd")
const _CardTarget := preload("res://scripts/card_effects/card_target.gd")

signal phase_changed(phase: int)
signal message(text: String)
signal stars_changed(human: int, cpu: int)
signal game_over(result: String)

enum Phase {
	BOOT = 0,
	PICK_RESTAURANT = 1,
	MULLIGAN = 2,
	SETUP = 3,
	FACEOFF = 4,
	SCORE = 5,
	ENDED = 6,
}

const P_HUMAN := 0
const P_CPU := 1

var tables_data: Dictionary = {}

var phase: int = Phase.BOOT
var setup_round: int = 0
var _last_faceoff_summary: Dictionary = {}
var _cpu_setup_placements: Array = []
var _rng := RandomNumberGenerator.new()

var _chef_row: Dictionary = {}
var _base_influence: int = 5

var _main: Array = [[], []] ## per player: Array of {table,id}
var _rest: Array = [[], []]
var _hand: Array = [[], []]
var _discard: Array = [[], []]

var _active_restaurant: Array = [{}, {}] ## resolved row dicts
var _equipped_foods: Array = [[], []] ## arrays of meal row dicts (max 3)

var stars: Array = [0, 0]

var _setup_line: Array = [[], []] ## {table,id} face-down set cards
var _influence: Array = [0, 0]
var _events_this_round: Array = [0, 0]

var _mulligan_used: Array = [false, false]
var _opening_dealt: bool = false
## After human locks, CPU fills; both lines stay visible until [method resolve_faceoff].
var _faceoff_pending: bool = false

## Carried from prior round effect hooks (e.g. Bevs cost 0).
var _bev_cost_zero: Array = [false, false]

## Faceoff resolution state (stepped reveal + card targeting).
var _auto_resolve_targets: bool = true
var _pending_target_chooser: int = -1
var _pending_target_prompt: String = ""
var _pending_target_candidates: Array = []
var _pending_target_resolver: Callable = Callable()
var _faceoff_ctx = null
var _faceoff_before_score_done: bool = false
var _faceoff_round_end_done: bool = false
var _faceoff_slot_resume: Dictionary = {}
var _faceoff_scores: Dictionary = {}
var _faceoff_hook_resume: Dictionary = {}


func _emit_phase() -> void:
	phase_changed.emit(phase)


func _log(s: String) -> void:
	message.emit(s)


func start_match(p_tables: Dictionary, loadout: Dictionary) -> void:
	tables_data = p_tables
	phase = Phase.BOOT
	var chef_id := str((loadout.get("chef", {}) as Dictionary).get("id", ""))
	_chef_row = _resolve_row(DeckRules.CHEF_TABLE, chef_id)
	var bi := SchemaKeys.get_base_influence_chef(_chef_row)
	if bi > 0:
		_base_influence = bi
	else:
		_base_influence = 5

	var main_entries: Array = _clone_entry_array(loadout.get("main_deck", []))
	var rest_entries: Array = _clone_entry_array(loadout.get("restaurant_deck", []))
	_main[P_HUMAN] = _shuffle(main_entries.duplicate())
	_main[P_CPU] = _shuffle(main_entries.duplicate())
	_rest[P_HUMAN] = _shuffle(rest_entries.duplicate())
	_rest[P_CPU] = _shuffle(rest_entries.duplicate())
	for p in [P_HUMAN, P_CPU]:
		_hand[p].clear()
		_discard[p].clear()
		_setup_line[p].clear()
		_equipped_foods[p].clear()
		_active_restaurant[p] = {}
		_events_this_round[p] = 0
		_mulligan_used[p] = false
	stars[P_HUMAN] = 0
	stars[P_CPU] = 0
	_opening_dealt = false
	_faceoff_pending = false
	_bev_cost_zero = [false, false]
	setup_round = 0
	_cpu_setup_placements.clear()
	_rng.randomize()
	phase = Phase.PICK_RESTAURANT
	_emit_phase()
	_log("Pick starting restaurant (top or bottom of your shuffled restaurant deck).")


func begin_opening_hands_after_restaurant_pick() -> void:
	if _opening_dealt:
		return
	_opening_dealt = true
	for p in [P_HUMAN, P_CPU]:
		if not _draw_until_to_min(p, MatchConfig.OPENING_HAND_SIZE):
			return
	phase = Phase.MULLIGAN
	_emit_phase()
	_log("Opening hands dealt. Mulligan (all-or-nothing) if you want.")


func restaurant_top_bottom_preview(player: int) -> Dictionary:
	var deck: Array = _rest[player]
	if deck.is_empty():
		return {"ok": false, "error": "Restaurant deck empty."}
	if deck.size() == 1:
		return {"ok": true, "top": deck[0].duplicate(), "bottom": deck[0].duplicate()}
	return {"ok": true, "top": deck[0].duplicate(), "bottom": deck[deck.size() - 1].duplicate()}


func commit_restaurant_pick(player: int, take_top: bool) -> Dictionary:
	var deck: Array = _rest[player]
	if deck.is_empty():
		return {"ok": false, "error": "Restaurant deck empty."}
	var pick: Dictionary
	if take_top:
		pick = deck.pop_front() as Dictionary
	else:
		pick = deck.pop_back() as Dictionary
	var id_str := str(pick.get("id", ""))
	var row := _resolve_row(DeckRules.RESTAURANT_TABLE, id_str)
	if row.is_empty():
		return {"ok": false, "error": "Chosen restaurant not in catalog."}
	_active_restaurant[player] = row
	if player == P_HUMAN and phase == Phase.PICK_RESTAURANT:
		# CPU picks automatically when human finishes — scene may call CPU separately.
		pass
	_log("Player %d chose active restaurant: %s" % [player, DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, row)])
	return {"ok": true}


func cpu_auto_pick_restaurant() -> void:
	var r := restaurant_top_bottom_preview(P_CPU)
	if not bool(r.get("ok", false)):
		# fall back: single card
		if not _rest[P_CPU].is_empty():
			var pick: Dictionary = _rest[P_CPU].pop_front() as Dictionary
			var row := _resolve_row(DeckRules.RESTAURANT_TABLE, str(pick.get("id", "")))
			if not row.is_empty():
				_active_restaurant[P_CPU] = row
		return
	var take_top := _rng.randi_range(0, 1) == 1
	commit_restaurant_pick(P_CPU, take_top)


func mulligan_all_or_nothing(player: int, do_mulligan: bool) -> Dictionary:
	if _mulligan_used[player]:
		return {"ok": false, "error": "Mulligan already used."}
	_mulligan_used[player] = true
	if not do_mulligan:
		_log("Player %d kept opening hand." % player)
		return {"ok": true}
	# Return entire hand to bottom of main deck in random order? GDD: shuffle back — put back then redraw 5
	var deck: Array = _main[player]
	var h: Array = _hand[player]
	while not h.is_empty():
		var c: Dictionary = h.pop_back() as Dictionary
		deck.append(c)
	_main[player] = _shuffle(deck)
	_hand[player].clear()
	if not _draw_until_to_min(player, MatchConfig.OPENING_HAND_SIZE):
		return {"ok": false, "error": "Cannot redraw after mulligan (deck empty)."}
	_log("Player %d took a full mulligan." % player)
	return {"ok": true}


func start_setup_round() -> bool:
	_faceoff_pending = false
	setup_round += 1
	_cpu_setup_placements.clear()
	for p in [P_HUMAN, P_CPU]:
		_setup_line[p].clear()
		_influence[p] = _base_influence
		_events_this_round[p] = 0
		if not _draw_until_to_min(p, MatchConfig.SETUP_MIN_HAND):
			return false
	phase = Phase.SETUP
	_emit_phase()
	_log(
		"Setup: draw to at least %d. Place Staff, Meals, and Events face-down up to influence. Support plays from hand are not modeled in v1 UI."
		% MatchConfig.SETUP_MIN_HAND
	)
	return true


func can_add_to_setup_line(player: int, card: Dictionary) -> String:
	var t := str(card.get("table", ""))
	var id_str := str(card.get("id", ""))
	if t.is_empty() or id_str.is_empty():
		return "Invalid card."
	var row := _resolve_row(t, id_str)
	if row.is_empty():
		return "Card not in catalog."
	if t == DeckRules.CHEF_TABLE or t == DeckRules.RESTAURANT_TABLE:
		return "Cannot set that card type in Setup."
	if t == "support_cards":
		return "Support cannot be set face-down (play from hand; v1 UI may omit)."
	if t == "event_cards":
		if int(_events_this_round[player]) >= 1:
			return "Only one Event per full round."
	var cost := _effective_influence_cost(player, t, row)
	if cost > int(_influence[player]):
		return "Not enough influence."
	return ""


func setup_add_card(player: int, hand_index: int) -> Dictionary:
	if _faceoff_pending:
		return {"ok": false, "error": "Line is locked. Reveal the Faceoff first."}
	if phase != Phase.SETUP:
		return {"ok": false, "error": "Not in Setup."}
	if hand_index < 0 or hand_index >= _hand[player].size():
		return {"ok": false, "error": "Bad hand index."}
	var card: Dictionary = (_hand[player][hand_index] as Dictionary).duplicate()
	var err := can_add_to_setup_line(player, card)
	if not err.is_empty():
		return {"ok": false, "error": err}
	var row := _resolve_row(str(card.get("table", "")), str(card.get("id", "")))
	var cost := _effective_influence_cost(player, str(card.get("table", "")), row)
	_hand[player].remove_at(hand_index)
	_setup_line[player].append(card)
	_influence[player] = int(_influence[player]) - cost
	if str(card.get("table", "")) == "event_cards":
		_events_this_round[player] = int(_events_this_round[player]) + 1
	return {"ok": true}


func setup_remove_last(player: int) -> Dictionary:
	if _faceoff_pending:
		return {"ok": false, "error": "Line is locked. Reveal the Faceoff first."}
	if phase != Phase.SETUP:
		return {"ok": false, "error": "Not in Setup."}
	if _setup_line[player].is_empty():
		return {"ok": false, "error": "Nothing to remove."}
	var card: Dictionary = _setup_line[player].pop_back() as Dictionary
	var row := _resolve_row(str(card.get("table", "")), str(card.get("id", "")))
	var cost := _effective_influence_cost(player, str(card.get("table", "")), row)
	_hand[player].append(card)
	_influence[player] = int(_influence[player]) + cost
	if str(card.get("table", "")) == "event_cards":
		_events_this_round[player] = maxi(0, int(_events_this_round[player]) - 1)
	return {"ok": true}


func validate_setup_locked(player: int) -> String:
	## Pre-lock validation: influence cannot be negative (already), line must be legal.
	var inf := int(_influence[player])
	if inf < 0:
		return "Invalid influence."
	if int(_events_this_round[player]) > 1:
		return "More than one Event this round."
	return ""


func submit_human_setup() -> Dictionary:
	var eh := validate_setup_locked(P_HUMAN)
	if not eh.is_empty():
		return {"ok": false, "error": eh}
	var cpu_snap := _snapshot_cpu_setup_state()
	cpu_fill_random_legal_setup()
	var ec := validate_setup_locked(P_CPU)
	if not ec.is_empty():
		_restore_cpu_setup_state(cpu_snap)
		return {"ok": false, "error": "CPU setup invalid: %s" % ec}
	if phase != Phase.SETUP:
		return {"ok": false, "error": "Not in Setup."}
	_faceoff_pending = true
	_emit_phase()
	_log("CPU has set its line. Review both fields, then reveal the Faceoff.")
	return {"ok": true}


func _snapshot_cpu_setup_state() -> Dictionary:
	return {
		"line": _dup_line_entries(_setup_line[P_CPU]),
		"hand": _dup_line_entries(_hand[P_CPU]),
		"inf": int(_influence[P_CPU]),
		"ev": int(_events_this_round[P_CPU]),
	}


func _restore_cpu_setup_state(snap: Dictionary) -> void:
	_setup_line[P_CPU] = snap.get("line", []) as Array
	_hand[P_CPU] = snap.get("hand", []) as Array
	_influence[P_CPU] = int(snap.get("inf", 0))
	_events_this_round[P_CPU] = int(snap.get("ev", 0))


func _dup_line_entries(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		if typeof(x) == TYPE_DICTIONARY:
			out.append((x as Dictionary).duplicate())
	return out


func resolve_faceoff() -> Dictionary:
	if not _faceoff_pending and _faceoff_ctx == null:
		return {"ok": false, "error": "Nothing to reveal yet."}
	_auto_resolve_targets = true
	var begin_r := begin_faceoff_resolution()
	if not bool(begin_r.get("ok", false)):
		return begin_r
	var slots := int(begin_r.get("slots", 0))
	for slot in range(slots):
		while true:
			var r: Dictionary = resolve_faceoff_slot(slot)
			while has_pending_target():
				_auto_submit_target()
			if bool(r.get("waiting_target", false)):
				continue
			break
	while true:
		var fin: Dictionary = finalize_faceoff_resolution()
		while has_pending_target():
			_auto_submit_target()
			fin = finalize_faceoff_resolution()
		if bool(fin.get("waiting_target", false)):
			continue
		if not bool(fin.get("ok", false)):
			return fin
		break
	return {"ok": true}


func set_auto_resolve_targets(enabled: bool) -> void:
	_auto_resolve_targets = enabled


func should_auto_resolve_target(player: int) -> bool:
	return _auto_resolve_targets or player == P_CPU


func enqueue_target_prompt(chooser: int, prompt: String, candidates: Array, resolver: Callable) -> void:
	_pending_target_chooser = chooser
	_pending_target_prompt = prompt
	_pending_target_candidates = candidates.duplicate(true)
	_pending_target_resolver = resolver
	if _faceoff_ctx != null:
		_faceoff_ctx.pending_target = get_pending_target()
	if chooser == P_HUMAN and not should_auto_resolve_target(chooser):
		_log("Choose a target: %s" % prompt)


func get_pending_target() -> Dictionary:
	if _pending_target_candidates.is_empty():
		return {}
	return {
		"chooser": _pending_target_chooser,
		"prompt": _pending_target_prompt,
		"candidates": _pending_target_candidates.duplicate(true),
	}


func has_pending_target() -> bool:
	return not _pending_target_candidates.is_empty()


func clear_pending_target() -> void:
	_pending_target_chooser = -1
	_pending_target_prompt = ""
	_pending_target_candidates.clear()
	_pending_target_resolver = Callable()
	if _faceoff_ctx != null:
		_faceoff_ctx.pending_target = {}


func submit_target(candidate_index: int) -> Dictionary:
	if _pending_target_candidates.is_empty():
		return {"ok": false, "error": "No target pending."}
	if candidate_index < 0 or candidate_index >= _pending_target_candidates.size():
		return {"ok": false, "error": "Invalid target."}
	var picked: Dictionary = _pending_target_candidates[candidate_index] as Dictionary
	var resolver := _pending_target_resolver
	clear_pending_target()
	if resolver.is_valid():
		resolver.call(picked)
	return {"ok": true}


func begin_faceoff_resolution() -> Dictionary:
	_faceoff_pending = false
	phase = Phase.FACEOFF
	_emit_phase()
	_faceoff_ctx = _MatchEffectContext.new(self, _rng)
	_faceoff_ctx.foods[P_HUMAN] = []
	_faceoff_ctx.foods[P_CPU] = []
	_faceoff_before_score_done = false
	_faceoff_round_end_done = false
	_faceoff_slot_resume.clear()
	_faceoff_scores.clear()
	_faceoff_hook_resume.clear()
	clear_pending_target()
	_log("Faceoff: revealing left to right.")
	var max_len := maxi(_setup_line[P_HUMAN].size(), _setup_line[P_CPU].size())
	return {"ok": true, "slots": max_len}


func resolve_faceoff_slot(slot: int) -> Dictionary:
	if _faceoff_ctx == null:
		var begin_r := begin_faceoff_resolution()
		if not bool(begin_r.get("ok", false)):
			return begin_r
	if has_pending_target():
		return {"ok": true, "waiting_target": true, "request": get_pending_target(), "slot": slot}
	var start_player_i := 0
	var skip_hook := false
	if int(_faceoff_slot_resume.get("slot", -1)) == slot:
		start_player_i = int(_faceoff_slot_resume.get("player_i", 0))
		skip_hook = bool(_faceoff_slot_resume.get("skip_hook", false))
	else:
		_faceoff_slot_resume.clear()
	var players := [P_HUMAN, P_CPU]
	for pi in range(start_player_i, players.size()):
		var player: int = players[pi]
		var r: Dictionary = _reveal_card_at_slot(_faceoff_ctx, slot, player, skip_hook)
		skip_hook = false
		if bool(r.get("waiting_target", false)):
			_faceoff_slot_resume = {"slot": slot, "player_i": pi, "skip_hook": true}
			return {"ok": true, "waiting_target": true, "request": get_pending_target(), "slot": slot}
		_faceoff_slot_resume.clear()
	return {"ok": true, "slot_done": slot}


func continue_faceoff_after_target() -> Dictionary:
	if _faceoff_ctx == null:
		return {"ok": false, "error": "Faceoff not started."}
	if has_pending_target():
		return {"ok": true, "waiting_target": true, "request": get_pending_target()}
	if not _faceoff_before_score_done:
		_apply_line_hooks_before_score(_faceoff_ctx)
		if has_pending_target():
			return {"ok": true, "waiting_target": true, "request": get_pending_target()}
		_faceoff_before_score_done = true
		return {"ok": true, "phase": "before_score"}
	if _faceoff_scores.is_empty():
		var sh := _score_player_with_ctx(_faceoff_ctx, P_HUMAN)
		var sc := _score_player_with_ctx(_faceoff_ctx, P_CPU)
		_faceoff_scores = {"score_h": sh, "score_c": sc}
	if not _faceoff_round_end_done:
		_apply_round_end_hooks(_faceoff_ctx)
		if has_pending_target():
			return {"ok": true, "waiting_target": true, "request": get_pending_target()}
		_faceoff_round_end_done = true
		return {"ok": true, "phase": "round_end"}
	return {"ok": true, "idle": true}


func finalize_faceoff_resolution() -> Dictionary:
	if _faceoff_ctx == null:
		return {"ok": false, "error": "Faceoff not started."}
	if has_pending_target():
		return {"ok": true, "waiting_target": true, "request": get_pending_target()}
	if not _faceoff_before_score_done:
		_apply_line_hooks_before_score(_faceoff_ctx)
		if has_pending_target():
			return {"ok": true, "waiting_target": true, "request": get_pending_target()}
		_faceoff_before_score_done = true
	var sh := _score_player_with_ctx(_faceoff_ctx, P_HUMAN)
	var sc := _score_player_with_ctx(_faceoff_ctx, P_CPU)
	_faceoff_scores = {"score_h": sh, "score_c": sc}
	if not _faceoff_round_end_done:
		_apply_round_end_hooks(_faceoff_ctx)
		if has_pending_target():
			return {"ok": true, "waiting_target": true, "request": get_pending_target()}
		_faceoff_round_end_done = true
	_complete_faceoff(_faceoff_ctx, sh, sc)
	_faceoff_ctx = null
	if phase != Phase.ENDED:
		if not start_setup_round():
			return {"ok": false, "error": "Cannot draw for next round."}
	return {"ok": true}


func _auto_submit_target() -> void:
	if _pending_target_candidates.is_empty():
		return
	var idx := 0
	if _pending_target_chooser == P_CPU:
		idx = _CardTarget.cpu_pick_index(_pending_target_candidates, _rng)
	else:
		idx = 0
	submit_target(idx)


func _reveal_card_at_slot(ctx, slot: int, player: int, skip_hook: bool = false) -> Dictionary:
	var line: Array = _setup_line[player]
	if slot >= line.size():
		return {}
	var card: Dictionary = line[slot] as Dictionary
	var t := str(card.get("table", ""))
	if not skip_hook:
		var fx: CardEffectBase = ctx.effect_for(card)
		if fx != null and not fx.is_silenced(ctx, player):
			fx.on_faceoff_reveal(ctx, player, slot)
			if has_pending_target():
				return {"waiting_target": true}
	if t == "meal_cards":
		var row := _resolve_row(t, str(card.get("id", "")))
		if row.is_empty():
			return {}
		var foods: Array = ctx.foods[player]
		if foods.size() >= MatchConfig.MAX_FOODS_PER_RESTAURANT:
			foods.pop_front()
		foods.append(row)
	return {}


func _complete_faceoff(ctx, score_h: int, score_c: int) -> void:
	var stars_h_before := int(stars[P_HUMAN])
	var stars_c_before := int(stars[P_CPU])
	_bev_cost_zero = ctx.next_round_bev_cost_zero.duplicate()
	_log("Scores — You: %d  CPU: %d" % [score_h, score_c])
	_apply_star_rules_with_ctx(ctx, score_h, score_c)
	_last_faceoff_summary = {
		"score_h": score_h,
		"score_c": score_c,
		"star_h_delta": int(stars[P_HUMAN]) - stars_h_before,
		"star_c_delta": int(stars[P_CPU]) - stars_c_before,
	}
	_trash_setup_lines_to_discard()
	phase = Phase.SCORE
	_emit_phase()
	_check_end_immediate()


func get_last_faceoff_summary() -> Dictionary:
	return _last_faceoff_summary.duplicate()


func is_faceoff_pending() -> bool:
	return _faceoff_pending


func get_setup_line(player: int) -> Array:
	if player < 0 or player > 1:
		return []
	return (_setup_line[player] as Array).duplicate()


func lock_setup_and_run_faceoff() -> Dictionary:
	## Back-compat: lock and score in one call (used if UI omits the reveal step).
	var a := submit_human_setup()
	if not bool(a.get("ok", false)):
		return a
	return resolve_faceoff()


func _run_faceoff_scoring() -> void:
	## Legacy synchronous path — prefer [method begin_faceoff_resolution] + stepped APIs.
	_auto_resolve_targets = true
	begin_faceoff_resolution()
	var max_len := maxi(_setup_line[P_HUMAN].size(), _setup_line[P_CPU].size())
	for slot in range(max_len):
		while true:
			resolve_faceoff_slot(slot)
			while has_pending_target():
				_auto_submit_target()
			if not has_pending_target():
				break
	while true:
		var fin := finalize_faceoff_resolution()
		while has_pending_target():
			_auto_submit_target()
			fin = finalize_faceoff_resolution()
		if not bool(fin.get("waiting_target", false)):
			break


func _apply_line_hooks_before_score(ctx) -> void:
	var start_player := int(_faceoff_hook_resume.get("player", 0)) if str(_faceoff_hook_resume.get("phase", "")) == "before_score" else 0
	var start_card := int(_faceoff_hook_resume.get("card", 0)) if str(_faceoff_hook_resume.get("phase", "")) == "before_score" else 0
	_faceoff_hook_resume.clear()
	for player_i in range(start_player, 2):
		var player: int = P_HUMAN if player_i == 0 else P_CPU
		var line: Array = _setup_line[player]
		var card_start := start_card if player_i == start_player else 0
		for card_i in range(card_start, line.size()):
			var card: Variant = line[card_i]
			if typeof(card) != TYPE_DICTIONARY:
				continue
			var fx: CardEffectBase = ctx.effect_for(card as Dictionary)
			if fx != null and not fx.is_silenced(ctx, player):
				fx.on_faceoff_before_score(ctx, player)
				if has_pending_target():
					_faceoff_hook_resume = {"phase": "before_score", "player": player_i, "card": card_i + 1}
					return


func _score_player_with_ctx(ctx, player: int) -> int:
	if int(ctx.score_override[player]) >= 0:
		return int(ctx.score_override[player])
	var rest: Dictionary = _active_restaurant[player]
	if rest.is_empty():
		return 0
	if ctx.silenced_restaurant[player]:
		var total_silenced := int(ctx.score_bonus[player])
		for card in _setup_line[player]:
			if typeof(card) != TYPE_DICTIONARY:
				continue
			var fx: CardEffectBase = ctx.effect_for(card as Dictionary)
			if fx != null and not fx.is_silenced(ctx, player):
				total_silenced = fx.modify_total_score(ctx, player, total_silenced)
		return total_silenced
	var total := 0
	if not ctx.silenced_restaurant[player]:
		total = SchemaKeys.get_base_rating(rest)
	if ctx.silenced_chef[player]:
		pass # chef ability silenced; restaurant rating kept unless restaurant silenced
	for meal_row in ctx.foods[player]:
		if typeof(meal_row) != TYPE_DICTIONARY:
			continue
		total += _CardEffectHelpers.resolve_meal_value(ctx, player, meal_row as Dictionary)
	total += int(ctx.score_bonus[player])
	for card in _setup_line[player]:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var fx: CardEffectBase = ctx.effect_for(card as Dictionary)
		if fx != null and not fx.is_silenced(ctx, player):
			total = fx.modify_total_score(ctx, player, total)
	return total


func _apply_round_end_hooks(ctx) -> void:
	var start_player := int(_faceoff_hook_resume.get("player", 0)) if str(_faceoff_hook_resume.get("phase", "")) == "round_end" else 0
	var start_card := int(_faceoff_hook_resume.get("card", 0)) if str(_faceoff_hook_resume.get("phase", "")) == "round_end" else 0
	_faceoff_hook_resume.clear()
	for player_i in range(start_player, 2):
		var player: int = P_HUMAN if player_i == 0 else P_CPU
		var line: Array = _setup_line[player]
		var card_start := start_card if player_i == start_player else 0
		for card_i in range(card_start, line.size()):
			var card: Variant = line[card_i]
			if typeof(card) != TYPE_DICTIONARY:
				continue
			var fx: CardEffectBase = ctx.effect_for(card as Dictionary)
			if fx != null and not fx.is_silenced(ctx, player):
				fx.on_round_end(ctx, player)
				if has_pending_target():
					_faceoff_hook_resume = {"phase": "round_end", "player": player_i, "card": card_i + 1}
					return


func _apply_star_rules_with_ctx(ctx, score_h: int, score_c: int) -> void:
	if ctx.coin_flip_winner_takes_all == 0:
		_add_stars(P_HUMAN, 1)
		_add_stars(P_CPU, 1)
		_log("Coin flip: both gain a star.")
		return
	if ctx.coin_flip_winner_takes_all == 1:
		_log("Coin flip: neither gains a star.")
		return
	_apply_star_rules(score_h, score_c)


func _apply_star_rules(score_h: int, score_c: int) -> void:
	if score_h == score_c:
		_add_stars(P_HUMAN, 1)
		_add_stars(P_CPU, 1)
		_log("Tie: both gain a star.")
	elif score_h > score_c:
		_add_stars(P_HUMAN, 1)
		_log("You win the Faceoff: +1 star.")
	else:
		_add_stars(P_CPU, 1)
		_log("CPU wins the Faceoff: +1 star.")


func _add_stars(player: int, delta: int) -> void:
	stars[player] = maxi(MatchConfig.STARS_FLOOR, int(stars[player]) + delta)
	stars_changed.emit(int(stars[P_HUMAN]), int(stars[P_CPU]))
	_check_end_immediate()


func _check_end_immediate() -> void:
	var h := int(stars[P_HUMAN])
	var c := int(stars[P_CPU])
	if h >= MatchConfig.STARS_TO_WIN and c >= MatchConfig.STARS_TO_WIN:
		phase = Phase.ENDED
		_emit_phase()
		game_over.emit("Draw (both reached %d+ stars)." % MatchConfig.STARS_TO_WIN)
		_log("Game over: draw.")
	elif h >= MatchConfig.STARS_TO_WIN:
		phase = Phase.ENDED
		_emit_phase()
		game_over.emit("You win.")
		_log("Game over: you win.")
	elif c >= MatchConfig.STARS_TO_WIN:
		phase = Phase.ENDED
		_emit_phase()
		game_over.emit("CPU wins.")
		_log("Game over: CPU wins.")


func _trash_setup_lines_to_discard() -> void:
	for p in [P_HUMAN, P_CPU]:
		for card in _setup_line[p]:
			_discard[p].append(card)
		_setup_line[p].clear()


func _draw_until_to_min(player: int, target: int) -> bool:
	var h: Array = _hand[player]
	var deck: Array = _main[player]
	while h.size() < target:
		if deck.is_empty():
			phase = Phase.ENDED
			_emit_phase()
			var msg := "You lose (cannot draw)." if player == P_HUMAN else "CPU cannot draw — you win."
			game_over.emit(msg)
			_log(msg)
			return false
		h.append(deck.pop_front())
	return true


func cpu_fill_random_legal_setup() -> void:
	var p := P_CPU
	_cpu_setup_placements.clear()
	_setup_line[p].clear()
	_influence[p] = _base_influence
	_events_this_round[p] = 0
	var progress := true
	var guard := 0
	while progress and guard < 200:
		guard += 1
		progress = false
		var order: Array = []
		for i in range(_hand[p].size()):
			order.append(i)
		order.shuffle()
		for idx in order:
			var i := int(idx)
			if i < 0 or i >= _hand[p].size():
				continue
			var card: Dictionary = (_hand[p][i] as Dictionary).duplicate()
			if not can_add_to_setup_line(p, card).is_empty():
				continue
			var t := str(card.get("table", ""))
			var row := _resolve_row(t, str(card.get("id", "")))
			var cost := _effective_influence_cost(p, t, row)
			if setup_add_card(p, i).get("ok", false):
				_cpu_setup_placements.append({
					"table": t,
					"id": str(card.get("id", "")),
					"cost": cost,
				})
				progress = true
				break


func get_setup_round() -> int:
	return setup_round


func get_cpu_setup_placements() -> Array:
	return _cpu_setup_placements.duplicate(true)


func get_hand(player: int) -> Array:
	return (_hand[player] as Array).duplicate()


func get_influence(player: int) -> int:
	return int(_influence[player])


func get_base_influence_value() -> int:
	return int(_base_influence)


func get_restaurant_deck_size(player: int) -> int:
	return int(_rest[player].size())


func get_active_restaurant(player: int) -> Dictionary:
	if player < 0 or player > 1:
		return {}
	return (_active_restaurant[player] as Dictionary).duplicate()


func resolve_row(table: String, id_str: String) -> Dictionary:
	return _resolve_row(table, id_str)


func discard_card(player: int, card: Dictionary) -> void:
	_discard[player].append(card.duplicate())


func set_hand(player: int, cards: Array) -> void:
	_hand[player] = cards.duplicate()


func draw_cards(player: int, count: int) -> int:
	var drawn := 0
	var deck: Array = _main[player]
	var h: Array = _hand[player]
	for _i in range(count):
		if deck.is_empty():
			break
		h.append(deck.pop_front())
		drawn += 1
	return drawn


func move_tagged_from_discard_to_hand(player: int, tag: String) -> bool:
	var pile: Array = _discard[player]
	for i in range(pile.size() - 1, -1, -1):
		var card: Dictionary = pile[i] as Dictionary
		var row := _resolve_row(str(card.get("table", "")), str(card.get("id", "")))
		if _CardTags.has_tag(str(card.get("table", "")), row, tag):
			pile.remove_at(i)
			_hand[player].append(card)
			return true
	return false


func _effective_influence_cost(player: int, table: String, row: Dictionary) -> int:
	var cost := SchemaKeys.get_influence_cost(row)
	if bool(_bev_cost_zero[player]):
		if _CardTags.has_tag(table, row, "bev") or _CardTags.has_tag(table, row, "coffee"):
			return 0
	return cost


func set_setup_line(player: int, cards: Array) -> void:
	_setup_line[player] = cards.duplicate()


func append_setup_line(player: int, card: Dictionary) -> void:
	_setup_line[player].append(card.duplicate())


func randomize_rng() -> void:
	_rng.randomize()


func _resolve_row(table: String, id_str: String) -> Dictionary:
	var rows: Variant = tables_data.get(table, [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = row
		if DeckRules.row_id(r) == id_str:
			return r
	return {}


func _clone_entry_array(src: Variant) -> Array:
	var out: Array = []
	if typeof(src) != TYPE_ARRAY:
		return out
	for item in src:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		out.append({"table": str(d.get("table", "")), "id": str(d.get("id", ""))})
	return out


func _shuffle(entries: Array) -> Array:
	var arr: Array = entries.duplicate()
	var n := arr.size()
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
