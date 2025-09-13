class_name MiningGrid
extends Node2D

# Signals
#signal cell_clicked(x: int, y: int)
signal treasure_revealed(treasure_data: Dictionary)

# Dependencies
var config: MiningConfig
var ui: Control

# Grid data
var grid = []
var cell_nodes = []
var treasures = []

func _init(p_config: MiningConfig) -> void:
    config = p_config
    
func initialize() -> void:
    _create_empty_grid()
    _generate_terrain()
    _place_treasures()
    
func _create_empty_grid() -> void:
    grid = []
    for y in config.grid_size.y:
        var row = []
        for x in config.grid_size.x:
            row.append({
                "layers": _create_cell_layers(),
                "current_layer": 0,
                "health": 100,
                "revealed": false
            })
        grid.append(row)

func _create_cell_layers() -> Array:
    # Create layers for a cell (stone, dirt, empty/treasure)
    return [
        {"type": config.LayerType.STONE, "health": 100, "revealed": false},
        {"type": config.LayerType.DIRT, "health": 100, "revealed": false},
        {"type": config.LayerType.EMPTY, "health": 0, "revealed": false}
    ]

func _generate_terrain() -> void:
    # Apply different generation algorithms
    _generate_horizontal_veins()
    _generate_stone_blobs()
    _generate_scattered_stones()

func _generate_horizontal_veins() -> void:
    # Implementation for horizontal vein generation
    pass

func _generate_stone_blobs() -> void:
    # Implementation for stone blob generation
    pass

func _generate_scattered_stones() -> void:
    # Implementation for scattered stones
    pass

func _place_treasures() -> void:
    # Place treasures in the grid
    var treasure_count = randi() % (config.max_treasures - config.min_treasures + 1) + config.min_treasures
    
    for _i in range(treasure_count):
        var treasure = _create_treasure()
        if treasure:
            treasures.append(treasure)

func _create_treasure() -> Dictionary:
    # Create a treasure with random position and properties
    # Returns null if no valid position found
    return {}

func hit_cell(x: int, y: int, tool_type: int) -> bool:
    if x < 0 or y < 0 or x >= config.grid_size.x or y >= config.grid_size.y:
        return false
        
    var cell = grid[y][x]
    if cell.revealed:
        return false
        
    # Apply damage based on tool type
    var damage = 0
    match tool_type:
        config.ToolType.PICKAXE:
            damage = _calculate_pickaxe_damage(cell)
        config.ToolType.HAMMER:
            damage = _calculate_hammer_damage(x, y)
            
    return _apply_damage(x, y, damage)

func _calculate_pickaxe_damage(cell: Dictionary) -> int:
    var layer = cell.layers[cell.current_layer]
    return config.pickaxe_damage.get(layer.type, 0)

func _calculate_hammer_damage(center_x: int, center_y: int) -> int:
    # Calculate total damage for 3x3 area
    var total_damage = 0
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            var x = center_x + dx
            var y = center_y + dy
            if x >= 0 and y >= 0 and x < config.grid_size.x and y < config.grid_size.y:
                var cell = grid[y][x]
                if not cell.revealed:
                    total_damage += _calculate_pickaxe_damage(cell)
    return total_damage

func _apply_damage(x: int, y: int, damage: int) -> bool:
    var cell = grid[y][x]
    var layer = cell.layers[cell.current_layer]
    
    layer.health = max(0, layer.health - damage)
    
    if layer.health <= 0:
        layer.revealed = true
        _process_layer_reveal(x, y)
        return true
    return false

func _process_layer_reveal(x: int, y: int) -> void:
    var cell = grid[y][x]
    var layer = cell.layers[cell.current_layer]
    
    if layer.type == config.LayerType.TREASURE:
        emit_signal("treasure_revealed", layer.treasure_data)
    
    # Move to next layer if available
    if cell.current_layer < cell.layers.size() - 1:
        cell.current_layer += 1
    else:
        cell.revealed = true
        
    # Update visual
    update_cell_visual(x, y)

func update_cell_visual(x: int, y: int) -> void:
    if y < 0 or y >= cell_nodes.size() or x < 0 or x >= cell_nodes[0].size():
        return
        
    var cell = grid[y][x]
    var cell_node = cell_nodes[y][x]
    var layer = cell.layers[cell.current_layer]
    
    # Update cell visual based on layer type and state
    match layer.type:
        config.LayerType.STONE:
            cell_node.modulate = config.color_stone
        config.LayerType.DIRT:
            cell_node.modulate = config.color_dirt
        config.LayerType.EMPTY:
            cell_node.modulate = config.color_empty
        config.LayerType.TREASURE:
            cell_node.modulate = config.color_treasure_bg
    
    # Apply damage/health visualization
    if layer.health < 100 and layer.health > 0:
        cell_node.modulate.a = lerp(config.cell_opacity_min, 1.0, layer.health / 100.0)
    else:
        cell_node.modulate.a = 1.0

func is_cell_revealed(x: int, y: int) -> bool:
    if y < 0 or y >= grid.size() or x < 0 or x >= grid[0].size():
        return false
    return grid[y][x].revealed

func get_cell_layer_type(x: int, y: int) -> int:
    if y < 0 or y >= grid.size() or x < 0 or x >= grid[0].size():
        return -1
    var cell = grid[y][x]
    return cell.layers[cell.current_layer].type

func get_treasure_at(x: int, y: int) -> Dictionary:
    for treasure in treasures:
        if treasure.x == x and treasure.y == y:
            return treasure
    return {}

func clear() -> void:
    grid.clear()
    cell_nodes.clear()
    treasures.clear()
