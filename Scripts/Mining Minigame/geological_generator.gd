class_name GeologicalGenerator
extends RefCounted

# Formation types and their characteristics
enum FormationType {
	HORIZONTAL_VEINS,
	STONE_BLOBS,
	SCATTERED_STONES,
	THICK_STRATA,
	ANGULAR_SLABS,
	STEPPED_TERRACES,
	CORNER_SLABS,
	EDGE_FRAME
}

# Minimum stone coverage guardrail (as fraction of total cells)
const MIN_STONE_COVERAGE: float = 0.40  # 40% default; tweak to 0.20–0.30 as desired
const COVERAGE_POSTPASS_MAX_ITERS: int = 8

# Hard caps: max fraction of cells any single formation may newly contribute
const MAX_FRACTION_PER_FORMATION := {
	FormationType.HORIZONTAL_VEINS: 0.16,
	FormationType.STONE_BLOBS: 0.14,
	FormationType.SCATTERED_STONES: 0.06,
	FormationType.THICK_STRATA: 0.18,
	FormationType.ANGULAR_SLABS: 0.10,
	FormationType.STEPPED_TERRACES: 0.12,
	FormationType.CORNER_SLABS: 0.10,
	FormationType.EDGE_FRAME: 0.12,
}

# Utility to check if a cell is already stone (top layer)
static func _is_stone_cell(grid: Array, x: int, y: int) -> bool:
	return grid[y][x]["layers"][0]["type"] == 0

# Configuration for each formation type
class FormationConfig:
	var type: FormationType
	var weight: float  # Probability of being selected
	var min_count: int
	var max_count: int
	var intensity: float  # How prominent this formation should be
	
	func _init(t: FormationType, w: float, min_c: int, max_c: int, i: float = 1.0):
		type = t
		weight = w
		min_count = min_c
		max_count = max_c
		intensity = i

