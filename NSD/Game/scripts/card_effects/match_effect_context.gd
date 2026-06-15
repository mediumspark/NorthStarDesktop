class_name MatchEffectContext
extends RefCounted

## Mutable faceoff / round state passed to [CardEffectBase] hooks.

var match_ref ## MatchState — untyped to avoid parse cycle with MatchEffectContext.
var rng: RandomNumberGenerator

## Per-player equipped meals (row dicts) during resolution.
var foods: Array = [[], []]

## Score adjustments applied after base restaurant + meal sum.
var score_bonus: Array = [0, 0]
var score_override: Array = [-1, -1] ## -1 = use computed

var silenced_staff: Array = [false, false]
var silenced_restaurant: Array = [false, false]
var silenced_chef: Array = [false, false]
var silenced_all_cards: Array = [false, false]

## Meal id -> forced value (-1 = no override)
var meal_value_override: Dictionary = {}

var staff_silenced_this_round: bool = false
var coin_flip_winner_takes_all: int = -1 ## 0 both win, 1 both lose, -1 normal

var next_round_bev_cost_zero: Array = [false, false]

var logs: PackedStringArray = PackedStringArray()


func _init(p_match: Variant, p_rng: RandomNumberGenerator) -> void:
	match_ref = p_match
	rng = p_rng
	foods = [[], []]


const P_HUMAN := 0
const P_CPU := 1


func opponent(player: int) -> int:
	return P_CPU if player == P_HUMAN else P_HUMAN


func log(msg: String) -> void:
	if msg.is_empty():
		return
	logs.append(msg)
	match_ref._log(msg)


func player_name(player: int) -> String:
	return "You" if player == P_HUMAN else "CPU"


func line_for(player: int) -> Array:
	return match_ref.get_setup_line(player)


func restaurant_row(player: int) -> Dictionary:
	return match_ref.get_active_restaurant(player)


func is_mobile_restaurant(player: int) -> bool:
	var rt := RestaurantRTypes.normalize_token(SchemaKeys.get_r_type(restaurant_row(player)))
	return rt == "mobile"


func card_row(card: Dictionary) -> Dictionary:
	return match_ref.resolve_row(str(card.get("table", "")), str(card.get("id", "")))


func effect_for(card: Dictionary) -> CardEffectBase:
	var t := str(card.get("table", ""))
	var id_str := str(card.get("id", ""))
	return CardEffectRegistry.make(t, id_str, card_row(card))


func is_card_silenced(player: int, table: String) -> bool:
	if silenced_all_cards[player]:
		return true
	if table == "staff_cards" and (silenced_staff[player] or staff_silenced_this_round):
		return true
	return false


func add_score(player: int, delta: int) -> void:
	score_bonus[player] = int(score_bonus[player]) + delta


func set_score_override(player: int, value: int) -> void:
	score_override[player] = value


func set_meal_value(meal_id: String, value: int) -> void:
	meal_value_override[meal_id] = value
