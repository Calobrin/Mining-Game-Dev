class_name MiningUI
extends Control

# UI Elements
@onready var grid_container: GridContainer = $GridContainer
@onready var durability_bar: ProgressBar = $DurabilityBar
@onready var tool_buttons: HBoxContainer = $ToolButtons
@onready var results_screen: Control = $ResultsScreen

# Dependencies
var config: MiningConfig
var game: Node

# UI state
var cell_nodes: Array = []

func _init(p_config: MiningConfig, p_game: Node) -> void:
    config = p_config
    game = p_game

func initialize() -> void:
    _setup_grid_container()
    _setup_tool_buttons()
    _setup_results_screen()
    update_durability_bar(1.0)

func _setup_grid_container() -> void:
    # Clear existing children
    for child in grid_container.get_children():
        child.queue_free()
    
    # Configure grid container
    grid_container.columns = config.grid_size.x
    
    # Create cell buttons using ColorRect instead of prefab
    cell_nodes = []  # Reset cell nodes array
    for y in range(config.grid_size.y):
        var row = []
        for x in range(config.grid_size.x):
            var cell = ColorRect.new()
            cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
            cell.custom_minimum_size = config.cell_size if config else Vector2(50, 50)
            cell.color = Color(0.6, 0.4, 0.2)  # Default dirt color
            cell.mouse_filter = Control.MOUSE_FILTER_STOP
            
            # Connect signals
            cell.gui_input.connect(_on_cell_input.bind(x, y))
            
            grid_container.add_child(cell)
            row.append(cell)
        
        cell_nodes.append(row)

func _setup_tool_buttons() -> void:
    # Clear existing buttons
    for child in tool_buttons.get_children():
        child.queue_free()
    
    # Create tool buttons
    var pickaxe_btn = Button.new()
    pickaxe_btn.text = "Pickaxe"
    pickaxe_btn.pressed.connect(_on_tool_selected.bind(config.ToolType.PICKAXE))
    tool_buttons.add_child(pickaxe_btn)
    
    var hammer_btn = Button.new()
    hammer_btn.text = "Hammer"
    hammer_btn.pressed.connect(_on_tool_selected.bind(config.ToolType.HAMMER))
    tool_buttons.add_child(hammer_btn)

func _setup_results_screen() -> void:
    # Hide results screen initially
    results_screen.visible = false
    
    # Connect results screen buttons
    var exit_btn = results_screen.get_node("ExitButton") as Button
    if exit_btn:
        exit_btn.pressed.connect(_on_exit_button_pressed)

func update_durability_bar(normalized_value: float) -> void:
    durability_bar.value = normalized_value * 100.0
    
    # Update color based on value
    if normalized_value < 0.2:
        durability_bar.add_theme_color_override("font_color", Color(1, 0, 0))
    else:
        durability_bar.remove_theme_color_override("font_color")

func show_results(treasures_found: int, total_value: int) -> void:
    var treasures_label = results_screen.get_node("TreasuresFound") as Label
    var value_label = results_screen.get_node("TotalValue") as Label
    
    if treasures_label:
        treasures_label.text = "Treasures Found: %d" % treasures_found
    if value_label:
        value_label.text = "Total Value: %d" % total_value
    
    results_screen.visible = true

func _on_cell_input(event: InputEvent, x: int, y: int) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        game.on_cell_clicked(x, y)

func update_tool_selection(tool_type: int) -> void:
    # Update tool button visuals based on selection
    var buttons = tool_buttons.get_children()
    for i in range(buttons.size()):
        var button = buttons[i] as Button
        if button:
            if i == tool_type:
                button.modulate = Color(1.2, 1.2, 0.4, 1.0)  # Highlight selected
            else:
                button.modulate = Color(0.6, 0.6, 0.6, 0.8)  # Dim unselected

func update_score(_treasures: int, _value: int) -> void:
    # Update score display if UI elements exist
    pass

func _on_tool_selected(tool_type: int) -> void:
    game.set_current_tool(tool_type)

func _on_exit_button_pressed() -> void:
    game.exit_game()

# =============================
# Results Overlay (static API)
# =============================
# These helpers let other scripts (like mining_minigame.gd) delegate UI creation here

static func cleanup_results_overlay(host: Node) -> void:
    if not host or not host.is_inside_tree():
        return
    # Remove sibling canvas layer if present
    var parent := host.get_parent()
    if parent:
        var existing_overlay := parent.get_node_or_null("ResultsCanvasLayer")
        if existing_overlay and is_instance_valid(existing_overlay):
            existing_overlay.queue_free()
    # Also clean up any direct children that might be left
    for child in host.get_children():
        if child.name == "ResultsCanvasLayer" and is_instance_valid(child):
            child.queue_free()

