extends SceneTree

## Smoke test: start match and resolve a faceoff with effect hooks.

const MatchStateScript := preload("res://scripts/match_state.gd")
const Catalog := preload("res://scenes/tutorials/tutorial_catalog.gd")


func _init() -> void:
	var tables := Catalog.load_tables()
	if tables.is_empty():
		push_error("no tutorial catalog")
		quit(1)
		return
	var ms = MatchStateScript.new()
	var loadout := {
		"chef": {"table": "chef_cards", "id": "TUT_CHEF"},
		"main_deck": [
			{"table": "staff_cards", "id": "TUT_STAFF"},
			{"table": "staff_cards", "id": "TUT_STAFF"},
			{"table": "meal_cards", "id": "TUT_MEAL"},
			{"table": "meal_cards", "id": "TUT_MEAL"},
			{"table": "event_cards", "id": "TUT_EVENT"},
			{"table": "event_cards", "id": "TUT_EVENT"},
			{"table": "support_cards", "id": "TUT_SUPPORT"},
			{"table": "support_cards", "id": "TUT_SUPPORT"},
		],
		"restaurant_deck": [
			{"table": "restaurant_cards", "id": "TUT_REST_TOP"},
		],
	}
	ms.start_match(tables, loadout)
	ms.commit_restaurant_pick(0, true)
	ms.cpu_auto_pick_restaurant()
	ms.begin_opening_hands_after_restaurant_pick()
	ms.mulligan_all_or_nothing(0, false)
	ms.start_setup_round()
	while ms.get_hand(0).size() > 0 and ms.get_influence(0) > 0:
		var r: Dictionary = ms.setup_add_card(0, 0)
		if not bool(r.get("ok", false)):
			break
	var sub: Dictionary = ms.submit_human_setup()
	if not bool(sub.get("ok", false)):
		push_error("submit failed: %s" % str(sub.get("error", "")))
		quit(1)
		return
	var r2: Dictionary = ms.resolve_faceoff()
	if not bool(r2.get("ok", false)):
		push_error("faceoff failed: %s" % str(r2.get("error", "")))
		quit(1)
		return
	print("effect_engine_smoke: OK")
	quit(0)
