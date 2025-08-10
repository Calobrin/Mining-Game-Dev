extends CanvasLayer

# ============================================================================
# CONSTANTS - Centralized values for easy tweaking
# ============================================================================

# Visual constants
const TREASURE_SIZE_MULTIPLIER = 0.8  # Treasure visual size relative to cell
const CELL_OPACITY_MIN = 0.3  # Minimum opacity for damaged cells
const BORDER_OPACITY = 0.5  # Border transparency

# Color constants
const COLOR_DIRT = Color(0.6, 0.4, 0.2)
const COLOR_STONE = Color(0.48, 0.48, 0.48)  # Realistic neutral stone gray
const COLOR_EMPTY = Color(0.2, 0.2, 0.2)
const COLOR_TREASURE_BG = Color(0.8, 0.7, 0.2)
const COLOR_TREASURE_ROCK = Color(0.28, 0.28, 0.28)   # Darker than stone
const COLOR_TREASURE_METAL = Color(0.95, 0.55, 0.20)  # Copper-like orange
const COLOR_TREASURE_GEM = Color(0.60, 0.85, 1.00)    # Light blue
const COLOR_BORDER = Color(0.3, 0.3, 0.3)

# Grid properties
const GRID_SIZE = Vector2i(17, 10)  # 17x10 grid				# No space between cells - continuous terrain

# Use fixed or dynamic cell size
@export var use_fixed_cell_size: bool = true		# Set to false for dynamic sizing based on container
@export var fixed_cell_size: Vector2 = Vector2(50, 50)	# Size of each cell in pixels when using fixed sizing

# Overlay dimensions (automatically calculated based on screen size)
@export_range(0.5, 0.9, 0.05) var overlay_width_percentage: float = 0.85  # Percentage of screen width
@export_range(0.5, 0.9, 0.05) var overlay_height_percentage: float = 0.8  # Percentage of screen height
@export var min_cell_size: Vector2 = Vector2(30, 30)  # Minimum cell size to ensure visibility
@export var grid_backdrop_color: Color = Color(0.2, 0.2, 0.2)  # Color behind the grid (for empty/crystal margins)

# Visual toggles
@export var show_cell_borders: bool = false  # Toggle grid cell borders on/off

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
@export_range(0.5, 3.0, 0.1) var pickaxe_base_cost: float = 1.0  # 1% per cell
@export_range(1.0, 5.0, 0.1) var hammer_base_cost_percent: float = 2.0  # 2% base cost for hammer
@export_range(0.1, 1.0, 0.1) var hammer_per_cell_cost_percent: float = 0.5  # 0.5% per additional cell
@export_range(3.0, 8.0, 0.1) var hammer_max_cost_percent: float = 5.0  # 5% maximum cost

# Mining properties - dirt and stone have the same health now (1 hit at 100 damage)
var pickaxe_damage = {
	LayerType.STONE: 100,
	LayerType.DIRT: 100
}

var hammer_damage = {
	LayerType.STONE: 100,
	LayerType.DIRT: 100
}

# Visual elements
var cell_nodes = []  # Stores references to the cell UI nodes

# Dirt texture (assign in Inspector to use a tiled texture for dirt cells)
@export var dirt_texture: Texture2D

# Dirt spritesheet settings (4 frames: 0=plain, 1=damaged, 2=rubble, 3=rubble+damaged)
const DIRT_SHEET_HFRAMES: int = 4
const DIRT_SHEET_VFRAMES: int = 1
const DIRT_TILE_SIZE: Vector2i = Vector2i(16, 16)

# Stone texture (assign in Inspector to use a tiled texture for stone cells)
@export var stone_texture: Texture2D

# Stone spritesheet settings (2 frames: 0=solid, 1=cracked)
const STONE_SHEET_HFRAMES: int = 2
const STONE_SHEET_VFRAMES: int = 1
const STONE_TILE_SIZE: Vector2i = Vector2i(16, 16)

# Called when the node enters the scene tree for the first time
func _ready():
	randomize()  # Initialize random number generator
	
	# Connect to window resize signals to handle resolution changes
	get_viewport().size_changed.connect(on_viewport_resized)
	
	# Ensure UI overlays (e.g., game over panel) render above the grid
	var ui_container := $MainContainer/"UI Elements"
	if ui_container:
		ui_container.z_index = 1000
		ui_container.z_as_relative = false

	# Keep grid container firmly in the background of this CanvasLayer
	var gridc: Control = $MainContainer/MainGameArea/GridContainer
	if gridc:
		gridc.z_as_relative = true
		gridc.z_index = 0

	# Optional: ensure cursor reticle always renders above grid
	var cursor_reticle := get_node_or_null("ReticleLayer/Reticle")
	if cursor_reticle:
		cursor_reticle.z_as_relative = false
		cursor_reticle.z_index = 1005
		if cursor_reticle is Control:
			cursor_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
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

