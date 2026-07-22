extends RefCounted
class_name CardRowText

## Pull human-facing strings from heterogeneous Supabase / JSON row shapes.


static func ability_from_row(row: Dictionary) -> String:
	for k in ["ability_description", "ability", "Ability", "ability_text", "AbilityText"]:
		if not row.has(k):
			continue
		var s := str(row[k]).strip_edges()
		if not s.is_empty():
			return s
	return "—"


static func effect_from_row(row: Dictionary) -> String:
	for k in ["effect_description", "effect", "Effect", "EffectText", "effect_text"]:
		if not row.has(k):
			continue
		var s := str(row[k]).strip_edges()
		if not s.is_empty():
			return s
	# Fall back to long description only when it looks like rules text, not art blurbs
	if row.has("description"):
		var d := str(row["description"]).strip_edges()
		if not d.is_empty() and d.length() < 220:
			return d
	return "—"


static func cost_line_for_row(table: String, row: Dictionary) -> String:
	if row.is_empty():
		return ""
	var n := SchemaKeys.get_influence_cost(row)
	return "Influence %d" % n


## Effect text when present; otherwise ability / short description.
static func primary_rules_text(_table: String, row: Dictionary) -> String:
	var effect := effect_from_row(row)
	if effect != "—":
		return effect
	return ability_from_row(row)
