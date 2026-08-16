class_name RunModifier
extends RefCounted

## Extension seam for light-roguelike content. A modifier is intentionally
## server-side only; it can change an event context, but never exposes hidden
## card information to clients.

var id := ""

func modify_event(_event_name: String, context: Dictionary) -> Dictionary:
	return context
