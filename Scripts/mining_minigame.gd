extends CanvasLayer


# Grid properties
const GRID_SIZE = Vector2i(17, 10)  # 10x10 grid				# No space between cells - continuous terrain

# Use fixed or dynamic cell size
@export var use_fixed_cell_size: bool = true		# Set to false for dynamic sizing based on container
@export var fixed_cell_size: Vector2 = Vector2(50, 50)	# Size of each cell in pixels when using fixed sizing

# Overlay dimensions (automatically calculated based on screen size)
@export_range(0.5, 0.9, 0.05) var overlay_width_percentage: float = 0.85  # Percentage of screen width
@export_range(0.5, 0.9, 0.05) var overlay_height_percentage: float = 0.8  # Percentage of screen height
@export var min_cell_size: Vector2 = Vector2(30, 30)  # Minimum cell size to ensure visibility

# Layer types
enum LayerType { STONE, DIRT, TREASURE, EMPTY }

# Tool types
enum ToolType { PICKAXE, HAMMER }
var current_tool = ToolType.PICKAXE

# Game state
var max_durability = 100
var current_durability = 0  # Will be set to max_durability in start_game()
var game_over = false
var grid = []  # Stores the terrain data
var treasures = []  # Stores the treasure locations and types

# Dev mode for testing
@export var dev_mode_unlimited_durability: bool = false  # Toggle in inspector for unlimited durability

# Treasure generation settings
@export_range(2, 5, 1) var min_treasures: int = 3  # Minimum treasures per game
@export_range(6, 15, 1) var max_treasures: int = 10  # Maximum treasures per game

# Durability cost percentages (easily adjustable for game balance)
@export_range(0.5, 3.0, 0.1) var pickaxe_durability_cost_percent: float = 1.0  # 1% per cell
@export_range(1.0, 5.0, 0.1) var hammer_base_cost_percent: float = 2.0  # 2% base cost for hammer
@export_range(0.1, 1.0, 0.1) var hammer_per_cell_cost_percent: float = 0.5  # 0.5% per additional cell
@export_range(3.0, 8.0, 0.1) var hammer_max_cost_percent: float = 5.0  # 5% maximum cost

# Mining properties - dirt breaks in 1 hit, stone in 2 hits
var pickaxe_damage = {
	LayerType.STONE: 50,  # Stone takes 2 hits (100 durability / 50 damage = 2 hits)
	LayerType.DIRT: 100   # Dirt takes 1 hit (100 durability / 100 damage = 1 hit)
}

var hammer_damage = {
	LayerType.STONE: 50,  # Stone takes 2 hits (same as pickaxe)
	LayerType.DIRT: 100   # Dirt takes 1 hit (same as pickaxe)
}

# Visual elements
var cell_nodes = []  # Stores references to the cell UI nodes
var treasure_nodes = []  # Stores references to the treasure UI nodes

# Called when the node enters the scene tree for the first time
func _ready():
	randomize()  # Initialize random number generator
	
	# Connect to window resize signals to handle resolution changes
	get_viewport().size_changed.connect(on_viewport_resized)
	
	# Check for MiningItemDatabase AutoLoad
	if get_node_or_null("/root/MiningItemDatabase") == null:
		print("WARNING: MiningItemDatabase AutoLoad not found! Using test data fallback.")
		print("Please add mining_item_database.gd as an AutoLoad named 'MiningItemDatabase' in Project Settings.")
		# Create a warning label
		var warning = Label.new()
		warning.text = "MiningItemDatabase not found! Using test data."
		warning.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
		warning.position = Vector2(10, 570)
		add_child(warning)
	else:
		print("MiningItemDatabase AutoLoad detected successfully!")
		
	# Connect tool buttons
	$MainContainer/ToolContainer/PickaxeTool.pressed.connect(func(): set_current_tool(ToolType.PICKAXE))
	$MainContainer/ToolContainer/HammerTool.pressed.connect(func(): set_current_tool(ToolType.HAMMER))
	
	# Connect close button
	$"MainContainer/CloseButton".pressed.connect(func(): close_minigame())
	
	# Start a new game (this will handle grid initialization, durability, and treasures)
	print("DEBUG: Starting new game from _ready()...")
	start_game()

