class_name ToolLogic
extends RefCounted

# Returns an array of dictionaries: { "pos": Vector2i, "multiplier": float }
# Pickaxe pattern: plus shape (center 100%, sides 50%)
static func get_pickaxe_positions(x: int, y: int) -> Array:
	return [
		{"pos": Vector2i(x, y), "multiplier": 1.0},      # Center - 100%
		{"pos": Vector2i(x - 1, y), "multiplier": 0.5},  # Left - 50%
		{"pos": Vector2i(x + 1, y), "multiplier": 0.5},  # Right - 50%
		{"pos": Vector2i(x, y - 1), "multiplier": 0.5},  # Up - 50%
		{"pos": Vector2i(x, y + 1), "multiplier": 0.5},  # Down - 50%
	]

# Returns an array of dictionaries: { "pos": Vector2i, "multiplier": float }
# Hammer pattern: full 3x3, center and sides 100%, corners 50%
static func get_hammer_positions(x: int, y: int) -> Array:
	return [
		# + shape (100% damage)
		{"pos": Vector2i(x, y), "multiplier": 1.0},      # Center - 100%
		{"pos": Vector2i(x - 1, y), "multiplier": 1.0},  # Left - 100%
		{"pos": Vector2i(x + 1, y), "multiplier": 1.0},  # Right - 100%
		{"pos": Vector2i(x, y - 1), "multiplier": 1.0},  # Up - 100%
		{"pos": Vector2i(x, y + 1), "multiplier": 1.0},  # Down - 100%
		# Corners (50% damage)
		{"pos": Vector2i(x - 1, y - 1), "multiplier": 0.5},
		{"pos": Vector2i(x + 1, y - 1), "multiplier": 0.5},
		{"pos": Vector2i(x - 1, y + 1), "multiplier": 0.5},
		{"pos": Vector2i(x + 1, y + 1), "multiplier": 0.5},
	]

# Compute pickaxe durability cost: base + per-cell increment for (affected_count - 1)
static func compute_pickaxe_cost(base_cost: float, affected_count: int, per_cell_increment: float = 0.5) -> float:
	if affected_count <= 0:
		return 0.0
	return base_cost + max(0, affected_count - 1) * per_cell_increment

# Compute hammer durability cost: base + per-cell increment, capped by max_cost
static func compute_hammer_cost(base_cost: float, affected_count: int, per_cell_increment: float, max_cost: float) -> float:
	if affected_count <= 0:
		return 0.0
	var cost = base_cost + max(0, affected_count - 1) * per_cell_increment
	return min(cost, max_cost)
