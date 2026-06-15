class_name CardTags
extends RefCounted

## Resolve food/staff tags from catalog rows (tags column or name heuristics).

const TAG_KEYS: Array[String] = [
	"tags",
	"Tags",
	"food_tags",
	"FoodTags",
	"card_tags",
	"CardTags",
	"subtype",
	"Subtype",
	"food_type",
	"FoodType",
]

const KNOWN_TAGS: Array[String] = [
	"rib",
	"bbq",
	"bev",
	"beverage",
	"coffee",
	"breakfast",
	"whole_hog",
	"celebrity",
]


static func tags_for_row(table: String, row: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k in TAG_KEYS:
		if not row.has(k):
			continue
		_append_tag_variant(row[k], out)
	var name := DeckRules.display_name_for_row(table, row).to_lower()
	for token in KNOWN_TAGS:
		if _name_implies_tag(name, token) and out.find(token) < 0:
			out.append(token)
	if table == "staff_cards" and name.contains("barista"):
		if out.find("bev") < 0:
			out.append("bev")
	if table == "meal_cards" and name.contains("rib"):
		if out.find("rib") < 0:
			out.append("rib")
	if table == "staff_cards" and name.contains("bbq"):
		if out.find("bbq") < 0:
			out.append("bbq")
	return out


static func has_tag(table: String, row: Dictionary, tag: String) -> bool:
	var want := tag.to_lower()
	for t in tags_for_row(table, row):
		if str(t).to_lower() == want:
			return true
	return false


static func _append_tag_variant(v: Variant, out: PackedStringArray) -> void:
	if v == null:
		return
	match typeof(v):
		TYPE_ARRAY:
			for item in v:
				var s := str(item).strip_edges().to_lower().replace(" ", "_")
				if not s.is_empty() and out.find(s) < 0:
					out.append(s)
		TYPE_STRING:
			var raw := str(v).strip_edges()
			if raw.begins_with("["):
				var parsed: Variant = JSON.parse_string(raw)
				if typeof(parsed) == TYPE_ARRAY:
					_append_tag_variant(parsed, out)
					return
			for part in raw.replace("|", ",").split(","):
				var p := part.strip_edges().to_lower().replace(" ", "_")
				if not p.is_empty() and out.find(p) < 0:
					out.append(p)


static func _name_implies_tag(name_lower: String, token: String) -> bool:
	match token:
		"rib":
			return name_lower.contains("rib")
		"bbq":
			return name_lower.contains("bbq")
		"bev", "beverage":
			return name_lower.contains("bev") or name_lower.contains("coffee") or name_lower.contains("cappuccino")
		"coffee":
			return name_lower.contains("coffee") or name_lower.contains("cappuccino")
		"breakfast":
			return name_lower.contains("breakfast")
		"whole_hog":
			return name_lower.contains("hog")
		"celebrity":
			return name_lower.contains("celebrity")
	return false