# Initialize the grid with layered structure
func init_grid():
	grid = []
	for y in range(GRID_SIZE.y):
		var row = []
		for x in range(GRID_SIZE.x):
			# Each cell has layers: stone (possibly), dirt, and content (treasure or empty)
			var has_stone = randf() < 0.4  # 40% chance of having stone layer
			
			# Each cell is a dictionary with layer information
			row.append({
				"layers": [
					# First element is topmost visible layer
					{
						"type": LayerType.STONE if has_stone else LayerType.DIRT,
						"durability": 100,  # Each layer starts with full durability
						"revealed": false   # Whether this layer has been broken through
					},
					# Second element is middle layer (only if we have stone on top)
					{
						"type": LayerType.DIRT if has_stone else LayerType.EMPTY,
						"durability": 100,
						"revealed": false
					},
					# Third element is bottom layer (treasure or empty)
					{
						"type": LayerType.EMPTY,  # Will be set to TREASURE later if needed
						"durability": 0,  # No durability for empty spaces
						"revealed": false,
						"treasure": null  # Will store treasure data if present
					}
				],
				"current_layer": 0  # Index of the currently visible/active layer
			})
		grid.append(row)

# Calculate overlay dimensions based on viewport size
func get_overlay_dimensions() -> Vector2:
	var viewport_size = get_viewport().get_visible_rect().size
	var width = viewport_size.x * overlay_width_percentage
	var height = viewport_size.y * overlay_height_percentage
	return Vector2(width, height)

# Calculate the offset needed to center the grid within the available space
func get_grid_centering_offset() -> Vector2:
	var actual_cell_size = get_actual_cell_size()
	
	# Calculate the total grid size
	var total_grid_width = GRID_SIZE.x * actual_cell_size.x + (GRID_SIZE.x - 1)
	var total_grid_height = GRID_SIZE.y * actual_cell_size.y + (GRID_SIZE.y - 1)
	
	# Use the overlay dimensions (which are based on viewport size) for centering
	var overlay_dims = get_overlay_dimensions()
	
	# Calculate offset to center the grid within the overlay space
	var offset_x = (overlay_dims.x - total_grid_width) / 2.0
	var offset_y = (overlay_dims.y - total_grid_height) / 2.0
	
	print("Overlay dims: ", overlay_dims, " Grid size: ", Vector2(total_grid_width, total_grid_height))
	print("Centering offset: ", Vector2(offset_x, offset_y))
	return Vector2(offset_x, offset_y)

# Calculate actual cell size based on settings and screen resolution
func get_actual_cell_size() -> Vector2:
	if use_fixed_cell_size:
		# Use fixed size - guaranteed perfect squares
		return fixed_cell_size
	else:
		# Dynamic sizing: calculate based on available space while maintaining square aspect ratio
		var overlay_dims = get_overlay_dimensions()
		
		# Calculate the maximum square size that fits both width and height constraints
		var max_cell_width = overlay_dims.x / GRID_SIZE.x
		var max_cell_height = overlay_dims.y / GRID_SIZE.y
		
		# Use the smaller dimension to ensure squares fit in both directions
		var cell_size = min(max_cell_width, max_cell_height)
		
		# Ensure we don't go below minimum size
		cell_size = max(cell_size, min_cell_size.x)  # Use x since min_cell_size should also be square
		
		# Return perfect squares
		return Vector2(cell_size, cell_size)

