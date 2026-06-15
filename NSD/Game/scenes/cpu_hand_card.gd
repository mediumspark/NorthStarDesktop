extends CardTileButton
class_name CpuHandCard

signal card_chosen(hand_index: int)

var _hand_index: int = -1


func setup_from(hand_index: int, fx: CardEffectBase, extra_opts: Dictionary = {}) -> void:
	_hand_index = hand_index
	var opts: Dictionary = extra_opts.duplicate()
	var hook := fx.cpu_match_hook_log()
	if not hook.is_empty():
		opts["hook_log"] = hook
	setup_card(fx.table, fx.row, opts, func () -> void:
		card_chosen.emit(_hand_index)
	)
