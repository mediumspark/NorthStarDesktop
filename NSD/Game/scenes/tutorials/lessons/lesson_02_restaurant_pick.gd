extends TutorialLessonBase

var _tables: Dictionary = {}


func _ready() -> void:
	_tables = TutorialCatalog.load_tables()
	super._ready()


func _after_sync_step() -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	if _step != 1:
		return
	lock_next()
	var top := Button.new()
	top.text = "Take TOP — %s" % _rest_label("TUT_REST_TOP")
	top.pressed.connect(func () -> void:
		_pick(true)
	)
	var bot := Button.new()
	bot.text = "Take BOTTOM — %s" % _rest_label("TUT_REST_BOT")
	bot.pressed.connect(func () -> void:
		_pick(false)
	)
	%ExtraSlot.add_child(top)
	%ExtraSlot.add_child(bot)


func _rest_label(code: String) -> String:
	var row := TutorialCatalog.row_by_code(_tables, DeckRules.RESTAURANT_TABLE, code)
	if row.is_empty():
		return code
	return DeckRules.display_name_for_row(DeckRules.RESTAURANT_TABLE, row)


func _pick(_take_top: bool) -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	allow_next()
	var done := Label.new()
	done.text = "Nice. In a real match this becomes your active restaurant."
	%ExtraSlot.add_child(done)
