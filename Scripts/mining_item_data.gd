class_name MiningItemData
extends Resource

## This Resource class represents a single item in the mining loot table

# Basic item properties
@export var id: String = ""
@export var name: String = ""
@export var category: String = ""

# Economic properties
@export var base_price: float = 0.0

# Rarity/generation properties
@export var base_weight: int = 0
@export var start_range: int = 0
@export var end_range: int = 0

# Game design properties
@export var mine_locations: Array[int] = []
@export_multiline var flavor_text: String = ""

# Visual properties (to be added later)
# @export var texture: Texture2D
# @export var grid_size: Vector2i = Vector2i(1, 1)  # How many grid cells this item occupies

# Helper function to check if this item can appear in a specific mine
func can_appear_in_mine(mine_id: int) -> bool:
    # If mine_locations is empty or contains "all", item can appear in any mine
    if mine_locations.is_empty() or mine_locations.has(0):
        return true
    
    # Otherwise, check if the specific mine ID is in the list
    return mine_locations.has(mine_id)
