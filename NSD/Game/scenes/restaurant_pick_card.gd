extends CardTileButton
class_name RestaurantPickCard

## Clickable restaurant preview for the TOP/BOTTOM pick step.


func setup_pick(
	entry: Dictionary,
	row: Dictionary,
	deck_banner: String,
	on_chosen: Callable,
	size_opts: Dictionary = {}
) -> void:
	var display_row := row
	if display_row.is_empty():
		display_row = {"name": str(entry.get("id", "Restaurant"))}
	var opts := size_opts.duplicate()
	opts["extra_banner"] = deck_banner
	if not opts.has("display_w"):
		opts["display_w"] = 132.0
	if not opts.has("display_h"):
		opts["display_h"] = 218.0
	setup_card(DeckRules.RESTAURANT_TABLE, display_row, opts, on_chosen)
	custom_minimum_size = Vector2(float(opts["display_w"]), float(opts["display_h"]) + 18.0)