# Main generation coordinator
static func generate_formations(grid: Array, grid_size: Vector2i, place_stone_callback: Callable) -> void:
	print("\n=== GEOLOGICAL FORMATION GENERATION ===")
	print("Grid Size: %dx%d" % [grid_size.x, grid_size.y])
	
	# Define available formations with BALANCED parameters for good stone coverage
	var available_formations = [
		FormationConfig.new(FormationType.HORIZONTAL_VEINS, 0.8, 1, 2, randf_range(0.8, 1.1)),    # Increased intensity: 0.8-1.1
		FormationConfig.new(FormationType.STONE_BLOBS, 0.7, 2, 4, randf_range(0.9, 1.2)),        # Increased count: 2-4, intensity: 0.9-1.2
		FormationConfig.new(FormationType.SCATTERED_STONES, 0.6, 8, 12, randf_range(0.6, 0.8)),  # Increased count: 8-12, intensity: 0.6-0.8
		FormationConfig.new(FormationType.THICK_STRATA, 0.4, 1, 1, randf_range(0.8, 1.0)),       # Increased intensity: 0.8-1.0
		FormationConfig.new(FormationType.ANGULAR_SLABS, 0.3, 1, 2, randf_range(0.7, 1.0)),      # Increased intensity: 0.7-1.0
		FormationConfig.new(FormationType.STEPPED_TERRACES, 0.25, 1, 1, randf_range(0.8, 1.1)),  # Increased intensity: 0.8-1.1
		FormationConfig.new(FormationType.CORNER_SLABS, 0.5, 1, 2, randf_range(0.8, 1.1)),       # Common corner coverage
		FormationConfig.new(FormationType.EDGE_FRAME, 0.7, 1, 1, randf_range(0.9, 1.1))          # Common edge framing
	]
	
	# Randomly select which formations to use (2-4 types for better coverage)
	var target_formation_count = randi_range(2, 4)
	var selected_formations = select_random_formations(available_formations, target_formation_count)
	
	# Guardrail: if only 2 were selected and one is Scattered Stones (a light filler),
	# ensure we also include at least one macro formation (Veins/Blobs/Thick Strata)
	if target_formation_count == 2:
		var has_macro := false
		for f in selected_formations:
			if f.type == FormationType.HORIZONTAL_VEINS or f.type == FormationType.STONE_BLOBS or f.type == FormationType.THICK_STRATA:
				has_macro = true
				break
		if not has_macro:
			# Build remaining macro pool excluding already selected
			var remaining_macro := []
			for f in available_formations:
				if (f.type == FormationType.HORIZONTAL_VEINS or f.type == FormationType.STONE_BLOBS or f.type == FormationType.THICK_STRATA) and not selected_formations.has(f):
					remaining_macro.append(f)
			if not remaining_macro.is_empty():
				var extra = select_random_formations(remaining_macro, 1)
				for e in extra:
					selected_formations.append(e)
	
	print("Selected %d formations out of %d available:" % [selected_formations.size(), available_formations.size()])
	for i in range(selected_formations.size()):
		var formation = selected_formations[i]
		var type_name = get_formation_type_name(formation.type)
		print("  %d. %s (weight: %.2f, intensity: %.2f)" % [i+1, type_name, formation.weight, formation.intensity])
	
	# Generate each selected formation 
	for formation in selected_formations:
		match formation.type:
			FormationType.HORIZONTAL_VEINS:
				generate_horizontal_veins(grid, grid_size, formation, place_stone_callback)
			FormationType.STONE_BLOBS:
				generate_stone_blobs(grid, grid_size, formation, place_stone_callback)
			FormationType.SCATTERED_STONES:
				generate_scattered_stones(grid, grid_size, formation, place_stone_callback)
			FormationType.THICK_STRATA:
				generate_thick_strata(grid, grid_size, formation, place_stone_callback)
			FormationType.ANGULAR_SLABS:
				generate_angular_slabs(grid, grid_size, formation, place_stone_callback)
			FormationType.STEPPED_TERRACES:
				generate_stepped_terraces(grid, grid_size, formation, place_stone_callback)
			FormationType.CORNER_SLABS:
				generate_corner_slabs(grid, grid_size, formation, place_stone_callback)
			FormationType.EDGE_FRAME:
				generate_edge_frame(grid, grid_size, formation, place_stone_callback)

	# Post-pass: enforce minimum stone coverage
	var coverage = _compute_stone_coverage(grid, grid_size)
	print("Stone coverage after formations: %.1f%%" % [coverage * 100.0])
	var iters = 0
	while coverage < MIN_STONE_COVERAGE and iters < COVERAGE_POSTPASS_MAX_ITERS:
		iters += 1
		# Add a medium-strength blob and a round of scattered stones to boost coverage naturally
		var boost_blob_cfg := FormationConfig.new(FormationType.STONE_BLOBS, 1.0, 1, 2, randf_range(0.9, 1.15))
		generate_stone_blobs(grid, grid_size, boost_blob_cfg, place_stone_callback)
		var boost_scatter_cfg := FormationConfig.new(FormationType.SCATTERED_STONES, 1.0, 6, 10, randf_range(0.6, 0.8))
		generate_scattered_stones(grid, grid_size, boost_scatter_cfg, place_stone_callback)
		coverage = _compute_stone_coverage(grid, grid_size)
		print("  → Coverage boost #%d → %.1f%%" % [iters, coverage * 100.0])

	print("Final stone coverage: %.1f%% (min target: %.0f%%)" % [coverage * 100.0, MIN_STONE_COVERAGE * 100.0])

# Select random formations based on weighted probability
static func select_random_formations(available: Array, target_count: int) -> Array:
	var selected = []
	var remaining = available.duplicate()
	
	for i in range(target_count):
		if remaining.is_empty():
			break
			
		# Weighted random selection
		var total_weight = 0.0
		for formation in remaining:
			total_weight += formation.weight
		
		var random_value = randf() * total_weight
		var current_weight = 0.0
		
		for j in range(remaining.size()):
			current_weight += remaining[j].weight
			if random_value <= current_weight:
				selected.append(remaining[j])
				remaining.remove_at(j)
				break
	
	return selected

