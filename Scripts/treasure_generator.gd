class_name TreasureGenerator
extends RefCounted

# ============================================================================
# TREASURE GENERATOR - Handles multi-cell treasure placement and management
# ============================================================================

# Treasure size configurations with weights (higher weight = more common) (calculated by adding up and normalizing)
const TREASURE_SIZES = [
	{"size": Vector2i(1, 1), "weight": 35.5, "name": "Small"},       	
	{"size": Vector2i(2, 2), "weight": 30.0, "name": "Medium"},      	
	#{"size": Vector2i(1, 2), "weight": 15.0, "name": "Tall"},       	
	#{"size": Vector2i(2, 1), "weight": 10.0, "name": "Wide"},       	
	#{"size": Vector2i(3, 2), "weight": 3.0, "name": "Large"},       	
	#{"size": Vector2i(2, 3), "weight": 1.5, "name": "Tall Large"},  	
	{"size": Vector2i(3, 3), "weight": 4.0, "name": "Large"},       	
	{"size": Vector2i(4, 4), "weight": 0.3, "name": "Huge"}             
]

# Debug flag - set to false when using sprite assets instead of colored rectangles
const SHOW_DEBUG_LABELS = true

# Data structure for a placed treasure
class PlacedTreasure:
	var treasure_data  # The actual treasure item (from database)
	var grid_positions: Array[Vector2i] = []  # All grid cells this treasure occupies
	var size: Vector2i  # Width x Height of the treasure
	var top_left: Vector2i  # Top-left corner position
	var revealed: bool = false  # Whether any part has been revealed
	var visual_node: Control = null  # Reference to the visual representation
	
	func _init(data, pos: Vector2i, treasure_size: Vector2i):
		treasure_data = data
		top_left = pos
		size = treasure_size
		
		# Calculate all grid positions this treasure occupies
		for y in range(size.y):
			for x in range(size.x):
				grid_positions.append(Vector2i(top_left.x + x, top_left.y + y))
	
	# Check if this treasure occupies a specific grid position
	func occupies_position(pos: Vector2i) -> bool:
		return pos in grid_positions
	
	# Get the center position for visual placement
	func get_center_position() -> Vector2:
		return Vector2(top_left.x + size.x / 2.0, top_left.y + size.y / 2.0)

# Main treasure placement function
static func place_treasures(grid: Array, grid_size: Vector2i, count: int, mine_id: int = 1, mining_database = null) -> Array[PlacedTreasure]:
	var placed_treasures: Array[PlacedTreasure] = []
	
	print("\n=== TREASURE PLACEMENT ===")
	print("Target treasures: %d, Grid: %dx%d, Mine ID: %d" % [count, grid_size.x, grid_size.y, mine_id])
	
	# Display treasure size distribution for balancing
	print_treasure_size_percentages()
	
	# Track rare gem placement for variety
	var rare_gems_placed = 0
	var max_rare_gems = max(1, float(count) / 3)
	
	# Create placement attempts with safety limit
	var placement_attempts = 0
	var max_attempts = count * 50  # Reasonable limit to prevent infinite loops
	
	while placed_treasures.size() < count and placement_attempts < max_attempts:
		placement_attempts += 1
		
		# Select treasure size based on weighted probability
		var treasure_size = select_treasure_size()
		
		# Find a valid placement position
		var placement_pos = find_valid_placement(grid_size, treasure_size, placed_treasures)
		if placement_pos == Vector2i(-1, -1):
			# No valid placement found, try smaller size or continue
			continue
		
		# Get treasure data from database
		var treasure_data = get_treasure_from_database(mine_id, rare_gems_placed, max_rare_gems, mining_database)
		if treasure_data == null:
			# Database error - skip this treasure placement
			print("Skipping treasure placement due to database error")
			continue
		
		# Increase rare gem count if this is a rare gem
		if is_rare_treasure(treasure_data):
			rare_gems_placed += 1
		
		# Create the placed treasure
		var placed_treasure = PlacedTreasure.new(treasure_data, placement_pos, treasure_size)
		placed_treasures.append(placed_treasure)
		
		# Update grid with treasure data
		update_grid_with_treasure(grid, placed_treasure)
		
		# Debug output for treasure placement
		var treasure_name = get_treasure_name_safe(treasure_data)
		var size_name = get_size_name(treasure_size)
		print("  → Placed " + size_name + " " + treasure_name + " at " + str(placement_pos) + " (" + str(treasure_size) + ")")
	
	print("TREASURE PLACEMENT COMPLETE: %d/%d treasures placed (%d attempts)" % [
		placed_treasures.size(), count, placement_attempts
	])
	
	return placed_treasures

