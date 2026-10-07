class_name HintText
extends RefCounted
## 集中所有 action hint 文案（英文，暂不翻译）。main._hint_for 委托到此；将来统一翻译只改本文件。

static func hint(state: Dictionary, phase: int, is_current: bool, action_mode: String) -> String:
	var name := str(state.get("current_name", ""))
	match phase:
		GameState.Phase.INITIAL_PEEK:
			return "Remember your two bottom cards, then click Ready"
		GameState.Phase.TURN_DRAW:
			var slap_note := ""
			if bool(state.get("slap_open", false)):
				slap_note = " · SLAP open: click matching card"
			if is_current:
				return "Draw from the deck or the discard pile (discard top only replaces)" + slap_note
			return "Waiting for %s to draw a card" % name + slap_note
		GameState.Phase.TURN_DECISION:
			return decision(state, is_current, name, action_mode)
		GameState.Phase.Q_DECISION:
			var qd: Dictionary = state.get("q_decision", {})
			if is_current:
				if not bool(qd.get("own_viewed", false)):
					return "Peeked their card. Now pick one of your own cards to peek"
				return "Swap the two viewed cards, or keep yours?"
			if not bool(qd.get("own_viewed", false)):
				return "Waiting for %s to peek one of their own cards" % name
			return "Waiting for %s to decide" % name
		GameState.Phase.SLAP_WINDOW:
			return "Slap: click a card of the same rank. Wrong slap draws a penalty"
		GameState.Phase.SLAP_EXCHANGE:
			if is_current:
				return "Choose one of your cards to give to the slapped player"
			return "Waiting for %s to give a card" % name
		GameState.Phase.SLAP_DUEL:
			return "Duel: stop closest to the red mark to win the slap"
		GameState.Phase.GAME_OVER:
			return "Ranked by total score, then card count, then highest single card"
	return "Waiting for %s to act" % name

static func decision(state: Dictionary, is_current: bool, name: String, action_mode: String) -> String:
	var pending: Dictionary = state.get("pending", {})
	var rank := str(pending.get("rank", ""))
	var source := str(pending.get("source", "draw"))
	if not is_current:
		if source == "discard":
			return "%s took a card from the Discard" % name
		if rank == "J":
			return "%s drew a card and is choosing cards to swap" % name
		if rank in ["7", "8", "9", "10", "Q"]:
			return "%s drew a card and is choosing a card to look at" % name
		return "%s drew a card from the Deck" % name
	if source == "discard":
		return "Replace one of your cards with the drawn card"
	match action_mode:
		"replace":
			return "Replace one of your cards, or discard the drawn card"
		"peek_own":
			return "Choose one of your own cards to peek"
		"peek_other":
			return "Choose another player's card to peek"
		"queen_target":
			return "Peek another player's card, then peek one of your own cards"
		"q_view_own":
			return "Peek one of your own cards, then decide to swap"
		"jack_target":
			return "J: pick an opponent's card to swap"
		"jack_own":
			return "J: pick one of your own cards, then confirm"
		"jack_ready":
			return "J: two cards picked — click Swap or Keep"
	if rank == "J":
		return "Discard to swap two cards, or replace one of your cards"
	if rank in ["7", "8"]:
		return "Discard to peek your own card, or replace one of your cards"
	if rank in ["9", "10"]:
		return "Discard to peek someone's card, or replace one of your cards"
	if rank == "Q":
		return "Discard to peek and decide to swap, or replace one of your cards"
	return "Discard the drawn card, or replace one of your cards"
