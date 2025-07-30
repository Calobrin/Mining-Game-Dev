@tool  # This makes the script run in the editor
extends Node

# This script converts CSV data to Godot Resources
# It only needs to be run once to create all your item resources

# Add this property to show a button in the Inspector
@export var run_import: bool = false:
	set(value):
		if value:
			import_csv_to_resources()
			run_import = false  # Reset the checkbox automatically

# Path to your CSV file
const CSV_PATH = "res://data/Mining Loot Table1.2.csv"
# Where to save the generated resources
const SAVE_DIRECTORY = "res://data/mining_items/"

# Function to run the importer
func import_csv_to_resources() -> void:
	print("Starting CSV import...")
	
	# Ensure the save directory exists
	var dir = DirAccess.open("res://")
	if !dir.dir_exists("data/mining_items"):
		dir.make_dir_recursive("data/mining_items")
	
	# Open and read the CSV file
	var file = FileAccess.open(CSV_PATH, FileAccess.READ)
	if !file:
		push_error("Failed to open CSV file at: " + CSV_PATH)
		return
	
	# Read the header line to get column names
	var headers = file.get_csv_line()
	print("Found headers: ", headers)
	
	# Read each data row and create a resource
	var items_created = 0
	while !file.eof_reached():
		var data = file.get_csv_line()
		# Skip empty lines
		if data.size() <= 1 or data[0].strip_edges() == "":
			continue
			
		# Create a new resource
		var item = create_item_resource(headers, data)
		if item:
			# Save the resource to a file
			var save_path = SAVE_DIRECTORY + item.id + ".tres"
			var err = ResourceSaver.save(item, save_path)
			if err == OK:
				items_created += 1
				print("Saved item: ", item.name)
			else:
				push_error("Failed to save item: " + item.name + ", Error: " + str(err))
	
	print("Import complete! Created " + str(items_created) + " items.")
	
# Create a MiningItemData resource from CSV row
func create_item_resource(headers: PackedStringArray, data: PackedStringArray) -> MiningItemData:
	var item = MiningItemData.new()
	
	# Map CSV columns to resource properties
	for i in range(min(headers.size(), data.size())):
		var column_name = headers[i]
		var value = data[i]
		
		# Skip if value is empty
		if value.strip_edges() == "":
			continue
			
		match column_name:
			"ID":
				item.id = value
			"Name":
				item.name = value
			"Category":
				item.category = value
			"Base_Price":
				# Convert to float, default to 0 if empty
				if value.strip_edges() != "":
					item.base_price = float(value)
			"Base_Weight":
				# Convert to int, default to 0 if empty
				if value.strip_edges() != "":
					item.base_weight = int(value)
			"Start_Range":
				if value.strip_edges() != "":
					item.start_range = int(value)
			"End_Range":
				if value.strip_edges() != "":
					item.end_range = int(value)
			"Mine_Locations":
				# Parse comma-separated list
				if value.strip_edges() != "":
					if value.to_lower() == "all":
						# Use 0 to represent "all" locations
						item.mine_locations = [0]
					else:
						# Split by comma and convert to integers
						var locations = value.split(",")
						for loc in locations:
							var trimmed = loc.strip_edges()
							if trimmed.is_valid_int():
								item.mine_locations.append(int(trimmed))
			"Flavor_Text":
				item.flavor_text = value
	
	return item