# Select a treasure size based on weighted probability
static func select_treasure_size() -> Vector2i:
	var total_weight = 0.0
	for size_config in TREASURE_SIZES:
		total_weight += size_config.weight
	
	var random_value = randf() * total_weight
	var current_weight = 0.0
	
	for size_config in TREASURE_SIZES:
		current_weight += size_config.weight
		if random_value <= current_weight:
			return size_config.size
	
	# Fallback to smallest size
	return Vector2i(1, 1)

# Find a valid placement position for a treasure of given size
static func find_valid_placement(grid_size: Vector2i, treasure_size: Vector2i, existing_treasures: Array[PlacedTreasure]) -> Vector2i:
	var max_attempts = 100
	
	for attempt in range(max_attempts):
		# Random position ensuring treasure fits within grid
		var x = randi() % (grid_size.x - treasure_size.x + 1)
		var y = randi() % (grid_size.y - treasure_size.y + 1)
		var test_pos = Vector2i(x, y)
		
		# Check if this position conflicts with existing treasures
		if is_position_valid(test_pos, treasure_size, existing_treasures):
			return test_pos
	
	# No valid position found
	return Vector2i(-1, -1)

# Check if a position is valid (no conflicts with existing treasures)
static func is_position_valid(pos: Vector2i, size: Vector2i, existing_treasures: Array[PlacedTreasure]) -> bool:
	# Check all cells this treasure would occupy
	for y in range(size.y):
		for x in range(size.x):
			var check_pos = Vector2i(pos.x + x, pos.y + y)
			
			# Check against all existing treasures
			for treasure in existing_treasures:
				if treasure.occupies_position(check_pos):
					return false
	
	return true

# Update grid cells with treasure data
static func update_grid_with_treasure(grid: Array, treasure: PlacedTreasure):
	for grid_pos in treasure.grid_positions:
		var x = grid_pos.x
		var y = grid_pos.y
		
		# Determine treasure layer based on grid structure
		var has_stone = grid[y][x]["layers"][0]["type"] == 0  # LayerType.STONE
		var treasure_layer = 2 if has_stone else 1
		
		# Set treasure data in the appropriate layer
		grid[y][x]["layers"][treasure_layer]["type"] = 2  # LayerType.TREASURE
		grid[y][x]["layers"][treasure_layer]["treasure"] = treasure.treasure_data
		grid[y][x]["layers"][treasure_layer]["treasure_ref"] = treasure  # Reference to full treasure object

# Get treasure data from database with rare gem logic
static func get_treasure_from_database(mine_id: int, rare_gems_placed: int, max_rare_gems: int, mining_data):
	if mining_data != null:
		# Decide if this should be a rare gem
		if rare_gems_placed < max_rare_gems and randf() < 0.3:
			# Try to get a rare gem (top 20% by price)
			var mine_items = mining_data.get_items_in_mine(mine_id)
			if mine_items.size() > 0:
				mine_items.sort_custom(func(a, b): return get_treasure_price_safe(a) > get_treasure_price_safe(b))
				var top_index = max(1, mine_items.size() / 5)
				return mine_items[randi() % int(top_index)]
		
		# Standard random selection
		return mining_data.get_random_item(mine_id)
	else:
		push_error("CRITICAL: MiningItemDatabase AutoLoad not found! Please add mining_item_database.gd as an AutoLoad named 'MiningItemDatabase' in Project Settings.")
		return null