# Helper function to get readable formation type names
static func get_formation_type_name(type: FormationType) -> String:
	match type:
		FormationType.HORIZONTAL_VEINS:
			return "Horizontal Veins"
		FormationType.STONE_BLOBS:
			return "Stone Blobs"
		FormationType.SCATTERED_STONES:
			return "Scattered Stones"
		FormationType.THICK_STRATA:
			return "Thick Strata"
		FormationType.ANGULAR_SLABS:
			return "Angular Slabs"
		FormationType.STEPPED_TERRACES:
			return "Stepped Terraces"
		FormationType.CORNER_SLABS:
			return "Corner Slabs"
		FormationType.EDGE_FRAME:
			return "Edge Frame"
		_:
			return "Unknown Formation"

# Enhanced horizontal veins with variable intensity
static func generate_horizontal_veins(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_veins = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Horizontal Veins (intensity: %.2f)" % [num_veins, config.intensity])
	
	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.HORIZONTAL_VEINS] * grid_size.x * grid_size.y)
	var painted := 0
	
	for i in range(num_veins):
		if painted >= budget:
			break
		var center_y = randi_range(1, grid_size.y - 2)
		var thickness = randi_range(1, max(1, int(3 * config.intensity)))
		
		# Variable width based on intensity (with proper bounds checking)
		var start_x = randi_range(0, max(0, int(grid_size.x / 3.0)))
		var end_x = randi_range(min(grid_size.x - 1, int(grid_size.x * 2.0 / 3.0)), grid_size.x - 1)
		# Ensure start_x <= end_x
		if start_x > end_x:
			var temp = start_x
			start_x = end_x
			end_x = temp
		
		for y in range(max(0, center_y - int(thickness / 2.0)), min(grid_size.y, center_y + int(thickness / 2.0) + 1)):
			for x in range(start_x, end_x + 1):
				if painted >= budget:
					break
				var edge_fade = min(x - start_x, end_x - x)
				var place_probability = 0.75 * config.intensity
				if edge_fade < 2:
					place_probability = 0.5 * config.intensity
				elif edge_fade < 4:
					place_probability = 0.65 * config.intensity
				if randf() < place_probability and not _is_stone_cell(_grid, x, y):
					place_stone_callback.call(x, y)
					painted += 1

# Enhanced stone blobs with variable size and density
static func generate_stone_blobs(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_blobs = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Stone Blobs (intensity: %.2f)" % [num_blobs, config.intensity])
	
	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.STONE_BLOBS] * grid_size.x * grid_size.y)
	var painted := 0
	
	for i in range(num_blobs):
		if painted >= budget:
			break
		var center_x = randi_range(2, grid_size.x - 3)
		var center_y = randi_range(2, grid_size.y - 3)
		var radius = randf_range(1.5 * config.intensity, 3.5 * config.intensity)
		
		for y in range(max(0, center_y - int(radius) - 1), min(grid_size.y, center_y + int(radius) + 2)):
			for x in range(max(0, center_x - int(radius) - 1), min(grid_size.x, center_x + int(radius) + 2)):
				if painted >= budget:
					break
				var distance = Vector2(x - center_x, y - center_y).length()
				
				var place_probability = 0.0
				if distance <= radius * 0.5:
					place_probability = 0.9 * config.intensity
				elif distance <= radius * 0.8:
					place_probability = 0.65 * config.intensity
				elif distance <= radius:
					place_probability = 0.35 * config.intensity
				elif distance <= radius * 1.2:
					place_probability = 0.12 * config.intensity
				
				if randf() < place_probability and not _is_stone_cell(_grid, x, y):
					place_stone_callback.call(x, y)
					painted += 1

# Scattered stones with variable density
static func generate_scattered_stones(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_scattered = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Scattered Stones (intensity: %.2f)" % [num_scattered, config.intensity])
	
	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.SCATTERED_STONES] * grid_size.x * grid_size.y)
	var painted := 0
	
	for i in range(num_scattered):
		if painted >= budget:
			break
		var x = randi_range(0, grid_size.x - 1)
		var y = randi_range(0, grid_size.y - 1)
		
		if randf() < (0.55 * config.intensity) and not _is_stone_cell(_grid, x, y):
			place_stone_callback.call(x, y)
			painted += 1

