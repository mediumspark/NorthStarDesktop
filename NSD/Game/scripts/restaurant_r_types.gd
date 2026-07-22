class_name RestaurantRTypes
extends RefCounted

## Canonical tokens for restaurant archetypes (closed enum for restaurant rows).
## Aliases map to these slugs for comparisons and chef allowlists.

const TYPELESS_SENTINEL := "NONE"

const CANONICAL: Array[String] = ["sit_down", "fast_casual", "mobile", "diner"]

## Human / DB variants -> canonical slug (lowercase snake).
const ALIAS_TO_CANONICAL: Dictionary = {
	"sit down": "sit_down",
	"sitdown": "sit_down",
	"sit_down": "sit_down",
	"fast casual": "fast_casual",
	"fastcasual": "fast_casual",
	"fast_casual": "fast_casual",
	"mobile": "mobile",
	"food truck": "mobile",
	"food_truck": "mobile",
	"diner": "diner",
}


static func normalize_token(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	var key := s.to_lower().replace("-", " ").replace("_", " ")
	while key.contains("  "):
		key = key.replace("  ", " ")
	key = key.strip_edges()
	if ALIAS_TO_CANONICAL.has(key):
		return str(ALIAS_TO_CANONICAL[key])
	# Already slug-like
	var slug := s.to_lower().replace(" ", "_").replace("-", "_")
	if CANONICAL.find(slug) >= 0:
		return slug
	return ""


static func is_known_restaurant_type(canonical: String) -> bool:
	return CANONICAL.find(canonical) >= 0


static func canonical_list_pretty() -> String:
	return ", ".join(CANONICAL)


## Display token for card banners, e.g. fast_casual -> FAST CASUAL.
static func format_pretty(canonical: String) -> String:
	var slug := normalize_token(canonical)
	if slug.is_empty():
		return canonical.strip_edges().to_upper().replace("_", " ")
	return slug.to_upper().replace("_", " ")


static func format_banner_from_row(table: String, row: Dictionary) -> String:
	if table == DeckRules.CHEF_TABLE:
		return _chef_allowed_banner(row)
	var rt := SchemaKeys.get_r_type(row)
	if rt.is_empty() or normalize_token(rt) == TYPELESS_SENTINEL:
		return ""
	return format_pretty(rt)


static func _chef_allowed_banner(row: Dictionary) -> String:
	var parts: Array[String] = []
	for k in SchemaKeys.CHEF_ALLOWED_TYPES_KEYS:
		if not row.has(k):
			continue
		_append_banner_parts(row[k], parts)
	for k in SchemaKeys.CHEF_ALLOWED_TYPES_STRING_KEYS:
		if not row.has(k):
			continue
		var v: Variant = row[k]
		if typeof(v) == TYPE_STRING:
			var s := str(v).strip_edges()
			if s.begins_with("["):
				_append_banner_parts(JSON.parse_string(s), parts)
			else:
				for part in s.replace("|", ",").split(","):
					var p := part.strip_edges()
					if not p.is_empty():
						var cn := normalize_token(p)
						if not cn.is_empty() and parts.find(format_pretty(cn)) < 0:
							parts.append(format_pretty(cn))
	if parts.is_empty():
		return ""
	return " / ".join(parts)


static func _append_banner_parts(v: Variant, parts: Array[String]) -> void:
	if v == null:
		return
	match typeof(v):
		TYPE_ARRAY:
			for item in v:
				var cn := normalize_token(str(item))
				if cn.is_empty():
					continue
				var pretty := format_pretty(cn)
				if parts.find(pretty) < 0:
					parts.append(pretty)
		TYPE_STRING:
			var cn2 := normalize_token(str(v))
			if not cn2.is_empty():
				var pretty2 := format_pretty(cn2)
				if parts.find(pretty2) < 0:
					parts.append(pretty2)