# Initialize the grid with layered structure using cluster-based stone generation
func init_grid():
	grid = []
	
	# First, create the base grid structure (all dirt initially)
	for y in range(GRID_SIZE.y):
		var row = []
		for x in range(GRID_SIZE.x):
			# Each cell starts as dirt-only configuration
			row.append({
				"layers": [
					{
						"type": LayerType.DIRT,
						"durability": 100,
						"revealed": false
					},
					{
						"type": LayerType.EMPTY,
						"durability": 100,
						"revealed": false
					},
					{
						"type": LayerType.EMPTY,
						"durability": 0,
						"revealed": false,
						"treasure": null
					}
				],
				"current_layer": 0,
				# Visual/state helpers
				"had_stone": false,
				"stone_broken": false
			})
		grid.append(row)
	
	# Now generate stone clusters using geological algorithms
	generate_stone_clusters()

# Generate realistic stone formations using multiple algorithms
func generate_stone_clusters():
	# Use the new modular geological generator
	GeologicalGenerator.generate_formations(grid, GRID_SIZE, place_stone_at)



# Helper function to place stone at a specific grid position
func place_stone_at(x: int, y: int):
	# Convert dirt-only cell to stone+dirt cell
	grid[y][x]["layers"][0]["type"] = LayerType.STONE  # Top layer becomes stone
	grid[y][x]["layers"][1]["type"] = LayerType.DIRT   # Middle layer becomes dirt
	# Bottom layer stays EMPTY (for potential treasures)
	# Mark that this cell originally had stone
	grid[y][x]["had_stone"] = true

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
			# Clip child drawing to the cell's rect so textures never spill outside
			cell.clip_contents = true
			# Position cell with centering offset
			cell.position = calculate_cell_position(x, y)
			
			# Set color based on top layer
			var current_layer = cell_data["layers"][cell_data["current_layer"]]
			
			if current_layer["type"] == LayerType.DIRT:
				cell.color = COLOR_DIRT
			elif current_layer["type"] == LayerType.STONE:
				cell.color = COLOR_STONE
			else:
				# EMPTY cells are fully transparent so the unified backdrop shows through
				cell.color = Color(0, 0, 0, 0)
			
			# Optional border for visual distinction
			if show_cell_borders:
				cell.add_theme_stylebox_override("panel", create_cell_style_box(cell.color))

			# Optional dirt texture child (spritesheet) - inset by 1px to keep border visible
			if dirt_texture != null:
				var dirt_tr := TextureRect.new()
				dirt_tr.name = "DirtTexture"
				dirt_tr.stretch_mode = TextureRect.STRETCH_SCALE
				# Enforce crisp pixels
				dirt_tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				# Inset by 1px only if borders are enabled
				var inset: int = 1 if show_cell_borders else 0
				dirt_tr.position = Vector2(inset, inset)
				dirt_tr.size = actual_cell_size - Vector2(inset * 2, inset * 2)
				dirt_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				# Use AtlasTexture to select a region from the spritesheet
				var atlas := AtlasTexture.new()
				atlas.atlas = dirt_texture
				# Default to frame 0 (plain)
				atlas.region = Rect2(0, 0, DIRT_TILE_SIZE.x, DIRT_TILE_SIZE.y)
				dirt_tr.texture = atlas
				cell.add_child(dirt_tr)
				# Initialize visibility based on current layer
				var is_dirt: bool = current_layer["type"] == LayerType.DIRT
				if is_dirt:
					dirt_tr.visible = true
					# Select frame based on state (0=plain,1=damaged,2=rubble,3=rubble+damaged)
					var frame_idx = 0
					var had_stone = grid[y][x]["had_stone"]
					var rubble = had_stone and grid[y][x]["stone_broken"]
					var damaged = current_layer["durability"] < 100
					if rubble and damaged:
						frame_idx = 3
					elif rubble:
						frame_idx = 2
					elif damaged:
						frame_idx = 1
					(dirt_tr.texture as AtlasTexture).region = Rect2(frame_idx * DIRT_TILE_SIZE.x, 0, DIRT_TILE_SIZE.x, DIRT_TILE_SIZE.y)
					# Make parent transparent so texture shows
					cell.color = Color(0, 0, 0, 0)
				else:
					dirt_tr.visible = false

			# Optional stone texture child (spritesheet) - inset by 1px to keep border visible
			if stone_texture != null:
				var stone_tr := TextureRect.new()
				stone_tr.name = "StoneTexture"
				stone_tr.stretch_mode = TextureRect.STRETCH_SCALE
				# Enforce crisp pixels
				stone_tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				# Use same inset as dirt for consistent borders
				var inset2: int = 1 if show_cell_borders else 0
				stone_tr.position = Vector2(inset2, inset2)
				stone_tr.size = actual_cell_size - Vector2(inset2 * 2, inset2 * 2)
				stone_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				# Use AtlasTexture to select a region from the spritesheet
				var satlas := AtlasTexture.new()
				satlas.atlas = stone_texture
				# Default to frame 0 (solid)
				satlas.region = Rect2(0, 0, STONE_TILE_SIZE.x, STONE_TILE_SIZE.y)
				stone_tr.texture = satlas
				cell.add_child(stone_tr)
				# Initialize visibility based on current layer
				var is_stone: bool = current_layer["type"] == LayerType.STONE
				if is_stone:
					stone_tr.visible = true
					# Select frame based on state (0=solid,1=cracked)
					var s_frame_idx = 0
					var s_damaged = current_layer["durability"] < 100
					if s_damaged:
						s_frame_idx = 1
					(stone_tr.texture as AtlasTexture).region = Rect2(s_frame_idx * STONE_TILE_SIZE.x, 0, STONE_TILE_SIZE.x, STONE_TILE_SIZE.y)
					# Ensure parent is transparent so texture shows
					cell.color = Color(0, 0, 0, 0)
				else:
					stone_tr.visible = false
			
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
	# Place reticle on its own CanvasLayer to guarantee it draws above the grid
	var reticle_layer := get_node_or_null("ReticleLayer")
	if reticle_layer == null:
		reticle_layer = CanvasLayer.new()
		reticle_layer.name = "ReticleLayer"
		# Ensure reticle draws above results overlay (which uses layer 10)
		reticle_layer.layer = 20
		add_child(reticle_layer)
	reticle_layer.add_child(reticle)

