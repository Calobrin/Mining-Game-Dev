extends Node2D

# Grid settings
const GRID_SIZE = Vector2(10, 10)  # 10x10 grid
const CELL_SIZE = Vector2(80, 50)   # Size of each cell in pixels
const SPACING = 2                  # Space between cells

# Terrain types
enum TerrainType { DIRT, STONE }

# Tool types
enum ToolType { PICKAXE, HAMMER }
var current_tool = ToolType.PICKAXE

# Game state
var max_durability = 100
var current_durability = 100
var game_over = false
var grid = []  # Stores the terrain data
var treasures = []  # Stores the treasure locations and types

# Mining properties - increased damage values for faster digging
var pickaxe_damage = {
	TerrainType.DIRT: 25,  # Was 10
	TerrainType.STONE: 15   # Was 5
}

var hammer_damage = {
	TerrainType.DIRT: 35,   # Was 15
	TerrainType.STONE: 20   # Was 8
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
		
	# Initialize the grid
	init_grid()
	
	# Create visual grid cells
	create_grid_visuals()
	
	# Place treasures
	place_treasures(5)  # Start with 5 treasures
	
	# Connect tool buttons
	$ToolContainer/PickaxeTool.pressed.connect(func(): set_current_tool(ToolType.PICKAXE))
	$ToolContainer/HammerTool.pressed.connect(func(): set_current_tool(ToolType.HAMMER))

# Initialize the grid with terrain types
func init_grid():
	grid = []
	for y in range(GRID_SIZE.y):
		var row = []
		for x in range(GRID_SIZE.x):
			# 70% chance of dirt, 30% chance of stone
			var terrain_type = TerrainType.DIRT if randf() < 0.7 else TerrainType.STONE
			# Each cell is a dictionary with properties
			row.append({
				"type": terrain_type,
				"durability": 100,  # Each cell starts with full durability
				"revealed": false,  # Whether the cell has been fully revealed
				"treasure": null    # Will store treasure data if present
			})
		grid.append(row)

# Create visual representation of the grid
func create_grid_visuals():
	cell_nodes = []
	for y in range(GRID_SIZE.y):
		var row = []
		for x in range(GRID_SIZE.x):
			# Create a cell visual
			var cell = ColorRect.new()
			cell.size = CELL_SIZE
			cell.position = Vector2(
				x * (CELL_SIZE.x + SPACING), 
				y * (CELL_SIZE.y + SPACING)
			)
			
			# Set color based on terrain type
			if grid[y][x]["type"] == TerrainType.DIRT:
				cell.color = Color(0.6, 0.4, 0.2)  # Brown for dirt
			else:
				cell.color = Color(0.5, 0.5, 0.55)  # Grey for stone
			
			# Make cell clickable
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			var button = Button.new()
			button.flat = true
			button.modulate = Color(1, 1, 1, 0)  # Invisible button
			button.size = CELL_SIZE
			
			# Store coordinates in the button for reference
			button.set_meta("grid_x", x)
			button.set_meta("grid_y", y)
			
			# Connect click event
			button.pressed.connect(func(): on_cell_clicked(x, y))
			
			cell.add_child(button)
			$GridContainer.add_child(cell)
			row.append(cell)
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
	$DurabilityLabel.text = "Durability: " + str(current_durability)

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
		
		# Check if the position is already occupied
		if grid[y][x]["treasure"] != null:
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
		
		# Store treasure data
		grid[y][x]["treasure"] = treasure
		
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
	var visual = ColorRect.new()
	visual.size = CELL_SIZE * 0.8  # Slightly smaller than the cell
	visual.position = Vector2(
		grid_x * (CELL_SIZE.x + SPACING) + CELL_SIZE.x * 0.1,
		grid_y * (CELL_SIZE.y + SPACING) + CELL_SIZE.y * 0.1
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
		
	# Get the current tool damage values
	var damage_values
	if current_tool == ToolType.PICKAXE:
		damage_values = pickaxe_damage
	else:  # HAMMER
		damage_values = hammer_damage
	
	# Apply tool effect based on shape
	if current_tool == ToolType.PICKAXE:
		# Pickaxe affects cells in a + pattern
		var cells_to_hit = [
			Vector2i(x, y),      # Center
			Vector2i(x+1, y),    # Right
			Vector2i(x-1, y),    # Left
			Vector2i(x, y+1),    # Down
			Vector2i(x, y-1)     # Up
		]
		
		for cell_pos in cells_to_hit:
			# Check if within grid bounds
			if cell_pos.x >= 0 and cell_pos.x < GRID_SIZE.x and cell_pos.y >= 0 and cell_pos.y < GRID_SIZE.y:
				hit_cell(cell_pos.x, cell_pos.y, damage_values)
	
	else:  # HAMMER
		# Hammer affects cells in a 3x3 square pattern with varying damage
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx = x + dx
				var ny = y + dy
				
				# Check if within grid bounds
				if nx >= 0 and nx < GRID_SIZE.x and ny >= 0 and ny < GRID_SIZE.y:
					# Center gets full damage, surrounding cells get half damage
					var damage_multiplier = 1.0 if (dx == 0 and dy == 0) else 0.5
					hit_cell(nx, ny, damage_values, damage_multiplier)
	
	# Reduce overall durability - lowered from 5 to 3 for better balance
	current_durability -= 3
	if current_durability <= 0:
		end_game()

# Hit a cell with a tool, applying damage
func hit_cell(x: int, y: int, damage_values, multiplier: float = 1.0):
	var cell = grid[y][x]
	
	# Skip if already fully revealed
	if cell["revealed"]:
		return
		
	# Calculate damage based on terrain type
	var damage = damage_values[cell["type"]] * multiplier
	
	# Apply damage to cell durability
	cell["durability"] -= damage
	
	# Update the cell visual
	update_cell_visual(x, y)
	
	# Check if cell is fully revealed
	if cell["durability"] <= 0:
		cell["revealed"] = true
		
		# Check for treasure
		if cell["treasure"]:
			reveal_treasure(x, y)

# Update the visual appearance of a cell based on its durability
func update_cell_visual(x: int, y: int):
	var cell = grid[y][x]
	var cell_visual = cell_nodes[y][x]
	
	# Calculate opacity based on durability (0-100%)
	var opacity = cell["durability"] / 100.0
	
	# Update color with opacity
	if cell["type"] == TerrainType.DIRT:
		cell_visual.color = Color(0.6, 0.4, 0.2, opacity)
	else:
		cell_visual.color = Color(0.5, 0.5, 0.55, opacity)

# Reveal a treasure at the specified grid position
func reveal_treasure(x: int, y: int):
	# Find the treasure in our list
	for treasure in treasures:
		if treasure["grid_pos"] == Vector2(x, y):
			# Make the treasure visible
			treasure["visual"].modulate.a = 1.0
			treasure["revealed"] = true
			break

# Set the current mining tool
func set_current_tool(tool_type):
	current_tool = tool_type
	
	# Update button visuals
	$ToolContainer/PickaxeTool.modulate = Color(1, 1, 1, 1) if tool_type == ToolType.PICKAXE else Color(0.7, 0.7, 0.7, 1)
	$ToolContainer/HammerTool.modulate = Color(1, 1, 1, 1) if tool_type == ToolType.HAMMER else Color(0.7, 0.7, 0.7, 1)

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
			var treasure_data = grid[grid_pos.y][grid_pos.x]["treasure"]
			
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
