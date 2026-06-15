extends RefCounted
class_name MatchHandFan

## Hearthstone-style arc layout for hand rows (Control parent with manual positions).


static func apply_to(row: Control) -> void:
	if row == null:
		return
	var cards: Array[Control] = []
	for c in row.get_children():
		if c is Control:
			cards.append(c as Control)
	var n := cards.size()
	if n == 0:
		return
	var max_spread := row.size.x
	if max_spread < 8.0:
		var p := row.get_parent_control()
		if p != null:
			max_spread = p.size.x
		if max_spread < 8.0:
			max_spread = 720.0
	var card_w := cards[0].custom_minimum_size.x
	if card_w <= 0.0:
		card_w = 80.0
	var overlap := maxf(6.0, card_w * 0.34)
	var total_w := card_w + overlap * float(n - 1)
	var start_x := maxf(0.0, (max_spread - total_w) * 0.5)
	var mid := (float(n) - 1.0) * 0.5
	var max_tilt := 8.0 if n > 1 else 0.0
	for i in range(n):
		var card := cards[i]
		var offset := float(i) - mid
		var angle := (offset / maxf(1.0, mid)) * max_tilt if mid > 0.0 else 0.0
		var x := start_x + overlap * float(i)
		var y_arc := absf(offset) * 4.0
		card.rotation_degrees = angle
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.position = Vector2(x, y_arc)
		card.z_index = i
