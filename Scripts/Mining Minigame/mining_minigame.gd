extends CanvasLayer
class_name MiningMinigame

# Set a high layer value to ensure we're above other UI

# =========================================================================
# Signals
# =========================================================================
signal minigame_closed(treasures_found: int, total_value: int)
signal minigame_closed_with_state(treasures_found: int, total_value: int, was_completed: bool, node_id: int, snapshot: Dictionary)

# =========================================================================
# Constants and configuration
# =========================================================================
# Visual constants
const TREASURE_SIZE_MULTIPLIER = 0.8
const CELL_OPACITY_MIN = 0.3
const BORDER_OPACITY = 0.5

# Colors
const COLOR_DIRT = Color(0.6, 0.4, 0.2)
const COLOR_STONE = Color(0.48, 0.48, 0.48)
const COLOR_EMPTY = Color(0.2, 0.2, 0.2)
const COLOR_TREASURE_BG = Color(0.8, 0.7, 0.2)
const COLOR_TREASURE_ROCK = Color(0.28, 0.28, 0.28)
const COLOR_TREASURE_METAL = Color(0.95, 0.55, 0.20)
const COLOR_TREASURE_GEM = Color(0.60, 0.85, 1.00)
const COLOR_BORDER = Color(0.3, 0.3, 0.3)

# Using global ToolLogic (from class_name in ToolLogic.gd); avoid local preload to prevent shadowing

# Grid size
const GRID_SIZE = Vector2i(17, 10)

# Sizing and layout
@export var use_fixed_cell_size: bool = true
@export var fixed_cell_size: Vector2 = Vector2(50, 50)
@export_range(0.5, 0.9, 0.05) var overlay_width_percentage: float = 0.85
@export_range(0.5, 0.9, 0.05) var overlay_height_percentage: float = 0.8
@export var min_cell_size: Vector2 = Vector2(30, 30)
@export var grid_backdrop_color: Color = Color(0.2, 0.2, 0.2)

# Visual toggle
@export var show_cell_borders: bool = false

# Enums
enum ToolType { PICKAXE, HAMMER }
enum LayerType { STONE, DIRT, TREASURE, EMPTY }

# Game state and settings
var game_over: bool = false
var current_tool = ToolType.PICKAXE
@export var difficulty: int = 1
@export var rewards_multiplier: float = 1.0
@export var dev_mode_unlimited_durability: bool = false
@export var node_id: int = -1
var was_completed: bool = false
@export var auto_start: bool = true

# Grid data
var grid = []
var cell_nodes = []
var treasures = []

# Treasure config
@export_range(2, 5, 1) var min_treasures: int = 3
@export_range(6, 15, 1) var max_treasures: int = 10

# Durability and costs
var max_durability: float = 100
var current_durability: float = 0
var revealed_count: int = 0
var total_value: int = 0
@export_range(0.5, 3.0, 0.1) var pickaxe_base_cost: float = 1.0
@export_range(1.0, 5.0, 0.1) var hammer_base_cost_percent: float = 2.0
@export_range(0.1, 1.0, 0.1) var hammer_per_cell_cost_percent: float = 0.5
@export_range(3.0, 8.0, 0.1) var hammer_max_cost_percent: float = 5.0

# Damage values
var pickaxe_damage = { LayerType.STONE: 100, LayerType.DIRT: 100 }
var hammer_damage = { LayerType.STONE: 100, LayerType.DIRT: 100 }

# Optional textures and spritesheet settings
@export var dirt_texture: Texture2D
const DIRT_SHEET_HFRAMES: int = 4
const DIRT_SHEET_VFRAMES: int = 1
const DIRT_TILE_SIZE: Vector2i = Vector2i(16, 16)

@export var stone_texture: Texture2D
const STONE_SHEET_HFRAMES: int = 2
const STONE_SHEET_VFRAMES: int = 1
const STONE_TILE_SIZE: Vector2i = Vector2i(16, 16)

