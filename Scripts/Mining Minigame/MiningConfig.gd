class_name MiningConfig
extends Resource

# Visual settings
@export var cell_size: Vector2 = Vector2(50, 50)
@export var min_cell_size: Vector2 = Vector2(30, 30)
@export var treasure_size_multiplier: float = 0.8
@export var cell_opacity_min: float = 0.3
@export var border_opacity: float = 0.5

# Grid settings
@export var grid_size: Vector2i = Vector2i(17, 10)
@export var use_fixed_cell_size: bool = true

# Color settings
@export var color_dirt: Color = Color(0.6, 0.4, 0.2)
@export var color_stone: Color = Color(0.48, 0.48, 0.48)
@export var color_empty: Color = Color(0.2, 0.2, 0.2)
@export var color_treasure_bg: Color = Color(0.8, 0.7, 0.2)
@export var color_treasure_rock: Color = Color(0.28, 0.28, 0.28)
@export var color_treasure_metal: Color = Color(0.95, 0.55, 0.20)
@export var color_treasure_gem: Color = Color(0.60, 0.85, 1.00)
@export var color_border: Color = Color(0.3, 0.3, 0.3)

# Game settings
@export var max_durability: int = 100
@export var pickaxe_base_cost: float = 1.0
@export var hammer_base_cost_percent: float = 2.0
@export var hammer_per_cell_cost_percent: float = 0.5
@export var hammer_max_cost_percent: float = 5.0
@export var min_treasures: int = 3
@export var max_treasures: int = 10

# Tool damage settings
@export var pickaxe_damage: Dictionary = {
    LayerType.STONE: 100,
    LayerType.DIRT: 100
}

@export var hammer_damage: Dictionary = {
    LayerType.STONE: 100,
    LayerType.DIRT: 100
}

# Layer types
enum LayerType { STONE, DIRT, TREASURE, EMPTY }

# Tool types
enum ToolType { PICKAXE, HAMMER }
