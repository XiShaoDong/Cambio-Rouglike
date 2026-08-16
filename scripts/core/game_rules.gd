class_name KongRules
extends RefCounted

## Central, data-only rules. Keep this independent from UI and ENet so the same
## match authority can run in a LAN host or a future headless VPS process.

const MAX_PLAYERS := 4
const MIN_PLAYERS := 2
const HAND_SIZE := 4
const SLAP_WINDOW_SECONDS := 2.5

const SPECIAL_RANKS := ["7", "8", "9", "10", "J", "Q"]

static func card_value(rank: String) -> int:
	match rank:
		"A": return 1
		"J", "Q": return 10
		"K": return -1
		"JOKER": return 0
		_: return int(rank)

static func has_ability(rank: String) -> bool:
	return rank in SPECIAL_RANKS

static func display_name(card: Dictionary) -> String:
	if card.rank == "JOKER":
		return "大王" if card.suit == "red" else "小王"
	return "%s%s" % [card.rank, card.suit]

static func new_default_run() -> Dictionary:
	# The MVP leaves modifiers disabled. Future relics/mutators belong in this
	# serializable run state, rather than in match-flow conditionals.
	return {
		"health": 3,
		"relic_slots": 2,
		"relics": {},
		"mutator_ids": [],
		"enable_relics": false,
	}
