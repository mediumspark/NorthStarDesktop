extends RefCounted
class_name MatchHandFan

## Hand row layout: level row or symmetric bell-curve fan (center highest, edges lowest).

enum FanShape { LEVEL, BELL_CURVE }

const META_FAN_POS := "fan_pos"
const META_FAN_ROT := "fan_rot"
const META_FAN_Z := "fan_z"
const META_FAN_SCALE := "fan_scale"
const META_HOVER_TWEEN := "fan_hover_tween"
const META_FAN_PEEK := "fan_peek_mode"

const HOVER_SCALE := 1.12
const HOVER_LIFT := 20.0
const HOVER_LIFT_PEEK_MULT := 0.82
const HOVER_TWEEN_SEC := 0.1

const OVERLAP_RATIO := 0.28

## Default hand shape during setup (LoR-style arc, cards stay upright).
const SETUP_FAN_SHAPE := FanShape.BELL_CURVE


static func apply_to(
	row: Control,
	spread_width: float = -1.0,
	peek_ratio: float = -1.0,
	shape: FanShape = SETUP_FAN_SHAPE,
	bell_peak: float = -1.0,
	apex_center_x: float = -1.0
) -> bool:
	if row == null:
		return false
	var cards: Array[Control] = []
	for c in row.get_children():
		if c is Control:
			cards.append(c as Control)
	var n := cards.size()
	if n == 0:
		return true
	var max_spread := spread_width if spread_width > 8.0 else row.size.x
	if max_spread < 8.0:
		var p: Control = row.get_parent_control()
		if p != null:
			max_spread = p.size.x
	if max_spread < 8.0:
		return false
	var card_h := cards[0].custom_minimum_size.y
	if card_h <= 0.0:
		card_h = 120.0
	var card_w := cards[0].size.x if cards[0].size.x > 1.0 else cards[0].custom_minimum_size.x
	if card_w <= 0.0:
		card_w = 80.0
	var overlap := maxf(6.0, card_w * OVERLAP_RATIO)
	var mid := (float(n) - 1.0) * 0.5
	# Place the bell apex (center / highest card) on the requested horizontal center.
	var anchor_x := apex_center_x if apex_center_x >= 0.0 else max_spread * 0.5
	var start_x := anchor_x - overlap * mid - card_w * 0.5
	var visible_fraction := peek_ratio if peek_ratio > 0.0 and peek_ratio < 1.0 else 1.0
	var peek_mode := visible_fraction < 1.0
	var row_h := row.size.y
	if peek_mode:
		if row_h < 8.0:
			var host: Control = row.get_parent_control()
			if host != null:
				row_h = host.size.y
	else:
		var peak := bell_peak if bell_peak > 0.0 else 24.0
		if row_h < card_h + peak:
			row_h = card_h + peak + HOVER_LIFT
	var baseline_y := row_h - card_h * visible_fraction
	var peak_h := bell_peak if bell_peak > 0.0 else _default_bell_peak(peek_mode, card_h)
	for i in range(n):
		var card := cards[i]
		var offset := float(i) - mid
		var x := start_x + overlap * float(i)
		var y_arc := _bell_y(baseline_y, offset, mid, peak_h, shape)
		var pos := Vector2(x, y_arc)
		card.rotation_degrees = 0.0
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.scale = Vector2.ONE
		card.position = pos
		card.z_index = i
		card.set_meta(META_FAN_POS, pos)
		card.set_meta(META_FAN_ROT, 0.0)
		card.set_meta(META_FAN_Z, i)
		card.set_meta(META_FAN_SCALE, Vector2.ONE)
		card.set_meta(META_FAN_PEEK, peek_mode)
		_wire_hover(card, i)
	return true


static func _default_bell_peak(peek_mode: bool, card_h: float) -> float:
	if peek_mode:
		return maxf(12.0, card_h * 0.08)
	return maxf(20.0, card_h * 0.12)


## Symmetric parabola: center card highest, outer cards share the same baseline.
static func _bell_y(baseline_y: float, offset: float, mid: float, peak: float, shape: FanShape) -> float:
	if shape == FanShape.LEVEL or mid <= 0.0:
		return baseline_y
	var norm := offset / mid
	var lift := peak * (1.0 - norm * norm)
	return baseline_y - lift


static func _wire_hover(card: Control, index: int) -> void:
	_kill_hover_tween(card)
	if card.has_meta("_fan_hover_enter"):
		var old_enter: Variant = card.get_meta("_fan_hover_enter")
		if old_enter is Callable and card.mouse_entered.is_connected(old_enter):
			card.mouse_entered.disconnect(old_enter)
		card.remove_meta("_fan_hover_enter")
	if card.has_meta("_fan_hover_exit"):
		var old_exit: Variant = card.get_meta("_fan_hover_exit")
		if old_exit is Callable and card.mouse_exited.is_connected(old_exit):
			card.mouse_exited.disconnect(old_exit)
		card.remove_meta("_fan_hover_exit")
	var on_enter := func () -> void:
		_on_hover_enter(card, index)
	var on_exit := func () -> void:
		_on_hover_exit(card)
	card.set_meta("_fan_hover_enter", on_enter)
	card.set_meta("_fan_hover_exit", on_exit)
	card.mouse_entered.connect(on_enter)
	card.mouse_exited.connect(on_exit)


static func _on_hover_enter(card: Control, index: int) -> void:
	if not is_instance_valid(card):
		return
	_kill_hover_tween(card)
	var base_pos: Vector2 = card.get_meta(META_FAN_POS) as Vector2
	card.z_index = 100 + index
	var lift := HOVER_LIFT
	if card.get_meta(META_FAN_PEEK, false):
		lift = card.custom_minimum_size.y * HOVER_LIFT_PEEK_MULT
	var target_pos := Vector2(base_pos.x, base_pos.y - lift)
	var tween := card.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(card, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_TWEEN_SEC)
	tween.tween_property(card, "position", target_pos, HOVER_TWEEN_SEC)
	tween.tween_property(card, "rotation_degrees", 0.0, HOVER_TWEEN_SEC)
	card.set_meta(META_HOVER_TWEEN, tween)


static func _on_hover_exit(card: Control) -> void:
	if not is_instance_valid(card):
		return
	_kill_hover_tween(card)
	var base_pos: Vector2 = card.get_meta(META_FAN_POS) as Vector2
	var base_z: int = int(card.get_meta(META_FAN_Z))
	card.z_index = base_z
	var tween := card.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(card, "scale", Vector2.ONE, HOVER_TWEEN_SEC)
	tween.tween_property(card, "position", base_pos, HOVER_TWEEN_SEC)
	tween.tween_property(card, "rotation_degrees", 0.0, HOVER_TWEEN_SEC)
	card.set_meta(META_HOVER_TWEEN, tween)


static func _kill_hover_tween(card: Control) -> void:
	if not card.has_meta(META_HOVER_TWEEN):
		return
	var existing: Variant = card.get_meta(META_HOVER_TWEEN)
	if existing is Tween and (existing as Tween).is_valid():
		(existing as Tween).kill()
	card.remove_meta(META_HOVER_TWEEN)