# Create visual representation of the grid
func create_grid_visuals():
	cell_nodes = []
	
	# Get the actual cell size to use
	var actual_cell_size = get_actual_cell_size()
	
	# Get the centering offset
	var centering_offset = get_grid_centering_offset()
	
	# Set up rows of cells
	for y in range(GRID_SIZE.y):
		var row = []
		for x in range(GRID_SIZE.x):
			var cell_data = grid[y][x]
			
			# Create cell visual
			var cell = ColorRect.new()
			cell.size = actual_cell_size
			# Prevent the container from stretching this cell
			cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# Position cell with centering offset
			cell.position = Vector2(
				centering_offset.x + x * (actual_cell_size.x),
				centering_offset.y + y * (actual_cell_size.y)
			)
			
			# Set color based on top layer
			var current_layer = cell_data["layers"][cell_data["current_layer"]]
			
			if current_layer["type"] == LayerType.DIRT:
				cell.color = Color(0.6, 0.4, 0.2)  # Brown for dirt
			elif current_layer["type"] == LayerType.STONE:
				cell.color = Color(0.5, 0.5, 0.55)  # Grey for stone
			else:
				cell.color = Color(0.2, 0.2, 0.2)  # Dark grey for empty or treasure (not visible yet)
			
			# Add subtle border for visual distinction
			var border_color = Color(0.3, 0.3, 0.3, 0.5)  # Semi-transparent dark border
			var style_box = StyleBoxFlat.new()
			style_box.bg_color = cell.color
			style_box.border_width_left = 1
			style_box.border_width_right = 1
			style_box.border_width_top = 1
			style_box.border_width_bottom = 1
			style_box.border_color = border_color
			cell.add_theme_stylebox_override("panel", style_box)
			
			# Make cell clickable with direct reference to coordinates
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			
			# Store the grid coordinates directly in the cell
			cell.set_meta("grid_x", x)
			cell.set_meta("grid_y", y)
			
			# Connect click event with explicit coordinates from metadata
			cell.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					var clicked_x = cell.get_meta("grid_x")
					var clicked_y = cell.get_meta("grid_y")
					on_cell_clicked(clicked_x, clicked_y))
			
			# Add to scene
			$MainContainer/MainGameArea/GridContainer.add_child(cell)
			row.append(cell)
		
		# Store the row
		cell_nodes.append(row)
	
	# Add a target reticle for aiming
	var reticle = create_reticle()
	$MainContainer/MainGameArea/GridContainer.add_child(reticle)

# Create an aiming reticle that follows the mouse
func create_reticle():
	var reticle = Control.new()
	reticle.name = "Reticle"
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create a cross shape using lines
	var reticle_lines = Line2D.new()
	reticle_lines.width = 2
	reticle_lines.default_color = Color(1, 0, 0, 0.8)  # Red
	
	# Cross shape points (horizontal line)
	reticle_lines.add_point(Vector2(-10, 0))
	reticle_lines.add_point(Vector2(10, 0))
	
	# Add a second line for vertical part
	var vertical_line = Line2D.new()
	vertical_line.width = 2
	vertical_line.default_color = Color(1, 0, 0, 0.8)
	vertical_line.add_point(Vector2(0, -10))
	vertical_line.add_point(Vector2(0, 10))
	
	reticle.add_child(reticle_lines)
	reticle.add_child(vertical_line)
	
	return reticle

# Process mouse movement to update reticle position
func _process(_delta):
	# Update reticle position if it exists
	var reticle = $MainContainer/MainGameArea/GridContainer.get_node_or_null("Reticle")
	if reticle:
		var grid_container = $MainContainer/MainGameArea/GridContainer
		# Get mouse position relative to the grid container, accounting for all UI offsets
		var mouse_pos = grid_container.get_local_mouse_position()
		reticle.position = mouse_pos

# Update durability label
func update_durability_label():
	var label = $"MainContainer/UI Elements/DurabilityLabel"
	if label != null:
		label.text = "Durability: " + str(current_durability)

# Handle viewport resizing
func on_viewport_resized():
	# DISABLED: This function was destroying treasures when window resized
	# The grid works fine without recreation - Godot handles UI scaling automatically
	print("Viewport resized - resize handler disabled to preserve game state")
	return

# Handle close button press
func on_close_button_pressed():
	# This is where you'd add code to hide the minigame and return to the main game
	print("Close button pressed - minigame should close")
	# For testing only - eventually remove this line
	visible = false
	# In your actual implementation, you'd use something like:
	# hide()
	# or emit a signal that the parent can listen for
	# emit_signal("minigame_closed")

