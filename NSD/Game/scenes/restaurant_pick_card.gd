extends CardTileButton
class_name RestaurantPickCard

## Clickable restaurant preview for the TOP/BOTTOM pick step.


func setup_pick(entry: Dictionary, row: Dictionary, deck_banner: String, on_chosen: Callable) -> void:
	var display_row := row
	if display_row.is_empty():
		display_row = {"name": str(entry.get("id", "Restaurant"))}
	var opts := {"extra_banner": deck_banner, "display_w": 132.0, "display_h": 218.0}
	setup_card(DeckRules.RESTAURANT_TABLE, display_row, opts, on_chosen)
	custom_minimum_size = Vector2(132, 236)
