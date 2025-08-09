extends Node
# This file contains all the mining item data in a single place
# No need for resource generation or importing - just pure data

# Path to the JSON data file (match actual case-sensitive path)
const ITEMS_DATA_PATH = "res://data/mining_items.json"

# Class to represent a mining item
class MiningItem:
	var id: String
	var name: String
	var category: String
	var base_price: float
	var base_weight: int
	var start_range: int
	var end_range: int
	var mine_locations: Array[int]
	var flavor_text: String
	
	func _init(p_id: String, p_name: String, p_category: String, p_price: float, 
			p_weight: int, p_start: int, p_end: int, p_locations: Array, p_flavor: String = ""):
		id = p_id
		name = p_name
		category = p_category
		base_price = p_price
		base_weight = p_weight
		start_range = p_start
		end_range = p_end
		# Convert string locations to ints if needed
		mine_locations = []
		for loc in p_locations:
			if loc is String and loc.to_lower() == "all":
				mine_locations = [0]  # 0 represents "all" locations
				break
			elif loc is int:
				mine_locations.append(loc)
			elif loc is float:
				# JSON parser returns floats, convert to int
				mine_locations.append(int(loc))
			elif loc is String and loc.strip_edges().is_valid_int():
				mine_locations.append(int(loc.strip_edges()))
		flavor_text = p_flavor
	
	# Helper function to check if this item can appear in a specific mine
	func can_appear_in_mine(mine_id: int) -> bool:
		# If the locations array contains the string "all", it can appear in any mine
		if "all" in mine_locations:
			return true
			
		# Otherwise, check if the specific mine ID is in the list
		return mine_id in mine_locations

# Helper function to check if an item can appear in a specific mine
func can_appear_in_mine(mine_locations: Array, mine_id: int) -> bool:
	# If mine_locations is empty, item can appear in any mine (universal items)
	if mine_locations.is_empty():
		return true
	
	# Check each location in the array
	for location in mine_locations:
		# Check for "all" indicator (0 means all mines)
		if location == 0:
			return true
		# Check for string "all" (in case someone uses this format)
		if typeof(location) == TYPE_STRING and location == "all":
			return true
		# Check if the specific mine ID matches
		if location == mine_id:
			return true
	
	# No match found
	return false

# Master list of all mining items (loaded from JSON)
var all_items: Array[MiningItem] = []

# Dictionary for quick lookup by ID
var items_by_id: Dictionary = {}

# Optional category weighting (future-proofing)
# Loaded from JSON top-level keys:
# - "category_weights": { category: weight }
# - "category_weights_by_mine": { mine_id_string: { category: weight } }
var global_category_weights: Dictionary = {}
var per_mine_category_weights: Dictionary = {}

func _ready():
	load_items_from_json()
	
	# Populate the lookup dictionary
	for item in all_items:
		items_by_id[item.id] = item
	
	print("Loaded " + str(all_items.size()) + " mining items from JSON")

# Load items from JSON file
func load_items_from_json():
	var file = FileAccess.open(ITEMS_DATA_PATH, FileAccess.READ)
	if file == null:
		print("ERROR: Could not open mining items data file: " + ITEMS_DATA_PATH)
		print("Creating fallback test data...")
		create_fallback_data()
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("ERROR: Failed to parse JSON data: " + str(parse_result))
		print("Creating fallback test data...")
		create_fallback_data()
		return
	
	var data = json.data
	if not data.has("items"):
		print("ERROR: JSON file missing 'items' array")
		create_fallback_data()
		return
	
	# Load optional category weights if present (safe to be absent)
	global_category_weights = data.get("category_weights", {})
	per_mine_category_weights = data.get("category_weights_by_mine", {})

	# Convert JSON data to MiningItem objects
	for item_data in data["items"]:
		var item = MiningItem.new(
			item_data.get("id", ""),
			item_data.get("name", "Unknown"),
			item_data.get("category", "misc"),
			item_data.get("base_price", 0.0),
			item_data.get("weight", 1),
			item_data.get("start_range", 0),
			item_data.get("end_range", 0),
			item_data.get("mine_locations", []),
			item_data.get("flavor_text", "")
		)
		all_items.append(item)
	
	print("Successfully loaded " + str(all_items.size()) + " items from JSON")