# Called when the node enters the scene tree for the first time
func _ready():
	# Make sure we can process input
	set_process_input(true)
	set_process_unhandled_input(true)
	
	# Make sure we can receive input
	get_viewport().gui_disable_input = false
	
	# Make sure we're the top layer
	layer = 128  # High layer number to ensure we're on top
	
	# Connect the close button signal if it exists
	var close_button = $MainContainer/CloseButton
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	
	randomize()  # Initialize random number generator
	
	# Connect to window resize signals to handle resolution changes
	get_viewport().size_changed.connect(on_viewport_resized)
	
	# Ensure UI overlays (e.g., game over panel) render above the grid
	var ui_container = $MainContainer/"UI Elements"
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
	if auto_start:
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
	# Centering is now handled by the scene layout:
	# - `MainGameArea` is a CenterContainer
	# - `GridContainer` uses SHRINK_CENTER size flags and its custom_minimum_size
	# Therefore, no extra offset is needed at the child level.
	return Vector2.ZERO

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
					try_mine_cell(clicked_x, clicked_y))
			
			# Add to scene
			$MainContainer/MainGameArea/GridContainer.add_child(cell)
			row.append(cell)
		
		# Store the row
		cell_nodes.append(row)
	
	# Create reticle as a direct child of this node (which is a CanvasLayer)
	# This ensures it's rendered above all other UI elements
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
	reticle.z_index = 1000
	reticle.visible = true
	# Ensure it's not affected by the viewport
	reticle.top_level = true
	
	# Create a cross shape using lines
	var reticle_lines = Line2D.new()
	reticle_lines.z_as_relative = false
	reticle_lines.z_index = 1005
	reticle_lines.width = 3  # Slightly thicker for better visibility
	reticle_lines.default_color = Color(1, 0, 0, 1.0)  # Solid red
	
	# Cross shape points (horizontal line)
	reticle_lines.add_point(Vector2(-10, 0))
	reticle_lines.add_point(Vector2(10, 0))
	
	# Add a second line for vertical part
	var vertical_line = Line2D.new()
	vertical_line.z_as_relative = false
	vertical_line.z_index = 1005
	vertical_line.width = 3  # Slightly thicker for better visibility
	vertical_line.default_color = Color(1, 0, 0, 1.0)  # Solid red
	vertical_line.add_point(Vector2(0, -10))
	vertical_line.add_point(Vector2(0, 10))
	
	reticle.add_child(reticle_lines)
	reticle.add_child(vertical_line)
	
	return reticle

# Process mouse movement to update reticle position
func _process(_delta):
	# Update reticle position if it exists
	var reticle = get_node_or_null("Reticle")
	if reticle and not game_over and get_tree() and get_viewport():
		# Get the mouse position in the viewport
		var mouse_pos = get_viewport().get_mouse_position()
		# Convert to global coordinates if needed
		reticle.global_position = mouse_pos - Vector2(10, 10)
		reticle.visible = true
		# Make sure it stays on top
		reticle.z_index = 1000

# Handle viewport resizing
func on_viewport_resized():
	# Only adjust the backdrop size/position to match the grid; do not rebuild the grid
	var gridc := $MainContainer/MainGameArea/GridContainer
	if gridc:
		var cell_sz := get_actual_cell_size()
		# Ensure the container advertises the grid's true size so CenterContainer can center it
		gridc.custom_minimum_size = Vector2(GRID_SIZE.x * cell_sz.x, GRID_SIZE.y * cell_sz.y)
		var backdrop: ColorRect = gridc.get_node_or_null("GridBackdrop")
		if backdrop:
			backdrop.position = Vector2.ZERO
			backdrop.size = gridc.custom_minimum_size
			backdrop.color = grid_backdrop_color
			backdrop.z_as_relative = true
			backdrop.z_index = -100
			backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Reflow all grid cells and treasure visuals so they stay centered and scaled
	reflow_grid_layout()
	# Optional: debug
	# print("Viewport resized - backdrop updated and reflowed")