# Create an aiming reticle that follows the mouse
func create_reticle():
	var reticle = Control.new()
	reticle.name = "Reticle"
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.z_as_relative = false
	reticle.z_index = 1005
	
	# Create a cross shape using lines
	var reticle_lines = Line2D.new()
	reticle_lines.z_as_relative = false
	reticle_lines.z_index = 1005
	reticle_lines.width = 2
	reticle_lines.default_color = Color(1, 0, 0, 0.8)  # Red
	
	# Cross shape points (horizontal line)
	reticle_lines.add_point(Vector2(-10, 0))
	reticle_lines.add_point(Vector2(10, 0))
	
	# Add a second line for vertical part
	var vertical_line = Line2D.new()
	vertical_line.z_as_relative = false
	vertical_line.z_index = 1005
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
	var reticle = get_node_or_null("ReticleLayer/Reticle")
	if reticle:
		# Reticle is on a CanvasLayer (screen space). Convert GridContainer-local mouse to SCREEN coordinates
		# using the canvas-aware global transform so scaling/offsets are handled.
		var grid_container = $MainContainer/MainGameArea/GridContainer
		var local_mouse = grid_container.get_local_mouse_position()
		var screen_pos: Vector2 = grid_container.get_global_transform_with_canvas() * local_mouse
		reticle.position = screen_pos

# Update durability label
func update_durability_label():
	var label = $"MainContainer/UI Elements/DurabilityLabel"
	if label != null:
		# Ensure displayed durability is never negative
		var display_durability = max(0, current_durability)
		label.text = "Durability: " + str(display_durability)

# Handle viewport resizing
func on_viewport_resized():
	# Only adjust the backdrop size/position to match the grid; do not rebuild the grid
	var gridc := $MainContainer/MainGameArea/GridContainer
	if gridc:
		var backdrop: ColorRect = gridc.get_node_or_null("GridBackdrop")
		if backdrop:
			var cell_sz := get_actual_cell_size()
			var offset := get_grid_centering_offset()
			backdrop.position = offset
			backdrop.size = Vector2(GRID_SIZE.x * cell_sz.x, GRID_SIZE.y * cell_sz.y)
			backdrop.color = grid_backdrop_color
			backdrop.z_as_relative = true
			backdrop.z_index = -100
			backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Optional: debug
	# print("Viewport resized - backdrop updated")

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
	# Add a backdrop behind all cells so transparent crystal margins match empty tiles
	var gridc_back := $MainContainer/MainGameArea/GridContainer
	if gridc_back:
		var backdrop := gridc_back.get_node_or_null("GridBackdrop")
		if grid_backdrop_color.a <= 0.001:
			# Transparent backdrop requested: remove existing backdrop if present
			if backdrop:
				backdrop.queue_free()
		else:
			# Opaque/semi-opaque backdrop requested: ensure it exists and is sized
			if backdrop == null:
				var cr := ColorRect.new()
				cr.name = "GridBackdrop"
				gridc_back.add_child(cr)
				# Ensure it renders behind all cell children
				gridc_back.move_child(cr, 0)
			# Size and position the backdrop to the exact grid bounds
			var cell_sz := get_actual_cell_size()
			var offset := get_grid_centering_offset()
			var bd: ColorRect = gridc_back.get_node_or_null("GridBackdrop")
			if bd:
				bd.position = offset
				bd.size = Vector2(GRID_SIZE.x * cell_sz.x, GRID_SIZE.y * cell_sz.y)
				bd.color = grid_backdrop_color
				bd.z_as_relative = true
				bd.z_index = -100
				bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Generate random number of treasures within the specified range
	var treasure_count = randi_range(min_treasures, max_treasures)
	place_treasures(treasure_count)
	
	# Update durability display
	update_durability_label()
	
	# Initialize tool selection (highlight default pickaxe)
	set_current_tool(current_tool)
	
	# Show tutorial text if desired
	print("Mining game started! Break through stone and dirt to find treasures!")
	print("Pickaxe: Single cell | Hammer: Plus shape (+) | Grid: " + str(GRID_SIZE.x) + " x " + str(GRID_SIZE.y))

	# If a reticle already exists (e.g., after a retry without full process restart), ensure it is visible
	var reticle_existing := get_node_or_null("ReticleLayer/Reticle")
	if reticle_existing:
		reticle_existing.visible = true

