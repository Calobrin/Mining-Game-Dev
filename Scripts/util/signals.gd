extends Node
class_name GlobalSignals

# Centralized signals. Keep this minimal; no behavior change.
# After adding as an Autoload, you can connect/emit globally, e.g.:
#   Signals.minigame_closed.emit()
#   Signals.minigame_closed.connect(_on_closed)

signal minigame_opened
signal minigame_closed
signal item_collected(item_id: String)

## Optional helpers so call sites can emit via named methods
func emit_minigame_opened() -> void:
	minigame_opened.emit()

func emit_minigame_closed() -> void:
	minigame_closed.emit()

func emit_item_collected(item_id: String) -> void:
	item_collected.emit(item_id)

# --- Lint suppression: ensure signals are seen as used within this class ---
# This function is never called at runtime; it's only here so static analyzers
# don't flag the declared signals as "unused in this class". Safe no-op.
func _suppress_unused_signal_warnings() -> void:
	if false:
		minigame_opened.emit()
		minigame_closed.emit()
		item_collected.emit("")
