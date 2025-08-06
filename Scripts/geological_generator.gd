class_name GeologicalGenerator
extends RefCounted

# Formation types and their characteristics
enum FormationType {
	HORIZONTAL_VEINS,
	STONE_BLOBS,
	SCATTERED_STONES,
	THICK_STRATA,
	ANGULAR_SLABS,
	STEPPED_TERRACES
}

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
		FormationConfig.new(FormationType.STEPPED_TERRACES, 0.25, 1, 1, randf_range(0.8, 1.1))   # Increased intensity: 0.8-1.1
	]
	
	# Randomly select which formations to use (2-4 types for better coverage)
	var target_formation_count = randi_range(2, 4)
	var selected_formations = select_random_formations(available_formations, target_formation_count)
	
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
		_:
			return "Unknown Formation"

# Enhanced horizontal veins with variable intensity
static func generate_horizontal_veins(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_veins = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Horizontal Veins (intensity: %.2f)" % [num_veins, config.intensity])
	
	for i in range(num_veins):
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
				var edge_fade = min(x - start_x, end_x - x)
				var place_probability = 0.9 * config.intensity
				
				if edge_fade < 2:
					place_probability = 0.6 * config.intensity
				elif edge_fade < 4:
					place_probability = 0.8 * config.intensity
				
				if randf() < place_probability:
					place_stone_callback.call(x, y)

# Enhanced stone blobs with variable size and density
static func generate_stone_blobs(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_blobs = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Stone Blobs (intensity: %.2f)" % [num_blobs, config.intensity])
	
	for i in range(num_blobs):
		var center_x = randi_range(2, grid_size.x - 3)
		var center_y = randi_range(2, grid_size.y - 3)
		var radius = randf_range(1.5 * config.intensity, 3.5 * config.intensity)
		
		for y in range(max(0, center_y - int(radius) - 1), min(grid_size.y, center_y + int(radius) + 2)):
			for x in range(max(0, center_x - int(radius) - 1), min(grid_size.x, center_x + int(radius) + 2)):
				var distance = Vector2(x - center_x, y - center_y).length()
				
				var place_probability = 0.0
				if distance <= radius * 0.5:
					place_probability = 0.95 * config.intensity
				elif distance <= radius * 0.8:
					place_probability = 0.7 * config.intensity
				elif distance <= radius:
					place_probability = 0.4 * config.intensity
				elif distance <= radius * 1.2:
					place_probability = 0.15 * config.intensity
				
				if randf() < place_probability:
					place_stone_callback.call(x, y)

# Scattered stones with variable density
static func generate_scattered_stones(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_scattered = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Scattered Stones (intensity: %.2f)" % [num_scattered, config.intensity])
	
	for i in range(num_scattered):
		var x = randi_range(0, grid_size.x - 1)
		var y = randi_range(0, grid_size.y - 1)
		
		if randf() < (0.6 * config.intensity):
			place_stone_callback.call(x, y)

# NEW: Thick geological strata (multi-row bands)
static func generate_thick_strata(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_strata = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Thick Strata (intensity: %.2f)" % [num_strata, config.intensity])
	
	for i in range(num_strata):
		var center_y = randi_range(2, max(2, grid_size.y - 3))
		var thickness = randi_range(3, max(3, int(6 * config.intensity)))  # Thick bands
		
		# Full width or nearly full width (with bounds checking)
		var start_x = randi_range(0, min(2, grid_size.x - 1))
		var end_x = randi_range(max(start_x, grid_size.x - 3), grid_size.x - 1)
		
		for y in range(max(0, center_y - int(thickness / 2.0)), min(grid_size.y, center_y + int(thickness / 2.0) + 1)):
			for x in range(start_x, end_x + 1):
				# Very high probability for thick strata
				if randf() < (0.95 * config.intensity):
					place_stone_callback.call(x, y)

# NEW: Angular rectangular/diamond formations
static func generate_angular_slabs(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_slabs = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Angular Slabs (intensity: %.2f)" % [num_slabs, config.intensity])
	
	for i in range(num_slabs):
		var center_x = randi_range(3, max(3, grid_size.x - 4))
		var center_y = randi_range(3, max(3, grid_size.y - 4))
		
		var width = randi_range(3, max(3, int(7 * config.intensity)))
		var height = randi_range(2, max(2, int(5 * config.intensity)))
		
		# Create rectangular formation
		for y in range(max(0, center_y - int(height / 2.0)), min(grid_size.y, center_y + int(height / 2.0) + 1)):
			for x in range(max(0, center_x - int(width / 2.0)), min(grid_size.x, center_x + int(width / 2.0) + 1)):
				if randf() < (0.85 * config.intensity):
					place_stone_callback.call(x, y)

# NEW: Stepped terraces (staggered horizontal layers)
static func generate_stepped_terraces(_grid: Array, grid_size: Vector2i, config: FormationConfig, place_stone_callback: Callable):
	var num_terraces = randi_range(config.min_count, config.max_count)
	print("  → Generating %d Stepped Terraces (intensity: %.2f)" % [num_terraces, config.intensity])
	
	for i in range(num_terraces):
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
					if randf() < (0.8 * config.intensity):
						place_stone_callback.call(x, y)
			
			# Offset next step slightly
			current_x += randi_range(-2, 3)
			current_x = max(0, min(current_x, grid_size.x - step_width))
