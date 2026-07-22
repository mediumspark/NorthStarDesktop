extends TutorialLessonBase

var _deck: Array = []
var _hand: Array = []
var _hand_label: Label
var _mulligan_used: bool = false


func _ready() -> void:
	_build_demo_deck()
	super._ready()


func _build_demo_deck() -> void:
	_deck.clear()
	for i in range(15):
		_deck.append({"table": "staff_cards", "id": "TUT_STAFF"})
	_shuffle_deck()


func _shuffle_deck() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(_deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = _deck[i]
		_deck[i] = _deck[j]
		_deck[j] = t


func _draw_five() -> void:
	_hand.clear()
	for _i in range(5):
		if _deck.is_empty():
			break
		_hand.append(_deck.pop_front())


func _return_hand_to_deck() -> void:
	while not _hand.is_empty():
		_deck.append(_hand.pop_back())
	_shuffle_deck()


func _after_sync_step() -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	if _step != 1:
		%NextButton.visible = true
		return
	_mulligan_used = false
	_draw_five()
	%NextButton.visible = false
	lock_next()
	_hand_label = Label.new()
	_hand_label.text = "Hand size: %d (demo staff cards)" % _hand.size()
	%ExtraSlot.add_child(_hand_label)
	var mull := Button.new()
	mull.text = "Mulligan all (return 5, redraw 5)"
	mull.pressed.connect(func () -> void:
		if _mulligan_used:
			return
		_mulligan_used = true
		_return_hand_to_deck()
		_draw_five()
		_hand_label.text = "Hand size: %d (after your one mulligan)" % _hand.size()
		mull.disabled = true
		mull.tooltip_text = "Rules: only one mulligan before the first round."
		TutorialVisuals.clear_band(%VisualBand)
		TutorialVisuals.add_staff_hand_backs(%VisualBand, _hand.size())
	)
	var keep := Button.new()
	keep.text = "Keep hand"
	keep.pressed.connect(func () -> void:
		TutorialProgress.mark_completed(lesson_id)
		super._go_hub()
	)
	%ExtraSlot.add_child(mull)
	%ExtraSlot.add_child(keep)
