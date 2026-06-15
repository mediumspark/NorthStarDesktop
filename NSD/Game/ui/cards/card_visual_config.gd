class_name CardVisualConfig
extends RefCounted

const CARD_W := 375.0
const CARD_H := 525.0
const DISPLAY_W := 132.0
const DISPLAY_H := 218.0

const TEMPLATE_STAFF := "res://ui/cards/templates/card_staff.svg"
const TEMPLATE_EVENT := "res://ui/cards/templates/card_event.svg"
const TEMPLATE_MEAL := "res://ui/cards/templates/card_meal.svg"
const TEMPLATE_CHEF := "res://ui/cards/templates/card_chef.svg"
const TEMPLATE_RESTAURANT := "res://ui/cards/templates/card_restaurant.svg"

enum LayoutKind { STAFF, MAIN_DECK, MEAL, CHEF, RESTAURANT }


static func template_path_for(table: String) -> String:
	match layout_for(table):
		LayoutKind.STAFF:
			return TEMPLATE_STAFF
		LayoutKind.MEAL:
			return TEMPLATE_MEAL
		LayoutKind.CHEF:
			return TEMPLATE_CHEF
		LayoutKind.RESTAURANT:
			return TEMPLATE_RESTAURANT
		_:
			return TEMPLATE_EVENT


static func layout_for(table: String) -> LayoutKind:
	match table:
		DeckRules.CHEF_TABLE:
			return LayoutKind.CHEF
		DeckRules.RESTAURANT_TABLE:
			return LayoutKind.RESTAURANT
		"staff_cards":
			return LayoutKind.STAFF
		"meal_cards":
			return LayoutKind.MEAL
		_:
			return LayoutKind.MAIN_DECK


static func show_cost(table: String) -> bool:
	return layout_for(table) in [LayoutKind.STAFF, LayoutKind.MAIN_DECK, LayoutKind.MEAL]


static func show_food_rating(table: String) -> bool:
	return table == "meal_cards"


static func show_stars(table: String) -> bool:
	return layout_for(table) in [LayoutKind.CHEF, LayoutKind.RESTAURANT]


static func show_type_banner(table: String) -> bool:
	return layout_for(table) != LayoutKind.STAFF


static func name_on_top_bar(table: String) -> bool:
	return layout_for(table) in [LayoutKind.MAIN_DECK, LayoutKind.MEAL]


static func name_on_footer(table: String) -> bool:
	return layout_for(table) in [LayoutKind.STAFF, LayoutKind.CHEF, LayoutKind.RESTAURANT]


static func star_count(table: String, row: Dictionary) -> int:
	if row.is_empty():
		return 0
	if table == DeckRules.RESTAURANT_TABLE:
		return clampi(SchemaKeys.get_base_rating(row), 0, 5)
	if table == DeckRules.CHEF_TABLE:
		var inf := SchemaKeys.get_base_influence_chef(row)
		if inf > 0:
			return clampi(inf / 3, 1, 5)
	return 0


static func display_scale() -> Vector2:
	return Vector2(DISPLAY_W / CARD_W, DISPLAY_H / CARD_H)