# Recompute positions/sizes for all cells and treasure visuals based on current viewport
func reflow_grid_layout():
	var cell_sz := get_actual_cell_size()

	# Update each grid cell's size and position
	for y in range(GRID_SIZE.y):
		if y >= cell_nodes.size():
			break
		var row = cell_nodes[y]
		for x in range(GRID_SIZE.x):
			if x >= row.size():
				continue
			var cell: Control = row[x]
			if cell == null:
				continue
			cell.size = cell_sz
			cell.position = calculate_cell_position(x, y)
			# Adjust child textures to keep 1px border (when enabled)
			var inset: int = 1 if show_cell_borders else 0
			var dirt_tr: TextureRect = cell.get_node_or_null("DirtTexture")
			if dirt_tr:
				dirt_tr.position = Vector2(inset, inset)
				dirt_tr.size = cell_sz - Vector2(inset * 2, inset * 2)
			var stone_tr: TextureRect = cell.get_node_or_null("StoneTexture")
			if stone_tr:
				var inset2: int = 1 if show_cell_borders else 0
				stone_tr.position = Vector2(inset2, inset2)
				stone_tr.size = cell_sz - Vector2(inset2 * 2, inset2 * 2)

	# Update any multi-cell treasure visuals (e.g., crystals)
	for treasure in treasures:
		var placed_treasure = treasure.get("placed_treasure", null)
		if placed_treasure == null:
			continue
		var visual: Control = placed_treasure.visual_node
		if visual == null:
			continue
		visual.size = Vector2(placed_treasure.size.x * cell_sz.x, placed_treasure.size.y * cell_sz.y)
		visual.position = calculate_cell_position(placed_treasure.top_left.x, placed_treasure.top_left.y)
		var ttex: TextureRect = visual.get_node_or_null("TreasureTexture")
		if ttex:
			ttex.size = visual.size

	# Ensure z-ordering remains consistent after size/visibility changes
	normalize_grid_layering()

# Handle close button press
func _on_close_button_pressed():
	# Make sure we restore input state before closing
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	close_minigame()

# Start a new game
func start_game():
	# Make sure we're visible and can receive input
	show()
	set_process_input(true)
	set_process_unhandled_input(true)
	
	# Show the mouse cursor for the minigame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Reset game state
	game_over = false
	was_completed = false
	
	# Clear any existing grid
	for child in $MainContainer/MainGameArea/GridContainer.get_children():
		child.queue_free()
	
	# Initialize new grid and visuals
	init_grid()
	# Prepare container sizing and backdrop BEFORE creating cells so centering is immediate
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
			# Size the GridContainer and the backdrop to the exact grid bounds
			var cell_sz := get_actual_cell_size()
			# Ensure the container advertises the grid's true size so CenterContainer can center it
			gridc_back.custom_minimum_size = Vector2(GRID_SIZE.x * cell_sz.x, GRID_SIZE.y * cell_sz.y)
			var bd: ColorRect = gridc_back.get_node_or_null("GridBackdrop")
			if bd:
				bd.position = Vector2.ZERO
				bd.size = gridc_back.custom_minimum_size
				bd.color = grid_backdrop_color
				bd.z_as_relative = true
				bd.z_index = -100
				bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Now create visuals (cells) after container is sized
	create_grid_visuals()
	# Generate random number of treasures within the specified range
	var treasure_count = randi_range(min_treasures, max_treasures)
	place_treasures(treasure_count)
	
	# Initialize tool selection (default to pickaxe on open)
	current_tool = ToolType.PICKAXE
	set_current_tool(current_tool)
	
	# Initialize durability
	current_durability = max_durability
	
	# Show tutorial text if desired
	print("Mining game started! Break through stone and dirt to find treasures!")
	print("Pickaxe: Single cell | Hammer: Plus shape (+) | Grid: " + str(GRID_SIZE.x) + " x " + str(GRID_SIZE.y))
	# Notify globally that the minigame opened
	Signals.emit_minigame_opened()

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

# Handle cell click (this is called by the cell's input_event signal)
func on_cell_clicked(x: int, y: int):
	# Make sure we're not in the middle of another action
	if game_over:
		return

	# Use the consolidated mining logic
	try_mine_cell(x, y)

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
func hit_cell(x: int, y: int, _damage_values, _multiplier: float = 1.0):
	# Legacy wrapper; our main logic is in try_mine_cell
	try_mine_cell(x, y)

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

# Handle input events (for dev mode toggle and ESC key)
func _input(event):
	# Always process ESC key first
	if event.is_action_pressed("ui_cancel"):
		close_minigame()
		var viewport = get_viewport()
		if viewport:
			viewport.set_input_as_handled()
		return
		
	# Process other input only if not game over
	if game_over:
		return
			
	# Toggle dev mode with F1 only (guard against key repeat)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		dev_mode_unlimited_durability = !dev_mode_unlimited_durability
		print("DEV MODE:", "ON" if dev_mode_unlimited_durability else "OFF")
		get_viewport().set_input_as_handled()

# Handle mouse clicks on the grid
func _unhandled_input(event: InputEvent) -> void:
	# Only process mouse clicks if not game over
	if game_over:
		return
		
	# Handle left mouse button clicks for mining
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Get the grid position from mouse position
		var grid_pos = get_grid_position_from_mouse(event.position)
		if grid_pos.x >= 0 and grid_pos.y >= 0 and try_mine_cell(grid_pos.x, grid_pos.y):
			get_viewport().set_input_as_handled()

