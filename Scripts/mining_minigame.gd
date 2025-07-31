extends Node2D

# Grid properties
const GRID_SIZE = Vector2i(13, 10)  # 13x10 grid
const CELL_SIZE = Vector2(48, 48)   # Size of each cell in pixels (adjusted for better visibility)
const SPACING = 2                   # Space between cells

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
	$ToolContainer/PickaxeTool.pressed.connect(func(): set_current_tool(ToolType.PICKAXE))
	$ToolContainer/HammerTool.pressed.connect(func(): set_current_tool(ToolType.HAMMER))
	
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

# Create visual representation of the grid
func create_grid_visuals():
	cell_nodes = []
	
	# For better visual layout, we'll scale the grid to fit the available space better
	var container_width = 650  # Adjusted based on the scene layout
	var container_height = 450
	
	# Calculate cell size that will fit the grid nicely
	var cell_width = (container_width - (GRID_SIZE.x - 1) * SPACING) / GRID_SIZE.x
	var cell_height = (container_height - (GRID_SIZE.y - 1) * SPACING) / GRID_SIZE.y
	var actual_cell_size = Vector2(cell_width, cell_height)
	
	# Set up rows of cells
	for y in range(GRID_SIZE.y):
		var row = []
		for x in range(GRID_SIZE.x):
			var cell_data = grid[y][x]
			
			# Create cell visual
			var cell = ColorRect.new()
			cell.size = actual_cell_size
			cell.position = Vector2(x * (actual_cell_size.x + SPACING), y * (actual_cell_size.y + SPACING))
			
			# Set color based on top layer
			var current_layer = cell_data["layers"][cell_data["current_layer"]]
			
			if current_layer["type"] == LayerType.DIRT:
				cell.color = Color(0.6, 0.4, 0.2)  # Brown for dirt
			elif current_layer["type"] == LayerType.STONE:
				cell.color = Color(0.5, 0.5, 0.55)  # Grey for stone
			else:
				cell.color = Color(0.2, 0.2, 0.2)  # Dark grey for empty or treasure (not visible yet)
			
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
			$GridContainer.add_child(cell)
			row.append(cell)
		
		# Store the row
		cell_nodes.append(row)
	
	# Add a target reticle for aiming
	var reticle = create_reticle()
	$GridContainer.add_child(reticle)

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
func _process(delta):
	# Update reticle position if it exists
	var reticle = $GridContainer.get_node_or_null("Reticle")
	if reticle:
		var mouse_pos = get_local_mouse_position() - $GridContainer.position
		reticle.position = mouse_pos
	
	# Update durability label
func update_durability_label():
	var label = $DurabilityLabel
	if label != null:
		label.text = "Durability: " + str(current_durability)

# Start a new game
func start_game():
	# Reset game state
	game_over = false
	current_durability = max_durability
	
	# Clear any existing grid
	for child in $GridContainer.get_children():
		child.queue_free()
	
	# Initialize new grid and visuals
	init_grid()
	create_grid_visuals()
	place_treasures(8)  # Placing 8 treasures for the larger grid
	
	# Update durability display
	update_durability_label()
	
	# Show tutorial text if desired
	print("Mining game started! Break through stone (2 hits) to reveal dirt (1 hit), and dirt to find treasures!")
	print("Pickaxe: Single cell | Hammer: Plus shape (+) | Grid: 13x10 | Treasures: 8")

# Place treasures in the grid using weighted random selection
func place_treasures(count: int):
	treasures = []
	
	# Mine ID that can be set when starting the minigame (default: mine 1)
	var mine_id = 1
	
	# Track rare gem placement to ensure some variety
	var rare_gems_placed = 0
	var max_rare_gems = max(1, count / 3)  # At least 1 rare gem, up to 1/3 of total
	
	print("Placing " + str(count) + " treasures in mine #" + str(mine_id))
	
	for i in range(count):
		# Pick a random position in the grid
		var x = randi() % int(GRID_SIZE.x)
		var y = randi() % int(GRID_SIZE.y)
		
		# Check if the bottom layer already has a treasure
		if grid[y][x]["layers"][2]["treasure"] != null:
			# Try again
			i -= 1
			continue
		
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
		
		# Store treasure data in the bottom layer
		grid[y][x]["layers"][2]["type"] = LayerType.TREASURE
		grid[y][x]["layers"][2]["treasure"] = treasure
		
		# Create a visual representation for the treasure (hidden initially)
		var treasure_visual = create_treasure_visual(treasure, x, y)
		treasure_visual.modulate.a = 0  # Start invisible
		$GridContainer.add_child(treasure_visual)
		treasures.append({
			"visual": treasure_visual,
			"grid_pos": Vector2(x, y),
			"revealed": false
		})

# Helper function to get treasure name safely whether it's a dictionary or object
func get_treasure_name(treasure_data):
	if typeof(treasure_data) == TYPE_DICTIONARY:
		return treasure_data["name"] if treasure_data.has("name") else "???"
	else:
		return treasure_data.name