# Place treasures using the new TreasureGenerator system
func place_treasures(count: int):
	# Mine ID that can be set when starting the minigame (default: mine 1)
	var mine_id = 1
	
	# Get database reference to pass to TreasureGenerator
	var mining_database = get_node_or_null("/root/MiningItemDatabase")
	
	# Use TreasureGenerator to place multi-cell treasures
	var placed_treasures = TreasureGenerator.place_treasures(grid, GRID_SIZE, count, mine_id, mining_database)
	
	# Convert PlacedTreasure objects to the format expected by the rest of the minigame
	treasures = []
	for placed_treasure in placed_treasures:
		# Store treasure data - no separate visual needed since grid cells show treasures
		treasures.append({
			"visual": null,  # Grid cells handle treasure display
			"placed_treasure": placed_treasure,  # Reference to the full PlacedTreasure object
			"revealed": false
		})
	
	# Confirm treasure placement
	print("TREASURE PLACEMENT COMPLETE: " + str(treasures.size()) + " treasures placed successfully!")
	print("Grid size: " + str(GRID_SIZE.x) + "x" + str(GRID_SIZE.y) + " = " + str(GRID_SIZE.x * GRID_SIZE.y) + " total cells")

# Helper function to get treasure name safely whether it's a dictionary or object
func get_treasure_name(treasure_data):
	return get_treasure_name_safe(treasure_data)

# Helper function to check if a cell is fully revealed (at bottom layer and revealed)
func is_cell_fully_revealed(x: int, y: int) -> bool:
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	
	# A cell is fully revealed if it's at the bottom layer (2) and that layer is revealed
	return current_layer_index == 2 and current_layer["revealed"]

