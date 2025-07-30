extends Node
# This file contains all the mining item data in a single place
# No need for resource generation or importing - just pure data

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

# Master list of all mining items
var all_items: Array[MiningItem] = [
	# Format: ID, Name, Category, Price, Weight, StartRange, EndRange, Locations, Flavor
	MiningItem.new("001", "Amethyst", "crystals_gems", 70.0, 65, 1, 65, [1, 2], ""),
	MiningItem.new("002", "Ruby", "crystals_gems", 74.0, 62, 66, 127, [1, 2], ""),
	MiningItem.new("003", "Sapphire", "crystals_gems", 78.0, 57, 128, 184, [1, 2], ""),
	MiningItem.new("004", "Emerald", "crystals_gems", 82.0, 52, 185, 236, [1, 2], ""),
	MiningItem.new("005", "Diamond", "crystals_gems", 25.0, 65, 237, 301, [1], "\"All my homies hate diamonds.\""),
	MiningItem.new("006", "Topaz", "crystals_gems", 92.0, 45, 302, 346, [2], ""),
	MiningItem.new("007", "Selenite", "crystals_gems", 64.0, 68, 347, 414, [1, 2], ""),
	MiningItem.new("008", "Quartz", "crystals_gems", 83.0, 48, 415, 462, [2], ""),
	MiningItem.new("009", "Rose Quartz", "crystals_gems", 94.0, 44, 463, 506, [2], "\"Slightly better than diamonds.\""),
	MiningItem.new("010", "Opal", "crystals_gems", 120.0, 20, 507, 526, ["all"], ""),
	MiningItem.new("011", "Garnet", "crystals_gems", 75.0, 60, 527, 586, [1, 2], ""),
	MiningItem.new("012", "Titanite", "crystals_gems", 96.0, 30, 587, 616, [2, 3], ""),
	MiningItem.new("013", "Alexandrite", "crystals_gems", 240.0, 8, 617, 624, [3], "\"Keep away from Gobbies.\""),
	MiningItem.new("014", "Moonstone", "crystals_gems", 99.0, 45, 625, 669, [2], ""),
	MiningItem.new("015", "Jade", "crystals_gems", 50.0, 23, 670, 692, [], ""),
	MiningItem.new("016", "Citrine", "crystals_gems", 55.0, 25, 693, 717, [], ""),
	MiningItem.new("017", "Agate", "crystals_gems", 45.0, 70, 718, 787, [], ""),
	MiningItem.new("018", "Fire Agate", "crystals_gems", 85.0, 45, 788, 832, [], ""),
	MiningItem.new("019", "Moss Agate", "crystals_gems", 65.0, 60, 833, 892, [], "")
]

# Dictionary for quick lookup by ID
var items_by_id: Dictionary = {}

func _ready():
	# Populate the lookup dictionary
	for item in all_items:
		items_by_id[item.id] = item

# Get a random mining item based on the specified mine location
func get_random_item(mine_id: int) -> MiningItem:
	# Find the maximum range value
	var total_range = 0
	for item in all_items:
		if item.can_appear_in_mine(mine_id) and item.end_range > total_range:
			total_range = item.end_range
	
	# Generate a random roll within the range
	var roll = randi_range(1, total_range)
	
	# Find which item this roll corresponds to
	for item in all_items:
		if item.can_appear_in_mine(mine_id) and roll >= item.start_range and roll <= item.end_range:
			return item
	
	# Fallback (should never happen if ranges are contiguous)
	return all_items[0]

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
		if item.can_appear_in_mine(mine_id):
			result.append(item)
	return result
