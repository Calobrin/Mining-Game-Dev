class_name MiningGame
extends Node

# Signals
signal game_over(treasures_found: int, total_value: int)
signal durability_changed(normalized_value: float)

# Tool types
enum ToolType { PICKAXE, HAMMER }

# Game settings
const PICKAXE_BASE_COST_PERCENT = 2.0  # 2% of max durability
const HAMMER_BASE_COST_PERCENT = 4.0   # 4% of max durability
const HAMMER_PER_CELL_PERCENT = 1.5    # 1.5% per additional cell
const HAMMER_MAX_COST_PERCENT = 8.0    # Max 8% of max durability

# Dependencies
var config: MiningConfig
var grid: MiningGrid
var ui: MiningUI

# Game state
var current_tool: int = ToolType.PICKAXE
var current_durability: float = 100.0
var max_durability: float = 100.0
var game_active: bool = false
var revealed_count: int = 0
var total_value: int = 0

func _init(p_config: MiningConfig) -> void:
    config = p_config
    grid = MiningGrid.new(config)
    max_durability = config.max_durability
    current_durability = max_durability
    
    # Connect grid signals
    grid.treasure_revealed.connect(_on_treasure_revealed)

func start_game() -> void:
    # Reset game state
    current_durability = config.max_durability
    game_active = true
    revealed_count = 0
    total_value = 0
    
    # Initialize grid and UI
    grid.initialize()
    ui.initialize()
    
    # Update UI
    emit_signal("durability_changed", current_durability / config.max_durability)

func process_cell_hit(x: int, y: int, damage_values: Dictionary, multiplier: float = 1.0) -> Dictionary:
    var result = {
        "layer_broken": false,
        "damage_dealt": 0,
        "durability_cost": 0
    }
    
    if not game_active:
        return result
    
    # Calculate durability cost
    var durability_cost = _calculate_durability_cost(x, y, damage_values, multiplier)
    
    # Check if we can afford the action
    if current_durability < durability_cost and not config.dev_mode_unlimited_durability:
        return result
    
    # Apply durability cost
    if not config.dev_mode_unlimited_durability:
        current_durability -= durability_cost
        emit_signal("durability_changed", current_durability / max_durability)
    
    # Calculate damage based on tool and cell type
    var cell_data = grid.get_cell(x, y)
    if not cell_data:
        return result
        
    var current_layer = cell_data.get_current_layer()
    var damage = damage_values.get(current_layer.type, 0) * multiplier
    
    if damage > 0:
        # Apply damage to the cell
        var layer_broken = grid.damage_cell(x, y, damage)
        result["layer_broken"] = layer_broken
        result["damage_dealt"] = damage
        result["durability_cost"] = durability_cost
        
        # Check for game over if durability is exhausted
        if current_durability <= 0 and not config.dev_mode_unlimited_durability:
            end_game()
    
    return result

func toggle_dev_mode() -> void:
    config.dev_mode_unlimited_durability = !config.dev_mode_unlimited_durability
    if config.dev_mode_unlimited_durability:
        print("DEV MODE ENABLED: Unlimited durability activated!")
    else:
        print("DEV MODE DISABLED: Normal durability restored.")

func _calculate_durability_cost(x: int, y: int, damage_values: Dictionary, multiplier: float) -> float:
    var cost = 0.0
    
    if current_tool == ToolType.PICKAXE:
        # Pickaxe: Fixed cost per use
        cost = max_durability * (PICKAXE_BASE_COST_PERCENT / 100.0)
    else:  # HAMMER
        # Hammer: Base cost + per-cell cost
        var affected_cells = _get_affected_cells(x, y)
        var cell_count = 0
        
        # Count only cells that can be damaged
        for cell in affected_cells:
            var cell_data = grid.get_cell(cell.x, cell.y)
            if cell_data and not cell_data.is_revealed():
                var layer_type = cell_data.get_current_layer_type()
                if damage_values.has(layer_type):
                    cell_count += 1
        
        # Calculate cost with diminishing returns
        var base_cost = max_durability * (HAMMER_BASE_COST_PERCENT / 100.0)
        var additional_cost = 0.0
        
        if cell_count > 1:
            additional_cost = max_durability * (HAMMER_PER_CELL_PERCENT / 100.0) * (cell_count - 1)
        
        cost = min(base_cost + additional_cost, max_durability * (HAMMER_MAX_COST_PERCENT / 100.0))
    
    return cost * multiplier

func _get_affected_cells(x: int, y: int) -> Array:
    # Return a 3x3 area centered on (x, y)
    var cells: Array = []
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            cells.append(Vector2i(x + dx, y + dy))
    return cells

func set_current_tool(tool_type: int) -> void:
    current_tool = tool_type
    # Update UI to show selected tool
    ui.update_tool_selection(tool_type)

func _on_treasure_revealed(treasure_data: Dictionary) -> void:
    revealed_count += 1
    total_value += treasure_data.get("value", 0)
    
    # Update UI
    ui.update_score(revealed_count, total_value)
    
    # Check for win condition (all treasures found)
    if _check_all_treasures_found():
        end_game()

func _check_all_treasures_found() -> bool:
    # Implementation depends on how you track total treasures
    return false  # Placeholder

func end_game() -> void:
    if not game_active:
        return
        
    game_active = false
    emit_signal("game_over", revealed_count, total_value)
    
    # Clean up resources
    if grid:
        grid.cleanup()
    
    # Notify UI to show game over screen
    if ui and ui.has_method("show_game_over"):
        ui.show_game_over(revealed_count, total_value)
    ui.show_results(revealed_count, total_value)

func exit_game() -> void:
    # Clean up resources
    grid.clear()
    queue_free()