# Helper: determine if a cell is fully excavated (all damageable material removed)
# Rules:
# - Dirt-only cells: excavated when layer 0 (DIRT) is revealed
# - Stone + Dirt cells: excavated when layer 0 (STONE) and layer 1 (DIRT) are both revealed
func is_cell_excavated(x: int, y: int) -> bool:
	var layers = grid[y][x]["layers"]
	var has_stone = layers[0]["type"] == LayerType.STONE
	if has_stone:
		return layers[0]["revealed"] and layers[1]["revealed"]
	else:
		return layers[0]["revealed"]

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
	
	# NOTE: Do NOT early-return on fully revealed bottom cells.
	# We allow clicking empty cells so adjacent damageable tiles can still be hit.
		
	# Get the current tool damage values
	var damage_values
	if current_tool == ToolType.PICKAXE:
		damage_values = pickaxe_damage
	else:  # HAMMER
		damage_values = hammer_damage
	
	# Calculate durability cost based on actual cells that will be affected
	# We compute a weighted sum using the same multipliers as damage application.
	var weighted_sum: float = 0.0
	# Pattern per tool
	if current_tool == ToolType.PICKAXE:
		# Plus pattern: center 1.0, sides 0.5 (only add if damageable)
		if can_cell_be_damaged(x, y):
			weighted_sum += 1.0
		if can_cell_be_damaged(x - 1, y):
			weighted_sum += 0.5
		if can_cell_be_damaged(x + 1, y):
			weighted_sum += 0.5
		if can_cell_be_damaged(x, y - 1):
			weighted_sum += 0.5
		if can_cell_be_damaged(x, y + 1):
			weighted_sum += 0.5
	else:
		# HAMMER: 3x3 pattern, center and plus at 1.0, corners at 0.5
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px = x + dx
				var py = y + dy
				var mult = 1.0 if (dx == 0 or dy == 0) else 0.5  # corners have both dx and dy non-zero
				if can_cell_be_damaged(px, py):
					weighted_sum += mult
	
	# Calculate dynamic durability cost
	var durability_cost = 0
	if weighted_sum > 0.0:
		if current_tool == ToolType.PICKAXE:
			# Pickaxe: cost scales by weighted cells
			# Use ceiling and enforce minimum 1 when any work is done to avoid 0-cost on small weights (e.g., 0.5)
			durability_cost = max(1, ceili(max_durability * (pickaxe_base_cost / 100.0) * weighted_sum))
		else:  # HAMMER
			# Hammer: base cost + weighted additional work (excluding center cost baked into base)
			# Estimate additional weight as (weighted_sum - 1.0), but not less than 0
			var additional_weight = maxf(0.0, weighted_sum - 1.0)
			var base_cost = max_durability * (hammer_base_cost_percent / 100.0)
			var additional_cost = max_durability * (hammer_per_cell_cost_percent / 100.0) * additional_weight
			var total_cost = base_cost + additional_cost
			# Cap at maximum cost
			var max_cost = max_durability * (hammer_max_cost_percent / 100.0)
			durability_cost = ceili(min(total_cost, max_cost))
		
		# Apply durability cost (unless dev mode is enabled)
		if dev_mode_unlimited_durability:
			print("DEV MODE: Durability cost ignored (", durability_cost, " would have been spent)")
		else:
			current_durability -= durability_cost
			# Ensure durability never goes below 0
			current_durability = max(0, current_durability)
			print("Durability cost: ", durability_cost, " (weighted work: ", str(roundf(weighted_sum * 100.0) / 100.0), ")")
		
		update_durability_label()
	
	# If nothing around is damageable, stop here to avoid wasted work
	if weighted_sum <= 0.0:
		return

	# Apply damage to cells based on tool pattern
	# Apply damage to the center cell first
	hit_cell(x, y, damage_values)
	
	# Apply damage based on tool pattern
	if current_tool == ToolType.PICKAXE:
		# Plus pattern: center 1.0, sides 0.5
		if x > 0:
			hit_cell(x - 1, y, damage_values, 0.5)
		if x < GRID_SIZE.x - 1:
			hit_cell(x + 1, y, damage_values, 0.5)
		if y > 0:
			hit_cell(x, y - 1, damage_values, 0.5)
		if y < GRID_SIZE.y - 1:
			hit_cell(x, y + 1, damage_values, 0.5)
	else:  # HAMMER
		# 3x3 pattern: center and plus at 1.0, corners at 0.5
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px = x + dx
				var py = y + dy
				# Bounds check to avoid invalid indices at edges
				if px < 0 or px >= GRID_SIZE.x or py < 0 or py >= GRID_SIZE.y:
					continue
				var mult = 1.0 if (dx == 0 or dy == 0) else 0.5
				if not (dx == 0 and dy == 0):
					hit_cell(px, py, damage_values, mult)
	
	# Check for game over
	if current_durability <= 0:
		end_game()

# Determine if a placed treasure is fully claimed (all its cells revealed at treasure layer)
func is_treasure_fully_claimed(placed_treasure) -> bool:
	if placed_treasure == null:
		return false
	for gp in placed_treasure.grid_positions:
		var x = gp.x
		var y = gp.y
		# Bounds safety
		if x < 0 or x >= GRID_SIZE.x or y < 0 or y >= GRID_SIZE.y:
			return false
		var cell_data = grid[y][x]
		var has_stone = cell_data["layers"][0]["type"] == LayerType.STONE
		var treasure_layer = 2 if has_stone else 1
		if not cell_data["layers"][treasure_layer]["revealed"]:
			return false
	return true

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
		
		# If we just broke stone, mark rubble state for the dirt below
		if current_layer["type"] == LayerType.STONE:
			cell_data["stone_broken"] = true
		
		# Move to next layer if there is one
		if current_layer_index < 2:
			cell_data["current_layer"] += 1
			update_cell_visual(x, y)  # Update visual to show new layer
		
		# Simple treasure reveal logic: if we just advanced to a layer that contains treasure, reveal it
		var current_layer_after_advance = cell_data["current_layer"]
		if current_layer_after_advance < 3 and cell_data["layers"][current_layer_after_advance]["type"] == LayerType.TREASURE:
			print("DEBUG: Found treasure at (" + str(x) + ", " + str(y) + ") at layer " + str(current_layer_after_advance) + " - revealing!")
			reveal_treasure(x, y)
	
	# Check if all cells are fully excavated (reached bottom layer)
	if not game_over:
		check_complete_excavation()

