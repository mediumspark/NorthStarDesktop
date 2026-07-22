extends TutorialLessonBase

var _tables: Dictionary = {}


func _ready() -> void:
	_tables = TutorialCatalog.load_tables()
	super._ready()


func _after_sync_step() -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	if _step != 2:
		return
	lock_next()
	var btn := Button.new()
	btn.text = "Show demo scores"
	btn.pressed.connect(_show_demo_scores)
	%ExtraSlot.add_child(btn)


func _show_demo_scores() -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	var meal := TutorialCatalog.row_by_code(_tables, "meal_cards", "TUT_MEAL")
	var rest_a := TutorialCatalog.row_by_code(_tables, DeckRules.RESTAURANT_TABLE, "TUT_REST_TOP")
	var rest_b := TutorialCatalog.row_by_code(_tables, DeckRules.RESTAURANT_TABLE, "TUT_REST_BOT")
	var total_win := SchemaKeys.get_base_rating(rest_a) + SchemaKeys.get_food_rating(meal) + SchemaKeys.get_food_rating(meal)
	var total_lose := SchemaKeys.get_base_rating(rest_b) + SchemaKeys.get_food_rating(meal)
	var box := VBoxContainer.new()
	var l1 := RichTextLabel.new()
	l1.bbcode_enabled = true
	l1.fit_content = true
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l1.text = (
		"[b]Board A[/b] — %s + two meals: base %d + food %d + food %d = [b]%d[/b]."
		% [
			DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, rest_a),
			SchemaKeys.get_base_rating(rest_a),
			SchemaKeys.get_food_rating(meal),
			SchemaKeys.get_food_rating(meal),
			total_win,
		]
	)
	var l2 := RichTextLabel.new()
	l2.bbcode_enabled = true
	l2.fit_content = true
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.text = (
		"[b]Board B[/b] — %s + one meal: base %d + food %d = [b]%d[/b]."
		% [
			DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, rest_b),
			SchemaKeys.get_base_rating(rest_b),
			SchemaKeys.get_food_rating(meal),
			total_lose,
		]
	)
	var l3 := RichTextLabel.new()
	l3.bbcode_enabled = true
	l3.fit_content = true
	l3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l3.text = "[b]Result:[/b] A wins the Faceoff → A gains 1 star (example from 0 → 1). B stays at 0."
	box.add_child(l1)
	box.add_child(l2)
	box.add_child(l3)
	var sep := HSeparator.new()
	box.add_child(sep)
	var tie_each := SchemaKeys.get_base_rating(rest_a) + SchemaKeys.get_food_rating(meal)
	var lt := RichTextLabel.new()
	lt.bbcode_enabled = true
	lt.fit_content = true
	lt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lt.text = (
		"[b]Tie example:[/b] same restaurant + one meal each → %d vs %d. [b]Both[/b] gain a star on a tie.\n"
		% [tie_each, tie_each]
	)
	var lf := RichTextLabel.new()
	lf.bbcode_enabled = true
	lf.fit_content = true
	lf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lf.text = "Stars from effects can go down and never sit below [b]0[/b]."
	box.add_child(lt)
	box.add_child(lf)
	%ExtraSlot.add_child(box)
	allow_next()