# Create a visual for a treasure with color based on value
func create_treasure_visual(treasure_data, grid_x, grid_y):
	# Use the same calculation for cell size that we use in create_grid_visuals
	var container_width = 650
	var container_height = 450
	var cell_width = (container_width - (GRID_SIZE.x - 1) * SPACING) / GRID_SIZE.x
	var cell_height = (container_height - (GRID_SIZE.y - 1) * SPACING) / GRID_SIZE.y
	var actual_cell_size = Vector2(cell_width, cell_height)
	
	var visual = ColorRect.new()
	visual.size = actual_cell_size * 0.8  # Slightly smaller than the cell
	visual.position = Vector2(
		grid_x * (actual_cell_size.x + SPACING) + actual_cell_size.x * 0.1,
		grid_y * (actual_cell_size.y + SPACING) + actual_cell_size.y * 0.1
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
	
	# Label with treasure name
	var label = Label.new()
	label.text = get_treasure_name(treasure_data)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = visual.size
	
	visual.add_child(label)
	return visual

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
	
	# Check if any of the cells that will be affected are still unbroken
	var will_affect_unbroken_cell = false
	
	# Check center cell
	if not (current_layer_index == 2 and current_layer["revealed"]):
		will_affect_unbroken_cell = true
	
	# For hammer, check surrounding cells too
	if current_tool == ToolType.HAMMER:
		# Check left cell
		if x > 0 and not is_cell_fully_revealed(x - 1, y):
			will_affect_unbroken_cell = true
		# Check right cell
		if x < GRID_SIZE.x - 1 and not is_cell_fully_revealed(x + 1, y):
			will_affect_unbroken_cell = true
		# Check up cell
		if y > 0 and not is_cell_fully_revealed(x, y - 1):
			will_affect_unbroken_cell = true
		# Check down cell
		if y < GRID_SIZE.y - 1 and not is_cell_fully_revealed(x, y + 1):
			will_affect_unbroken_cell = true
	
	# Only reduce durability if we're actually breaking something
	if will_affect_unbroken_cell:
		if current_tool == ToolType.HAMMER:
			current_durability -= 2
			update_durability_label()
		else:
			current_durability -= 1
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

# Helper function to check if a cell is fully revealed (at bottom layer and revealed)
func is_cell_fully_revealed(x: int, y: int) -> bool:
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	
	# A cell is fully revealed if it's at the bottom layer (2) and that layer is revealed
	return current_layer_index == 2 and current_layer["revealed"]

# Hit a cell with a tool, applying damage
func hit_cell(x: int, y: int, damage_values, multiplier: float = 1.0):
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	
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
		
		# Check for treasure in bottom layer
		if current_layer_index == 1 and cell_data["layers"][2]["type"] == LayerType.TREASURE:
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
	if current_layer["type"] == LayerType.DIRT:
		cell_visual.color = Color(0.6, 0.4, 0.2, opacity)  # Brown for dirt
	elif current_layer["type"] == LayerType.STONE:
		cell_visual.color = Color(0.5, 0.5, 0.55, opacity)  # Grey for stone
	elif current_layer["type"] == LayerType.EMPTY:
		cell_visual.color = Color(0.2, 0.2, 0.2)  # Dark grey for empty
	elif current_layer["type"] == LayerType.TREASURE:
		cell_visual.color = Color(0.8, 0.7, 0.2)  # Gold background for treasure

# Reveal a treasure at the specified grid position
func reveal_treasure(x: int, y: int):
	# Find the treasure in our list
	for treasure in treasures:
		if treasure["grid_pos"] == Vector2(x, y):
			# Make the treasure visible
			treasure["visual"].modulate.a = 1.0
			treasure["revealed"] = true
			
			# Mark the bottom layer as revealed
			grid[y][x]["layers"][2]["revealed"] = true
			break

# Set the current mining tool
func set_current_tool(tool_type):
	current_tool = tool_type
	
	# Update button visuals
	$ToolContainer/PickaxeTool.modulate = Color(1, 1, 1, 1) if tool_type == ToolType.PICKAXE else Color(0.7, 0.7, 0.7, 1)
	$ToolContainer/HammerTool.modulate = Color(1, 1, 1, 1) if tool_type == ToolType.HAMMER else Color(0.7, 0.7, 0.7, 1)
	
	# Update tool description directly on the buttons
	if tool_type == ToolType.PICKAXE:
		$ToolContainer/PickaxeTool.text = "Pickaxe\n(single cell)"
		$ToolContainer/HammerTool.text = "Hammer"
	else:  # HAMMER
		$ToolContainer/PickaxeTool.text = "Pickaxe"
		$ToolContainer/HammerTool.text = "Hammer\n(+ shape)"

# End the game and display results
func end_game():
	game_over = true
	
	# Count revealed treasures
	var revealed_count = 0
	var total_value = 0
	
	for treasure in treasures:
		if treasure["revealed"]:
			revealed_count += 1
			
			# Get the grid position
			var grid_pos = treasure["grid_pos"]
			var treasure_data = grid[grid_pos.y][grid_pos.x]["layers"][2]["treasure"]
			
			# Add value if available - handle both dictionary and object formats
			if typeof(treasure_data) == TYPE_DICTIONARY:
				# It's a dictionary (test data)
				if treasure_data.has("base_price"):
					total_value += treasure_data["base_price"]
			else:
				# It's an object (MiningItem)
				total_value += treasure_data.base_price
	
	# Create results popup
	var results = Label.new()
	results.text = "Mining Complete!\n\nTreasures Found: " + str(revealed_count) + "\nTotal Value: " + str(total_value)
	results.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	var panel = Panel.new()
	panel.name = "ResultsPanel"
	panel.size = Vector2(400, 300)
	panel.position = (get_viewport_rect().size - panel.size) / 2
	
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