# NEW: Thick geological strata (multi-row bands)
static func generate_thick_strata(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_strata = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Thick Strata (intensity: %.2f)" % [num_strata, config.intensity])
	
	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.THICK_STRATA] * grid_size.x * grid_size.y)
	var painted := 0
	
	for i in range(num_strata):
		if painted >= budget:
			break
		var center_y = randi_range(2, max(2, grid_size.y - 3))
		var thickness = randi_range(3, max(3, int(5 * config.intensity)))  # Slightly softer
		
		# Span limited to 45–85% of width, with per-row jitter to avoid perfect rectangles
		var span = randi_range(int(grid_size.x * 0.45), int(grid_size.x * 0.85))
		var start_x = randi_range(0, grid_size.x - span)
		var end_x = start_x + span - 1
		
		for y in range(max(0, center_y - int(thickness / 2.0)), min(grid_size.y, center_y + int(thickness / 2.0) + 1)):
			# jitter edges row-by-row
			var row_start = max(0, start_x + randi_range(0, 2))
			var row_end = min(grid_size.x - 1, end_x - randi_range(0, 2))
			for x in range(row_start, row_end + 1):
				if painted >= budget:
					break
				# Softer fill with small holes
				if randf() < (0.75 * config.intensity) and not _is_stone_cell(_grid, x, y):
					place_stone_callback.call(x, y)
					painted += 1

# NEW: Angular rectangular/diamond formations
static func generate_angular_slabs(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_slabs = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Angular Slabs (intensity: %.2f)" % [num_slabs, config.intensity])
	
	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.ANGULAR_SLABS] * grid_size.x * grid_size.y)
	var painted := 0
	
	for i in range(num_slabs):
		if painted >= budget:
			break
		var center_x = randi_range(3, max(3, grid_size.x - 4))
		var center_y = randi_range(3, max(3, grid_size.y - 4))
		
		var width = randi_range(3, max(3, int(6 * config.intensity)))
		var height = randi_range(2, max(2, int(4 * config.intensity)))
		
		# Create rectangular formation
		for y in range(max(0, center_y - int(height / 2.0)), min(grid_size.y, center_y + int(height / 2.0) + 1)):
			for x in range(max(0, center_x - int(width / 2.0)), min(grid_size.x, center_x + int(width / 2.0) + 1)):
				if painted >= budget:
					break
				if randf() < (0.7 * config.intensity) and not _is_stone_cell(_grid, x, y):
					place_stone_callback.call(x, y)
					painted += 1

# NEW: Stepped terraces (staggered horizontal layers)
static func generate_stepped_terraces(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_terraces = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Stepped Terraces (intensity: %.2f)" % [num_terraces, config.intensity])
	
	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.STEPPED_TERRACES] * grid_size.x * grid_size.y)
	var painted := 0
	
	for i in range(num_terraces):
		if painted >= budget:
			break
		var start_y = randi_range(1, max(1, grid_size.y - 6))
		var steps = randi_range(2, 4)
		var step_width = randi_range(3, max(3, int(8 * config.intensity)))
		
		# Ensure step_width doesn't exceed grid width
		step_width = min(step_width, grid_size.x - 1)
		var current_x = randi_range(0, max(0, grid_size.x - step_width - 1))
		
		for step in range(steps):
			var step_y = start_y + step * 2  # 2 rows per step
			if step_y >= grid_size.y - 1:
				break
				
			# Create horizontal step
			for x in range(current_x, min(grid_size.x, current_x + step_width)):
				for y in range(step_y, min(grid_size.y, step_y + 2)):
					if painted >= budget:
						break
					if randf() < (0.75 * config.intensity) and not _is_stone_cell(_grid, x, y):
						place_stone_callback.call(x, y)
						painted += 1
			
			# Offset next step slightly
			current_x += randi_range(-2, 3)
			current_x = max(0, min(current_x, grid_size.x - step_width))