# Start a new game
func start_game():
	# Hide system cursor and show custom crosshair
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	# Reset game state
	game_over = false
	current_durability = max_durability
	
	# Clear any existing grid
	for child in $MainContainer/MainGameArea/GridContainer.get_children():
		child.queue_free()
	
	# Initialize new grid and visuals
	init_grid()
	create_grid_visuals()
	# Generate random number of treasures within the specified range
	var treasure_count = randi_range(min_treasures, max_treasures)
	place_treasures(treasure_count)
	
	# Update durability display
	update_durability_label()
	
	# Initialize tool selection (highlight default pickaxe)
	set_current_tool(current_tool)
	
	# Show tutorial text if desired
	print("Mining game started! Break through stone (4 hits) to reveal dirt (1 hit), and dirt to find treasures!")
	print("Pickaxe: Single cell | Hammer: Plus shape (+) | Grid: " + str(GRID_SIZE.x) + " x " + str(GRID_SIZE.y))

# Place treasures in the grid using weighted random selection
func place_treasures(count: int):
	treasures = []
	
	# Mine ID that can be set when starting the minigame (default: mine 1)
	var mine_id = 1
	
	# Track rare gem placement to ensure some variety
	var rare_gems_placed = 0
	var max_rare_gems = max(1, float(count) / 3)  # At least 1 rare gem, up to 1/3 of total
	
	print("Placing " + str(count) + " treasures in mine #" + str(mine_id))
	
	# Create a list of all available positions
	var available_positions = []
	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			available_positions.append(Vector2(x, y))
	
	# Shuffle the positions for random placement
	available_positions.shuffle()
	
	# Ensure we don't try to place more treasures than available positions
	var treasures_to_place = min(count, available_positions.size())
	if treasures_to_place < count:
		print("WARNING: Only placing " + str(treasures_to_place) + " treasures (grid too small for " + str(count) + ")")
	
	for i in range(treasures_to_place):
		# Get the next available position
		var pos = available_positions[i]
		var x = int(pos.x)
		var y = int(pos.y)
		
		# Get a treasure from the database
		var treasure = null
		var mining_data = get_node_or_null("/root/MiningItemDatabase")
		if mining_data != null:
			print("Using MiningData for treasure selection...")
			
			# Choose either rare or common treasure
			if rare_gems_placed < max_rare_gems and randf() < 0.3:  # 30% chance for rare gems
				# Try to get a rare gem (more expensive)
				var mine_items = mining_data.get_items_in_mine(mine_id)
				print("Found " + str(mine_items.size()) + " items for mine #" + str(mine_id))
				
				if mine_items.size() > 0:
					# Sort by price (descending)
					mine_items.sort_custom(func(a, b): return a.base_price > b.base_price)
					
					# Get a gem from the top 20% price range
					var top_index = max(1, mine_items.size() / 5)
					treasure = mine_items[randi() % int(top_index)]
					rare_gems_placed += 1
					print("Placed rare gem: " + treasure.name + " (value: " + str(treasure.base_price) + ")")
				else:
					# Fallback to random if no items found
					treasure = mining_data.get_random_item(mine_id)
					print("No specific mine items found, using random item: " + treasure.name)
			else:
				# Standard random selection using weighted distribution
				treasure = mining_data.get_random_item(mine_id)
				print("Using standard weighted random: " + treasure.name)
		else:
			print("MiningItemDatabase not found, using test fallback data...")
			# Fallback for testing when database isn't available
			var test_gems = ["Amethyst-test", "Ruby-test", "Sapphire-test", "Emerald-test", "Diamond-test"]
			var test_prices = [70.0, 74.0, 78.0, 82.0, 100.0]
			var gem_index = randi() % test_gems.size()
			treasure = {
				"id": "test_" + str(i),
				"name": test_gems[gem_index],
				"base_price": test_prices[gem_index]
			}
		
		# Store treasure data in the correct layer based on structure
		# If there's stone: Stone(0) -> Dirt(1) -> Treasure(2)
		# If no stone: Dirt(0) -> Treasure(1)
		var has_stone = grid[y][x]["layers"][0]["type"] == LayerType.STONE
		var treasure_layer = 2 if has_stone else 1
		
		grid[y][x]["layers"][treasure_layer]["type"] = LayerType.TREASURE
		grid[y][x]["layers"][treasure_layer]["treasure"] = treasure
		print("DEBUG: Placed treasure at layer " + str(treasure_layer) + " (has_stone: " + str(has_stone) + ")")
		print("DEBUG: Placed treasure '" + get_treasure_name(treasure) + "' at position (" + str(x) + ", " + str(y) + ")")
		
		# Create a visual representation for the treasure (hidden initially)
		var treasure_visual = create_treasure_visual(treasure, x, y)
		treasure_visual.modulate.a = 0  # Start invisible
		print("DEBUG: Created treasure visual at position: " + str(treasure_visual.position) + " size: " + str(treasure_visual.size))
		$MainContainer/MainGameArea/GridContainer.add_child(treasure_visual)
		treasures.append({
			"visual": treasure_visual,
			"grid_pos": Vector2(x, y),
			"revealed": false
		})
	
	# Confirm treasure placement
	print("TREASURE PLACEMENT COMPLETE: " + str(treasures.size()) + " treasures placed successfully!")
	print("Grid size: " + str(GRID_SIZE.x) + "x" + str(GRID_SIZE.y) + " = " + str(GRID_SIZE.x * GRID_SIZE.y) + " total cells")

