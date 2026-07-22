class_name CardEffectTargets
extends RefCounted

## Bridges hard-coded card effects to the match targeting layer.


static func request(
	ctx: MatchEffectContext,
	chooser: int,
	prompt: String,
	candidates: Array,
	resolver: Callable
) -> bool:
	## Queue or auto-resolve a target pick. Returns true when waiting on human input.
	if candidates.is_empty():
		return false
	var ms = ctx.match_ref
	if ms.should_auto_resolve_target(chooser):
		var idx := CardTarget.cpu_pick_index(candidates, ctx.rng)
		if idx < 0:
			return false
		resolver.call(candidates[idx])
		return false
	ms.enqueue_target_prompt(chooser, prompt, candidates, resolver)
	return true