# Check if all cells have been fully excavated (reached the bottom layer)
func check_complete_excavation():
	var total_cells = GRID_SIZE.x * GRID_SIZE.y
	var fully_excavated_cells = 0
	
	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			if is_cell_excavated(x, y):
				fully_excavated_cells += 1
	
	# If all cells are fully excavated, end the game
	if fully_excavated_cells >= total_cells:
		print("All cells excavated! Ending game...")
		end_game()

# Update the visual appearance of a cell based on its durability
func update_cell_visual(x: int, y: int):
	var cell_data = grid[y][x]
	var current_layer_index = cell_data["current_layer"]
	var current_layer = cell_data["layers"][current_layer_index]
	var cell_visual = cell_nodes[y][x]
	# Grab optional dirt texture child
	var dirt_tr: TextureRect = cell_visual.get_node_or_null("DirtTexture")
	# Grab optional stone texture child
	var stone_tr: TextureRect = cell_visual.get_node_or_null("StoneTexture")

	# All grid visuals should use relative z so UI with absolute z can render above
	cell_visual.z_as_relative = true
	if dirt_tr:
		dirt_tr.z_as_relative = true
	if stone_tr:
		stone_tr.z_as_relative = true
	
	# Default base z for the cell
	cell_visual.z_index = 0
	
	# Update visual based on layer type (with dirt spritesheet support)
	var new_color: Color
	# Track crystal ownership across branches for stylebox decisions
	var belongs_to_crystal := false
	var is_crystal_cell := false
	if current_layer["type"] == LayerType.DIRT:
		if dirt_tr:
			# Show dirt spritesheet frame and make parent transparent
			dirt_tr.visible = true
			dirt_tr.z_index = 2
			if stone_tr:
				stone_tr.visible = false
				stone_tr.z_index = 0
			# Choose frame (0=plain,1=damaged,2=rubble,3=rubble+damaged)
			var frame_idx = 0
			var had_stone = grid[y][x]["had_stone"]
			var rubble = had_stone and grid[y][x]["stone_broken"]
			var damaged = current_layer["durability"] < 100
			if rubble and damaged:
				frame_idx = 3
			elif rubble:
				frame_idx = 2
			elif damaged:
				frame_idx = 1
			var atlas2 := dirt_tr.texture as AtlasTexture
			if atlas2 == null:
				atlas2 = AtlasTexture.new()
				atlas2.atlas = dirt_texture
				dirt_tr.texture = atlas2
			atlas2.region = Rect2(frame_idx * DIRT_TILE_SIZE.x, 0, DIRT_TILE_SIZE.x, DIRT_TILE_SIZE.y)
			# Keep the base panel opaque so any transparent pixels in the texture don't reveal content beneath
			new_color = COLOR_DIRT
		else:
			# Fallback to flat color if no texture assigned
			new_color = COLOR_DIRT
			# Ensure flat-colored dirt still occludes crystals
			cell_visual.z_index = 2
	elif current_layer["type"] == LayerType.STONE:
		if dirt_tr:
			dirt_tr.visible = false
			dirt_tr.z_index = 0
		if stone_tr:
			# Show stone spritesheet frame and make parent transparent
			stone_tr.visible = true
			stone_tr.z_index = 2
			var s_frame_idx = 0
			var s_damaged = current_layer["durability"] < 100
			if s_damaged:
				s_frame_idx = 1
			var satlas2 := stone_tr.texture as AtlasTexture
			if satlas2 == null:
				satlas2 = AtlasTexture.new()
				satlas2.atlas = stone_texture
				stone_tr.texture = satlas2
			satlas2.region = Rect2(s_frame_idx * STONE_TILE_SIZE.x, 0, STONE_TILE_SIZE.x, STONE_TILE_SIZE.y)
			# Keep the base panel opaque so any transparent pixels in the texture don't reveal content beneath
			var factor_visible: float = maxf(CELL_OPACITY_MIN, float(current_layer["durability"]) / 100.0)
			new_color = Color(COLOR_STONE.r * factor_visible, COLOR_STONE.g * factor_visible, COLOR_STONE.b * factor_visible, 1.0)
		else:
			# Fallback to flat color if no texture assigned
			# Darken stone as durability decreases (factor between CELL_OPACITY_MIN and 1)
			var factor: float = maxf(CELL_OPACITY_MIN, float(current_layer["durability"]) / 100.0)
			new_color = Color(COLOR_STONE.r * factor, COLOR_STONE.g * factor, COLOR_STONE.b * factor, 1.0)
			# Ensure flat-colored stone still occludes crystals
			cell_visual.z_index = 2
	elif current_layer["type"] == LayerType.EMPTY:
		if dirt_tr:
			dirt_tr.visible = false
			dirt_tr.z_index = 0
		if stone_tr:
			stone_tr.visible = false
			stone_tr.z_index = 0
		cell_visual.z_index = 0
		# EMPTY cells are always fully transparent so the unified backdrop/UI shows through
		belongs_to_crystal = false
		new_color = Color(0, 0, 0, 0)
	elif current_layer["type"] == LayerType.TREASURE:
		if dirt_tr:
			dirt_tr.visible = false
			dirt_tr.z_index = 0
		if stone_tr:
			stone_tr.visible = false
			stone_tr.z_index = 0
		# For crystals/gems, make the cell transparent (image visual will be drawn above)
		var treasure_color := COLOR_TREASURE_BG
		# Find which placed treasure occupies this cell, if any
		for treasure in treasures:
			var placed_treasure = treasure["placed_treasure"]
			if placed_treasure != null and placed_treasure.occupies_position(Vector2i(x, y)):
				if TreasureGenerator._is_crystals_gems(placed_treasure.treasure_data):
					new_color = Color(0, 0, 0, 0)
					is_crystal_cell = true
				else:
					treasure_color = TreasureGenerator.get_treasure_color_safe(placed_treasure.treasure_data)
					new_color = treasure_color
				break

	# Apply color and optional border
	cell_visual.color = new_color
	# Avoid any panel tint on crystal-owned cells (both EMPTY and TREASURE transparent cases)
	var crystal_owned := false
	if current_layer["type"] == LayerType.EMPTY and belongs_to_crystal:
		crystal_owned = true
	elif current_layer["type"] == LayerType.TREASURE and is_crystal_cell:
		crystal_owned = true
	
	if crystal_owned:
		cell_visual.remove_theme_stylebox_override("panel")
	elif show_cell_borders:
		cell_visual.add_theme_stylebox_override("panel", create_cell_style_box(new_color))
	else:
		cell_visual.remove_theme_stylebox_override("panel")

	# Final safety: enforce layering rules after individual updates
	normalize_grid_layering()

