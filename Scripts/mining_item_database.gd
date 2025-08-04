extends Node
# This file contains all the mining item data in a single place
# No need for resource generation or importing - just pure data

# Path to the JSON data file
const ITEMS_DATA_PATH = "res://Data/mining_items.json"

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
func get_random_item(mine_id: int) -> MiningItem:
	# Find the maximum range value
	var total_range = 0
	for item in all_items:
		if can_appear_in_mine(item.mine_locations, mine_id) and item.end_range > total_range:
			total_range = item.end_range
	
	# Generate a random roll within the range
	var roll = randi_range(1, total_range)
	
	# Find which item this roll corresponds to
	for item in all_items:
		if can_appear_in_mine(item.mine_locations, mine_id) and roll >= item.start_range and roll <= item.end_range:
			return item
	
	# Fallback (should never happen if ranges are contiguous)
	return all_items[0] if all_items.size() > 0 else null

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