static func create_results_overlay(host: Node, revealed_count: int, total_value: int, exit_pressed_callable: Callable) -> void:
    if not host or not host.is_inside_tree():
        return
    cleanup_results_overlay(host)

    # Get viewport info first
    var viewport := host.get_viewport()
    var viewport_size := viewport.get_visible_rect().size if viewport else Vector2(1280, 720)

    # Create a new CanvasLayer for the results overlay
    var results_canvas := CanvasLayer.new()
    results_canvas.layer = 200
    results_canvas.name = "ResultsCanvasLayer"

    # Root overlay control
    var overlay := Control.new()
    overlay.name = "ResultsOverlay"
    overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    results_canvas.add_child(overlay)

    # Add the canvas layer to the scene tree as a sibling of host
    host.add_sibling(results_canvas, true)

    await host.get_tree().process_frame

    # Background
    var background := ColorRect.new()
    background.anchor_right = 1.0
    background.anchor_bottom = 1.0
    background.color = Color(0, 0, 0, 0.7)
    background.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.add_child(background)

    # Container to assist centering
    var container := Control.new()
    container.anchor_right = 1.0
    container.anchor_bottom = 1.0
    container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    overlay.add_child(container)

    # Panel
    var panel := PanelContainer.new()
    panel.size = Vector2(500, 400)
    panel.position = (viewport_size - panel.size) * 0.5
    var stylebox := StyleBoxFlat.new()
    stylebox.bg_color = Color(0.1, 0.1, 0.15)
    stylebox.border_width_bottom = 2
    stylebox.border_width_left = 2
    stylebox.border_width_right = 2
    stylebox.border_width_top = 2
    stylebox.border_color = Color(0.3, 0.3, 0.4)
    stylebox.corner_radius_top_left = 10
    stylebox.corner_radius_top_right = 10
    stylebox.corner_radius_bottom_right = 10
    stylebox.corner_radius_bottom_left = 10
    panel.add_theme_stylebox_override("panel", stylebox)
    container.add_child(panel)

    # Content margins and vbox
    var margin_container := MarginContainer.new()
    margin_container.anchor_right = 1.0
    margin_container.anchor_bottom = 1.0
    margin_container.add_theme_constant_override("margin_left", 20)
    margin_container.add_theme_constant_override("margin_top", 20)
    margin_container.add_theme_constant_override("margin_right", 20)
    margin_container.add_theme_constant_override("margin_bottom", 20)
    panel.add_child(margin_container)

    var vbox := VBoxContainer.new()
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    vbox.add_theme_constant_override("separation", 20)
    margin_container.add_child(vbox)

    # Title
    var game_over_label := Label.new()
    game_over_label.text = "Mining Complete!"
    game_over_label.add_theme_font_size_override("font_size", 42)
    game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    game_over_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    game_over_label.add_theme_color_override("font_color", Color(1, 1, 1))
    vbox.add_child(game_over_label)

    # Divider
    var divider := ColorRect.new()
    divider.custom_minimum_size = Vector2(0, 2)
    divider.color = Color(0.3, 0.3, 0.4)
    divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_child(divider)

    # Results labels
    var results_container := VBoxContainer.new()
    results_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    results_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    results_container.add_theme_constant_override("separation", 15)
    vbox.add_child(results_container)

    var treasures_found_label := Label.new()
    treasures_found_label.text = "Treasures Found: %d" % revealed_count
    treasures_found_label.add_theme_font_size_override("font_size", 28)
    treasures_found_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    treasures_found_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
    results_container.add_child(treasures_found_label)

    var total_value_label := Label.new()
    total_value_label.text = "Total Value: %d" % total_value
    total_value_label.add_theme_font_size_override("font_size", 32)
    total_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    total_value_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
    results_container.add_child(total_value_label)

    # Exit button row
    var button_container := HBoxContainer.new()
    button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button_container.add_spacer(true)

    var exit_button := Button.new()
    exit_button.name = "ExitButton"
    exit_button.custom_minimum_size = Vector2(200, 50)
    exit_button.text = "Finish Mining"
    exit_button.add_theme_font_size_override("font_size", 24)

    var normal_style := StyleBoxFlat.new()
    normal_style.bg_color = Color(0.2, 0.6, 0.9)
    normal_style.corner_radius_top_left = 5
    normal_style.corner_radius_top_right = 5git 
    normal_style.corner_radius_bottom_right = 5
    normal_style.corner_radius_bottom_left = 5

    var hover_style := normal_style.duplicate()
    hover_style.bg_color = Color(0.3, 0.7, 1.0)

    var pressed_style := normal_style.duplicate()
    pressed_style.bg_color = Color(0.1, 0.5, 0.8)

    exit_button.add_theme_stylebox_override("normal", normal_style)
    exit_button.add_theme_stylebox_override("hover", hover_style)
    exit_button.add_theme_stylebox_override("pressed", pressed_style)
    exit_button.add_theme_color_override("font_color", Color(1, 1, 1))
    exit_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
    exit_button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))

    if exit_pressed_callable.is_valid():
        exit_button.pressed.connect(exit_pressed_callable)

    button_container.add_child(exit_button)
    button_container.add_spacer(true)
    vbox.add_child(button_container)

    # Focus and sizing
    exit_button.mouse_filter = Control.MOUSE_FILTER_STOP
    exit_button.z_index = 1001
    exit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    if host.is_inside_tree():
        exit_button.call_deferred("grab_focus")
    exit_button.process_mode = Node.PROCESS_MODE_ALWAYS

    if is_instance_valid(overlay):
        overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)
        overlay.size = viewport_size
        overlay.z_index = 1000