# Helper: get category weight for a given mine with sensible defaults
func _get_category_weight_for_mine(category: String, mine_id: int, eligible_by_cat: Dictionary) -> int:
	# Per-mine override takes priority (mine_id as string key for JSON compatibility)
	var mine_key := str(mine_id)
	if per_mine_category_weights.has(mine_key):
		var mine_weights: Dictionary = per_mine_category_weights[mine_key]
		if mine_weights.has(category):
			return int(mine_weights[category])

	# Global category weight
	if global_category_weights.has(category):
		return int(global_category_weights[category])

	# Fallback: preserve current behavior by using the sum of item weights
	# This makes results identical to the old system when no category weights are provided
	var sum_weight := 0
	if eligible_by_cat.has(category):
		for item in eligible_by_cat[category]:
			sum_weight += max(0, item.base_weight)
	return sum_weight

# Fallback data in case JSON loading fails
func create_fallback_data():
	print("Using hardcoded fallback data...")
	all_items = [
		MiningItem.new("001", "Amethyst", "crystals_gems", 70.0, 65, 1, 65, [1, 2], ""),
		MiningItem.new("002", "Ruby", "crystals_gems", 74.0, 62, 66, 127, [1, 2], ""),
		MiningItem.new("003", "Sapphire", "crystals_gems", 78.0, 57, 128, 184, [1, 2], ""),
		MiningItem.new("004", "Emerald", "crystals_gems", 82.0, 52, 185, 236, [1, 2], ""),
		MiningItem.new("005", "Diamond", "crystals_gems", 25.0, 65, 237, 301, [1], "All my homies hate diamonds.")
	]

# Get a random mining item based on the specified mine location
# Now supports optional category-first weighted selection with full backward compatibility
func get_random_item(mine_id: int) -> MiningItem:
	# Build eligible items grouped by category
	var eligible_by_cat: Dictionary = {}
	for item in all_items:
		if can_appear_in_mine(item.mine_locations, mine_id):
			if not eligible_by_cat.has(item.category):
				eligible_by_cat[item.category] = []
			eligible_by_cat[item.category].append(item)

	# Safety: no eligible categories
	if eligible_by_cat.is_empty():
		return all_items[0] if all_items.size() > 0 else null

	# Determine category weights (respect per-mine and global configs; fallback preserves old behavior)
	var categories: Array = eligible_by_cat.keys()
	var cat_total := 0
	var cat_weights: Dictionary = {}
	for cat in categories:
		var w: int = max(0, _get_category_weight_for_mine(cat, mine_id, eligible_by_cat))
		cat_weights[cat] = w
		cat_total += w

	# If total category weight is zero (e.g., all configured as 0), pick a category uniformly
	var chosen_category: String = ""
	if cat_total <= 0:
		chosen_category = categories[randi() % categories.size()]
	else:
		var roll_cat := randi_range(1, cat_total)
		var acc_cat := 0
		for cat in categories:
			acc_cat += int(cat_weights[cat])
			if roll_cat <= acc_cat:
				chosen_category = cat
				break

	# Select item within chosen category using existing item weights
	# Convert untyped Array from dictionary into a typed Array[MiningItem]
	var src_items: Array = eligible_by_cat[chosen_category]
	var items: Array[MiningItem] = []
	for _it in src_items:
		items.append(_it as MiningItem)
	var item_total := 0
	for it in items:
		item_total += max(0, it.base_weight)

	# If all item weights are zero, choose uniformly; otherwise weighted by base_weight
	if item_total <= 0:
		return items[randi() % items.size()]
	else:
		var roll := randi_range(1, item_total)
		var acc := 0
		for it in items:
			acc += max(0, it.base_weight)
			if roll <= acc:
				return it

	# Fallback (shouldn't happen)
	return items.back()

# Get an item by its ID
func get_item_by_id(id: String) -> MiningItem:
	if items_by_id.has(id):
		return items_by_id[id]
	return null

# Get all items of a specific category
func get_items_by_category(category: String) -> Array[MiningItem]:
	var result: Array[MiningItem] = []
	for item in all_items:
		if item.category == category:
			result.append(item)
	return result

# Get all items available in a specific mine
func get_items_in_mine(mine_id: int) -> Array[MiningItem]:
	var result: Array[MiningItem] = []
	for item in all_items:
		if can_appear_in_mine(item.mine_locations, mine_id):
			result.append(item)
	return result

# Reload items from JSON (useful for development/modding)
func reload_items():
	all_items.clear()
	items_by_id.clear()
	load_items_from_json()
	
	# Repopulate lookup dictionary
	for item in all_items:
		items_by_id[item.id] = item
	
	print("Reloaded " + str(all_items.size()) + " items from JSON")
