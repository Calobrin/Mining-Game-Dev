extends Node
class_name GlobalConstants

# Centralized constants. Keep this minimal and non-behavior-changing.
# Refer to with: Constants.<NAME> after adding as an Autoload in project.godot

# Project/version metadata
const VERSION := "0.1"

# Common resource paths (mirror current layout; update if files move)
const Paths := {
	MINING_ITEMS_JSON = "res://data/mining_items.json"
}

# UI defaults
const UI := {
	DEFAULT_MARGIN = 8,
	DEFAULT_SPACING = 6
}

# Gameplay defaults (non-authoritative; use as shared defaults only)
const Gameplay := {
	DEFAULT_GRID_ROWS = 24,
	DEFAULT_GRID_COLS = 24
}