# Convert screen position to grid coordinates
func get_grid_position_from_mouse(_mouse_pos: Vector2) -> Vector2i:
	var grid_container = $MainContainer/MainGameArea/GridContainer
	if not grid_container:
		return Vector2i(-1, -1)
		
	# Convert mouse position to local grid container space
	var local_pos = grid_container.get_local_mouse_position()
	var cell_size = get_actual_cell_size()
	
	# Calculate grid position
	var grid_x = int(local_pos.x / cell_size.x)
	var grid_y = int(local_pos.y / cell_size.y)
	
	# Check if position is within grid bounds
	if grid_x >= 0 and grid_x < GRID_SIZE.x and grid_y >= 0 and grid_y < GRID_SIZE.y:
		return Vector2i(grid_x, grid_y)
	return Vector2i(-1, -1)

# Try to mine a cell at the given grid position
func try_mine_cell(x: int, y: int) -> bool:
	var damage_applied = false
	
	# Calculate damage based on tool
	if current_tool == ToolType.PICKAXE:
		# Pickaxe affects a + shape (center 100%, sides 50%)
		var pickaxe_positions = ToolLogic.get_pickaxe_positions(x, y)
		var pickaxe_cells_affected = 0
		
		for pos_data in pickaxe_positions:
			var nx = pos_data.pos.x
			var ny = pos_data.pos.y
			var multiplier = pos_data.multiplier
			
			if nx >= 0 and nx < GRID_SIZE.x and ny >= 0 and ny < GRID_SIZE.y:
				if can_cell_be_damaged(nx, ny):
					var target_cell = grid[ny][nx]
					var target_layer = target_cell["layers"][target_cell["current_layer"]]
					var base_damage = pickaxe_damage.get(target_layer["type"], 0)
					var actual_damage = int(base_damage * multiplier)
					
					if actual_damage > 0:
						damage_applied = true
						target_layer["durability"] -= actual_damage
						if target_layer["durability"] <= 0:
							target_layer["revealed"] = true
						update_cell_visual(nx, ny)
						pickaxe_cells_affected += 1
						
						# Check if layer is destroyed
						if target_layer["durability"] <= 0:
							# Mark stone as broken if we just destroyed a stone layer
							if target_layer["type"] == LayerType.STONE:
								target_cell["stone_broken"] = true
							
							# Move to next layer if available
							if target_cell["current_layer"] < target_cell["layers"].size() - 1:
								target_cell["current_layer"] += 1
								# If next layer is treasure, reveal it
								if target_cell["layers"][target_cell["current_layer"]]["type"] == LayerType.TREASURE:
									reveal_treasure(nx, ny)
								update_cell_visual(nx, ny)
		
		# Calculate pickaxe durability cost (base + per-cell affected)
		if not dev_mode_unlimited_durability and damage_applied:
			var pickaxe_cost = ToolLogic.compute_pickaxe_cost(pickaxe_base_cost, pickaxe_cells_affected, 0.5)
			current_durability -= pickaxe_cost
		
	else: # HAMMER
		# Hammer affects 3x3 area with + shape pattern (center/sides 100%, corners 50%)
		var hammer_positions = ToolLogic.get_hammer_positions(x, y)
		
		var cells_affected = 0
		for pos_data in hammer_positions:
			var nx = pos_data.pos.x
			var ny = pos_data.pos.y
			var multiplier = pos_data.multiplier
			
			if nx >= 0 and nx < GRID_SIZE.x and ny >= 0 and ny < GRID_SIZE.y:
				if can_cell_be_damaged(nx, ny):
					var target_cell = grid[ny][nx]
					var target_layer = target_cell["layers"][target_cell["current_layer"]]
					var base_damage = hammer_damage.get(target_layer["type"], 0)
					var actual_damage = int(base_damage * multiplier)
					
					if actual_damage > 0:
						damage_applied = true
						target_layer["durability"] -= actual_damage
						if target_layer["durability"] <= 0:
							target_layer["revealed"] = true
						update_cell_visual(nx, ny)
						cells_affected += 1
						
						# Check if layer is destroyed
						if target_layer["durability"] <= 0:
							# Mark stone as broken if we just destroyed a stone layer
							if target_layer["type"] == LayerType.STONE:
								target_cell["stone_broken"] = true
							
							# Move to next layer if available
							if target_cell["current_layer"] < target_cell["layers"].size() - 1:
								target_cell["current_layer"] += 1
								# If next layer is treasure, reveal it
								if target_cell["layers"][target_cell["current_layer"]]["type"] == LayerType.TREASURE:
									reveal_treasure(nx, ny)
								update_cell_visual(nx, ny)
		
		# Calculate hammer durability cost (base + per-cell affected)
		if not dev_mode_unlimited_durability and damage_applied:
			var hammer_cost = ToolLogic.compute_hammer_cost(hammer_base_cost_percent, cells_affected, hammer_per_cell_cost_percent, hammer_max_cost_percent)
			current_durability -= hammer_cost
	
	# Update UI and check for game over if damage was applied
	if damage_applied:
		update_durability_display()
		if current_durability <= 0 and not dev_mode_unlimited_durability:
			current_durability = 0
			end_game()
		# Also check if all cells are excavated (works even in dev mode)
		elif not game_over:
			check_complete_excavation()
	
	return damage_applied