# Reveal a treasure at the specified grid position (Battleship-style partial reveals)
func reveal_treasure(x: int, y: int):
	# Find the treasure that occupies this grid position
	for treasure in treasures:
		var placed_treasure = treasure["placed_treasure"]
		
		# Check if this treasure occupies the clicked position
		if placed_treasure != null and placed_treasure.occupies_position(Vector2i(x, y)):
			# Mark this specific cell as having its treasure layer revealed
			var has_stone = grid[y][x]["layers"][0]["type"] == LayerType.STONE
			var treasure_layer = 2 if has_stone else 1
			grid[y][x]["layers"][treasure_layer]["revealed"] = true
			# Mark the treasure as revealed for scoring
			treasure["revealed"] = true
			# Immediately create the crystal visual once a crystal cell is revealed
			if placed_treasure.visual_node == null:
				var cat_dbg := ""
				if placed_treasure.treasure_data != null:
					cat_dbg = TreasureGenerator._get_category_safe(placed_treasure.treasure_data)
				print("Reveal: attempting visual for ", TreasureGenerator.get_treasure_name_safe(placed_treasure.treasure_data), " category=", cat_dbg)
				var cell_size_v := get_actual_cell_size()
				var parent_container_v: Control = $MainContainer/MainGameArea/GridContainer
				var visual_v := TreasureGenerator.create_treasure_visual(placed_treasure, cell_size_v, parent_container_v)
				if visual_v != null:
					visual_v.position = calculate_cell_position(placed_treasure.top_left.x, placed_treasure.top_left.y)
					parent_container_v.add_child(visual_v)
					parent_container_v.move_child(visual_v, parent_container_v.get_child_count() - 1)
					print("DEBUG: Added treasure visual (immediate) for ", TreasureGenerator.get_treasure_name_safe(placed_treasure.treasure_data))
					normalize_grid_layering()
					# Force-refresh all cells in this treasure's footprint so covering dirt/stone
					# immediately re-apply opaque color/z-order and occlude the visual where needed.
					for gp in placed_treasure.grid_positions:
						update_cell_visual(gp.x, gp.y)
					print("DEBUG: forced refresh of treasure footprint complete")
			# Return regardless of whether a visual was created (non-crystal categories)
			return

	print("ERROR: reveal_treasure() could not find placed treasure at ", Vector2i(x, y))