# Create visual representation for a multi-cell treasure
static func create_treasure_visual(treasure: PlacedTreasure, cell_size: Vector2, parent_container: Control) -> Control:
	var visual = ColorRect.new()
	
	# Size spans multiple cells
	visual.size = Vector2(treasure.size.x * cell_size.x, treasure.size.y * cell_size.y) * 0.8
	
	# Find the GridContainer within the parent to get its offset
	var grid_container = parent_container.get_node("GridContainer")
	var grid_offset = Vector2.ZERO
	if grid_container != null:
		grid_offset = grid_container.position
	
	# Center the treasure visual across all occupied grid cells
	# Calculate the center point of the treasure's grid area
	var treasure_center_x = treasure.top_left.x + (treasure.size.x - 1) / 2.0
	var treasure_center_y = treasure.top_left.y + (treasure.size.y - 1) / 2.0
	
	# Position the visual so it's centered on the treasure area, accounting for grid offset
	visual.position = Vector2(
		grid_offset.x + treasure_center_x * cell_size.x - visual.size.x / 2.0,
		grid_offset.y + treasure_center_y * cell_size.y - visual.size.y / 2.0
	)
	
	# Color based on treasure value
	visual.color = get_treasure_color_safe(treasure.treasure_data)
	
	# Disable mouse input so it doesn't block grid clicks
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add label with treasure name and size info (only in debug mode)
	if SHOW_DEBUG_LABELS:
		var label = Label.new()
		label.text = get_treasure_name_safe(treasure.treasure_data)
		if treasure.size != Vector2i(1, 1):
			label.text += "\n" + get_size_name(treasure.size)
		
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = visual.size
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		visual.add_child(label)
	treasure.visual_node = visual
	
	return visual

# Check if any cell of a treasure has been revealed
static func check_treasure_visibility(treasure: PlacedTreasure, grid: Array) -> bool:
	for grid_pos in treasure.grid_positions:
		var x = grid_pos.x
		var y = grid_pos.y
		var cell_data = grid[y][x]
		
		# Check if the treasure layer is accessible (all layers above are revealed)
		var has_stone = cell_data["layers"][0]["type"] == 0  # LayerType.STONE
		var treasure_layer = 2 if has_stone else 1
		
		# Check if we can see the treasure layer
		var can_see_treasure = true
		for layer_idx in range(treasure_layer):
			if not cell_data["layers"][layer_idx]["revealed"]:
				can_see_treasure = false
				break
		
		if can_see_treasure:
			return true
	
	return false

# Helper functions for safe data access
static func get_treasure_name_safe(treasure_data) -> String:
	if treasure_data == null:
		return "Unknown"
	if treasure_data is Dictionary:
		return treasure_data.get("name", "Unknown")
	elif treasure_data.has_method("get_name"):
		return treasure_data.get_name()
	elif "name" in treasure_data:
		return treasure_data.name
	return "Unknown"

static func get_treasure_price_safe(treasure_data) -> float:
	if treasure_data == null:
		return 0.0
	if treasure_data is Dictionary:
		return treasure_data.get("base_price", 0.0)
	elif treasure_data.has_method("get_price"):
		return treasure_data.get_price()
	elif "base_price" in treasure_data:
		return treasure_data.base_price
	return 0.0

static func get_treasure_color_safe(treasure_data) -> Color:
	var price = get_treasure_price_safe(treasure_data)
	
	# Color based on value ranges
	if price >= 100.0:
		return Color(1.0, 0.2, 1.0)  # Magenta - Ultra rare
	elif price >= 80.0:
		return Color(1.0, 0.4, 0.0)  # Orange - Very rare
	elif price >= 60.0:
		return Color(0.2, 0.8, 1.0)  # Cyan - Rare
	elif price >= 40.0:
		return Color(0.2, 1.0, 0.2)  # Green - Uncommon
	else:
		return Color(0.8, 0.7, 0.2)  # Yellow - Common

static func is_rare_treasure(treasure_data) -> bool:
	return get_treasure_price_safe(treasure_data) >= 80.0

static func get_size_name(size: Vector2i) -> String:
	for size_config in TREASURE_SIZES:
		if size_config.size == size:
			return size_config.name
	return "Custom"

# Display treasure size distribution for balancing
static func print_treasure_size_percentages():
	var total_weight = 0.0
	for size_config in TREASURE_SIZES:
		total_weight += size_config.weight
	
	print("Treasure size distribution:")
	for size_config in TREASURE_SIZES:
		var percentage = (size_config.weight / total_weight) * 100.0
		print("  - %s (%dx%d): %.1f%%" % [size_config.name, size_config.size.x, size_config.size.y, percentage])