# Update the durability display in the UI
func update_durability_display() -> void:
	var durability_label = get_node_or_null("MainContainer/UI Elements/DurabilityLabel")
	if durability_label:
		durability_label.text = "Durability: %d" % current_durability

# Clean up the results overlay if it exists (delegate to MiningUI)
func cleanup_results_overlay():
	if not is_inside_tree():
		return
	MiningUI.cleanup_results_overlay(self)

# End the game and display results
func end_game():
	if game_over:
		return  # Already ended
		
	game_over = true
	was_completed = true
	
	# Disable input processing
	set_process_input(false)
	set_process_unhandled_input(false)
	
	# Count only explicitly revealed treasures - no credit for partially accessible ones!
	self.revealed_count = 0
	self.total_value = 0
	
	for i in range(treasures.size()):
		var treasure = treasures[i]
		var placed_treasure = treasure["placed_treasure"]
		print("\nChecking treasure", i, ":", placed_treasure)
		
		if placed_treasure:
			print("- Is fully claimed:", is_treasure_fully_claimed(placed_treasure))
			print("- Has treasure_data:", placed_treasure.has_method("get") and placed_treasure.get("treasure_data") != null)
			
			if is_treasure_fully_claimed(placed_treasure):
				self.revealed_count += 1
				var treasure_data = null
				if placed_treasure.has_method("get"):
					treasure_data = placed_treasure.get("treasure_data")
					if treasure_data:
						var value = int(round(TreasureGenerator.get_treasure_price_safe(treasure_data)))
						print("- Treasure value:", value)
						self.total_value += value
					else:
						print("- WARNING: treasure_data is null")
				else:
					print("- WARNING: placed_treasure doesn't have 'get' method")
		else:
			print("- WARNING: placed_treasure is null")

	
	# Clean up any existing overlay first
	cleanup_results_overlay()

	# Create results overlay via UI helper
	await MiningUI.create_results_overlay(self, self.revealed_count, self.total_value, Callable(self, "_on_exit_button_pressed"))

	# Show the system cursor for the exit button
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Hide any reticle that might be showing
	var reticle_to_hide = get_node_or_null("ReticleLayer/Reticle")
	if reticle_to_hide:
		reticle_to_hide.visible = false

# Close the minigame and clean up
func _on_exit_button_pressed():
	print("Exit button pressed!")
	# Get the button reference
	var exit_button = get_node_or_null("ResultsCanvasLayer/ResultsOverlay/UIContainer/VBoxContainer/HBoxContainer/ExitButton")
	if exit_button:
		# Disable the button to prevent multiple clicks
		exit_button.disabled = true
		# Visual feedback
		exit_button.modulate = Color(0.8, 0.8, 0.8, 1.0)
	
	# Close immediately without waiting
	close_minigame()

