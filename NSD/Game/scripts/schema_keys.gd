class_name SchemaKeys
extends RefCounted

## Candidate column names for card / row fields (Supabase may use snake_case or mixed).
## Adjust after inspecting `data/catalog_cache.json` from launcher Sync.

const R_TYPE_KEYS: Array[String] = [
	"r_type",
	"RType",
	"R_TYPE",
	"restaurant_type",
	"RestaurantType",
	"archetype",
	"Archetype",
	"deck_archetype",
]

const CHEF_ALLOWED_TYPES_KEYS: Array[String] = [
	"allowed_restaurant_r_types",
	"allowed_r_types",
	"allowed_restaurant_types",
	"restaurant_types_allowed",
	"chef_allowed_r_types",
]

## Single string field that lists types (pipe/comma separated) if no array column exists.
const CHEF_ALLOWED_TYPES_STRING_KEYS: Array[String] = [
	"allowed_types",
	"restaurant_specializations",
	"specializations",
	"chef_specialization",
]

const BASE_INFLUENCE_KEYS: Array[String] = [
	"base_influence",
	"BaseInfluence",
	"influence",
	"Influence",
	"starting_influence",
]

const INFLUENCE_COST_KEYS: Array[String] = [
	"influence_cost",
	"InfluenceCost",
	"play_cost",
	"cost",
	"influence",
]

const BASE_RATING_KEYS: Array[String] = [
	"base_rating",
	"BaseRating",
	"rating",
	"Rating",
	"restaurant_rating",
]

const FOOD_RATING_KEYS: Array[String] = [
	"food_rating",
	"FoodRating",
	"meal_rating",
	"Rating",
	"rating",
]


static func get_first_string(row: Dictionary, keys: Array[String]) -> String:
	for k in keys:
		if not row.has(k):
			continue
		var v: Variant = row[k]
		if v == null:
			continue
		var s := str(v).strip_edges()
		if not s.is_empty():
			return s
	return ""


static func get_r_type(row: Dictionary) -> String:
	return get_first_string(row, R_TYPE_KEYS)


static func get_influence_cost(row: Dictionary) -> int:
	for k in INFLUENCE_COST_KEYS:
		if not row.has(k):
			continue
		var v: Variant = row[k]
		var n := _coerce_int(v)
		if n >= 0:
			return maxi(0, n)
	return 1


static func get_base_influence_chef(row: Dictionary) -> int:
	for k in BASE_INFLUENCE_KEYS:
		if not row.has(k):
			continue
		var v: Variant = row[k]
		var n := _coerce_int(v)
		if n > 0:
			return n
	return -1


static func get_base_rating(row: Dictionary) -> int:
	for k in BASE_RATING_KEYS:
		if not row.has(k):
			continue
		var v: Variant = row[k]
		var n := _coerce_int(v)
		if n >= 0:
			return n
	return 0


static func get_food_rating(row: Dictionary) -> int:
	for k in FOOD_RATING_KEYS:
		if not row.has(k):
			continue
		var v: Variant = row[k]
		var n := _coerce_int(v)
		return n
	return 0


static func _coerce_int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(v)
		TYPE_STRING:
			var s := str(v).strip_edges()
			if s.is_valid_int():
				return int(s)
			if s.is_valid_float():
				return int(float(s))
	return -1