# Helper function to get treasure name safely whether it's a dictionary or object
func get_treasure_name(treasure_data):
	if typeof(treasure_data) == TYPE_DICTIONARY:
		return treasure_data["name"] if treasure_data.has("name") else "???"
	else:
		return treasure_data.name

# Create a visual for a treasure with color based on value
func create_treasure_visual(treasure_data, grid_x, grid_y):
	# Use the same cell size calculation
	var actual_cell_size = get_actual_cell_size()
	
	var visual = ColorRect.new()
	visual.size = actual_cell_size * 0.8  # Slightly smaller than the cell
	
	# Get centering offset to match grid positioning
	var centering_offset = get_grid_centering_offset()
	visual.position = Vector2(
		centering_offset.x + grid_x * (actual_cell_size.x) + actual_cell_size.x * 0.1,
		centering_offset.y + grid_y * (actual_cell_size.y) + actual_cell_size.y * 0.1
	)
	
	# Color based on treasure value
	# In a real game, you'd use sprites instead of colored rectangles
	var gem_color = Color(0.8, 0.5, 0.9)  # Default purple for generic gem
	
	# If treasure has a price, use color coding by value
	var price = 0.0
	
	# Check if treasure_data is a dictionary or an object
	if typeof(treasure_data) == TYPE_DICTIONARY:
		# It's a dictionary (test data)
		if treasure_data.has("base_price"):
			price = treasure_data["base_price"]
	else:
		# It's an object (MiningItem)
		price = treasure_data.base_price
		
	# Set color based on price
	if price > 100.0:  # High value - gold/yellow
		gem_color = Color(0.9, 0.85, 0.2)
		print("High value gem: " + get_treasure_name(treasure_data) + " (" + str(price) + ")")
	elif price > 75.0:  # Medium-high value - blue
		gem_color = Color(0.2, 0.6, 0.9)
	elif price > 50.0:  # Medium value - green
		gem_color = Color(0.2, 0.8, 0.4)
	elif price > 0:  # Lower value - pink/purple
		gem_color = Color(0.8, 0.5, 0.9)
	
	visual.color = gem_color
	
	# CRITICAL FIX: Disable mouse input so treasure visuals don't block grid clicks
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Label with treasure name
	var label = Label.new()
	label.text = get_treasure_name(treasure_data)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = visual.size
	# Also disable mouse input on the label
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	visual.add_child(label)
	return visual