func close_minigame():
	print("Closing minigame...")  # Debug print
	print("Treasures found:", revealed_count, " Value:", total_value)  # Debug print
	
	# Clean up any existing overlay first
	cleanup_results_overlay()
	
	# Make sure cursor is visible
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Prepare snapshot for persistence
	var snapshot := create_state_snapshot()

	# Emit signals with results (new enriched signal + legacy for compatibility)
	if is_inside_tree() and has_signal("minigame_closed"):
		var _connections = get_signal_connection_list("minigame_closed")
		if _connections.size() == 0:
			print("Warning: minigame_closed signal has no connections")
		else:
			emit_signal("minigame_closed", revealed_count, total_value)

	# New signal carrying full state for session persistence
	if is_inside_tree() and has_signal("minigame_closed_with_state"):
		emit_signal("minigame_closed_with_state", revealed_count, total_value, was_completed, node_id, snapshot)
	
	# Use call_deferred to safely remove from tree
	call_deferred("_safe_remove_minigame")

func _safe_remove_minigame():
	# Safely remove the minigame from the tree
	if is_inside_tree():
		var parent = get_parent()
		if parent:
			parent.remove_child(self)
	queue_free()

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

# =========================================================================
# PERSISTENCE: Snapshot and Restore
# =========================================================================

func _get_item_id_safe(treasure_data) -> String:
	if treasure_data == null:
		return ""
	if typeof(treasure_data) == TYPE_DICTIONARY:
		return String(treasure_data.get("id", ""))
	# Try common property access on objects
	if "id" in treasure_data:
		return String(treasure_data.id)
	return ""

func _resolve_item_by_id(id: String):
	if id == "":
		return null
	var db = get_node_or_null("/root/MiningItemDatabase")
	if db and db.has_method("get_item_by_id"):
		return db.get_item_by_id(id)
	return null

# Build a serializable snapshot of the current game state
func create_state_snapshot() -> Dictionary:
	var grid_copy := []
	for y in range(GRID_SIZE.y):
		var row := []
		for x in range(GRID_SIZE.x):
			var cell: Dictionary = grid[y][x]
			var layers_snap := []
			for li in range(cell["layers"].size()):
				var lyr: Dictionary = cell["layers"][li]
				var snap := {
					"type": lyr.get("type", LayerType.EMPTY),
					"durability": lyr.get("durability", 0),
					"revealed": lyr.get("revealed", false)
				}
				# Store treasure id if present
				if lyr.has("treasure") and lyr["treasure"] != null:
					snap["treasure_id"] = _get_item_id_safe(lyr["treasure"])
				layers_snap.append(snap)
			row.append({
				"layers": layers_snap,
				"current_layer": cell.get("current_layer", 0),
				"had_stone": cell.get("had_stone", false),
				"stone_broken": cell.get("stone_broken", false)
			})
		grid_copy.append(row)

	var treasures_snap := []
	for t in treasures:
		var placed = t.get("placed_treasure", null)
		if placed == null:
			continue
		var item_id := _get_item_id_safe(placed.treasure_data)
		var gp_list := []
		for gp in placed.grid_positions:
			gp_list.append(Vector2i(gp.x, gp.y))
		treasures_snap.append({
			"top_left": Vector2i(placed.top_left.x, placed.top_left.y),
			"size": Vector2i(placed.size.x, placed.size.y),
			"grid_positions": gp_list,
			"item_id": item_id
		})

	return {
		"version": 1,
		"node_id": node_id,
		"grid_size": Vector2i(GRID_SIZE.x, GRID_SIZE.y),
		"grid": grid_copy,
		"treasures": treasures_snap,
		"current_durability": current_durability,
		"current_tool": current_tool,
		"game_over": game_over,
		"was_completed": was_completed,
		"revealed_count": revealed_count,
		"total_value": total_value
	}