# Enforce predictable z-order across the entire grid
func normalize_grid_layering():
	var gridc: Control = $MainContainer/MainGameArea/GridContainer
	if gridc:
		gridc.z_as_relative = true
		gridc.z_index = 0
	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			if y >= cell_nodes.size():
				continue
			var row = cell_nodes[y]
			if x >= row.size():
				continue
			var cv: Control = row[x]
			if cv == null:
				continue
			cv.z_as_relative = true
			# Base cell at 0 for empty/treasure; leave as set for dirt/stone flat-color branch
			var cell_data = grid[y][x]
			var current_layer_index = cell_data["current_layer"]
			var ltype = cell_data["layers"][current_layer_index]["type"]
			if ltype == LayerType.EMPTY or ltype == LayerType.TREASURE:
				cv.z_index = 0
			var dt: TextureRect = cv.get_node_or_null("DirtTexture")
			if dt:
				dt.z_as_relative = true
				dt.z_index = 2 if dt.visible else 0
			var st: TextureRect = cv.get_node_or_null("StoneTexture")
			if st:
				st.z_as_relative = true
				st.z_index = 2 if st.visible else 0

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
	
	# Count only explicitly revealed treasures - no credit for partially accessible ones!
	var revealed_count = 0
	var total_value = 0
	
	for treasure in treasures:
		var placed_treasure = treasure["placed_treasure"]
		if is_treasure_fully_claimed(placed_treasure):
			revealed_count += 1
			var treasure_data = placed_treasure.treasure_data if placed_treasure != null else null
			if treasure_data != null:
				total_value += TreasureGenerator.get_treasure_price_safe(treasure_data)
			else:
				print("WARNING: Could not find treasure data for fully-claimed treasure")
	
	# Build a full-screen overlay with dim background and a centered results panel
	var overlay := Control.new()
	overlay.name = "ResultsOverlay"
	overlay.z_as_relative = false
	overlay.z_index = 1100
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0,0,0,0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	# Centered panel container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := Panel.new()
	panel.name = "ResultsPanel"
	panel.custom_minimum_size = Vector2(420, 240)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0
	vbox.anchor_top = 0
	vbox.anchor_right = 1
	vbox.anchor_bottom = 1
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var results := Label.new()
	results.text = "Mining Complete!\n\nTreasures Found: " + str(revealed_count) + "\nTotal Value: " + str(total_value)
	results.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(results)

	# Add a retry button
	var retry_button := Button.new()
	retry_button.text = "Try Again"
	retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry_button.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(retry_button)

	# Put overlay on its own CanvasLayer so nothing from the grid can overdraw it
	var results_layer := CanvasLayer.new()
	results_layer.layer = 10
	results_layer.name = "ResultsCanvasLayer"
	results_layer.add_child(overlay)
	add_child(results_layer)

	# Keep using the custom crosshair cursor over the results overlay
	# Ensure the OS cursor stays hidden and the reticle is visible above everything
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	var reticle_to_show := get_node_or_null("ReticleLayer/Reticle")
	if reticle_to_show:
		reticle_to_show.visible = true

# Close the minigame and restore cursor
func close_minigame():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# You can add additional cleanup here if needed
	# For now, just hide the minigame or go back to main scene
	queue_free()  # Remove the minigame scene

# Ensure cursor is restored when leaving the minigame
func _exit_tree():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# ============================================================================
# HELPER FUNCTIONS - Utility functions to reduce code duplication
# ============================================================================

# Helper function to safely get treasure properties (handles both dict and object)
func get_treasure_property(treasure_data, property_name: String, default_value = null):
	if treasure_data == null:
		return default_value
		
	if typeof(treasure_data) == TYPE_DICTIONARY:
		return treasure_data.get(property_name, default_value)
	else:
		# It's an object (MiningItem)
		if treasure_data.has_method("get"):
			return treasure_data.get(property_name)
		else:
			# Direct property access
			match property_name:
				"name":
					return treasure_data.name if "name" in treasure_data else default_value
				"base_price":
					return treasure_data.base_price if "base_price" in treasure_data else default_value
				_:
					return default_value

# Helper function to get treasure name safely
func get_treasure_name_safe(treasure_data) -> String:
	return get_treasure_property(treasure_data, "name", "???")

# Helper function to get treasure price safely
func get_treasure_price(treasure_data) -> float:
	return get_treasure_property(treasure_data, "base_price", 0.0)

# Helper function to calculate cell position with centering
func calculate_cell_position(grid_x: int, grid_y: int, size_multiplier: float = 1.0) -> Vector2:
	var actual_cell_size = get_actual_cell_size()
	var centering_offset = get_grid_centering_offset()
	
	return Vector2(
		centering_offset.x + grid_x * actual_cell_size.x + actual_cell_size.x * (1.0 - size_multiplier) * 0.5,
		centering_offset.y + grid_y * actual_cell_size.y + actual_cell_size.y * (1.0 - size_multiplier) * 0.5
	)

# (Removed) get_treasure_color: use TreasureGenerator.get_treasure_color_safe instead to avoid duplication

# Helper function to create style box for cells (reduces object creation)
func create_cell_style_box(bg_color: Color) -> StyleBoxFlat:
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = bg_color
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, BORDER_OPACITY)
	return style_box