# Helper function to check if a cell is fully revealed (at bottom layer and revealed)
func is_cell_fully_revealed(x: int, y: int) -> bool:
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	
	# A cell is fully revealed if it's at the bottom layer (2) and that layer is revealed
	return current_layer_index == 2 and current_layer["revealed"]

# Helper function to check if a cell has damageable material (dirt or stone) in its current layer
func can_cell_be_damaged(x: int, y: int) -> bool:
	# Check bounds
	if x < 0 or x >= GRID_SIZE.x or y < 0 or y >= GRID_SIZE.y:
		return false
	
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	
	# Can only damage if current layer is dirt or stone AND not already revealed
	return (current_layer["type"] == LayerType.DIRT or current_layer["type"] == LayerType.STONE) and not current_layer["revealed"]

# Handle cell clicking
func on_cell_clicked(x: int, y: int):
	if game_over:
		return
		
	# Get current layer of the clicked cell
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	
	# Skip if this is the bottom layer and already revealed (empty or revealed treasure)
	if current_layer_index == 2 and current_layer["revealed"]:
		return
		
	# Get the current tool damage values
	var damage_values
	if current_tool == ToolType.PICKAXE:
		damage_values = pickaxe_damage
	else:  # HAMMER
		damage_values = hammer_damage
	
	# Calculate durability cost based on actual cells that will be affected
	var cells_that_will_be_damaged = 0
	
	# Check center cell - only count if it has damageable material
	if can_cell_be_damaged(x, y):
		cells_that_will_be_damaged += 1
	
	# For hammer, check surrounding cells too
	if current_tool == ToolType.HAMMER:
		# Check left cell
		if can_cell_be_damaged(x - 1, y):
			cells_that_will_be_damaged += 1
		# Check right cell
		if can_cell_be_damaged(x + 1, y):
			cells_that_will_be_damaged += 1
		# Check up cell
		if can_cell_be_damaged(x, y - 1):
			cells_that_will_be_damaged += 1
		# Check down cell 
		if can_cell_be_damaged(x, y + 1):
			cells_that_will_be_damaged += 1
	
	# Calculate dynamic durability cost
	var durability_cost = 0
	if cells_that_will_be_damaged > 0:
		if current_tool == ToolType.PICKAXE:
			# Pickaxe: simple percentage per cell
			durability_cost = int(max_durability * (pickaxe_durability_cost_percent / 100.0) * cells_that_will_be_damaged)
		else:  # HAMMER
			# Hammer: base cost + additional cost per cell beyond the first
			var base_cost = max_durability * (hammer_base_cost_percent / 100.0)
			var additional_cells = max(0, cells_that_will_be_damaged - 1)
			var additional_cost = max_durability * (hammer_per_cell_cost_percent / 100.0) * additional_cells
			var total_cost = base_cost + additional_cost
			
			# Cap at maximum cost
			var max_cost = max_durability * (hammer_max_cost_percent / 100.0)
			durability_cost = int(min(total_cost, max_cost))
		
		# Apply durability cost (unless dev mode is enabled)
		if dev_mode_unlimited_durability:
			print("DEV MODE: Durability cost ignored (", durability_cost, " would have been spent)")
		else:
			current_durability -= durability_cost
			print("Durability cost: ", durability_cost, " (", cells_that_will_be_damaged, " cells affected)")
		
		update_durability_label()
	
	# Apply damage to cells based on tool pattern
	# Apply damage to the center cell first
	hit_cell(x, y, damage_values)
	
	# Apply damage based on tool pattern
	if current_tool == ToolType.PICKAXE:
		# Pickaxe now only affects a single cell (already handled above)
		# No additional cells are affected
		pass
	else:  # HAMMER
		# Hammer now affects cells in a plus pattern
		if x > 0:
			hit_cell(x - 1, y, damage_values)  # Left
		if x < GRID_SIZE.x - 1:
			hit_cell(x + 1, y, damage_values)  # Right
		if y > 0:
			hit_cell(x, y - 1, damage_values)  # Up
		if y < GRID_SIZE.y - 1:
			hit_cell(x, y + 1, damage_values)  # Down
	
	# Check for game over
	if current_durability <= 0:
		end_game()