# Restore the game from a snapshot
func init_from_state(state: Dictionary) -> void:
	# Basic guards
	if state.is_empty():
		start_game()
		return

	show()
	set_process_input(true)
	set_process_unhandled_input(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	game_over = false
	was_completed = false

	# Clear existing grid visuals
	for child in $MainContainer/MainGameArea/GridContainer.get_children():
		child.queue_free()

	# Recreate container/backdrop sizing like start_game()
	var gridc_back := $MainContainer/MainGameArea/GridContainer
	if gridc_back:
		var backdrop := gridc_back.get_node_or_null("GridBackdrop")
		if grid_backdrop_color.a <= 0.001:
			if backdrop:
				backdrop.queue_free()
		else:
			if backdrop == null:
				var cr := ColorRect.new()
				cr.name = "GridBackdrop"
				gridc_back.add_child(cr)
				gridc_back.move_child(cr, 0)
			var cell_sz := get_actual_cell_size()
			gridc_back.custom_minimum_size = Vector2(GRID_SIZE.x * cell_sz.x, GRID_SIZE.y * cell_sz.y)
			var bd: ColorRect = gridc_back.get_node_or_null("GridBackdrop")
			if bd:
				bd.position = Vector2.ZERO
				bd.size = gridc_back.custom_minimum_size
				bd.color = grid_backdrop_color
				bd.z_as_relative = true
				bd.z_index = -100
				bd.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load grid from snapshot
	grid = []
	var snap_grid: Array = state.get("grid", [])
	for y in range(GRID_SIZE.y):
		var row := []
		if y < snap_grid.size():
			var srow: Array = snap_grid[y]
			for x in range(GRID_SIZE.x):
				var cell_dict := {
					"layers": [
						{"type": LayerType.EMPTY, "durability": 0, "revealed": false},
						{"type": LayerType.EMPTY, "durability": 0, "revealed": false},
						{"type": LayerType.EMPTY, "durability": 0, "revealed": false}
					],
					"current_layer": 0,
					"had_stone": false,
					"stone_broken": false
				}
				if x < srow.size():
					var scell: Dictionary = srow[x]
					var slayers: Array = scell.get("layers", [])
					for li in range(min(3, slayers.size())):
						var sl: Dictionary = slayers[li]
						cell_dict["layers"][li]["type"] = sl.get("type", LayerType.EMPTY)
						cell_dict["layers"][li]["durability"] = sl.get("durability", 0)
						cell_dict["layers"][li]["revealed"] = sl.get("revealed", false)
						# We do not store complex treasure objects in the grid; visuals are driven by treasures list
					cell_dict["current_layer"] = scell.get("current_layer", 0)
					cell_dict["had_stone"] = scell.get("had_stone", false)
					cell_dict["stone_broken"] = scell.get("stone_broken", false)
				row.append(cell_dict)
		grid.append(row)

	# Rebuild visuals
	create_grid_visuals()

	# Reconstruct treasures list
	treasures = []
	var tlist: Array = state.get("treasures", [])
	for tsnap in tlist:
		var item_id: String = String(tsnap.get("item_id", ""))
		var item = _resolve_item_by_id(item_id)
		var top_left: Vector2i = tsnap.get("top_left", Vector2i.ZERO)
		var size: Vector2i = tsnap.get("size", Vector2i(1,1))
		var placed = TreasureGenerator.PlacedTreasure.new(item, top_left, size)
		# Ensure grid_positions exactly match snapshot
		placed.grid_positions.clear()
		for gp in tsnap.get("grid_positions", []):
			placed.grid_positions.append(Vector2i(gp.x, gp.y))
		treasures.append({
			"visual": null,
			"placed_treasure": placed,
			"revealed": false
		})

	# Create visuals for any crystals/gems that have revealed treasure cells
	var cell_size_v := get_actual_cell_size()
	var parent_container_v: Control = $MainContainer/MainGameArea/GridContainer
	for t in treasures:
		var placed_treasure = t["placed_treasure"]
		var any_revealed := false
		for gp in placed_treasure.grid_positions:
			var cx = gp.x
			var cy = gp.y
			var has_stone = grid[cy][cx]["layers"][0]["type"] == LayerType.STONE
			var treasure_layer = 2 if has_stone else 1
			if grid[cy][cx]["layers"][treasure_layer]["revealed"]:
				any_revealed = true
				break
		if any_revealed and placed_treasure.visual_node == null and TreasureGenerator._is_crystals_gems(placed_treasure.treasure_data):
			var visual_v := TreasureGenerator.create_treasure_visual(placed_treasure, cell_size_v, parent_container_v)
			if visual_v != null:
				visual_v.position = calculate_cell_position(placed_treasure.top_left.x, placed_treasure.top_left.y)
				parent_container_v.add_child(visual_v)
				parent_container_v.move_child(visual_v, parent_container_v.get_child_count() - 1)
	normalize_grid_layering()

	# IMPORTANT: Now that treasures have been reconstructed, force-refresh all cells so
	# non-crystal treasure cells render their category color (this relies on 'treasures').
	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			update_cell_visual(x, y)

	# Restore simple state
	current_durability = clamp(state.get("current_durability", max_durability), 0.0, max_durability)
	update_durability_display()
	# Default to pickaxe on resume and update UI highlight
	current_tool = ToolType.PICKAXE
	set_current_tool(current_tool)

	# Announce open (optional)
	Signals.emit_minigame_opened()
