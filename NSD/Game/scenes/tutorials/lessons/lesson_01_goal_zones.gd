extends TutorialLessonBase


func _after_sync_step() -> void:
	for c in %ExtraSlot.get_children():
		c.queue_free()
	if _step == 2:
		lock_next()
		var b := Button.new()
		b.text = "Chef — baseline influence each Setup"
		b.pressed.connect(func () -> void:
			allow_next()
		)
		%ExtraSlot.add_child(b)