# Hit a cell with a tool, applying damage
func hit_cell(x: int, y: int, damage_values, multiplier: float = 1.0):
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	
	print("DEBUG: Hitting cell (" + str(x) + ", " + str(y) + ") - Layer " + str(current_layer_index) + " (" + str(LayerType.keys()[current_layer["type"]]) + ")")
	
	# Skip if this is the bottom layer and already revealed
	if current_layer_index == 2 and current_layer["revealed"]:
		return
	
	# Calculate damage based on layer type
	var damage = 0
	if current_layer["type"] == LayerType.STONE or current_layer["type"] == LayerType.DIRT:
		damage = damage_values[current_layer["type"]] * multiplier
	
	# Apply damage to current layer durability
	current_layer["durability"] -= damage
	
	# Update the cell visual
	update_cell_visual(x, y)
	
	# Check if current layer is broken through
	if current_layer["durability"] <= 0:
		current_layer["revealed"] = true
		
		# Move to next layer if there is one
		if current_layer_index < 2:
			cell_data["current_layer"] += 1
			update_cell_visual(x, y)  # Update visual to show new layer
		
		# Simple treasure reveal logic: if we just advanced to a layer that contains treasure, reveal it
		var current_layer_after_advance = cell_data["current_layer"]
		if current_layer_after_advance < 3 and cell_data["layers"][current_layer_after_advance]["type"] == LayerType.TREASURE:
			print("DEBUG: Found treasure at (" + str(x) + ", " + str(y) + ") at layer " + str(current_layer_after_advance) + " - revealing!")
			reveal_treasure(x, y)

# Update the visual appearance of a cell based on its durability
func update_cell_visual(x: int, y: int):
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	var cell_visual = cell_nodes[y][x]
	
	# Calculate opacity based on durability (0-100%)
	var opacity = 1.0
	if current_layer["type"] != LayerType.EMPTY and current_layer["type"] != LayerType.TREASURE:
		opacity = max(0.3, current_layer["durability"] / 100.0)  # Minimum opacity of 30%
	
	# Update color based on layer type
	var new_color: Color
	if current_layer["type"] == LayerType.DIRT:
		new_color = Color(0.6, 0.4, 0.2, opacity)  # Brown for dirt
	elif current_layer["type"] == LayerType.STONE:
		new_color = Color(0.5, 0.5, 0.55, opacity)  # Grey for stone
	elif current_layer["type"] == LayerType.EMPTY:
		new_color = Color(0.2, 0.2, 0.2)  # Dark grey for empty
	elif current_layer["type"] == LayerType.TREASURE:
		new_color = Color(0.8, 0.7, 0.2)  # Gold background for treasure
	
	# Update both the color property and the style box
	cell_visual.color = new_color
	
	# Update the style box to maintain border with new color
	var border_color = Color(0.3, 0.3, 0.3, 0.5)  # Semi-transparent dark border
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = new_color
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = border_color
	cell_visual.add_theme_stylebox_override("panel", style_box)

# Reveal a treasure at the specified grid position
func reveal_treasure(x: int, y: int):
	# Find the treasure in our list
	for treasure in treasures:
		if treasure["grid_pos"] == Vector2(x, y):
			# Safety check: only access visual if it still exists
			if treasure["visual"] != null and is_instance_valid(treasure["visual"]):
				# Make the treasure visible
				treasure["visual"].modulate.a = 1.0
			else:
				print("WARNING: Treasure visual was destroyed (likely by window resize)")
			
			treasure["revealed"] = true
			
			# Mark the bottom layer as revealed
			grid[y][x]["layers"][2]["revealed"] = true
			break

