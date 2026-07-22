extends TutorialLessonBase

var _tables: Dictionary = {}
var _influence: int = 0
var _line: Array = []
var _hand: Array = []


func _ready() -> void:
	_tables = TutorialCatalog.load_tables()
	_influence = 5
	_line.clear()
	_hand = [
		{"table": "staff_cards", "id": "TUT_STAFF"},
		{"table": "event_cards", "id": "TUT_EVENT"},
		{"table": "meal_cards", "id": "TUT_MEAL"},
		{"table": "support_cards", "id": "TUT_SUPPORT"},
	]
	super._ready()


func _after_sync_step() -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	if _step != 2:
		return
	_refresh_setup_ui()


func _refresh_setup_ui() -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	var inf := Label.new()
	inf.text = "Influence remaining: %d" % _influence
	%ExtraSlot.add_child(inf)
	var row := HBoxContainer.new()
	for i in range(_hand.size()):
		var idx := i
		var card: Dictionary = _hand[i] as Dictionary
		var t := str(card.get("table", ""))
		var b := Button.new()
		b.text = _label_for(card)
		if t == "support_cards":
			b.disabled = true
			b.tooltip_text = "Support is not set in your line; you play it from hand when rules allow."
		else:
			b.pressed.connect(func () -> void:
				_try_add(idx)
				_refresh_setup_ui()
			)
		row.add_child(b)
	%ExtraSlot.add_child(row)
	var rem := Button.new()
	rem.text = "Remove last set card"
	rem.pressed.connect(func () -> void:
		_pop_line()
		_refresh_setup_ui()
	)
	%ExtraSlot.add_child(rem)


func _label_for(card: Dictionary) -> String:
	var t := str(card.get("table", ""))
	var id_str := str(card.get("id", ""))
	var row := TutorialCatalog.row_by_code(_tables, t, id_str)
	if row.is_empty():
		return "%s" % id_str
	return "%s — %s" % [SupabaseClient.TABLE_LABELS.get(t, t), DeckRules.display_name_for_row(t, row)]


func _try_add(hand_index: int) -> void:
	if hand_index < 0 or hand_index >= _hand.size():
		return
	var card: Dictionary = _hand[hand_index] as Dictionary
	var t := str(card.get("table", ""))
	var id_str := str(card.get("id", ""))
	var row := TutorialCatalog.row_by_code(_tables, t, id_str)
	var cost := SchemaKeys.get_influence_cost(row)
	if cost > _influence:
		return
	_influence -= cost
	_line.append(card)
	_hand.remove_at(hand_index)


func _pop_line() -> void:
	if _line.is_empty():
		return
	var card: Dictionary = _line.pop_back() as Dictionary
	var t := str(card.get("table", ""))
	var id_str := str(card.get("id", ""))
	var row := TutorialCatalog.row_by_code(_tables, t, id_str)
	var cost := SchemaKeys.get_influence_cost(row)
	_influence += cost
	_hand.append(card)
