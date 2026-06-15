extends SceneTree

## Headless spot-check for card templates. Run from repo:
##   godot4 --path NSD/Game --headless -s res://ui/cards/verify_card_views.gd

const CardViewScene := preload("res://ui/cards/card_view.tscn")
const VisualConfig := preload("res://ui/cards/card_visual_config.gd")
const Catalog := preload("res://scenes/tutorials/tutorial_catalog.gd")

const TABLES: Array[String] = [
	"chef_cards",
	"restaurant_cards",
	"staff_cards",
	"meal_cards",
	"event_cards",
	"support_cards",
]


func _init() -> void:
	var tables := Catalog.load_tables()
	var failures: PackedStringArray = []
	var scene := CardViewScene
	if scene == null:
		failures.append("card_view.tscn failed to load")
		_report(failures)
		return
	for table in TABLES:
		var rows: Variant = tables.get(table, [])
		if typeof(rows) != TYPE_ARRAY or rows.is_empty():
			failures.append("missing sample row for %s" % table)
			continue
		var row: Dictionary = rows[0]
		var cv := scene.instantiate()
		root.add_child(cv)
		cv.call("setup", table, row)
		var path: String = VisualConfig.template_path_for(table)
		if not ResourceLoader.exists(path):
			failures.append("missing template: %s" % path)
		var name_lbl := cv.get_node("%NameLabel") as Label
		if name_lbl.text.is_empty():
			failures.append("%s: empty name" % table)
		if table == "meal_cards":
			var food := cv.get_node("%FoodRatingBadge") as Label
			if not food.visible:
				failures.append("meal_cards: food rating badge hidden")
		if table in ["chef_cards", "restaurant_cards"]:
			var stars := cv.get_node("%StarRow") as HBoxContainer
			if not stars.visible or stars.get_child_count() == 0:
				failures.append("%s: star row empty" % table)
		if table in ["staff_cards", "event_cards", "support_cards", "meal_cards"]:
			var cost := cv.get_node("%CostBadge") as Label
			if not cost.visible:
				failures.append("%s: cost badge hidden" % table)
		cv.queue_free()
	_report(failures)


func _report(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("verify_card_views: OK (6 types)")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		quit(1)