# Set the current mining tool
func set_current_tool(tool_type):
	current_tool = tool_type
	
	# Get references to the tool buttons with the new UI structure
	var pickaxe_button = $MainContainer/ToolContainer/PickaxeTool
	var hammer_button = $MainContainer/ToolContainer/HammerTool
	
	# Make sure buttons exist before trying to modify them
	if pickaxe_button != null and hammer_button != null:
		# Update button visuals with more prominent highlighting
		if tool_type == ToolType.PICKAXE:
			# Highlight pickaxe - bright yellow with full opacity
			pickaxe_button.modulate = Color(1.2, 1.2, 0.4, 1)
			# Give pickaxe focus to show the border (same as when clicked)
			pickaxe_button.grab_focus()
			# Dim hammer and remove focus
			hammer_button.modulate = Color(0.6, 0.6, 0.6, 0.8)
			hammer_button.release_focus()
		else:
			# Highlight hammer - bright yellow with full opacity
			hammer_button.modulate = Color(1.2, 1.2, 0.4, 1)
			# Give hammer focus to show the border (same as when clicked)
			hammer_button.grab_focus()
			# Dim pickaxe and remove focus
			pickaxe_button.modulate = Color(0.6, 0.6, 0.6, 0.8)
			pickaxe_button.release_focus()
		
		# Keep button text consistent to avoid size changes
		pickaxe_button.text = "Pickaxe"
		hammer_button.text = "Hammer"
		
		# You could add a label below the buttons to show the current tool's function instead
		# Or use a tooltip or status bar to display which tool is active
		
		print("Selected " + ("pickaxe" if tool_type == ToolType.PICKAXE else "hammer") + " tool")
	else:
		print("WARNING: Tool buttons not found in the scene!")

# Handle input events (for dev mode toggle)
func _input(event):
	if event is InputEventKey and event.pressed:
		# Toggle dev mode with F1 key
		if event.keycode == KEY_F1:
			dev_mode_unlimited_durability = !dev_mode_unlimited_durability
			update_durability_label()
			if dev_mode_unlimited_durability:
				print("DEV MODE ENABLED: Unlimited durability activated!")
			else:
				print("DEV MODE DISABLED: Normal durability restored.")

# End the game and display results
func end_game():
	game_over = true
	
	# Count revealed treasures
	var revealed_count = 0
	var total_value = 0
	
	for treasure in treasures:
		if treasure["revealed"]:
			revealed_count += 1
			
			# Get the grid position and find the treasure data in the correct layer
			var grid_pos = treasure["grid_pos"]
			var cell_data = grid[grid_pos.y][grid_pos.x]
			
			# Find which layer contains the treasure
			var treasure_data = null
			for layer in cell_data["layers"]:
				if layer["type"] == LayerType.TREASURE and layer.has("treasure"):
					treasure_data = layer["treasure"]
					break
			
			# Add value if treasure data exists and is valid
			if treasure_data != null:
				if typeof(treasure_data) == TYPE_DICTIONARY:
					# It's a dictionary (test data)
					if treasure_data.has("base_price"):
						total_value += treasure_data["base_price"]
				else:
					# It's an object (MiningItem)
					total_value += treasure_data.base_price
			else:
				print("WARNING: Could not find treasure data for revealed treasure at " + str(grid_pos))
	
	# Create results popup
	var results = Label.new()
	results.text = "Mining Complete!\n\nTreasures Found: " + str(revealed_count) + "\nTotal Value: " + str(total_value)
	results.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	var panel = Panel.new()
	panel.name = "ResultsPanel"
	panel.size = Vector2(400, 300)
	panel.position = (get_viewport().get_visible_rect().size - panel.size) / 2
	
	var vbox = VBoxContainer.new()
	vbox.size = panel.size
	vbox.add_child(results)
	
	# Add a retry button
	var retry_button = Button.new()
	retry_button.text = "Try Again"
	retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry_button.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(retry_button)
	
	panel.add_child(vbox)
	add_child(panel)

# Close the minigame and restore cursor
func close_minigame():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# You can add additional cleanup here if needed
	# For now, just hide the minigame or go back to main scene
	queue_free()  # Remove the minigame scene

# Ensure cursor is restored when leaving the minigame
func _exit_tree():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