# NEW: Corner slabs growing inward from grid corners
static func generate_corner_slabs(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_slabs = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Corner Slabs (intensity: %.2f)" % [num_slabs, config.intensity])
	
	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.CORNER_SLABS] * grid_size.x * grid_size.y)
	var painted := 0
	
	# Define corner anchors
	var corners: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(grid_size.x - 1, 0),
		Vector2i(0, grid_size.y - 1),
		Vector2i(grid_size.x - 1, grid_size.y - 1)
	]
	
	for i in range(num_slabs):
		if painted >= budget:
			break
		var anchor: Vector2i = corners[randi() % corners.size()]
		var is_left: bool = anchor.x == 0
		var is_top: bool = anchor.y == 0
		
		# Size as a fraction of grid with randomness; tends to be compact but noticeable
		var max_w = int(clamp(grid_size.x * randf_range(0.25, 0.55) * config.intensity, 3.0, grid_size.x * 0.7))
		var max_h = int(clamp(grid_size.y * randf_range(0.25, 0.55) * config.intensity, 3.0, grid_size.y * 0.7))
		var width = randi_range(3, max(3, max_w))
		var height = randi_range(3, max(3, max_h))
		
		# Starting rectangle from the corner, extend inward
		var start_x = 0 if is_left else max(0, grid_size.x - width)
		var start_y = 0 if is_top else max(0, grid_size.y - height)
		var end_x = min(grid_size.x - 1, start_x + width - 1)
		var end_y = min(grid_size.y - 1, start_y + height - 1)
		
		for y in range(start_y, end_y + 1):
			# inward jitter trims to avoid perfect rectangles
			var trim_x = randi_range(0, 2)
			var row_start = start_x + trim_x if is_left else start_x
			var row_end = end_x if is_left else max(start_x, end_x - trim_x)
			for x in range(row_start, row_end + 1):
				if painted >= budget:
					break
				var _edge_bias := 0.7 * config.intensity
				# Slightly higher density near the outermost edge fading inward
				var inward_dist = (x - start_x if is_left else end_x - x) + (y - start_y if is_top else end_y - y)
				var place_probability = clamp(0.75 * config.intensity - 0.04 * inward_dist, 0.35, 0.8)
				if randf() < place_probability and not _is_stone_cell(_grid, x, y):
					place_stone_callback.call(x, y)
					painted += 1
		
		# Optional: small corner nibble to make it feel natural
		if painted < budget and randf() < 0.5:
			var nibble_w = randi_range(1, min(3, width))
			var nibble_h = randi_range(1, min(3, height))
			var nibble_start_x = start_x
			var nibble_start_y = start_y
			for y in range(nibble_start_y, min(grid_size.y, nibble_start_y + nibble_h)):
				for x in range(nibble_start_x, min(grid_size.x, nibble_start_x + nibble_w)):
					if painted >= budget:
						break
					if randf() < 0.5 and not _is_stone_cell(_grid, x, y):
						place_stone_callback.call(x, y)
						painted += 1

# NEW: Edge frame generator – biases stone along all borders with inward falloff
static func generate_edge_frame(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_frames = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Edge Frame (intensity: %.2f)" % [num_frames, config.intensity])

	var budget := int(MAX_FRACTION_PER_FORMATION[FormationType.EDGE_FRAME] * grid_size.x * grid_size.y)
	var painted := 0

	# How far inward the frame can extend
	var max_band = int(ceil(min(grid_size.x, grid_size.y) * 0.25 * config.intensity))
	max_band = max(2, max_band)

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			if painted >= budget:
				break
			var dist_left = x
			var dist_right = grid_size.x - 1 - x
			var dist_top = y
			var dist_bottom = grid_size.y - 1 - y
			var d = min(min(dist_left, dist_right), min(dist_top, dist_bottom))

			if d > max_band:
				continue

			# Probability decreases as we move inward from the edge
			var base = 0.85 * config.intensity
			var decay = 0.12 * float(d)
			var jitter = randf_range(-0.05, 0.05)
			var p = clamp(base - decay + jitter, 0.15, 0.95)

			if randf() < p and not _is_stone_cell(_grid, x, y):
				place_stone_callback.call(x, y)
				painted += 1

# Utility: compute current stone coverage (top layer stone only)
static func _compute_stone_coverage(grid: Array, grid_size: Vector2i) -> float:
	var stone_cells := 0
	var total_cells := grid_size.x * grid_size.y
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			# Our grid stores layer types using LayerType enum from mining_minigame.gd
			# We cannot import it here, so compare by integer: 0=STONE in that enum definition
			if grid[y][x]["layers"][0]["type"] == 0:
				stone_cells += 1
	return float(stone_cells) / float(total_cells)
